import Foundation

/// Instant, on-device report shaping & speech cleanup (Wispr Flow style).
/// Strips conversational fillers (e.g. "kya bolte hain", "uh", "you know"),
/// resolves self-corrections, formats units, and normalizes standard headings.
enum LiveReportFormatter {
    private static let conversationalFillers: [String] = [
        "kya bolte hain",
        "kya bolte hai",
        "kya kehte hain",
        "kya kehte hai",
        "matlab ki",
        "yani ki",
        "matlab",
        "samjho ki",
        "samjho",
        "you know",
        "sort of",
        "kind of",
        "scratch that",
        "strike that",
        "wait wait",
        "uhm",
        "umm",
        "um",
        "uh",
        "ahh",
        "ah"
    ]

    private static let lexicon: [(String, String)] = [
        ("cardio pulmonary", "cardiopulmonary"),
        ("costo phrenic", "costophrenic"),
        ("pneumo thorax", "pneumothorax"),
        ("pleural effusion", "pleural effusion"),
        ("x ray", "X-ray"),
        ("chest x-ray", "chest X-ray"),
        ("bi basilar", "bibasilar"),
        ("atelecta sis", "atelectasis"),
        ("mediastinal contours", "mediastinal contours"),
        ("no acute cardio pulmonary process", "no acute cardiopulmonary process"),
        ("impresion", "impression"),
        ("millimeter", "mm"),
        ("millimeters", "mm"),
        ("centimeter", "cm"),
        ("centimeters", "cm"),
        ("c m", "cm"),
        ("m m", "mm"),
        ("c t", "CT"),
        ("m r i", "MRI"),
        ("u s g", "USG")
    ]

    private static let headingMap: [(spoken: String, titled: String)] = [
        ("clinical history", "Clinical History"),
        ("indication", "Indication"),
        ("technique", "Technique"),
        ("comparison", "Comparison"),
        ("findings", "Findings"),
        ("impression", "Impression"),
        ("history", "History"),
    ]

    static func format(_ raw: String) -> String {
        var text = raw

        // 1. Strip conversational fillers and hesitations
        for filler in conversationalFillers {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: filler))\\b"
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        // 2. Resolve self-corrections (e.g., "in left... sorry I mean right" -> "in right")
        let correctionPatterns = [
            "(?i)\\b(?:sorry\\s+I\\s+mean|no\\s+I\\s+mean|actually\\s+I\\s+mean|wait\\s+no|actually)\\s+",
            "(?i)\\b(?:scratch\\s+that|strike\\s+that)\\s*"
        ]
        for pattern in correctionPatterns {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        // 3. Clean up spacing and punctuation glitches
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+,", with: ",", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+\\.", with: ".", options: .regularExpression)
        text = text.replacingOccurrences(of: ",+", with: ",", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\.{2,}", with: ".", options: .regularExpression)

        // 4. Lexicon replacement
        for (wrong, right) in lexicon {
            text = text.replacingOccurrences(of: wrong, with: right, options: .caseInsensitive)
        }

        // 5. Headings
        for (spoken, titled) in headingMap {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: spoken))\\b"
            text = text.replacingOccurrences(of: pattern, with: titled, options: [.regularExpression, .caseInsensitive])
        }

        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return capitalizeSentences(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitalizeSentences(_ text: String) -> String {
        var chars = Array(text)
        var capNext = true
        for i in chars.indices {
            if chars[i].isNewline || chars[i] == "." {
                capNext = true
                continue
            }
            if capNext, chars[i].isLetter {
                chars[i] = Character(String(chars[i]).uppercased())
                capNext = false
            } else if !chars[i].isWhitespace {
                capNext = false
            }
        }
        return String(chars)
    }
}

