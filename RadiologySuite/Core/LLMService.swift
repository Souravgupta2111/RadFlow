import Foundation

protocol LLMService {
    func polish(_ raw: String, section: String) async throws -> String
    func polishStreaming(_ raw: String, section: String, onChunk: @escaping (String) -> Void) async throws
    func summarize(_ reportText: String) async throws -> String
    func summarizeStreaming(_ reportText: String, onChunk: @escaping (String) -> Void) async throws
    func suggestDifferentials(reportText: String, images: [Data]) async throws -> [Differential]
    func generateQuestionnaire(reportText: String, modality: String) async throws -> [Question]
    func analyzeAndGenerateSummary(reportText: String, modality: String, language: String) async throws -> CoPilotAnalysis
    func fillTemplateFromSpeech(speech: String, templateHeadings: [String], templateName: String) async throws -> [String: String]
}

struct Differential: Codable, Hashable {
    var finding: String
    var confidence: String
    var basis: String
}

struct Question: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var kind: Kind
    var options: [String]

    enum Kind: String, Codable { case yesNo, singleChoice, freeText }
}

final class OpenAICompatibleService: LLMService {
    private let endpoint: URL
    private let accessToken: String?
    private let modelID: String

    init(endpoint: URL = URL(string: "\(SupabaseConfig.projectURL)/functions/v1/ai-proxy")!,
         accessToken: String? = nil,
         modelID: String = "gpt-4o-mini") {
        self.endpoint = endpoint
        self.accessToken = accessToken
        self.modelID = modelID
    }

    func polish(_ raw: String, section: String) async throws -> String {
        try await chat(system: """
            You are a medical transcription corrector for radiology reports. Fix only \
            speech-recognition errors using standard radiology terminology (RadLex). \
            Preserve the author's meaning exactly. Section: \(section).
            """, user: raw)
    }

    func polishStreaming(_ raw: String, section: String, onChunk: @escaping (String) -> Void) async throws {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        
        let headers = accessToken != nil ? SupabaseConfig.authHeaders(accessToken: accessToken!) : SupabaseConfig.baseHeaders
        req.allHTTPHeaderFields = headers
        
        let payload: [String: Any] = [
            "model": modelID,
            "stream": true,
            "messages": [
                ["role": "system", "content": "You are a medical transcription corrector for radiology reports. Fix only speech-recognition errors using standard radiology terminology (RadLex). Preserve the author's meaning exactly. Section: \(section)."],
                ["role": "user", "content": raw]
            ],
            "temperature": 0.2
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let jsonStr = line.dropFirst(6)
                if jsonStr == "[DONE]" { break }
                guard let data = jsonStr.data(using: .utf8) else { continue }
                if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = dict["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    onChunk(content)
                }
            }
        }
    }

    func summarize(_ reportText: String) async throws -> String {
        let textToSummarize = chunk(reportText: reportText)
        return try await chat(system: "Summarize this radiology report in 3 concise sentences for a referring physician.",
                       user: textToSummarize)
    }

    func summarizeStreaming(_ reportText: String, onChunk: @escaping (String) -> Void) async throws {
        let textToSummarize = chunk(reportText: reportText)
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        
        let headers = accessToken != nil ? SupabaseConfig.authHeaders(accessToken: accessToken!) : SupabaseConfig.baseHeaders
        req.allHTTPHeaderFields = headers
        
        let payload: [String: Any] = [
            "model": modelID,
            "stream": true,
            "messages": [
                ["role": "system", "content": "Summarize this radiology report in 3 concise sentences for a referring physician."],
                ["role": "user", "content": textToSummarize]
            ],
            "temperature": 0.2
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let jsonStr = line.dropFirst(6)
                if jsonStr == "[DONE]" { break }
                guard let data = jsonStr.data(using: .utf8) else { continue }
                if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = dict["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    onChunk(content)
                }
            }
        }
    }

    private func chunk(reportText: String) -> String {
        // Simple chunking for > 10000 chars
        if reportText.count > 10000 {
            return String(reportText.prefix(10000)) + "\n[Text truncated for length...]"
        }
        return reportText
    }

    func suggestDifferentials(reportText: String, images: [Data]) async throws -> [Differential] {
        var content: [[String: Any]] = [
            ["type": "text", "text": reportText.isEmpty ? "Analyze the attached images." : reportText]
        ]
        for imageData in images {
            let b64 = imageData.base64EncodedString()
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(b64)", "detail": "high"]
            ])
        }
        
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        
        let headers = accessToken != nil ? SupabaseConfig.authHeaders(accessToken: accessToken!) : SupabaseConfig.baseHeaders
        req.allHTTPHeaderFields = headers
        
        let payload: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": "You are a radiology decision-support assistant. Given the report (and image if provided), list up to 5 differential diagnoses. Return a strict JSON array of objects with keys: 'finding', 'confidence' (high/medium/low), 'basis'."],
                ["role": "user", "content": content]
            ],
            "temperature": 0.2,
            "max_tokens": 500,
            "response_format": ["type": "json_object"]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: req)
        
        guard let decodedResponse = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let jsonString = decodedResponse.choices.first?.message.content,
              let jsonData = jsonString.data(using: .utf8) else { return [] }
        
        // Sometimes GPT wraps the array in a root object if response_format is json_object
        struct DifferentialsRoot: Decodable {
            let differentials: [Differential]?
        }
        
        if let root = try? JSONDecoder().decode(DifferentialsRoot.self, from: jsonData), let diffs = root.differentials {
            return diffs
        }
        
        return (try? JSONDecoder().decode([Differential].self, from: jsonData)) ?? []
    }

    func generateQuestionnaire(reportText: String, modality: String) async throws -> [Question] {
        let raw = try await chat(
            system: """
                Generate 5 patient questions that would clarify findings in this radiology report. \
                The modality is \(modality) (e.g. XR for chest symptoms, MR for pain/activity, CT for neuro). \
                Return strict JSON array of {"text": "...", "kind": "yesNo|singleChoice|freeText", \
                "options": ["..."]} only.
                """, user: reportText)
        
        guard let data = raw.data(using: .utf8) else { return [] }
        
        struct QuestionsRoot: Decodable {
            let questions: [Question]?
        }
        
        if let root = try? JSONDecoder().decode(QuestionsRoot.self, from: data), let qs = root.questions {
            return qs
        }
        
        return (try? JSONDecoder().decode([Question].self, from: data)) ?? []
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable { struct Msg: Decodable { let content: String }; let message: Msg }
        let choices: [Choice]
    }

    private func chat(system: String, user: String) async throws -> String {
        return try await chat(system: system, user: user, json: false)
    }

    private func chat(system: String, user: String, json: Bool) async throws -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        
        let headers = accessToken != nil ? SupabaseConfig.authHeaders(accessToken: accessToken!) : SupabaseConfig.baseHeaders
        req.allHTTPHeaderFields = headers
        
        let payload: [String: Any] = [
            "model": modelID,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "response_format": json ? ["type": "json_object"] : ["type": "text"],
            "temperature": 0.2
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: req)
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    private func cleanJSON(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
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
        A doctor just dictated notes (may contain conversational speech, shorthand, findings, or disorganized sentences).
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
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }
}

