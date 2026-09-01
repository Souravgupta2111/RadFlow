import Foundation
import MLX
import MLXNN
import OSLog

enum AppError: LocalizedError {
    case speechUnavailable
    case modelMissing
    case audioFormat

    var errorDescription: String? {
        switch self {
        case .speechUnavailable: return "On-device speech recognition is unavailable."
        case .modelMissing:      return "MedASR MLX weights were not found. They download on first launch."
        case .audioFormat:       return "Unsupported audio format for MedASR."
        }
    }
}

/// On-device MedASR via MLX FP16 (ainergiz/medasr-mlx-fp16), not Core ML.
///
/// Weights: Hugging Face `ainergiz/medasr-mlx-fp16` (`weights.npz` + `config.json`).
/// Architecture: LASR Conformer-CTC ported from the public MLX Swift app.
final class MedASREngine: SpeechEngine, ObservableObject {
    static let shared = MedASREngine()

    var onPartial: ((String) -> Void)?
    var onFinal: ((TranscriptChunk) -> Void)?
    private(set) var isRunning = false
    @Published private(set) var isLoaded = false
    @Published private(set) var status = "Not loaded"
    @Published private(set) var lastError: String?

    private let maxBufferSamples = 16_000 * 15
    private let inferenceIntervalSamples = 16_000
    private static let log = Logger(subsystem: "RadiologySuite", category: "MedASR")

    private var model: LasrForCTC?
    private var decoder: MedASRDecoder?
    private var loadTask: Task<Void, Never>?
    private let loadLock = NSLock()
    private var ringBuffer: [Float] = []
    private var samplesIngestedSinceLastInference = 0
    private var windowIndex = 0
    private let queue = DispatchQueue(label: "medasr.mlx", qos: .userInitiated)

    private static let hfBase = "https://huggingface.co/ainergiz/medasr-mlx-fp16/resolve/main"

    func preload() {
        Task(priority: .userInitiated) { await loadIfNeeded() }
    }

    static func locateModel() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = [
            Bundle.main.url(forResource: "weights", withExtension: "npz", subdirectory: "MedASR-MLX"),
            Bundle.main.url(forResource: "weights", withExtension: "npz"),
            Bundle.main.resourceURL?.appendingPathComponent("MedASR-MLX/weights.npz"),
            Bundle.main.bundleURL.appendingPathComponent("MedASR-MLX/weights.npz"),
        ].compactMap { $0 }

        if let folder = Bundle.main.url(forResource: "MedASR-MLX", withExtension: nil) {
            candidates.append(folder.appendingPathComponent("weights.npz"))
        }

        for npz in candidates where fm.fileExists(atPath: npz.path) {
            log.info("Found bundled weights at \(npz.path, privacy: .public)")
            return npz.deletingLastPathComponent()
        }

