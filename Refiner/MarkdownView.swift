//
//  MarkdownView.swift
//  Refiner
//

import SwiftUI

// MARK: - Model

struct MarkdownBlock: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case unorderedList(items: [MarkdownListItem])
        case orderedList(items: [MarkdownListItem])
        case blockquote(blocks: [MarkdownBlock])
        case codeBlock(language: String?, code: String)
        case horizontalRule
        case image(alt: String, url: String)
    }
}

struct MarkdownListItem: Identifiable {
    let id = UUID()
    let text: String
    let children: [MarkdownListItem]
}

// MARK: - Parser

enum MarkdownParser {

    private enum State {
        case normal
        case fencedCode(language: String?, lines: [String])
    }

    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var state = State.normal
        var paragraphBuffer: [String] = []
        var i = 0

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let text = paragraphBuffer.joined(separator: "\n")
            blocks.append(MarkdownBlock(kind: .paragraph(text: text)))
            paragraphBuffer.removeAll()
        }

        while i < lines.count {
            let line = lines[i]

            switch state {
            case .fencedCode(let language, var codeLines):
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    let code = codeLines.joined(separator: "\n")
                    blocks.append(MarkdownBlock(kind: .codeBlock(language: language, code: code)))
                    state = .normal
                } else {
                    codeLines.append(line)
                    state = .fencedCode(language: language, lines: codeLines)
                }
                i += 1

            case .normal:
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // 1. Empty line
                if trimmed.isEmpty {
                    flushParagraph()
                    i += 1
                    continue
                }

                // 2. Fenced code opening
                if trimmed.hasPrefix("```") {
                    flushParagraph()
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    state = .fencedCode(language: lang.isEmpty ? nil : lang, lines: [])
                    i += 1
                    continue
                }

                // 3. Horizontal rule
                if matchesHorizontalRule(trimmed) {
                    flushParagraph()
                    blocks.append(MarkdownBlock(kind: .horizontalRule))
                    i += 1
                    continue
                }

                // 4. Heading
                if let (level, text) = matchHeading(trimmed) {
                    flushParagraph()
                    blocks.append(MarkdownBlock(kind: .heading(level: level, text: text)))
                    i += 1
                    continue
                }

                // 5. Image (standalone line)
                if let (alt, url) = matchImage(trimmed) {
                    flushParagraph()
                    blocks.append(MarkdownBlock(kind: .image(alt: alt, url: url)))
                    i += 1
                    continue
                }

                // 6. Unordered list
                if matchesUnorderedListItem(line) {
                    flushParagraph()
                    let (items, nextIndex) = consumeUnorderedList(lines: lines, from: i)
                    blocks.append(MarkdownBlock(kind: .unorderedList(items: items)))
                    i = nextIndex
                    continue
                }

                // 7. Ordered list
                if matchesOrderedListItem(line) {
                    flushParagraph()
                    let (items, nextIndex) = consumeOrderedList(lines: lines, from: i)
                    blocks.append(MarkdownBlock(kind: .orderedList(items: items)))
                    i = nextIndex
                    continue
                }

                // 8. Blockquote
                if trimmed.hasPrefix(">") {
                    flushParagraph()
                    let (quoteBlocks, nextIndex) = consumeBlockquote(lines: lines, from: i)
                    blocks.append(MarkdownBlock(kind: .blockquote(blocks: quoteBlocks)))
                    i = nextIndex
                    continue
                }

                // 9. Default → paragraph buffer
                paragraphBuffer.append(line)
                i += 1
            }
        }

        // Flush any remaining state
        switch state {
        case .fencedCode(let language, let codeLines):
            let code = codeLines.joined(separator: "\n")
            blocks.append(MarkdownBlock(kind: .codeBlock(language: language, code: code)))
        case .normal:
            flushParagraph()
        }

        return blocks
    }

    // MARK: - Matchers

    private static func matchesHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let chars = Set(trimmed.filter { !$0.isWhitespace })
        return chars.count == 1 && (chars.contains("-") || chars.contains("*") || chars.contains("_"))
    }

    private static func matchHeading(_ trimmed: String) -> (Int, String)? {
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6, trimmed.count > level else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.first == " " else { return nil }
        return (level, String(rest).trimmingCharacters(in: .whitespaces))
    }

    private static func matchImage(_ trimmed: String) -> (String, String)? {
        guard trimmed.hasPrefix("![") else { return nil }
        guard let closeBracket = trimmed.firstIndex(of: "]"),
              trimmed.index(after: closeBracket) < trimmed.endIndex,
              trimmed[trimmed.index(after: closeBracket)] == "(" else { return nil }
        let alt = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<closeBracket])
        let urlStart = trimmed.index(closeBracket, offsetBy: 2)
        guard let closeParen = trimmed.lastIndex(of: ")") else { return nil }
        let url = String(trimmed[urlStart..<closeParen]).trimmingCharacters(in: .whitespaces)
        return (alt, url)
    }

    private static let unorderedListRegex = try! NSRegularExpression(pattern: #"^(\s*)([-*+])\s+"#)
    private static let orderedListRegex = try! NSRegularExpression(pattern: #"^(\s*)(\d+)\.\s+"#)

    private static func matchesUnorderedListItem(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..., in: line)
        return unorderedListRegex.firstMatch(in: line, range: range) != nil
    }

    private static func matchesOrderedListItem(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..., in: line)
        return orderedListRegex.firstMatch(in: line, range: range) != nil
    }

    // MARK: - List consumption

    private static func consumeUnorderedList(lines: [String], from start: Int) -> ([MarkdownListItem], Int) {
        consumeList(lines: lines, from: start, itemPattern: #"^(\s*)([-*+])\s+(.*)$"#)
    }

    private static func consumeOrderedList(lines: [String], from start: Int) -> ([MarkdownListItem], Int) {
        consumeList(lines: lines, from: start, itemPattern: #"^(\s*)(\d+)\.\s+(.*)$"#)
    }

    private static func consumeList(lines: [String], from start: Int, itemPattern: String) -> ([MarkdownListItem], Int) {
        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern) else {
            return ([], start)
        }
        var i = start
        var flat: [(indent: Int, text: String)] = []

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }

            let range = NSRange(line.startIndex..., in: line)
            if let match = itemRegex.firstMatch(in: line, range: range),
               let indentRange = Range(match.range(at: 1), in: line),
               let textRange = Range(match.range(at: 3), in: line) {
                flat.append((indent: String(line[indentRange]).count, text: String(line[textRange])))
            } else if !flat.isEmpty {
                // Continuation line — append to last item
                flat[flat.count - 1].text += " " + trimmed
            } else {
                break
            }
            i += 1
        }

        return (buildListTree(flat: flat, index: 0, minIndent: 0).items, i)
    }

    private static func buildListTree(flat: [(indent: Int, text: String)], index: Int, minIndent: Int) -> (items: [MarkdownListItem], nextIndex: Int) {
        var items: [MarkdownListItem] = []
        var i = index

        while i < flat.count {
            let (indent, text) = flat[i]
            if indent < minIndent { break }
            i += 1

            // Collect children at deeper indent
            let (children, nextI) = buildListTree(flat: flat, index: i, minIndent: indent + 1)
            items.append(MarkdownListItem(text: text, children: children))
            i = nextI
        }

        return (items, i)
    }

    // MARK: - Blockquote consumption

    private static func consumeBlockquote(lines: [String], from start: Int) -> ([MarkdownBlock], Int) {
        var i = start
        var quoteLines: [String] = []

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") {
                var stripped = String(trimmed.dropFirst())
                if stripped.hasPrefix(" ") { stripped = String(stripped.dropFirst()) }
                quoteLines.append(stripped)
            } else if trimmed.isEmpty && !quoteLines.isEmpty {
                // Blank line might continue the blockquote if the next line is also a quote
                if i + 1 < lines.count && lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quoteLines.append("")
                } else {
                    break
                }
            } else {
                break
            }
            i += 1
        }

        let inner = quoteLines.joined(separator: "\n")
        return (parse(inner), i)
    }
}