final class MockLLMService: LLMService {
    func polish(_ raw: String, section: String) async throws -> String { raw }

    func polishStreaming(_ raw: String, section: String, onChunk: @escaping (String) -> Void) async throws {
        for char in raw {
            try await Task.sleep(nanoseconds: 20_000_000)
            onChunk(String(char))
        }
    }

    func summarize(_ reportText: String) async throws -> String {
        "Mock summary — connect an LLM key in Settings to enable live analysis.\n\n"
        + "The study demonstrates findings as dictated. No acute critical abnormality is highlighted in this preview."
    }

    func summarizeStreaming(_ reportText: String, onChunk: @escaping (String) -> Void) async throws {
        let text = "Mock summary — connect an LLM key in Settings to enable live analysis.\n\nThe study demonstrates findings as dictated. No acute critical abnormality is highlighted in this preview."
        for char in text {
            try await Task.sleep(nanoseconds: 20_000_000)
            onChunk(String(char))
        }
    }

    func suggestDifferentials(reportText: String, images: [Data]) async throws -> [Differential] {
        [
            Differential(finding: "No focal consolidation", confidence: "high", basis: "Clear lungs bilaterally"),
            Differential(finding: "Cardiomegaly", confidence: "medium", basis: "Enlarged cardiac silhouette"),
            Differential(finding: "Degenerative changes", confidence: "low", basis: "Mild osteophytes in spine")
        ]
    }

    func generateQuestionnaire(reportText: String, modality: String) async throws -> [Question] {
        [
            Question(text: "Have you had shortness of breath recently?", kind: .yesNo, options: []),
            Question(text: "Rate your chest pain", kind: .singleChoice, options: ["None", "Mild", "Moderate", "Severe"]),
            Question(text: "Any prior surgeries on this area?", kind: .freeText, options: [])
        ]
    }
    
    func analyzeAndGenerateSummary(reportText: String, modality: String, language: String) async throws -> CoPilotAnalysis {
        return CoPilotAnalysis(
            clinicalImpression: "Mock impression",
            discrepancyWarnings: [],
            radsRecommendation: nil,
            patientSummary: "Mock patient summary",
            recommendedTests: [],
            followUpAdvice: "Mock follow-up",
            medicationsOrPrecautions: "None"
        )
    }

    func fillTemplateFromSpeech(speech: String, templateHeadings: [String], templateName: String) async throws -> [String: String] {
        var result: [String: String] = [:]
        for heading in templateHeadings {
            result[heading] = "Mock text for \(heading)"
        }
        return result
    }
}

enum LLMProvider {
    static var service: LLMService {
        if UserDefaults.standard.bool(forKey: "dictation.useMedASR") {
            if let key = try? KeychainService.load(key: "llm.apiKey"), !key.isEmpty {
                return MedGemmaService(apiKey: key)
            }
        } 
        
        let token = try? KeychainService.load(key: "supabase.accessToken")
        return OpenAICompatibleService(accessToken: token, modelID: UserDefaults.standard.string(forKey: "llm.model") ?? "gpt-4o-mini")
    }
}
