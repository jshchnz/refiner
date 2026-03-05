//
//  ContentView.swift
//  Refiner
//

import SwiftUI
import AppKit

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
    @EnvironmentObject private var openFileController: OpenFileController
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
    @State private var hasNonWhitespaceContent = false
    @State private var textRevision: Int = 0
    @State private var externalTextToken: Int = 0
    @State private var isLoadingFile = false
    @State private var fileLoadError: String?

    private var detectedFormat: TextFormat {
        detectionResult.format
    }

    private var hasContent: Bool {
        hasNonWhitespaceContent
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

                    Button {
                        openFileFromDisk()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Open File")

                    if hasContent {
                        if detectionResult.autoFixedJSON != nil {
                            Button {
                                if let original = preFixText {
                                    isApplyingFix = false
                                    preFixText = nil
                                    externalTextToken += 1
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

                    if showTreeControls {
                        Button {
                            treeExpansionDepth = .max; treeRevision = UUID(); expandAllBounce += 1
                        } label: {
                            Image(systemName: "chevron.down")
                                .symbolEffect(.bounce, value: expandAllBounce)
                        }
                        .buttonStyle(.borderless)
                        .help("Expand All")

                        Button {
                            treeExpansionDepth = 0; treeRevision = UUID(); collapseAllBounce += 1
                        } label: {
                            Image(systemName: "chevron.right")
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
                        EditorTextView(text: $inputText, isEditable: true, useMonospaceFont: true, externalTextToken: externalTextToken)
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
                                EditorTextView(text: $inputText, isEditable: true, useMonospaceFont: true, externalTextToken: externalTextToken)
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
        .background(.ultraThinMaterial)
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
        .onChange(of: inputText) { _, newValue in
            let previousHasContent = hasNonWhitespaceContent
            let newHasContent = containsNonWhitespace(newValue)

            textRevision += 1
            hasNonWhitespaceContent = newHasContent
            treeExpansionDepth = 2
            treeRevision = UUID()

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
                externalTextToken += 1
                inputText = fixed
            }

            if selectedTab == .raw && !previousHasContent && newHasContent {
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
                    externalTextToken += 1
                    inputText = fixed
                }
            }
        }
        .onAppear {
            hasNonWhitespaceContent = containsNonWhitespace(inputText)
            consumePendingOpenFileRequest()
        }
        .onChange(of: openFileController.requestID) { _, _ in
            consumePendingOpenFileRequest()
        }
        .alert("Couldn’t open file", isPresented: Binding(
            get: { fileLoadError != nil },
            set: { if !$0 { fileLoadError = nil } }
        )) {
            Button("OK", role: .cancel) { fileLoadError = nil }
        } message: {
            Text(fileLoadError ?? "Unknown error")
        }
        .overlay {
            if isLoadingFile {
                ProgressView("Loading file…")
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func containsNonWhitespace(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
    }

    private func consumePendingOpenFileRequest() {
        guard openFileController.consumePendingRequest() else { return }
        openFileFromDisk()
    }

    private func openFileFromDisk() {
        let appDelegate = NSApp.delegate as? AppDelegate
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"

        defer {
            appDelegate?.setPresentingModalPanel(false)
        }

        guard panel.runModal() == .OK, let fileURL = panel.url else {
            return
        }

        isLoadingFile = true
        Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                let loadedText = String(decoding: data, as: UTF8.self)
                await MainActor.run {
                    externalTextToken += 1
                    inputText = loadedText
                    isLoadingFile = false
                }
            } catch {
                await MainActor.run {
                    isLoadingFile = false
                    fileLoadError = error.localizedDescription
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
        if !hasContent {
            ContentUnavailableView("No Content", systemImage: "doc.text", description: Text("Type or paste some text"))
        } else if detectedFormat == .json, let root = JSONNode.parse(detectionResult.autoFixedJSON ?? inputText) {
            JSONTreeView(root: root, defaultExpansionDepth: treeExpansionDepth).id(treeRevision)
        } else if detectedFormat == .xml, let root = XMLTreeParser.parse(inputText) {
            XMLTreeView(root: root, defaultExpansionDepth: treeExpansionDepth).id(treeRevision)
        } else if detectedFormat == .csv {
            csvView
        } else if detectedFormat == .markdown {
            MarkdownView(text: inputText)
        } else if detectedFormat == .plain {
            EditorTextView(text: .constant(inputText), isEditable: false, useMonospaceFont: false, externalTextToken: textRevision)
                .padding(8)
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

struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let useMonospaceFont: Bool
    let externalTextToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.allowsUndo = isEditable
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.font = useMonospaceFont ? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) : .systemFont(ofSize: NSFont.systemFontSize)
        textView.string = text

        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.layoutManager?.backgroundLayoutEnabled = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }

        let font = useMonospaceFont ? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) : NSFont.systemFont(ofSize: NSFont.systemFontSize)
        if textView.font != font {
            textView.font = font
        }

        if context.coordinator.lastAppliedExternalTextToken != externalTextToken {
            textView.string = text
            context.coordinator.lastAppliedExternalTextToken = externalTextToken
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: EditorTextView
        var lastAppliedExternalTextToken: Int

        init(_ parent: EditorTextView) {
            self.parent = parent
            self.lastAppliedExternalTextToken = parent.externalTextToken
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(OpenFileController())
}
