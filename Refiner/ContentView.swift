//
//  ContentView.swift
//  Refiner
//

import SwiftUI

enum ViewMode: String, CaseIterable {
    case raw = "Raw"
    case formatted = "Formatted"
    case sideBySide = "Side by Side"
}

struct SlidingCapsulePicker: View {
    @Binding var selection: ViewMode
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Text(mode.rawValue)
                    .font(.subheadline)
                    .fontWeight(selection == mode ? .semibold : .regular)
                    .foregroundStyle(selection == mode ? .primary : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        if selection == mode {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(.white.opacity(0.15))
                                .matchedGeometryEffect(id: "tab", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = mode }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(0.06))
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selection)
    }
}

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var inputText = ""
    @State private var selectedTab: ViewMode = .raw
    @State private var treeExpansionDepth: Int = 2
    @State private var treeRevision: UUID = UUID()
    @State private var expandAllBounce: Int = 0
    @State private var collapseAllBounce: Int = 0
    @State private var showCopyCheckmark = false
    @AppStorage("autoFixJSON") private var autoFixJSON = false
    @State private var detectionResult = DetectionResult(format: .plain, autoFixedJSON: nil)
    @State private var preFixText: String?
    @State private var isApplyingFix = false
    @AppStorage("jsonViewStyle") private var jsonViewStyle: JSONViewStyle = .tree

    enum JSONViewStyle: String { case tree, flatTable }

    private var detectedFormat: TextFormat {
        detectionResult.format
    }

    private var hasContent: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showTreeControls: Bool {
        (selectedTab == .formatted || selectedTab == .sideBySide)
        && (detectedFormat == .json || detectedFormat == .xml)
        && hasContent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Inline toolbar
            ZStack {
                // Centered picker
                SlidingCapsulePicker(selection: $selectedTab)

                // Right-aligned items
                HStack(spacing: 12) {
                    Spacer()

                    if hasContent {
                        if detectionResult.autoFixedJSON != nil {
                            Button {
                                if let original = preFixText {
                                    isApplyingFix = false
                                    preFixText = nil
                                    inputText = original
                                    detectionResult = TextFormat.detect(original, autoFixJSON: false)
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.uturn.backward")
                                    Text("Revert")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("Revert to original text before auto-fix")
                        }

                        if detectedFormat == .json {
                            Menu {
                                Button {
                                    jsonViewStyle = .tree
                                } label: {
                                    if jsonViewStyle == .tree { Image(systemName: "checkmark") }
                                    Text("Tree View")
                                }
                                Button {
                                    jsonViewStyle = .flatTable
                                } label: {
                                    if jsonViewStyle == .flatTable { Image(systemName: "checkmark") }
                                    Text("Table View")
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(jsonViewStyle == .tree ? "JSON Tree" : "JSON Table")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    if detectionResult.autoFixedJSON != nil {
                                        Text("Auto-fixed")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .contentTransition(.interpolate)
                        } else {
                            HStack(spacing: 4) {
                                Text(detectedFormat.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                if detectionResult.autoFixedJSON != nil {
                                    Text("Auto-fixed")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .contentTransition(.interpolate)
                        }
                    }

                    if (selectedTab == .formatted || selectedTab == .sideBySide) && hasContent {
                        Button {
                            copyFormattedOutput()
                        } label: {
                            Image(systemName: showCopyCheckmark ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.borderless)
                        .help("Copy Formatted Output")
                    }

                    if showTreeControls && jsonViewStyle == .tree {
                        Button {
                            treeExpansionDepth = .max; treeRevision = UUID(); expandAllBounce += 1
                        } label: {
                            Image(systemName: "arrow.down.left.and.arrow.up.right")
                                .symbolEffect(.bounce, value: expandAllBounce)
                        }
                        .buttonStyle(.borderless)
                        .help("Expand All")

                        Button {
                            treeExpansionDepth = 0; treeRevision = UUID(); collapseAllBounce += 1
                        } label: {
                            Image(systemName: "arrow.up.right.and.arrow.down.left")
                                .symbolEffect(.bounce, value: collapseAllBounce)
                        }
                        .buttonStyle(.borderless)
                        .help("Collapse All")
                    }

                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Content area
            Group {
                switch selectedTab {
                case .raw:
                    if preFixText != nil {
                        diffHighlightedView
                            .transition(.opacity)
                    } else {
                        TextEditor(text: $inputText)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .transition(.opacity)
                    }

                case .formatted:
                    formattedView
                        .transition(.opacity)

                case .sideBySide:
                    HSplitView {
                        Group {
                            if preFixText != nil {
                                diffHighlightedView
                            } else {
                                TextEditor(text: $inputText)
                                    .font(.system(.body, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                            }
                        }
                        .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
                        formattedView
                            .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Hidden buttons for keyboard shortcuts
            hiddenShortcuts
        }
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            if !hasCompletedOnboarding {
                OnboardingView {
                    withAnimation(.easeOut(duration: 0.3)) {
                        hasCompletedOnboarding = true
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.opacity)
            }
        }
        .onChange(of: inputText) { oldValue, newValue in
            treeExpansionDepth = 2; treeRevision = UUID()
            if isApplyingFix {
                isApplyingFix = false
                return
            }
            preFixText = nil
            let result = TextFormat.detect(newValue, autoFixJSON: autoFixJSON)
            detectionResult = result
            if let fixed = result.autoFixedJSON {
                preFixText = newValue
                isApplyingFix = true
                inputText = fixed
            }
            if selectedTab == .raw
                && oldValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedTab = .formatted
            }
        }
        .onChange(of: autoFixJSON) {
            if !autoFixJSON {
                preFixText = nil
                detectionResult = TextFormat.detect(inputText, autoFixJSON: false)
            } else {
                let result = TextFormat.detect(inputText, autoFixJSON: true)
                detectionResult = result
                if let fixed = result.autoFixedJSON {
                    preFixText = inputText
                    isApplyingFix = true
                    inputText = fixed
                }
            }
        }
    }

    // MARK: - Keyboard Shortcuts

    @ViewBuilder
    private var hiddenShortcuts: some View {
        HStack(spacing: 0) {
            Button("") { selectedTab = .raw }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { selectedTab = .formatted }
                .keyboardShortcut("2", modifiers: .command)
            Button("") { selectedTab = .sideBySide }
                .keyboardShortcut("3", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - Copy

    private func copyFormattedOutput() {
        let output: String
        let jsonSource = detectionResult.autoFixedJSON ?? inputText
        if detectedFormat == .json,
           let data = jsonSource.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: pretty, encoding: .utf8) {
            output = str
        } else {
            output = inputText
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        showCopyCheckmark = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopyCheckmark = false
        }
    }

    // MARK: - Diff Highlighted View

    @ViewBuilder
    private var diffHighlightedView: some View {
        ScrollView {
            Text(diffAttributedString)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
    }

    private var diffAttributedString: AttributedString {
        guard let original = preFixText else { return AttributedString(inputText) }
        let oldChars = Array(original)
        let newChars = Array(inputText)
        let diff = newChars.difference(from: oldChars)

        var insertedIndices = Set<Int>()
        for change in diff {
            switch change {
            case .insert(let offset, _, _):
                insertedIndices.insert(offset)
            default:
                break
            }
        }

        var result = AttributedString()
        for (i, char) in newChars.enumerated() {
            var part = AttributedString(String(char))
            if insertedIndices.contains(i) {
                part.foregroundColor = .teal
                part.backgroundColor = .teal.opacity(0.15)
            }
            result.append(part)
        }
        return result
    }

    // MARK: - Formatted View

    @ViewBuilder
    private var formattedView: some View {
        if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView("No Content", systemImage: "doc.text", description: Text("Type or paste some text"))
        } else if detectedFormat == .json, let root = JSONNode.parse(detectionResult.autoFixedJSON ?? inputText) {
            if jsonViewStyle == .flatTable {
                JSONFlatTableView(root: root).id(treeRevision)
            } else {
                JSONTreeView(root: root, defaultExpansionDepth: treeExpansionDepth).id(treeRevision)
            }
        } else if detectedFormat == .xml, let root = XMLTreeParser.parse(inputText) {
            XMLTreeView(root: root, defaultExpansionDepth: treeExpansionDepth).id(treeRevision)
        } else if detectedFormat == .csv {
            csvView
        } else if detectedFormat == .markdown {
            MarkdownView(text: inputText)
        } else {
            ScrollView {
                Text(renderedText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    private var renderedText: AttributedString {
        switch detectedFormat {
        case .code:  Renderers.renderCode(inputText)
        default:     Renderers.renderPlain(inputText)
        }
    }

    private var csvView: some View {
        let rows = Renderers.csvRows(inputText)
        return ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .fontWeight(rowIdx == 0 ? .bold : .regular)
                                .textSelection(.enabled)
                                .padding(.vertical, 4)
                        }
                    }
                    .background(rowIdx > 0 && rowIdx % 2 == 0 ? Color.primary.opacity(0.04) : Color.clear)
                    if rowIdx == 0 {
                        Divider()
                    }
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
