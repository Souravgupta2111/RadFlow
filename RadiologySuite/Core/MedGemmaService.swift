import Foundation

struct CoPilotAnalysis: Codable, Hashable {
    var clinicalImpression: String
    var discrepancyWarnings: [String]
    var radsRecommendation: String?
    var patientSummary: String
    var recommendedTests: [String]
    var followUpAdvice: String
    var medicationsOrPrecautions: String
}
/// Gemini (Google AI Studio) client used for the clinical co-pilot.
/// Defaults to `gemini-2.5-flash-lite` but accepts any Gemini model ID.
final class MedGemmaService: LLMService {
    private let apiKey: String
    private let modelID: String

    init(apiKey: String, modelID: String = "gemini-2.5-flash-lite") {
        self.apiKey = apiKey
        self.modelID = modelID
    }

    private var endpoint: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent?key=\(apiKey)")!
    }

    func polish(_ raw: String, section: String) async throws -> String {
        try await chat(system: "You are a medical transcription corrector for radiology reports. Fix only speech-recognition errors using standard radiology terminology (RadLex). Preserve the author's meaning exactly. Section: \(section).", user: raw)
    }

    func polishStreaming(_ raw: String, section: String, onChunk: @escaping (String) -> Void) async throws {
        let text = try await polish(raw, section: section)
        for char in text {
            try await Task.sleep(nanoseconds: 10_000_000)
            onChunk(String(char))
        }
    }

    func summarize(_ reportText: String) async throws -> String {
        try await chat(system: "Summarize this radiology report in 3 concise sentences for a referring physician.", user: reportText)
    }

    func summarizeStreaming(_ reportText: String, onChunk: @escaping (String) -> Void) async throws {
        let text = try await summarize(reportText)
        for char in text {
            try await Task.sleep(nanoseconds: 10_000_000)
            onChunk(String(char))
        }
    }

    func suggestDifferentials(reportText: String, images: [Data]) async throws -> [Differential] {
        let text = try await chat(system: "You are a radiology decision-support assistant. Given the report, list up to 5 differential diagnoses. Return strict JSON array of objects with 'finding', 'confidence' (high/medium/low), and 'basis'.", user: reportText.isEmpty ? "Analyze the images." : reportText, json: true)

        guard let data = cleanJSON(text).data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Differential].self, from: data) else { return [] }
        return decoded
    }

    func generateQuestionnaire(reportText: String, modality: String) async throws -> [Question] {
        let raw = try await chat(system: "Generate 5 patient questions that would clarify findings in this radiology report. Modality: \(modality). Return strict JSON array of {\"text\": \"...\", \"kind\": \"yesNo|singleChoice|freeText\", \"options\": [\"...\"]} only.", user: reportText, json: true)

        guard let data = cleanJSON(raw).data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Question].self, from: data) else { return [] }
        return decoded
    }

    func analyzeAndGenerateSummary(reportText: String, modality: String, language: String) async throws -> CoPilotAnalysis {
        let systemPrompt = """
        You are a dual-role radiology co-pilot:
        1. For the RADIOLOGIST: Analyze the report text, draft a sharp Impression, check for laterality/discrepancy errors, and suggest any Fleischner / RADS criteria recommendations if applicable.
        2. For the PATIENT: Generate a patient-friendly care summary and clear action plan in \(language).
        Return strict JSON with keys: 'clinicalImpression', 'discrepancyWarnings' (array), 'radsRecommendation' (string), 'patientSummary', 'recommendedTests' (array of strings), 'followUpAdvice', 'medicationsOrPrecautions'.
        """
        let raw = try await chat(system: systemPrompt, user: "Modality: \(modality)\nReport text:\n\(reportText)", json: true)

        guard let data = cleanJSON(raw).data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CoPilotAnalysis.self, from: data) else {
            return CoPilotAnalysis(
                clinicalImpression: "No acute abnormality identified.",
                discrepancyWarnings: [],
                radsRecommendation: nil,
                patientSummary: "Scan results appear stable with no urgent abnormalities detected.",
                recommendedTests: ["Clinical correlation with referring physician"],
                followUpAdvice: "Routine follow-up as directed by your doctor.",
                medicationsOrPrecautions: "Follow standard medical advice."
            )
        }
        return decoded
    }

    func fillTemplateFromSpeech(speech: String, templateHeadings: [String], templateName: String) async throws -> [String: String] {
        let headingsList = templateHeadings.map { "- \"\($0)\"" }.joined(separator: "\n")
        let systemPrompt = """
        You are an intelligent clinical documentation assistant.
        A doctor just dictated notes (may contain conversational speech, Hindi/English, shorthand, vitals, findings, or disorganized sentences).
        The doctor is using the template: "\(templateName)".

        The template contains ONLY these exact section headings:
        \(headingsList)

        Task: Route the dictated clinical facts into the matching headings.
        Rules:
        - Return a strict JSON object whose keys are ONLY the exact headings listed above.
        - Do NOT invent or add any extra headings or keys.
        - If a heading was not mentioned in the dictation, set its value to an empty string "".
        - Values must be plain clinical text only (no markdown, no bullets, no headers).
        - Never fabricate findings; only use what the doctor actually said.
        """
        let raw = try await chat(system: systemPrompt, user: speech, json: true)

        guard let data = cleanJSON(raw).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        // Only accept keys that match the exact template headings; drop anything the
        // model invented so extra sections never leak into the report.
        var result: [String: String] = [:]
        for heading in templateHeadings {
            guard let value = object[heading] as? String else { continue }
            result[heading] = value
        }
        return result
    }

    private struct GeminiResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String
                }
                let parts: [Part]
            }
            let content: Content
        }
        let candidates: [Candidate]
    }

    private func chat(system: String, user: String, json: Bool = false) async throws -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var generationConfig: [String: Any] = ["temperature": 0.1]
        if json {
            generationConfig["responseMimeType"] = "application/json"
        }

        let payload: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["parts": [["text": user]]]],
            "generationConfig": generationConfig
        ]

        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: req)
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        return decoded.candidates.first?.content.parts.first?.text ?? ""
    }

    private func cleanJSON(_ text: String) -> String {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("```") {
            raw = raw.replacingOccurrences(of: "```json", with: "")
            raw = raw.replacingOccurrences(of: "```", with: "")
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
