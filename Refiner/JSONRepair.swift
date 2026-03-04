//
//  JSONRepair.swift
//  Refiner
//

import Foundation

enum JSONRepair {
    /// Attempts to repair common JSON errors using a recursive descent parser.
    /// Returns the fixed string only if it parses as valid JSON.
    static func repair(_ text: String) -> String? {
        var parser = Parser(text)
        guard parser.parse() else { return nil }
        let result = parser.output
        // Final validation
        guard let data = result.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return nil
        }
        return result
    }
}

// MARK: - Recursive Descent Parser

private struct Parser {
    let chars: [Character]
    var i: Int = 0
    var output: String = ""

    init(_ text: String) {
        self.chars = Array(text)
    }

    // MARK: - Entry Point

    mutating func parse() -> Bool {
        skipWhitespaceAndComments()
        let ok = parseValue()
        skipWhitespaceAndComments()
        // If there's trailing content that looks like another value, ignore it
        return ok
    }

    // MARK: - Value Dispatch

    mutating func parseValue() -> Bool {
        skipWhitespaceAndComments()
        guard i < chars.count else { return false }

        let c = chars[i]
        if c == "{" { return parseObject() }
        if c == "[" { return parseArray() }
        if c == "\"" { return parseString() }
        if c == "'" { return parseString() }
        if c == "-" || c.isNumber { return parseNumber() }
        if parseKeyword() { return true }
        // Try unquoted string as a value
        return parseUnquotedString()
    }

    // MARK: - Object

    mutating func parseObject() -> Bool {
        guard i < chars.count, chars[i] == "{" else { return false }
        output.append("{")
        i += 1
        skipWhitespaceAndComments()

        var needsComma = false

        while i < chars.count, chars[i] != "}" {
            skipWhitespaceAndComments()
            if i < chars.count, chars[i] == "}" { break }

            // Handle trailing comma before }
            if i < chars.count, chars[i] == "," {
                i += 1
                skipWhitespaceAndComments()
                if i < chars.count, chars[i] == "}" { break }
                if needsComma {
                    output.append(",")
                }
                needsComma = false
            }

            // Insert missing comma between properties
            if needsComma {
                output.append(",")
            }

            // Parse key
            skipWhitespaceAndComments()
            guard i < chars.count else { break }

            if !parseObjectKey() {
                break
            }

            // Expect colon
            skipWhitespaceAndComments()
            if i < chars.count, chars[i] == ":" {
                output.append(":")
                i += 1
            } else {
                // Insert missing colon
                output.append(":")
            }

            // Parse value
            skipWhitespaceAndComments()
            if i >= chars.count || chars[i] == "}" || chars[i] == "," {
                // Missing value — insert null
                output.append("null")
            } else {
                if !parseValue() {
                    output.append("null")
                }
            }

            needsComma = true
            skipWhitespaceAndComments()
        }

        if i < chars.count, chars[i] == "}" {
            i += 1
        }
        // else: missing closing brace — we append it
        output.append("}")
        return true
    }

    // MARK: - Object Key

    mutating func parseObjectKey() -> Bool {
        guard i < chars.count else { return false }
        let c = chars[i]

        if c == "\"" || c == "'" {
            return parseString()
        }

        // Unquoted key — collect until colon, whitespace, or end
        var key = ""
        while i < chars.count {
            let ch = chars[i]
            if ch == ":" || ch == "{" || ch == "}" || ch == "[" || ch == "]" || ch == "," {
                break
            }
            if ch.isWhitespace || ch.isNewline {
                break
            }
            key.append(ch)
            i += 1
        }
        guard !key.isEmpty else { return false }
        output.append("\"")
        output.append(escapeStringContents(key))
        output.append("\"")
        return true
    }

    // MARK: - Array

