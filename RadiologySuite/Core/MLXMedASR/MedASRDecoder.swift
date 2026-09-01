import Foundation
import MLX

/// CTC greedy decoder for MedASR (SentencePiece pieces).
struct MedASRDecoder {
    let vocab: [Int: String]
    let vocabSize: Int

    static let blankId = 0
    static let bosId = 1
    static let eosId = 2
    static let unkId = 3
    private static let specialIds: Set<Int> = [blankId, bosId, eosId, unkId]

    init(tokenizerURL: URL) throws {
        let data = try Data(contentsOf: tokenizerURL)
        let json = try JSONSerialization.jsonObject(with: data)
        var tokenMap = [Int: String]()

        if let dict = json as? [String: Any] {
            if let model = dict["model"] as? [String: Any] {
                if let vocabArray = model["vocab"] as? [[Any]] {
                    for (id, entry) in vocabArray.enumerated() {
                        if let piece = entry.first as? String { tokenMap[id] = piece }
                    }
                } else if let vocabDict = model["vocab"] as? [String: Int] {
                    for (piece, id) in vocabDict { tokenMap[id] = piece }
                } else if let vocabDict = model["vocab"] as? [String: Any] {
                    for (piece, idValue) in vocabDict {
                        if let id = idValue as? Int { tokenMap[id] = piece }
                    }
                }
            }
            if tokenMap.isEmpty {
                for (k, v) in dict {
                    if let id = Int(k), let piece = v as? String {
                        tokenMap[id] = piece
                    }
                }
            }
        }

        if tokenMap.isEmpty {
            throw MedASRDecoderError.invalidTokenizer("Unable to read vocabulary")
        }
        vocabSize = (tokenMap.keys.max() ?? 511) + 1
        vocab = tokenMap
    }

    init(vocab: [Int: String]) {
        self.vocab = vocab
        self.vocabSize = (vocab.keys.max() ?? 511) + 1
    }

    func decode(_ logits: MLXArray) -> String {
        let predIds: MLXArray
        if logits.ndim == 3 {
            predIds = MLX.argMax(logits[0], axis: -1)
        } else {
            predIds = MLX.argMax(logits, axis: -1)
        }
        let numFrames = predIds.shape[0]
        let ids = (0..<numFrames).map { predIds[$0].item(Int.self) }
        return decodeIds(ids)
    }

    func decodeIds(_ ids: [Int]) -> String {
        var collapsed = [Int]()
        var prev = -1
        for id in ids {
            if id != prev {
                collapsed.append(id)
                prev = id
            }
        }
        let filtered = collapsed.filter { !Self.specialIds.contains($0) }
        let pieces = filtered.map { vocab[$0] ?? "" }
        var text = pieces.joined()
            .replacingOccurrences(of: "\u{2581}", with: " ")
            .trimmingCharacters(in: .whitespaces)

        let punctuation: [(String, String)] = [
            ("{ period }", "."), ("{ comma }", ","),
            ("{ colon }", ":"), ("{ new paragraph }", "\n\n"),
            ("{ new line }", "\n"), ("{ hyphen }", "-"),
            ("{period}", "."), ("{comma}", ","),
            ("{colon}", ":"), ("{new paragraph}", "\n\n"),
        ]
        for (token, repl) in punctuation {
            text = text.replacingOccurrences(of: token, with: repl, options: .caseInsensitive)
        }
        if let regex = try? NSRegularExpression(pattern: "\\{[^}]{0,40}\\}") {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        text = text.replacingOccurrences(of: "comma}", with: ",")
        text = text.replacingOccurrences(of: "period}", with: ".")
        return text
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .trimmingCharacters(in: .whitespaces)
    }
}

enum MedASRDecoderError: Error, LocalizedError {
    case invalidTokenizer(String)
    var errorDescription: String? {
        switch self {
        case .invalidTokenizer(let msg): return "Invalid tokenizer: \(msg)"
        }
    }
}
