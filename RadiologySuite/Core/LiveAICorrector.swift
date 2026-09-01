import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Rolling polish of the latest ~400 characters, while you speak.
/// Prefers Apple on-device Foundation Models (free). Falls back to the Settings API (Groq/OpenAI).
@MainActor
final class LiveAICorrector {
    static let shared = LiveAICorrector()

    private var pending: String = ""
    private var task: Task<Void, Never>?
    private var generation = 0

    static var foundationModelsAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            FoundationLivePolish.prewarm()
        }
        #endif
    }

    func cancel() {
        generation += 1
        task?.cancel()
        pending = ""
    }

    func schedule(_ fullText: String, apply: @escaping (String) -> Void) {
        guard UserDefaults.standard.bool(forKey: "dictation.liveAI") else { return }
        let canFoundation = Self.foundationModelsAvailable
        let canAPI = !(LLMProvider.service is MockLLMService)
        guard canFoundation || canAPI else { return }
        guard fullText.count >= 24 else { return }

        pending = fullText
        generation += 1
        let gen = generation
        task?.cancel()
        task = Task { [pending] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, gen == self.generation else { return }
            await self.run(fullText: pending, apply: apply)
        }
    }

    private func run(fullText: String, apply: @escaping (String) -> Void) async {
        let tailLen = min(420, fullText.count)
        let prefix = String(fullText.dropLast(tailLen))
        let tail = String(fullText.suffix(tailLen))
        do {
            let corrected: String
            if Self.foundationModelsAvailable {
                corrected = try await polishWithFoundationModels(tail)
            } else {
                corrected = try await LLMProvider.service.polish(tail, section: "live dictation tail")
            }
            let cleaned = LiveReportFormatter.format(corrected)
            guard !cleaned.isEmpty else { return }
            // Models often return the whole report. Never glue that onto the prefix.
            if prefix.isEmpty || cleaned.count > tail.count + 60 {
                apply(cleaned)
            } else {
                apply(prefix + cleaned)
            }
        } catch {
            // Keep the on-device formatted text if the model is busy or guarded.
        }
    }

    private func polishWithFoundationModels(_ tail: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return try await FoundationLivePolish.correct(tail)
        }
        #endif
        throw URLError(.unsupportedURL)
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
enum FoundationLivePolish {
    private static let instructions = """
        You are a radiology dictation editor. Correct speech-recognition errors, \
        punctuation, and section headings (Clinical History, Findings, Impression). \
        Use standard radiology terms. Do not add findings the speaker did not say. \
        Output only the corrected text.
        """

    static func prewarm() {
        guard case .available = SystemLanguageModel.default.availability else { return }
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
    }

    static func correct(_ tail: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: tail)
        return response.content
    }
}
#endif
