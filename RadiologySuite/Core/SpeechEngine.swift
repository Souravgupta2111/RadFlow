import AVFoundation
import Speech
import Combine

struct TranscriptChunk: Identifiable, Equatable {
    let id: UUID
    var text: String
    var confidence: Float
    var isFinal: Bool

    init(text: String = "", confidence: Float = 0, isFinal: Bool = false) {
        self.id = UUID()
        self.text = text
        self.confidence = confidence
        self.isFinal = isFinal
    }
}

protocol SpeechEngine: AnyObject {
    var onPartial: ((String) -> Void)? { get set }
    var onFinal: ((TranscriptChunk) -> Void)? { get set }
    var isRunning: Bool { get }
    func start() throws
    func stop()
    func setContext(_ phrases: [String])
}

final class AppleStreamingEngine: SpeechEngine {
    var onPartial: ((String) -> Void)?
    var onFinal: ((TranscriptChunk) -> Void)?
    private(set) var isRunning = false

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var contextualPhrases: [String] = []
    private var wantsRunning = false
    private var taskEpoch = 0
    private var preferOnDevice = true
    private var lastPartialText = ""

    init() {
        contextualPhrases = Array(Self.loadRadLexTerms().prefix(25))
    }

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    func setContext(_ phrases: [String]) {
        let baseTerms = Self.loadRadLexTerms()
        let additional = Array(phrases.prefix(20))
        contextualPhrases = Array((baseTerms + additional).prefix(25))
    }

    func ingest(buffer: AVAudioPCMBuffer) {
        guard isRunning, wantsRunning else { return }
        print("[AppleEngine] ingest (buffer.frameLength)"); request?.append(buffer)
    }

    func start() throws {
        guard !isRunning else { return }
        
        if recognizer == nil {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US")) ?? SFSpeechRecognizer()
        }
        
        guard let recognizer, recognizer.isAvailable else {
            throw AppError.speechUnavailable
        }
        wantsRunning = true
        preferOnDevice = true
        try beginTask(onDevice: true)
    }

    private func beginTask(onDevice: Bool) throws {
        guard let recognizer else { throw AppError.speechUnavailable }

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { throw AppError.speechUnavailable }
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = onDevice && preferOnDevice
        request.addsPunctuation = true
        request.taskHint = .dictation
        if !contextualPhrases.isEmpty {
            request.contextualStrings = contextualPhrases
        }

        isRunning = true
        taskEpoch += 1
        let epoch = taskEpoch

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, epoch == self.taskEpoch else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                
                // Detect Apple auto-segmenting (dropping old text to start a new sentence)
                if !self.lastPartialText.isEmpty {
                    let lengthDrop = self.lastPartialText.count - text.count
                    if lengthDrop > 15 || (self.lastPartialText.count > 10 && text.count < self.lastPartialText.count / 2) {
                        self.onFinal?(TranscriptChunk(text: self.lastPartialText, confidence: 1.0, isFinal: true))
                    }
                }

                self.lastPartialText = text
print("[AppleEngine] partial result: \(text)")
                if !text.isEmpty {
                    self.onPartial?(text)
                }
                if result.isFinal {
                    if !text.isEmpty {
                        self.onFinal?(TranscriptChunk(text: text, confidence: 1.0, isFinal: true))
                    }
                    self.lastPartialText = ""
                }
            }

            // Empty isFinal on start is normal — do not tear down the request.
            if result?.isFinal == true, (result?.bestTranscription.formattedString.isEmpty ?? true),
               error == nil {
                return
            }

            guard let error else { return }
print("[AppleEngine] Error: \(error)")
            guard self.wantsRunning else {
                self.isRunning = false
                return
            }

            let ns = error as NSError
            // 216/209: cancelled (we stopped). 203: no speech. 1110: on-device unavailable.
            if ns.code == 216 || ns.code == 209 { return }
            
            if !self.lastPartialText.isEmpty {
                self.onFinal?(TranscriptChunk(text: self.lastPartialText, confidence: 1.0, isFinal: true))
                self.lastPartialText = ""
            }

            self.task = nil
            self.request = nil

            let tryOffDevice = onDevice && (ns.code == 1110 || ns.code == 1700 || ns.code == 301 || ns.code == 201)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.wantsRunning, epoch == self.taskEpoch else { return }
                if tryOffDevice {
                    self.preferOnDevice = false
                    try? self.beginTask(onDevice: false)
                } else {
                    try? self.beginTask(onDevice: self.preferOnDevice)
                }
            }
        }
    }

    func stop() {
        wantsRunning = false
        taskEpoch += 1
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRunning = false
    }
}

extension AppleStreamingEngine {
    static func loadRadLexTerms() -> [String] {
        guard let url = Bundle.main.url(forResource: "radlex_terms", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let terms = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Array(terms.prefix(25))
    }
}
