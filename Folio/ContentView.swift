import AppKit
import SwiftUI

private struct TableEditorSession: Identifiable {
    let id = UUID()
    let candidates: [TableCandidate]
}

// NavigationSplitView + .listStyle(.sidebar) is the real native sidebar container, materials included.
private struct OutlineSidebarView: View {
    let headings: [HeadingItem]
    let currentHeadingID: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        List {
            if headings.isEmpty {
                Text("No headings")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(headings) { heading in
                    let isCurrent = heading.id == currentHeadingID
                    Button {
                        onSelect(heading.id)
                    } label: {
                        Text(heading.title)
                            .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background {
                                if isCurrent {
                                    RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    @Environment(UpdateStore.self) private var updateStore
    @Environment(SettingsStore.self) private var settingsStore
    @State private var zoom: CGFloat = 1.0
    @State private var isPreviewing: Bool
    @State private var editableTextView: MarkdownTextView?
    @State private var tableEditorSession: TableEditorSession?
    @State private var fileMonitor: FileChangeMonitor?
    @State private var lastKnownDiskText: String?
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var isFindBarVisible = false
    @State private var findState = FindState()
    @State private var scrollTarget: Int?
    @State private var scrollProgress: Double = 0
    @State private var visibleBlockID: Int?
    @State private var editCursorLocation: Int = 0
    @State private var editTextLength: Int = 0

    init(document: Binding<MarkdownDocument>, fileURL: URL?) {
        self._document = document
        self.fileURL = fileURL
        // No fileURL means a brand-new unsaved document — start it in edit mode, not previewing blank content.
        self._isPreviewing = State(initialValue: fileURL != nil)
    }

    private var finderIcon: NSImage {
        NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
    }

    private var exportBaseName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    private var wordCount: Int {
        document.text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var characterCount: Int {
        document.text.count
    }

    private var editProgress: Double {
        guard editTextLength > 0 else { return 0 }
        return min(max(Double(editCursorLocation) / Double(editTextLength), 0), 1)
    }

    private func themedFont(size: CGFloat) -> Font {
        settingsStore.fontFamily.isEmpty ? .system(size: size) : .custom(settingsStore.fontFamily, size: size)
    }

    private func startFileMonitoring() {
        guard let fileURL else { return }
        lastKnownDiskText = document.text
        fileMonitor = FileChangeMonitor(fileURL: fileURL) { newText in
            // Only reload if there are no unsaved local edits, so we never clobber active typing.
            guard document.text == lastKnownDiskText, newText != document.text else { return }
            document.text = newText
            lastKnownDiskText = newText
        }
    }

    private func currentHeadingID(in headings: [HeadingItem]) -> Int? {
        guard let visibleBlockID else { return nil }
        return headings.last(where: { $0.id <= visibleBlockID })?.id
    }

    var body: some View {
        let headings = HeadingParser.parse(document.text)

        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            OutlineSidebarView(headings: headings, currentHeadingID: currentHeadingID(in: headings)) { blockID in
                // Jumping from the outline always switches to preview — there's nothing to scroll to in edit mode.
                if !isPreviewing { isPreviewing = true }
                scrollTarget = blockID
            }
            .navigationSplitViewColumnWidth(220)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    if isPreviewing {
                        ScrollViewReader { proxy in
                            ScrollView {
                                MarkdownRenderer(markdown: document.text)
                                    .font(themedFont(size: settingsStore.baseFontSize * zoom))
                                    .foregroundStyle(settingsStore.theme.id == "system" ? Color.primary : settingsStore.theme.foreground)
                                    .environment(\.markdownFontScale, zoom)
                                    .environment(\.markdownTheme, settingsStore.theme)
                                    .environment(\.markdownFontFamily, settingsStore.fontFamily)
                                    .environment(\.markdownReadingWidth, CGFloat(settingsStore.readingWidth))
                                    .environment(\.markdownTableWidth, CGFloat(settingsStore.tableWidth))
                                    .environment(\.markdownHighlightBlockID, findState.highlightedBlockID)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(32)
                                    .textSelection(.enabled)
                                    .background(ScrollPositionObserver { progress in scrollProgress = progress })
                            }
                            .scrollPosition(id: $visibleBlockID, anchor: .top)
                            .background(settingsStore.theme.background)
                            .onTapGesture(count: 3) {
                                isPreviewing = false
                            }
                            .onChange(of: findState.highlightedBlockID) { _, blockID in
                                guard let blockID else { return }
                                withAnimation { proxy.scrollTo(blockID, anchor: .center) }
                            }
                            // .task also fires on first appearance, unlike onChange — needed since editing-to-preview jumps set scrollTarget before this view even exists.
                            .task(id: scrollTarget) {
                                guard let target = scrollTarget else { return }
                                withAnimation { proxy.scrollTo(target, anchor: .top) }
                                scrollTarget = nil
                            }
                            .overlay(alignment: .topTrailing) {
                                if isFindBarVisible {
                                    FindBar(state: findState) {
                                        isFindBarVisible = false
                                        findState.clear()
                                    }
                                }
                            }
                        }
                    } else {
                        MarkdownEditorView(
                            text: $document.text,
                            fontSize: (settingsStore.baseFontSize + 1) * zoom,
                            fontFamily: settingsStore.fontFamily,
                            theme: settingsStore.theme
                        ) { textView in
                            DispatchQueue.main.async {
                                editableTextView = textView
                            }
                        } onSelectionChange: { location, length in
                            editCursorLocation = location
                            editTextLength = length
                        }
                        .background(settingsStore.theme.background)
                    }
                }
                .background(WindowAppearanceSetter(colorScheme: settingsStore.theme.colorScheme))

                Divider()
                StatusBarView(
                    wordCount: wordCount,
                    characterCount: characterCount,
                    progress: isPreviewing ? scrollProgress : editProgress
                )
            }
        }
        .overlay(alignment: .top) {
            if updateStore.state != .none {
                UpdateBannerView(store: updateStore)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: updateStore.state)
        .onAppear {
            startFileMonitoring()
            if isPreviewing {
                findState.setContext(text: document.text, blockRanges: HeadingParser.blockRanges(in: document.text))
            }
        }
        .onChange(of: document.text) { _, newText in
            guard isPreviewing else { return }
            findState.setContext(text: newText, blockRanges: HeadingParser.blockRanges(in: newText))
        }
        .onChange(of: isPreviewing) { _, previewing in
            if previewing {
                findState.setContext(text: document.text, blockRanges: HeadingParser.blockRanges(in: document.text))
            } else {
                isFindBarVisible = false
                findState.clear()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .markdownDocumentDidSave)) { note in
            guard let text = note.userInfo?["text"] as? String, text == document.text else { return }
            lastKnownDiskText = text
        }
        .onReceive(NotificationCenter.default.publisher(for: .folioFindShow)) { _ in
            guard isPreviewing else { return }
            isFindBarVisible.toggle()
            if !isFindBarVisible { findState.clear() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .folioFindNext)) { _ in
            guard isPreviewing, isFindBarVisible else { return }
            findState.next()
        }
        .onReceive(NotificationCenter.default.publisher(for: .folioFindPrevious)) { _ in
            guard isPreviewing, isFindBarVisible else { return }
            findState.previous()
        }
        .sheet(item: $tableEditorSession) { session in
            TableEditorSheet(candidates: session.candidates) { edited in
                for candidate in edited.sorted(by: { $0.range.location > $1.range.location }) {
                    let text = MarkdownTableFormatter.serialize(candidate.table)
                    editableTextView?.replaceTableBlock(range: candidate.range, with: text)
                }
                tableEditorSession = nil
            } onCancel: {
                tableEditorSession = nil
            }
        }
        .toolbar {
            // Sidebar toggle button is automatic, courtesy of NavigationSplitView.
            ToolbarItemGroup {
                Button {
                    zoom = max(0.5, zoom - 0.1)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .keyboardShortcut("-", modifiers: .command)

                Button {
                    zoom = 1.0
                } label: {
                    Image(systemName: "1.magnifyingglass")
                }
                .keyboardShortcut("0", modifiers: .command)

                Button {
                    zoom = min(2.5, zoom + 0.1)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .keyboardShortcut("+", modifiers: .command)
            }

            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed)
            }


            ToolbarItemGroup {
                if isPreviewing {
                    Button {
                        isFindBarVisible.toggle()
                        if !isFindBarVisible { findState.clear() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .help("Find in Document")
                }
            }

            ToolbarItemGroup {
                if !isPreviewing {
                    Button {
                        let candidates = (editableTextView?.allTableBlocks() ?? []).compactMap { block -> TableCandidate? in
                            guard let parsed = MarkdownTableFormatter.parse(block.text) else { return nil }
                            return TableCandidate(range: block.range, table: parsed)
                        }
                        guard !candidates.isEmpty else { return }
                        tableEditorSession = TableEditorSession(candidates: candidates)
                    } label: {
                        Image(systemName: "tablecells")
                    }
                    .help("Edit Table")
                }

                Button {
                    isPreviewing.toggle()
                } label: {
                    Image(systemName: isPreviewing ? "pencil" : "eye")
                }
                .keyboardShortcut("e", modifiers: .command)
                .help(isPreviewing ? "Edit" : "Preview")

                Menu {
                    Button("Export as HTML…") {
                        ExportManager.exportHTML(markdown: document.text, suggestedName: exportBaseName)
                    }
                    Button("Export as PDF…") {
                        ExportManager.exportPDF(markdown: document.text, suggestedName: exportBaseName)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up.on.square")
                }
                .help("Export")

                if let fileURL {
                    Menu {
                        ForEach(ExternalEditor.allCases, id: \.self) { editor in
                            if editor.appURL != nil {
                                Button {
                                    editor.open(fileURL)
                                } label: {
                                    Label {
                                        Text(editor.title)
                                    } icon: {
                                        if let icon = editor.icon {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .frame(width: 16, height: 16)
                                        }
                                    }
                                }
                            }
                        }
                        Divider()
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                        } label: {
                            Label {
                                Text("Reveal in Finder")
                            } icon: {
                                Image(nsImage: finderIcon)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.forward.app")
                            Divider()
                                .frame(height: 14)
                        }
                    }
                }
            }

            ToolbarItemGroup {
                if let fileURL {
                    ShareLink(item: fileURL)
                }
            }
        }
    }
}

/// SwiftUI's `.preferredColorScheme(nil)` doesn't reliably revert a window's effective
/// appearance after a previous non-nil value forced it (a known SwiftUI/AppKit sync bug) —
/// switching a themed doc back to "System" left the window stuck dark, making `.primary` text
/// invisible against the now-light background. Setting `NSWindow.appearance` directly instead
/// is unaffected by that bug: it's a plain AppKit property write, always applied fresh.
struct WindowAppearanceSetter: NSViewRepresentable {
    let colorScheme: ColorScheme?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { apply(to: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSView) {
        guard let window = view.window else { return }
        switch colorScheme {
        case .dark:
            window.appearance = NSAppearance(named: .darkAqua)
        case .light:
            window.appearance = NSAppearance(named: .aqua)
        default:
            // Setting `.appearance = nil` (defer to the system) doesn't reliably force AppKit to
            // re-derive and repaint after a previous explicit assignment — the window can stay
            // stuck on the old appearance. Assigning an explicit appearance that matches the
            // current system setting is just as correct and, unlike nil, always triggers a
            // real change notification.
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        }
    }
}