    mutating func parseArray() -> Bool {
        guard i < chars.count, chars[i] == "[" else { return false }
        output.append("[")
        i += 1
        skipWhitespaceAndComments()

        var needsComma = false

        while i < chars.count, chars[i] != "]" {
            skipWhitespaceAndComments()
            if i < chars.count, chars[i] == "]" { break }

            // Handle comma
            if i < chars.count, chars[i] == "," {
                i += 1
                skipWhitespaceAndComments()
                if i < chars.count, chars[i] == "]" { break } // trailing comma
                if needsComma {
                    output.append(",")
                }
                needsComma = false
            }

            if needsComma {
                output.append(",")
            }

            skipWhitespaceAndComments()
            if i >= chars.count || chars[i] == "]" { break }

            if !parseValue() {
                break
            }

            needsComma = true
            skipWhitespaceAndComments()
        }

        if i < chars.count, chars[i] == "]" {
            i += 1
        }
        output.append("]")
        return true
    }

    // MARK: - String

    mutating func parseString() -> Bool {
        guard i < chars.count else { return false }
        let quote = chars[i]
        guard quote == "\"" || quote == "'" else { return false }
        i += 1
        output.append("\"")

        while i < chars.count {
            let c = chars[i]

            // Backslash escape
            if c == "\\" {
                if i + 1 < chars.count {
                    let next = chars[i + 1]
                    if "\"\\/'bfnrtu".contains(next) {
                        if next == "'" {
                            output.append("'")
                            i += 2
                        } else {
                            output.append("\\")
                            output.append(next)
                            i += 2
                        }
                    } else {
                        output.append("\\\\")
                        i += 1
                    }
                    continue
                } else {
                    i += 1
                    continue
                }
            }

            // Matching closing quote
            if c == quote {
                // Check if this is really the closing quote or an embedded one.
                // If followed by a valid JSON structural continuation → closing quote.
                // Otherwise → embedded quote, escape it.
                if looksLikeStringEnd(at: i + 1) {
                    i += 1
                    output.append("\"")
                    return true
                } else {
                    // Embedded unescaped quote — escape it
                    output.append("\\\"")
                    i += 1
                    continue
                }
            }

            // A double quote inside a single-quoted string — escape it
            if c == "\"" && quote == "'" {
                output.append("\\\"")
                i += 1
                continue
            }

            // Heuristic: comma followed by what looks like an object property
            // means the string was supposed to end before the comma
            if c == "," && looksLikeObjectProperty(at: i + 1) {
                output.append("\"")
                return true // don't consume the comma
            }

            // Unescaped control characters
            if let ascii = c.asciiValue, ascii < 0x20 {
                if c == "\n" {
                    output.append("\\n")
                } else if c == "\r" {
                    output.append("\\r")
                } else if c == "\t" {
                    output.append("\\t")
                } else {
                    output.append(String(format: "\\u%04x", ascii))
                }
                i += 1
                continue
            }

            output.append(c)
            i += 1
        }

        // Reached end of input without closing quote — close it
        output.append("\"")
        return true
    }

    /// After a potential closing quote at position `pos`, does the remaining text
    /// look like valid JSON continuation? (comma, colon, closing bracket, EOF, etc.)
    func looksLikeStringEnd(at pos: Int) -> Bool {
        var j = pos
        // Skip whitespace
        while j < chars.count && (chars[j].isWhitespace || chars[j].isNewline) { j += 1 }
        if j >= chars.count { return true } // EOF is valid
        let c = chars[j]
        return c == "," || c == ":" || c == "}" || c == "]" || c == "/"
    }

    /// Starting at `pos`, does the text look like `"key":` or `key:` (an object property)?
    func looksLikeObjectProperty(at pos: Int) -> Bool {
        var j = pos
        // Skip whitespace
        while j < chars.count && (chars[j].isWhitespace || chars[j].isNewline) { j += 1 }
        guard j < chars.count else { return false }

        if chars[j] == "\"" || chars[j] == "'" {
            // Quoted key — find closing quote
            let q = chars[j]
            j += 1
            while j < chars.count && chars[j] != q {
                if chars[j] == "\\" { j += 1 } // skip escaped char
                j += 1
            }
            guard j < chars.count else { return false }
            j += 1 // skip closing quote
        } else if chars[j].isLetter || chars[j] == "_" {
            // Unquoted key
            while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_") { j += 1 }
        } else {
            return false
        }

        // Skip whitespace, expect colon
        while j < chars.count && (chars[j].isWhitespace || chars[j].isNewline) { j += 1 }
        return j < chars.count && chars[j] == ":"
    }

