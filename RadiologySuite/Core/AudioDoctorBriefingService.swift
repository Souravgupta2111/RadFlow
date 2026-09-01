import Foundation
import AVFoundation
import Combine

/// Speech audio briefing player for doctors.
/// Synthesizes and reads concise patient clinical histories, past visits, imaging findings,
/// and AI recommendations directly into the doctor's headphones or speaker.
final class AudioDoctorBriefingService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AudioDoctorBriefingService()

    @Published var isSpeaking: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentText: String = ""
    @Published var spokenWordProgress: Float = 0.0

    private let synthesizer = AVSpeechSynthesizer()

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Generates and reads a doctor audio briefing for a patient.
    func speakBriefing(for patient: Patient, latestReport: RadiologyReport? = nil) {
        let text = generateBriefingScript(patient: patient, latestReport: latestReport)
        speak(text: text)
    }

    /// Speaks any clinical summary or report impression.
    func speak(text: String) {
        stop()
        guard !text.isEmpty else { return }

        currentText = text
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US") ?? AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95 // Clear, authoritative pace
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        isSpeaking = true
        isPaused = false
        synthesizer.speak(utterance)
    }

    func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
        }
    }

    func resume() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        isPaused = false
        currentText = ""
        spokenWordProgress = 0.0
    }

    // MARK: - Script Generation
    private func generateBriefingScript(patient: Patient, latestReport: RadiologyReport?) -> String {
        var parts: [String] = []

        // Demographics
        let intro = "Doctor briefing for patient \(patient.name), \(patient.age) years old, \(patient.sex). MRN \(patient.mrn)."
        parts.append(intro)

        // Clinical Alerts & Allergies
        if !patient.allergiesAlert.isEmpty {
            parts.append("Important alert: \(patient.allergiesAlert).")
        }

        // Longitudinal Study History
        let totalStudies = patient.reports.count
        if totalStudies > 1 {
            parts.append("Patient has \(totalStudies) total encounters on record.")
            if let prior = patient.reports.dropFirst().first {
                let priorDate = prior.studyDate.formatted(date: .abbreviated, time: .omitted)
                parts.append("Prior study on \(priorDate) for \(prior.modality).")
            }
        }

        // Latest Findings & AI Recommendations
        if let report = latestReport ?? patient.reports.first {
            let studyName = report.title
            parts.append("Latest study: \(studyName).")

            if let impression = report.sections.first(where: { $0.heading.lowercased().contains("impression") || $0.heading.lowercased().contains("diagnosis") })?.text, !impression.isEmpty {
                parts.append("Impression: \(impression).")
            }

            if let followUp = report.followUpAdvice, !followUp.isEmpty {
                parts.append("Recommended follow-up: \(followUp).")
            }
        } else {
            parts.append("No active studies recorded for this patient yet.")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
            self.isPaused = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.isPaused = false
            self.spokenWordProgress = 1.0
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.isPaused = false
        }
    }
}