// MARK: - Inline rendering helper

private func renderInline(_ text: String) -> AttributedString {
    if let md = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
        return md
    }
    return AttributedString(text)
}

// MARK: - Views

struct MarkdownView: View {
    let text: String

    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(text)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(blocks) { block in
                    MarkdownBlockView(block: block)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block.kind {
        case .heading(let level, let text):
            headingView(level: level, text: text)

        case .paragraph(let text):
            Text(renderInline(text))
                .font(.body)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                    MarkdownListItemView(item: item, ordered: false, index: 0, depth: 0)
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    MarkdownListItemView(item: item, ordered: true, index: index, depth: 0)
                }
            }

        case .blockquote(let blocks):
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(blocks) { inner in
                        MarkdownBlockView(block: inner)
                    }
                }
                .padding(.leading, 12)
            }
            .padding(.vertical, 4)
            .padding(.trailing, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 4))

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

        case .horizontalRule:
            Divider()

        case .image(let alt, _):
            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                Text(alt.isEmpty ? "Image" : alt)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func headingView(level: Int, text: String) -> some View {
        Text(renderInline(text))
            .font(headingFont(level))
            .fontWeight(.bold)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        case 4: return .headline
        case 5: return .subheadline
        default: return .footnote
        }
    }
}

struct MarkdownListItemView: View {
    let item: MarkdownListItem
    let ordered: Bool
    let index: Int
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Color.clear.frame(width: CGFloat(depth) * 16, height: 1)
                Text(ordered ? "\(index + 1)." : "\u{2022}")
                    .foregroundStyle(.secondary)
                Text(renderInline(item.text))
            }
            ForEach(Array(item.children.enumerated()), id: \.element.id) { childIndex, child in
                MarkdownListItemView(item: child, ordered: ordered, index: childIndex, depth: depth + 1)
            }
        }
    }
}
