import Accelerate
import Foundation
import MLX

/// Log-mel spectrogram matching Hugging Face `LasrFeatureExtractor`:
/// unfold win=400, hop=160, rFFT n=512, log(clamp(mel, 1e-5)).
enum MedASRMelSpectrogram {
    static let sampleRate = 16_000
    static let hopLength = 160
    static let nFFT = 512
    static let winLength = 400
    static let nMels = 128

    static func compute(samples: [Float]) -> MLXArray {
        let frames = logMel(samples: samples)
        let t = frames.count
        var flat = [Float](repeating: 0, count: t * nMels)
        for i in 0..<t {
            for m in 0..<nMels { flat[i * nMels + m] = frames[i][m] }
        }
        return MLXArray(flat, [t, nMels])
    }

    private static func logMel(samples: [Float]) -> [[Float]] {
        let hann = (0..<winLength).map { i -> Float in
            0.5 * (1 - cos(2 * .pi * Float(i) / Float(winLength - 1)))
        }
        let fb = melFilterbank()
        var results: [[Float]] = []
        let n = samples.count
        let halfN = nFFT / 2 + 1
        let log2N = vDSP_Length(log2(Float(nFFT)))
        guard let fftSetup = vDSP_create_fftsetup(log2N, FFTRadix(kFFTRadix2)) else {
            return results
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var start = 0
        while start + winLength <= n {
            var frame = Array(samples[start ..< (start + winLength)])
            vDSP_vmul(frame, 1, hann, 1, &frame, 1, vDSP_Length(winLength))
            var padded = frame + [Float](repeating: 0, count: nFFT - winLength)
            var realP = [Float](repeating: 0, count: nFFT / 2)
            var imagP = [Float](repeating: 0, count: nFFT / 2)
            padded.withUnsafeMutableBufferPointer { rawPtr in
                rawPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: nFFT / 2) { cPtr in
                    var split = DSPSplitComplex(realp: &realP, imagp: &imagP)
                    vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(nFFT / 2))
                    vDSP_fft_zrip(fftSetup, &split, 1, log2N, FFTDirection(FFT_FORWARD))
                }
            }
            var power = [Float](repeating: 0, count: halfN)
            power[0] = realP[0] * realP[0]
            power[halfN - 1] = imagP[0] * imagP[0]
            for k in 1 ..< (halfN - 1) {
                power[k] = realP[k] * realP[k] + imagP[k] * imagP[k]
            }
            var melFrame = [Float](repeating: 0, count: nMels)
            for m in 0 ..< nMels {
                var s: Float = 0
                vDSP_dotpr(fb[m], 1, power, 1, &s, vDSP_Length(halfN))
                melFrame[m] = log(max(s, 1e-5))
            }
            results.append(melFrame)
            start += hopLength
        }
        return results
    }

    /// HTK/Kaldi-style bank used by LasrFeatureExtractor (125–7500 Hz, skip DC).
    private static func melFilterbank() -> [[Float]] {
        let halfN = nFFT / 2 + 1
        let sampleRate = Double(self.sampleRate)
        let nFFT = Double(self.nFFT)
        func hzToMel(_ hz: Double) -> Double { 2595 * log10(1 + hz / 700) }
        func melToHz(_ m: Double) -> Double { 700 * (pow(10, m / 2595) - 1) }

        let nyquist = sampleRate / 2
        var linearFreq = [Double](repeating: 0, count: halfN)
        for k in 0..<halfN { linearFreq[k] = Double(k) * nyquist / Double(halfN - 1) }

        let loHz = 125.0
        let hiHz = 7500.0
        let melMin = hzToMel(loHz)
        let melMax = hzToMel(hiHz)
        var pts = [Double](repeating: 0, count: nMels + 2)
        for i in 0..<(nMels + 2) {
            pts[i] = melToHz(melMin + Double(i) * (melMax - melMin) / Double(nMels + 1))
        }

        var fb = [[Float]](repeating: [Float](repeating: 0, count: halfN), count: nMels)
        for m in 0..<nMels {
            let lo = pts[m], ctr = pts[m + 1], hi = pts[m + 2]
            for k in 1..<halfN { // skip DC like the HF extractor
                let f = linearFreq[k]
                if f >= lo && f <= ctr { fb[m][k] = Float((f - lo) / (ctr - lo)) }
                else if f > ctr && f <= hi { fb[m][k] = Float((hi - f) / (hi - ctr)) }
            }
        }
        return fb
    }
}