        if let bundled = Bundle.main.url(forResource: "config", withExtension: "json", subdirectory: "MedASR-MLX") {
            let dir = bundled.deletingLastPathComponent()
            let npz = dir.appendingPathComponent("weights.npz")
            if fm.fileExists(atPath: npz.path) { return dir }
        }
        let cache = cacheDirectory()
        if fm.fileExists(atPath: cache.appendingPathComponent("weights.npz").path) {
            return cache
        }
        log.error("weights.npz not found in bundle or cache")
        return nil
    }

    func loadIfNeeded() async {
        if isLoaded { return }
        let task: Task<Void, Never> = loadLock.withLock {
            if let existing = loadTask {
                return existing
            } else {
                let created = Task { await self.performLoad() }
                loadTask = created
                return created
            }
        }
        await task.value
    }

    private func performLoad() async {
        #if targetEnvironment(simulator)
        await MainActor.run {
            Self.log.info("Running on iOS Simulator — MLX Metal GPU bypassed in favor of Apple Speech Engine.")
            self.lastError = nil
            self.isLoaded = true
            self.status = "Ready (Apple ASR Simulator)"
        }
        #else
        await MainActor.run { status = "Loading MedASR (MLX)…" }
        // 200 MB FP16 weights must fit in the Metal buffer cache. A 32 MB
        // cap (or default-small on some iOS builds) makes load thrash.
        GPU.set(cacheLimit: 512 * 1024 * 1024)
        let t0 = CFAbsoluteTimeGetCurrent()

        do {
            let dir = try await ensureWeights()
            Self.log.info("Weights ready in \(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)) ms at \(dir.path, privacy: .public)")
            let loaded = try MedASRModelLoader.load(from: dir)
            let decoder = try makeDecoder(directory: dir)
            model = loaded
            self.decoder = decoder
            await MainActor.run {
                lastError = nil
                isLoaded = true
                status = "Ready (MLX FP16)"
            }
            Self.log.info("MedASR MLX ready in \(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)) ms")
        } catch {
            Self.log.error("MedASR load failed: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                lastError = error.localizedDescription
                status = "Failed — using Apple ASR"
            }
            loadLock.lock()
            loadTask = nil
            loadLock.unlock()
        }
        #endif
    }

    func setContext(_ phrases: [String]) {}

    func start() throws {
        guard isLoaded else { throw AppError.modelMissing }
        ringBuffer.removeAll(keepingCapacity: true)
        samplesIngestedSinceLastInference = 0
        windowIndex = 0
        isRunning = true
        print("[MedASR] start  max_buffer=15.0s (\(maxBufferSamples) samples)  interval=1.0s (\(inferenceIntervalSamples) samples)  16 kHz")
    }

    func stop() {
        isRunning = false
        flushFinal()
    }

    func ingest(samples: [Float]) {
        guard isRunning else { return }
        ringBuffer.append(contentsOf: samples)
        samplesIngestedSinceLastInference += samples.count
        
        guard samplesIngestedSinceLastInference >= inferenceIntervalSamples else { return }
        samplesIngestedSinceLastInference = 0
        windowIndex += 1
        let idx = windowIndex
        
        if ringBuffer.count >= maxBufferSamples {
            let chunkToTranscribe = Array(ringBuffer.prefix(maxBufferSamples))
            let leftover = ringBuffer.count > maxBufferSamples ? Array(ringBuffer.suffix(from: maxBufferSamples)) : []
            ringBuffer = leftover
            print("[MedASR] window #\(idx) max length reached, flushing (\(chunkToTranscribe.count) samples)")
            queue.async { [weak self] in
                guard let self else { return }
                let t0 = CFAbsoluteTimeGetCurrent()
                let text = self.transcribe(chunkToTranscribe) ?? ""
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[MedASR] flush decode #\(idx) \(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000))ms chars=\(trimmed.count) live=\"\(trimmed)\"")
                DispatchQueue.main.async {
                    self.onFinal?(TranscriptChunk(text: trimmed, confidence: 1.0, isFinal: true))
                }
            }
        } else {
            let chunkToTranscribe = ringBuffer
            print("[MedASR] window #\(idx) running partial inference (\(chunkToTranscribe.count) samples)")
            queue.async { [weak self] in
                guard let self else { return }
                let t0 = CFAbsoluteTimeGetCurrent()
                let text = self.transcribe(chunkToTranscribe) ?? ""
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[MedASR] partial decode #\(idx) \(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000))ms chars=\(trimmed.count) live=\"\(trimmed)\"")
                if trimmed.count >= 3 {
                    DispatchQueue.main.async {
                        self.onPartial?(trimmed)
                    }
                }
            }
        }
    }

    private func flushFinal() {
        let chunk = ringBuffer
        ringBuffer.removeAll()
        if chunk.count >= 1600 {
            print("[MedASR] flush remainder \(chunk.count) samples")
            queue.async { [weak self] in
                let text = self?.transcribe(chunk) ?? ""
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[MedASR] flush decode chars=\(trimmed.count) live=\"\(trimmed)\"")
                DispatchQueue.main.async {
                    self?.onFinal?(TranscriptChunk(text: trimmed, confidence: 1.0, isFinal: true))
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onFinal?(TranscriptChunk(text: "", confidence: 1.0, isFinal: true))
            }
        }
    }

    private func transcribe(_ samples: [Float]) -> String? {
        #if targetEnvironment(simulator)
        return nil
        #else
        guard let model, let decoder else { return nil }
        var padded = samples
        // Always pad to at least 1 second
        if padded.count < 16_000 {
            padded.append(contentsOf: [Float](repeating: 0, count: 16_000 - padded.count))
        }
        let mel = MedASRMelSpectrogram.compute(samples: padded)
        let input = mel.expandedDimensions(axis: 0) // [1, T, 128]
        let logits = model(input)
        eval(logits)
        return decoder.decode(logits)
        #endif
    }

    // MARK: - Weights

    private static func cacheDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MedASR-MLX", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func ensureWeights() async throws -> URL {
        if let existing = Self.locateModel() { return existing }
        let dest = Self.cacheDirectory()
        await MainActor.run { status = "Downloading MedASR FP16…" }
        try await download(filename: "config.json", to: dest.appendingPathComponent("config.json"))
        try await download(filename: "weights.npz", to: dest.appendingPathComponent("weights.npz"))
        return dest
    }

    private func download(filename: String, to dest: URL) async throws {
        if FileManager.default.fileExists(atPath: dest.path) { return }
        guard let url = URL(string: "\(Self.hfBase)/\(filename)") else { throw AppError.modelMissing }
        let (temp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: temp, to: dest)
    }

    private func makeDecoder(directory: URL) throws -> MedASRDecoder {
        let tok = directory.appendingPathComponent("tokenizer.json")
        if FileManager.default.fileExists(atPath: tok.path) {
            return try MedASRDecoder(tokenizerURL: tok)
        }
        if let bundled = Bundle.main.url(forResource: "medasr_vocab", withExtension: "json") {
            return try MedASRDecoder(tokenizerURL: bundled)
        }
        throw AppError.modelMissing
    }
}