    // MARK: - Number

    mutating func parseNumber() -> Bool {
        guard i < chars.count else { return false }
        let start = i

        if chars[i] == "-" { i += 1 }

        guard i < chars.count, chars[i].isNumber else {
            i = start
            return false
        }

        while i < chars.count, chars[i].isNumber { i += 1 }

        // Decimal
        if i < chars.count, chars[i] == "." {
            i += 1
            while i < chars.count, chars[i].isNumber { i += 1 }
        }

        // Exponent
        if i < chars.count, (chars[i] == "e" || chars[i] == "E") {
            i += 1
            if i < chars.count, (chars[i] == "+" || chars[i] == "-") { i += 1 }
            while i < chars.count, chars[i].isNumber { i += 1 }
        }

        let numStr = String(chars[start..<i])
        output.append(numStr)
        return true
    }

    // MARK: - Keywords

    mutating func parseKeyword() -> Bool {
        // JSON keywords
        let mappings: [(String, String)] = [
            ("true", "true"),
            ("false", "false"),
            ("null", "null"),
            ("True", "true"),
            ("False", "false"),
            ("None", "null"),
            ("undefined", "null"),
            ("NaN", "null"),
            ("Infinity", "null"),
            ("-Infinity", "null"),
        ]

        for (keyword, replacement) in mappings {
            if matchKeyword(keyword) {
                output.append(replacement)
                return true
            }
        }
        return false
    }

    mutating func matchKeyword(_ keyword: String) -> Bool {
        let keyChars = Array(keyword)
        guard i + keyChars.count <= chars.count else { return false }
        for j in 0..<keyChars.count {
            if chars[i + j] != keyChars[j] { return false }
        }
        // Must be followed by a non-alphanumeric character (word boundary)
        let afterIdx = i + keyChars.count
        if afterIdx < chars.count {
            let after = chars[afterIdx]
            if after.isLetter || after.isNumber || after == "_" {
                return false
            }
        }
        i += keyChars.count
        return true
    }

    // MARK: - Unquoted String

    mutating func parseUnquotedString() -> Bool {
        guard i < chars.count else { return false }
        let c = chars[i]
        // Don't treat structural characters as unquoted strings
        if c == "," || c == ":" || c == "}" || c == "]" || c == "{" || c == "[" {
            return false
        }

        var value = ""
        while i < chars.count {
            let ch = chars[i]
            if ch == "," || ch == "}" || ch == "]" || ch == ":" || ch == "{" || ch == "[" {
                break
            }
            if ch == "\n" || ch == "\r" {
                break
            }
            value.append(ch)
            i += 1
        }
        value = value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return false }

        output.append("\"")
        output.append(escapeStringContents(value))
        output.append("\"")
        return true
    }

    // MARK: - Whitespace & Comments

    mutating func skipWhitespaceAndComments() {
        while i < chars.count {
            let c = chars[i]

            // Whitespace
            if c.isWhitespace || c.isNewline {
                i += 1
                continue
            }

            // Single-line comment
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                i += 2
                while i < chars.count && chars[i] != "\n" {
                    i += 1
                }
                continue
            }

            // Block comment
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                i += 2
                while i < chars.count {
                    if chars[i] == "*" && i + 1 < chars.count && chars[i + 1] == "/" {
                        i += 2
                        break
                    }
                    i += 1
                }
                continue
            }

            break
        }
    }

    // MARK: - Helpers

    func escapeStringContents(_ s: String) -> String {
        var result = ""
        for c in s {
            switch c {
            case "\"": result.append("\\\"")
            case "\\": result.append("\\\\")
            case "\n": result.append("\\n")
            case "\r": result.append("\\r")
            case "\t": result.append("\\t")
            default:
                if let ascii = c.asciiValue, ascii < 0x20 {
                    result.append(String(format: "\\u%04x", ascii))
                } else {
                    result.append(c)
                }
            }
        }
        return result
    }
}
