//
//  XMLTreeView.swift
//  Refiner
//

import SwiftUI

struct XMLNode: Identifiable {
    let id = UUID()
    let tagName: String
    var attributes: [String: String]
    var children: [XMLNode]
    var textContent: String

    var isBranch: Bool {
        !children.isEmpty
    }

    var collapsedPreview: String {
        if !children.isEmpty {
            let tags = children.prefix(3).map { $0.tagName }
            let suffix = children.count > 3 ? ", ..." : ""
            return tags.joined(separator: ", ") + suffix
        } else if !textContent.isEmpty {
            let truncated = textContent.count > 40
                ? String(textContent.prefix(40)) + "..."
                : textContent
            return truncated
        }
        return ""
    }
}

class XMLTreeParser: NSObject, XMLParserDelegate {
    private var stack: [XMLNode] = []
    private var root: XMLNode?

    static func parse(_ text: String) -> XMLNode? {
        guard let data = text.data(using: .utf8) else { return nil }
        let parser = Foundation.XMLParser(data: data)
        let delegate = XMLTreeParser()
        parser.delegate = delegate
        return parser.parse() ? delegate.root : nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let node = XMLNode(tagName: elementName, attributes: attributeDict, children: [], textContent: "")
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let lastIndex = stack.indices.last else { return }
        stack[lastIndex].textContent += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard var finished = stack.popLast() else { return }
        finished.textContent = finished.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lastIndex = stack.indices.last {
            stack[lastIndex].children.append(finished)
        } else {
            root = finished
        }
    }
}

struct XMLTreeView: View {
    let root: XMLNode
    let defaultExpansionDepth: Int

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                XMLRowView(node: root, depth: 0, defaultExpansionDepth: defaultExpansionDepth)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
    }
}

struct XMLRowView: View {
    let node: XMLNode
    let depth: Int
    let defaultExpansionDepth: Int
    @State private var isExpanded: Bool
    @State private var isHovered = false

    init(node: XMLNode, depth: Int, defaultExpansionDepth: Int = 2) {
        self.node = node
        self.depth = depth
        self.defaultExpansionDepth = defaultExpansionDepth
        self._isExpanded = State(initialValue: depth < defaultExpansionDepth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if node.isBranch && isExpanded {
                ForEach(node.children) { child in
                    XMLRowView(node: child, depth: depth + 1, defaultExpansionDepth: defaultExpansionDepth)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var row: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: CGFloat(depth) * 16, height: 1)
            chevron
            content
            Spacer(minLength: 0)
        }
        .frame(minHeight: 24)
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contentShape(Rectangle())
        .if(node.isBranch) { view in
            view
                .onHover { isHovered = $0 }
                .onTapGesture {
                    withAnimation(.spring(duration: 0.25, bounce: 0.0)) {
                        isExpanded.toggle()
                    }
                }
        }
    }

    private var chevron: some View {
        Group {
            if node.isBranch {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(duration: 0.25, bounce: 0.0), value: isExpanded)
            } else {
                Color.clear
            }
        }
        .frame(width: 16, height: 16)
    }

    @ViewBuilder
    private var content: some View {
        if node.isBranch {
            branchContent
        } else if node.textContent.isEmpty {
            selfClosingTag
        } else {
            leafWithText
        }
    }

    private var branchContent: some View {
        HStack(spacing: 2) {
            Text("<").foregroundStyle(.secondary)
            Text(node.tagName).foregroundStyle(.blue)
            attributesView
            Text(">").foregroundStyle(.secondary)
            if !isExpanded {
                Text(node.collapsedPreview).foregroundStyle(.secondary)
                Text("</").foregroundStyle(.secondary)
                Text(node.tagName).foregroundStyle(.blue)
                Text(">").foregroundStyle(.secondary)
            }
        }
    }

    private var selfClosingTag: some View {
        HStack(spacing: 2) {
            Text("<").foregroundStyle(.secondary)
            Text(node.tagName).foregroundStyle(.blue)
            attributesView
            Text("/>").foregroundStyle(.secondary)
        }
    }

    private var leafWithText: some View {
        HStack(spacing: 2) {
            Text("<").foregroundStyle(.secondary)
            Text(node.tagName).foregroundStyle(.blue)
            attributesView
            Text(">").foregroundStyle(.secondary)
            Text(node.textContent)
            Text("</").foregroundStyle(.secondary)
            Text(node.tagName).foregroundStyle(.blue)
            Text(">").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var attributesView: some View {
        ForEach(Array(node.attributes.keys.sorted()), id: \.self) { key in
            Text(" \(key)=").foregroundStyle(.purple)
            Text("\"\(node.attributes[key] ?? "")\"").foregroundStyle(.green)
        }
    }
}
