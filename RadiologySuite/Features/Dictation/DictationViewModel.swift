import Foundation
import SwiftUI
import SwiftData
import Combine
import AVFoundation

@MainActor
final class DictationViewModel: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var level: Float = 0
    @Published var engineName = "Apple on-device"
    @Published var modality = "XR"
    @Published var patientName = ""
    @Published var errorMessage: String? = nil
    @Published var isProcessingAI = false
    /// True while the user is typing in the transcript; live ASR must not overwrite edits.
    var isEditingTranscript = false

    let audio = AudioCapture()
    private var appleEngine = AppleStreamingEngine()
    private var medasr = MedASREngine.shared
    /// Text that has scrolled out of the 3s window. Never rewritten.
    private var frozen = ""
    /// Latest 3s decode (or current Apple session). Replaced every hop/update.
    private var liveTail = ""
    private var useMedASR = false
    private var sessionGeneration = 0

    init() {
        appleEngine.onPartial = { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isEditingTranscript else { return }
                guard !self.useMedASR else { return }
                self.liveTail = text
                self.transcript = Self.glue(self.frozen, self.liveTail)
            }
        }
        appleEngine.onFinal = { [weak self] chunk in
            Task { @MainActor in
                guard let self, !chunk.text.isEmpty else { return }
                guard !self.isEditingTranscript else { return }
                guard !self.useMedASR else { return }
                self.frozen = Self.glue(self.frozen, chunk.text)
                self.liveTail = ""
                self.transcript = self.frozen
            }
        }

        medasr.onPartial = { [weak self] text in
            Task { @MainActor in
                guard let self, !text.isEmpty else { return }
                guard !self.isEditingTranscript else { return }
                self.liveTail = text
                self.transcript = Self.glue(self.frozen, self.liveTail)
            }
        }
        medasr.onFinal = { [weak self] chunk in
            Task { @MainActor in
                guard let self, !chunk.text.isEmpty else { return }
                guard !self.isEditingTranscript else { return }
                self.frozen = Self.glue(self.frozen, chunk.text)
                self.liveTail = ""
                self.transcript = self.frozen
            }
        }

        audio.levelHandler = { [weak self] l in self?.level = l }
        audio.onInterruption = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.errorMessage = "Audio session interrupted (e.g. by a phone call). Dictation paused."
                self.pause()
            }
        }
    }

    func begin() {
        sessionGeneration += 1
        let generation = sessionGeneration
        useMedASR = false
        
        if !liveTail.isEmpty {
            frozen = Self.glue(frozen, liveTail)
            liveTail = ""
        }
        if frozen.isEmpty, !transcript.isEmpty {
            frozen = transcript
        }

        Task { @MainActor in
            let userPrefersMedASR = UserDefaults.standard.object(forKey: "dictation.useMedASR") == nil ? true : UserDefaults.standard.bool(forKey: "dictation.useMedASR")
            
            if userPrefersMedASR {
                await medasr.loadIfNeeded()
            }
            guard generation == self.sessionGeneration else { return }

            let micOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
            }
            guard generation == self.sessionGeneration else { return }
            if !micOK {
                errorMessage = "Microphone permission is required for dictation."
                return
            }

            let appleFallback = !userPrefersMedASR || !medasr.isLoaded
            if appleFallback {
                let speechOK = await AppleStreamingEngine.requestAuthorization()
                guard generation == self.sessionGeneration else { return }
                if !speechOK {
                    errorMessage = "Speech recognition permission is required until MedASR finishes loading."
                    return
                }
            }

            do {
                audio.onSamples = userPrefersMedASR ? { [weak self] samples in
                    self?.medasr.ingest(samples: samples)
                } : nil
                audio.onPCMBuffer = appleFallback ? { [weak self] buffer in
                    (self?.appleEngine as? AppleStreamingEngine)?.ingest(buffer: buffer)
                } : nil
                if appleFallback {
                    try appleEngine.start()
                }
                try audio.start()
                isRecording = true
                isPaused    = false
                if userPrefersMedASR && medasr.isLoaded {
                    useMedASR = true
                    engineName = "MedASR (on-device)"
                    try medasr.start()
                } else {
                    useMedASR = false
                    engineName = "Apple on-device"
                }
            } catch {
                errorMessage = "Could not start recording. Check microphone permissions."
                return
            }
        }
    }

    func pause() {
        medasr.stop()
        appleEngine.stop()
        audio.stop()
        audio.onSamples   = nil
        audio.onPCMBuffer = nil
        isPaused = true
        level = 0
    }

    func resume() {
        isPaused = false
        begin()
    }

    func finish() {
        medasr.stop()
        appleEngine.stop()
        audio.deactivate()
        audio.onSamples   = nil
        audio.onPCMBuffer = nil
        isRecording = false
        isPaused    = false
        level       = 0
    }

    /// Stop recording and drop the transcript. Does not write a report.
    func discard() {
        finish()
        transcript = ""
        frozen = ""
        liveTail = ""
        isEditingTranscript = false
    }

    func applyUserEdit(_ text: String) {
        transcript = text
        guard isEditingTranscript else { return }
        frozen = text
        liveTail = ""
    }



    private static func glue(_ a: String, _ b: String) -> String {
        let a = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        if a.last?.isWhitespace == true || b.first?.isWhitespace == true {
            return a + b
        }
        return a + " " + b
    }

    private static func clip(_ text: String, n: Int = 120) -> String {
        if text.count <= n { return text }
        return "…" + String(text.suffix(n))
    }

    private static func appendDeduped(base: String, new: String) -> String {
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { return new }
        let b = base.lowercased()
        let n = new.lowercased()
        if n.hasPrefix(b) { return new }
        if b.hasPrefix(n) { return base }
        if b.hasSuffix(n) { return base }
        return glue(base, new)
    }

    func sendToReport(context: ModelContext) async -> RadiologyReport? {
        if selectedTemplate == nil {
            let defaultName = UserDefaults.standard.string(forKey: "report.defaultTemplateName") ?? ""
            let descriptor = FetchDescriptor<ReportTemplate>()
            if let all = try? context.fetch(descriptor) {
                selectedTemplate = all.first(where: { $0.name == defaultName }) ?? all.first
            }
        }
        
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var resolvedPatientName = patientName
        if resolvedPatientName.isEmpty, let detected = extractPatientName(from: text) {
            resolvedPatientName = detected
        }
        
        var title = selectedTemplate?.name ?? modality
        if !resolvedPatientName.isEmpty {
            let firstName = resolvedPatientName.components(separatedBy: .whitespaces).first ?? resolvedPatientName
            title += " · \(firstName)"
        }
        
        let report = RadiologyReport(title: title, modality: modality)
        report.patientName = resolvedPatientName
        report.template = selectedTemplate
        report.sections = parseSections(from: text)
        context.insert(report)
        
        // Always save the dictation session for audit trail
        let session = DictationSession(engineUsed: engineName)
        session.endedAt = Date()
        session.rawTranscript = text
        session.report = report
        context.insert(session)
        
        try? context.save()
        
        isProcessingAI = true
        await autoFillTemplate(report: report, rawSpeech: text)
        isProcessingAI = false
        
        try? context.save()
        
        return report
    }
    
    private func autoFillTemplate(report: RadiologyReport, rawSpeech: String) async {
        guard !rawSpeech.isEmpty else { return }
        let service = LLMProvider.service
        let templateHeadings = report.sections.map(\.heading)
        let templateName = report.template?.name ?? "Radiology Report"

        do {
            let filled = try await service.fillTemplateFromSpeech(
                speech: rawSpeech,
                templateHeadings: templateHeadings,
                templateName: templateName
            )
            for i in 0..<report.sections.count {
                let heading = report.sections[i].heading
                if let content = filled[heading], !content.isEmpty {
                    report.sections[i].text = content
                    report.sections[i].isAIPolished = true
                }
            }
        } catch {
            print("AI template fill failed: \(error)")
        }
    }

    /// Template the dictation is routed into (chosen on the record screen,
    /// persisted as the default in `report.defaultTemplateName`).
    @Published var selectedTemplate: ReportTemplate?

    /// Best-effort extraction of a patient name from spoken dictation, so the
    /// report header can be pre-filled even before a patient is formally linked.
    /// Only fires on explicit patterns ("patient name is …", "name is …") or
    /// honorifics ("Mr/Mrs/Ms/Dr …") to avoid false positives.
    private func extractPatientName(from raw: String) -> String? {
        let patterns = [
            #"(?:patient(?:'s)?\s+)?name\s+(?:is|:)\s+([A-Za-z][A-Za-z'.\- ]{1,40})"#,
            #"\b(?:mr|mrs|ms|miss|dr|mister)\.?\s+([A-Za-z][A-Za-z'.\- ]{1,40})"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let nsRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            guard let match = regex.firstMatch(in: raw, options: [], range: nsRange),
                  let range = Range(match.range(at: 1), in: raw) else { continue }

            let name = String(raw[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:-"))
            guard name.count >= 2 else { continue }
            return name
        }
        return nil
    }

    private func parseSections(from raw: String) -> [ReportSection] {
        let defaultHeadings = ["Clinical History", "Technique", "Findings", "Impression", "Indication", "Comparison"]
        let headings = selectedTemplate?.headings ?? defaultHeadings
        
        var result: [ReportSection] = []
        var currentHeading = headings.first ?? "Findings"
        var currentLines: [String] = []

        var processedRaw = raw
        
        // Handle Voice Macros
        if let macros = selectedTemplate?.macros {
            for macro in macros {
                processedRaw = processedRaw.replacingOccurrences(
                    of: macro.trigger,
                    with: macro.expansion,
                    options: .caseInsensitive
                )
            }
        }

        for line in processedRaw.components(separatedBy: .newlines) {
            let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
            if let match = headings.first(where: { lower.hasPrefix($0.lowercased()) }) {
                flush(into: &result, heading: &currentHeading, lines: &currentLines)
                currentHeading = match
                currentLines = [String(line.dropFirst(match.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: ": "))]
                    .filter { !$0.isEmpty }
            } else {
                currentLines.append(line)
            }
        }
        flush(into: &result, heading: &currentHeading, lines: &currentLines)
        
        // Ensure all template headings and modular block configurations exist in the result
        if let template = selectedTemplate {
            var finalSections: [ReportSection] = []
            if !template.blocks.isEmpty {
                for block in template.blocks {
                    let existingText = result.first(where: { $0.heading.lowercased() == block.title.lowercased() })?.text ?? ""
                    let sec = ReportSection(
                        heading: block.title,
                        text: existingText.isEmpty ? block.defaultContent : existingText,
                        column: block.column.rawValue,
                        blockType: block.blockType.rawValue
                    )
                    finalSections.append(sec)
                }
            } else {
                for heading in template.headings {
                    let existingText = result.first(where: { $0.heading.lowercased() == heading.lowercased() })?.text ?? ""
                    finalSections.append(ReportSection(heading: heading, text: existingText))
                }
            }
            return finalSections
        }

        if result.isEmpty {
            result = [ReportSection(heading: "Findings", text: processedRaw)]
        }
        
        return result
    }

    private func flush(into result: inout [ReportSection],
                       heading: inout String,
                       lines: inout [String]) {
        let tail = lines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty || !result.isEmpty {
            if !tail.isEmpty {
                result.append(ReportSection(heading: heading, text: tail))
            }
        }
        lines.removeAll()
    }
}
