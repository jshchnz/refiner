//
//  JSONTableView.swift
//  Refiner
//

import SwiftUI

// MARK: - Flattened Key-Value Table (works for any JSON shape)

struct JSONFlatTableView: View {
    let root: JSONNode

    var body: some View {
        let pairs = flatten(node: root)

        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Key")
                        .fontWeight(.bold)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                    Text("Value")
                        .fontWeight(.bold)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                Divider()

                ForEach(Array(pairs.enumerated()), id: \.offset) { rowIdx, pair in
                    GridRow {
                        Text(pair.key)
                            .foregroundStyle(.blue)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                        leafView(for: pair.node)
                            .padding(.vertical, 4)
                    }
                    .background(rowIdx % 2 == 1 ? Color.primary.opacity(0.04) : Color.clear)
                }
            }
            .padding()
        }
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
    }

    private func flatten(node: JSONNode, prefix: String = "") -> [(key: String, node: JSONNode)] {
        switch node.kind {
        case .object(let children):
            return children.flatMap { child -> [(key: String, node: JSONNode)] in
                let childKey = child.key ?? ""
                let newPrefix = prefix.isEmpty ? childKey : prefix + "." + childKey
                return flatten(node: child, prefix: newPrefix)
            }
        case .array(let children):
            return children.enumerated().flatMap { i, child -> [(key: String, node: JSONNode)] in
                let newPrefix = prefix + "[\(i)]"
                return flatten(node: child, prefix: newPrefix)
            }
        default:
            let key = prefix.isEmpty ? "(root)" : prefix
            return [(key: key, node: node)]
        }
    }

    @ViewBuilder
    private func leafView(for node: JSONNode) -> some View {
        switch node.kind {
        case .string(let v):
            Text("\"\(v)\"").foregroundStyle(.green)
        case .number(let v):
            Text(v).foregroundStyle(.orange)
        case .bool(let v):
            Text(v ? "true" : "false").foregroundStyle(.purple)
        case .null:
            Text("null").foregroundStyle(.gray)
        default:
            Text(node.collapsedPreview).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tabular Array Table (legacy)

struct JSONTableView: View {
    let root: JSONNode

    var body: some View {
        let columns = root.tableColumns
        let rows = tableRows(columns: columns)

        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    ForEach(columns, id: \.self) { col in
                        Text(col)
                            .fontWeight(.bold)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                }
                Divider()

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    GridRow {
                        ForEach(columns, id: \.self) { col in
                            cellView(for: row[col] ?? nil)
                                .padding(.vertical, 4)
                        }
                    }
                    .background(rowIdx % 2 == 1 ? Color.primary.opacity(0.04) : Color.clear)
                }
            }
            .padding()
        }
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
    }

    private func tableRows(columns: [String]) -> [[String: JSONNode?]] {
        guard case .array(let children) = root.kind else { return [] }
        return children.map { child in
            var row: [String: JSONNode?] = [:]
            for col in columns {
                if case .object(let props) = child.kind {
                    row[col] = props.first(where: { $0.key == col })
                } else {
                    row[col] = nil
                }
            }
            return row
        }
    }

    @ViewBuilder
    private func cellView(for node: JSONNode?) -> some View {
        if let node = node {
            switch node.kind {
            case .string(let v):
                Text(v).foregroundStyle(.green)
            case .number(let v):
                Text(v).foregroundStyle(.orange)
            case .bool(let v):
                Text(v ? "true" : "false").foregroundStyle(.purple)
            case .null:
                Text("null").foregroundStyle(.gray)
            case .object, .array:
                Text(node.collapsedPreview)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text("-")
                .foregroundStyle(.quaternary)
        }
    }
}
