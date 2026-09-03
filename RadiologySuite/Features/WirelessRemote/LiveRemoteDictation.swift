import Foundation
import AVFoundation
import Combine

/// Live wireless-mic engine for the Remote tab.
/// Streams every finalized speech chunk to the connected desktop the moment it
/// is recognized, so text types at the cursor while the doctor is still
/// talking. Connect once, go live, speak — no stop/send step.
@MainActor
final class LiveRemoteDictation: ObservableObject {
    @Published private(set) var isLive = false
    @Published private(set) var level: Float = 0
    @Published private(set) var liveTail = ""
    /// Recently finalized chunks that were typed at the cursor (newest first).
    @Published private(set) var typedLog: [String] = []
    @Published var errorMessage: String?

    private let audio = AudioCapture()
    private let medasr = MedASREngine.shared
    private let appleEngine = AppleStreamingEngine()
    private var useMedASR = false
    private var sessionGeneration = 0
    private weak var conn: RemoteConnectionService?

    func start(connection: RemoteConnectionService) {
        conn = connection
        errorMessage = nil
        Task { await beginSession() }
    }

    func stop() {
        // Stop audio capture first so no new samples arrive
        audio.stop()
        audio.onSamples = nil
        audio.onPCMBuffer = nil
        audio.levelHandler = nil
        audio.onInterruption = nil
        appleEngine.stop()
        
        // MedASR.stop() triggers flushFinal() which runs async.
        // We must keep isLive=true and onFinal alive so the flush
        // callback can still deliver the last transcribed chunk.
        medasr.stop()
        
        // Give the async flush a moment to complete and fire onFinal,
        // then clean up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.medasr.onPartial = nil
            self.medasr.onFinal = nil
            self.appleEngine.onPartial = nil
            self.appleEngine.onFinal = nil
            self.isLive = false
            self.liveTail = ""
            self.level = 0
        }
    }

    // MARK: - Session

    private func beginSession() async {
        sessionGeneration += 1
        let generation = sessionGeneration
        useMedASR = false

        let userPrefersMedASR = UserDefaults.standard.object(forKey: "dictation.useMedASR") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "dictation.useMedASR")

        if userPrefersMedASR {
            await medasr.loadIfNeeded()
        }
        guard generation == sessionGeneration else { return }

        let micOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
        guard generation == sessionGeneration else { return }
        guard micOK else {
            errorMessage = "Microphone permission is required for wireless dictation."
            return
        }

        let appleFallback = !userPrefersMedASR || !medasr.isLoaded
        if appleFallback {
            let speechOK = await AppleStreamingEngine.requestAuthorization()
            guard generation == sessionGeneration else { return }
            guard speechOK else {
                errorMessage = "Speech recognition permission is required until MedASR finishes loading."
                return
            }
        }

        wireStreamingCallbacks(appleFallback: appleFallback)

        do {
            audio.onSamples = userPrefersMedASR ? { [weak self] samples in
                self?.medasr.ingest(samples: samples)
            } : nil
            audio.onPCMBuffer = appleFallback ? { [weak self] buffer in
                self?.appleEngine.ingest(buffer: buffer)
            } : nil
            if appleFallback { try appleEngine.start() }
            try audio.start()
            if userPrefersMedASR && medasr.isLoaded {
                useMedASR = true
                try medasr.start()
            }
            isLive = true
        } catch {
            errorMessage = "Could not start the microphone. Check permissions."
        }
    }

    private func wireStreamingCallbacks(appleFallback: Bool) {
        medasr.onPartial = { [weak self] text in
            Task { @MainActor in
                guard let self, self.isLive else { return }
                self.liveTail = text
            }
        }
        medasr.onFinal = { [weak self] chunk in
            Task { @MainActor in
                guard let self, self.isLive else { return }
                self.deliver(chunk.text)
            }
        }

        appleEngine.onPartial = { [weak self] text in
            Task { @MainActor in
                guard let self, self.isLive, !self.useMedASR else { return }
                self.liveTail = text
            }
        }
        appleEngine.onFinal = { [weak self] chunk in
            Task { @MainActor in
                guard let self, self.isLive, !self.useMedASR else { return }
                self.deliver(chunk.text)
            }
        }

        audio.levelHandler = { [weak self] l in self?.level = l }
        audio.onInterruption = { [weak self] in
            Task { @MainActor in
                self?.stop()
                self?.errorMessage = "Audio interrupted (call?). Tap the mic to go live again."
            }
        }
    }

    // MARK: - Deliver

    private func deliver(_ raw: String) {
        print("[DICTATION-DEBUG] deliver() called with raw: \(raw.prefix(80))")
        let cleaned = LiveReportFormatter.format(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            print("[DICTATION-DEBUG] deliver() — cleaned text is empty, skipping")
            return
        }
        liveTail = ""
        typedLog.insert(cleaned, at: 0)
        if typedLog.count > 6 { typedLog.removeLast() }
        print("[DICTATION-DEBUG] calling conn?.send(text:) with: \(cleaned.prefix(80)), conn is \(conn == nil ? "nil" : "set")")
        conn?.send(text: cleaned)
        DS.haptic(.light)
    }
}
