import AVFoundation
import Accelerate
import Foundation

/// Captures microphone audio and delivers:
///   - Raw level updates for the waveform visualiser (main thread)
///   - PCM float samples resampled to 16 kHz mono (background, for MedASR)
///   - Raw AVAudioPCMBuffer (background, for Apple SFSpeechRecognizer)
///
/// Safe for repeated start/stop (pause/resume). Never crashes with
/// "required condition is false: nullptr == Tap()" because the engine is
/// fully reset and the tap is removed before every new start.
final class AudioCapture: ObservableObject {

    // MARK: - Public callbacks
    var onSamples:      (([Float]) -> Void)?
    var onPCMBuffer:    ((AVAudioPCMBuffer) -> Void)?
    var levelHandler:   ((Float) -> Void)?
    var onInterruption: (() -> Void)?

    // MARK: - Private
    /// A fresh engine is created for every start() call to guarantee a clean state.
    /// Reusing the same engine instance across stop/start is the root cause of the
    /// "nullptr == Tap()" crash on iOS — the input node's tap state is not fully
    /// cleared by stop() + removeTap(), but creating a new engine always is.
    private var engine: AVAudioEngine = AVAudioEngine()
    private var tapInstalled = false

    private let targetSampleRate: Double = 16_000
    private var nativeRate: Double = 44_100  // updated on start

    init() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let raw  = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began { self?.onInterruption?() }
        }
    }

    // MARK: - Start

    func start() throws {
        // Always start from a clean engine to avoid the double-tap crash.
        // AVAudioEngine is cheap to recreate; this is the Apple-recommended
        // pattern for stop/restart scenarios in audio session interruption docs.
        engine = AVAudioEngine()
        tapInstalled = false

        let session = AVAudioSession.sharedInstance()
        // Only change category if needed — avoid unnecessary reconfiguration
        let currentCategory = session.category
        if currentCategory != .playAndRecord {
            try session.setCategory(.playAndRecord,
                                    mode: .measurement,
                                    options: [.defaultToSpeaker, AVAudioSession.CategoryOptions.allowBluetooth])
        }
        try session.setActive(true)

        let input        = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)
        nativeRate       = nativeFormat.sampleRate   // 44100 or 48000 depending on device

        input.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Forward raw buffer to Apple ASR
            self.onPCMBuffer?(buffer)

            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }

            // Extract channel 0
            var native = [Float](repeating: 0, count: frames)
            if let ptr = buffer.floatChannelData?[0] {
                native = Array(UnsafeBufferPointer(start: ptr, count: frames))
            }

            // Level meter (main thread)
            var rms: Float = 0
            vDSP_rmsqv(native, 1, &rms, vDSP_Length(frames))
            DispatchQueue.main.async { self.levelHandler?(min(rms * 12, 1.0)) }

            // Resample to 16 kHz for MedASR
            let resampled: [Float]
            if abs(self.nativeRate - self.targetSampleRate) < 1 {
                resampled = native
            } else {
                resampled = Self.resample(native,
                                         fromRate: self.nativeRate,
                                         toRate:   self.targetSampleRate)
            }
            self.onSamples?(resampled)
        }
        tapInstalled = true

        engine.prepare()
        try engine.start()
    }

    // MARK: - Stop (pause-safe — does NOT deactivate the audio session)

    func stop() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        // Do NOT call setActive(false) here — that would cut off the audio session
        // for the entire app. Deactivate only when fully done (see deactivate()).
    }

    // MARK: - Deactivate (call when recording session is fully finished)

    func deactivate() {
        stop()
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }

    // MARK: - Resample (linear interpolation, good enough for speech)

    private static func resample(_ input: [Float],
                                 fromRate: Double,
                                 toRate: Double) -> [Float] {
        let ratio       = toRate / fromRate
        let outputCount = Int((Double(input.count) * ratio).rounded())
        guard outputCount > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputCount)
        let scale  = Float(fromRate / toRate)

        for i in 0..<outputCount {
            let srcPos = Float(i) * scale
            let srcIdx = Int(srcPos)
            let frac   = srcPos - Float(srcIdx)
            let s0     = srcIdx     < input.count ? input[srcIdx]     : 0
            let s1     = srcIdx + 1 < input.count ? input[srcIdx + 1] : 0
            output[i]  = s0 + frac * (s1 - s0)
        }
        return output
    }
}
