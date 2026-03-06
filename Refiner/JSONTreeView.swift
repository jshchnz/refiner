//
//  JSONTreeView.swift
//  Refiner
//

import SwiftUI

struct JSONNode: Identifiable {
    let id = UUID()
    let key: String?
    let kind: Kind

    enum Kind {
        case object([JSONNode])
        case array([JSONNode])
        case string(String)
        case number(String)
        case bool(Bool)
        case null
    }

    var isBranch: Bool {
        switch kind {
        case .object, .array: return true
        default: return false
        }
    }

    var children: [JSONNode] {
        switch kind {
        case .object(let c), .array(let c): return c
        default: return []
        }
    }

    var collapsedPreview: String {
        switch kind {
        case .object(let children):
            let keys = children.prefix(3).compactMap { $0.key }
            let suffix = children.count > 3 ? ", ..." : ""
            return "{ " + keys.joined(separator: ", ") + suffix + " }"
        case .array(let children):
            let vals = children.prefix(3).map { $0.inlineValue }
            let suffix = children.count > 3 ? ", ..." : ""
            return "[ " + vals.joined(separator: ", ") + suffix + " ]"
        default: return inlineValue
        }
    }

    var inlineValue: String {
        switch kind {
        case .string(let v): return "\"\(v)\""
        case .number(let v): return v
        case .bool(let v): return v ? "true" : "false"
        case .null: return "null"
        case .object(let c): return "{\(c.count)}"
        case .array(let c): return "[\(c.count)]"
        }
    }

    static func parse(_ text: String) -> JSONNode? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return fromAny(key: nil, value: obj)
    }

    /// True if this node is an array containing at least one object child.
    var isTabularArray: Bool {
        guard case .array(let children) = kind else { return false }
        return !children.isEmpty && children.contains {
            if case .object = $0.kind { return true }
            return false
        }
    }

    /// Union of all keys across object children, in first-seen order.
    var tableColumns: [String] {
        guard case .array(let children) = kind else { return [] }
        var seen = Set<String>()
        var columns: [String] = []
        for child in children {
            guard case .object(let props) = child.kind else { continue }
            for prop in props {
                if let key = prop.key, !seen.contains(key) {
                    seen.insert(key)
                    columns.append(key)
                }
            }
        }
        return columns
    }

    private static func fromAny(key: String?, value: Any) -> JSONNode {
        switch value {
        case let dict as [String: Any]:
            let children = dict.keys.sorted().compactMap { k -> JSONNode? in
                guard let value = dict[k] else { return nil }
                return fromAny(key: k, value: value)
            }
            return JSONNode(key: key, kind: .object(children))

        case let arr as [Any]:
            let children = arr.enumerated().map { i, v in
                fromAny(key: "[\(i)]", value: v)
            }
            return JSONNode(key: key, kind: .array(children))

        case let num as NSNumber:
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return JSONNode(key: key, kind: .bool(num.boolValue))
            }
            return JSONNode(key: key, kind: .number(num.description))

        case let str as String:
            return JSONNode(key: key, kind: .string(str))

        default:
            return JSONNode(key: key, kind: .null)
        }
    }
}

struct JSONTreeView: View {
    let root: JSONNode
    let defaultExpansionDepth: Int

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                JSONRowView(node: root, depth: 0, defaultExpansionDepth: defaultExpansionDepth)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
    }
}

struct JSONRowView: View {
    let node: JSONNode
    let depth: Int
    let defaultExpansionDepth: Int
    @State private var isExpanded: Bool
    @State private var isHovered = false

    init(node: JSONNode, depth: Int, defaultExpansionDepth: Int = 2) {
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
                    JSONRowView(node: child, depth: depth + 1, defaultExpansionDepth: defaultExpansionDepth)
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
        switch node.kind {
        case .object, .array:
            branchContent
        case .string(let val):
            HStack(spacing: 2) {
                keyLabel
                Text("\"\(val)\"").foregroundStyle(.green)
            }
        case .number(let val):
            HStack(spacing: 2) {
                keyLabel
                Text(val).foregroundStyle(.orange)
            }
        case .bool(let val):
            HStack(spacing: 2) {
                keyLabel
                Text(val ? "true" : "false").foregroundStyle(.purple)
            }
        case .null:
            HStack(spacing: 2) {
                keyLabel
                Text("null").foregroundStyle(.gray)
            }
        }
    }

    private var branchContent: some View {
        HStack(spacing: 2) {
            keyLabel
            if isExpanded {
                switch node.kind {
                case .object: Text("{").foregroundStyle(.secondary)
                case .array: Text("[").foregroundStyle(.secondary)
                default: EmptyView()
                }
            } else {
                Text(node.collapsedPreview).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var keyLabel: some View {
        if let key = node.key {
            Text(key + ": ").foregroundStyle(.blue)
        }
    }
}
