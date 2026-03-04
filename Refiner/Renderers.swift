//
//  Renderers.swift
//  Refiner
//

import SwiftUI

enum Renderers {

    // MARK: - JSON

    static func renderJSON(_ text: String) -> AttributedString {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else {
            return AttributedString(text)
        }
        return colorizeJSON(str)
    }

    private static func colorizeJSON(_ text: String) -> AttributedString {
        colorize(text, patterns: [
            (#""[^"]*"\s*:"#, .blue),     // keys (quoted string followed by colon)
            (#""[^"]*""#, .green),         // string values
            (#"\b\d+\.?\d*\b"#, .orange),  // numbers
            (#"\b(true|false)\b"#, .purple), // booleans
            (#"\bnull\b"#, .gray),         // null
        ])
    }

    // MARK: - XML

    static func renderXML(_ text: String) -> AttributedString {
        let indented = indentXML(text)
        return colorizeXML(indented)
    }

    private static func indentXML(_ text: String) -> String {
        var result = ""
        var depth = 0
        let stripped = text.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")

        guard let regex = try? NSRegularExpression(pattern: #"(<[^>]+>|[^<]+)"#) else { return text }
        let range = NSRange(stripped.startIndex..., in: stripped)

        for match in regex.matches(in: stripped, range: range) {
            guard let r = Range(match.range, in: stripped) else { continue }
            let token = String(stripped[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { continue }

            if token.hasPrefix("</") {
                depth = max(0, depth - 1)
                result += String(repeating: "  ", count: depth) + token + "\n"
            } else if token.hasPrefix("<") && token.hasSuffix("/>") {
                result += String(repeating: "  ", count: depth) + token + "\n"
            } else if token.hasPrefix("<") && !token.hasPrefix("<?") && !token.hasPrefix("<!") {
                result += String(repeating: "  ", count: depth) + token + "\n"
                depth += 1
            } else {
                result += String(repeating: "  ", count: depth) + token + "\n"
            }
        }
        return result
    }

    private static func colorizeXML(_ text: String) -> AttributedString {
        colorize(text, patterns: [
            (#"</?[\w:-]+"#, .blue),       // tag names
            (#">"#, .blue),                // closing bracket
            (#"/>"#, .blue),               // self-closing
            (#"\b[\w:-]+="#, .purple),      // attribute names
            (#""[^"]*""#, .green),         // attribute values
        ])
    }

    // MARK: - Markdown

    static func renderMarkdown(_ text: String) -> AttributedString {
        if let md = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return md
        }
        return AttributedString(text)
    }

    // MARK: - CSV

    static func detectCSVDelimiter(in lines: [String], sampleCount: Int = 5) -> Character? {
        let delimiters: [Character] = [",", "\t", ";"]
        for d in delimiters {
            let counts = lines.prefix(sampleCount).map { $0.filter { $0 == d }.count }
            if let first = counts.first, first > 0, counts.allSatisfy({ $0 == first }) {
                return d
            }
        }
        return nil
    }

    static func csvRows(_ text: String) -> [[String]] {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let delimiter = detectCSVDelimiter(in: lines) ?? ","
        return lines.map { $0.split(separator: delimiter, omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) } }
    }

    // MARK: - Code

    static func renderCode(_ text: String) -> AttributedString {
        colorize(text, patterns: [
            (#"//.*$"#, .gray),                // line comments
            (#"/\*[\s\S]*?\*/"#, .gray),       // block comments
            (#"#.*$"#, .gray),                 // hash comments
            (#""[^"\n]*""#, .green),           // double-quoted strings
            (#"'[^'\n]*'"#, .green),           // single-quoted strings
            (#"\b\d+\.?\d*\b"#, .orange),      // numbers
            (#"\b(func|function|class|struct|enum|protocol|import|var|let|const|return|if|else|for|while|switch|case|break|continue|def|self|Self|nil|None|true|false|public|private|internal|static|override|guard|throw|throws|try|catch|async|await)\b"#, .purple),
        ], options: .anchorsMatchLines)
    }

    // MARK: - Shared colorizer

    private static func colorize(_ text: String, patterns: [(String, Color)], options: NSRegularExpression.Options = []) -> AttributedString {
        var colored = [(Range<String.Index>, Color)]()
        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { continue }
            let nsRange = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: nsRange) {
                if let r = Range(match.range, in: text) {
                    let overlaps = colored.contains { $0.0.overlaps(r) }
                    if !overlaps { colored.append((r, color)) }
                }
            }
        }

        var result = AttributedString()
        var pos = text.startIndex
        let sorted = colored.sorted { $0.0.lowerBound < $1.0.lowerBound }
        for (range, color) in sorted {
            if pos < range.lowerBound {
                result += AttributedString(text[pos..<range.lowerBound])
            }
            var part = AttributedString(text[range])
            part.foregroundColor = color
            result += part
            pos = range.upperBound
        }
        if pos < text.endIndex {
            result += AttributedString(text[pos...])
        }

        result.font = .system(.body, design: .monospaced)
        return result
    }

    // MARK: - Plain

    static func renderPlain(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        result.font = .system(.body)
        return result
    }
}
