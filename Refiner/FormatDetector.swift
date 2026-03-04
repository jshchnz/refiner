//
//  FormatDetector.swift
//  Refiner
//

import Foundation

struct DetectionResult {
    let format: TextFormat
    let autoFixedJSON: String?  // non-nil only when repair was applied
}

enum TextFormat: String, CaseIterable {
    case json = "JSON"
    case xml = "XML"
    case csv = "CSV"
    case markdown = "Markdown"
    case code = "Code"
    case plain = "Plain"

    static func detect(_ text: String) -> TextFormat {
        detect(text, autoFixJSON: false).format
    }

    static func detect(_ text: String, autoFixJSON: Bool) -> DetectionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return DetectionResult(format: .plain, autoFixedJSON: nil) }

        // 1. JSON
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return DetectionResult(format: .json, autoFixedJSON: nil)
        }

        // 1b. Auto-fix JSON
        if autoFixJSON, let repaired = JSONRepair.repair(trimmed) {
            return DetectionResult(format: .json, autoFixedJSON: repaired)
        }

        // 2. XML
        if trimmed.hasPrefix("<") {
            let tagPattern = #"<(\w+)[\s>]"#
            let closePattern = #"</(\w+)>"#
            let openTags = matches(for: tagPattern, in: trimmed)
            let closeTags = matches(for: closePattern, in: trimmed)
            if !openTags.isEmpty && !closeTags.isEmpty {
                return DetectionResult(format: .xml, autoFixedJSON: nil)
            }
        }

        // 3. CSV
        let lines = trimmed.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if lines.count >= 3, Renderers.detectCSVDelimiter(in: lines) != nil {
            return DetectionResult(format: .csv, autoFixedJSON: nil)
        }

        // 4. Markdown
        var mdScore = 0
        let mdPatterns = [
            #"^#{1,6}\s"#,        // headings
            #"^[-*+]\s"#,         // unordered lists
            #"^\d+\.\s"#,         // ordered lists
            #"\[.+\]\(.+\)"#,     // links
            #"```"#,              // code fences
            #"\*\*.+\*\*"#,       // bold
            #"_.+_"#,             // italic
        ]
        for pattern in mdPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                mdScore += 1
            }
        }
        if mdScore >= 2 { return DetectionResult(format: .markdown, autoFixedJSON: nil) }

        // 5. Code
        let codeKeywords = ["func ", "function ", "class ", "import ", "var ", "let ", "const ",
                            "return ", "if ", "else ", "for ", "while ", "switch ", "case ",
                            "struct ", "enum ", "def ", "public ", "private ", "static "]
        let keywordCount = codeKeywords.reduce(0) { count, kw in
            count + (trimmed.contains(kw) ? 1 : 0)
        }
        let braceCount = trimmed.filter { $0 == "{" || $0 == "}" }.count
        if keywordCount >= 2 || (keywordCount >= 1 && braceCount >= 2) {
            return DetectionResult(format: .code, autoFixedJSON: nil)
        }

        return DetectionResult(format: .plain, autoFixedJSON: nil)
    }

    private static func matches(for pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
