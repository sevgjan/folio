import AppKit
import Markdown
import SwiftUI

private struct TableEditorSession: Identifiable {
    let id = UUID()
    let source: String
    let candidates: [TableCandidate]
}

// NavigationSplitView + .listStyle(.sidebar) is the real native sidebar container, materials included.
private struct OutlineSidebarView: View {
    let headings: [HeadingItem]
    let visibleBlockTracker: VisibleBlockTracker
    let onSelect: (Int) -> Void

    // Reading visibleBlockTracker.blockID here (not in ContentView) keeps the scroll-driven
    // dependency local to this view — see VisibleBlockTracker's comment.
    private var currentHeadingID: Int? {
        guard let blockID = visibleBlockTracker.blockID else { return nil }
        return headings.last(where: { $0.id <= blockID })?.id
    }

    var body: some View {
        List {
            if headings.isEmpty {
                SwiftUI.Text("No headings")
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
    @State private var snapshot: MarkdownSnapshot
    @State private var focusBlock: Int?
    @State private var showSource = false
    @State private var tableSession: TableEditorSession?
    @State private var showExternalVersion = false
    @State private var externalText: String?
    @State private var fileMonitor: FileChangeMonitor?
    @State private var lastKnownDiskText: String?
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var isFindBarVisible = false
    @State private var findState = FindState()
    @State private var scrollTarget: Int?
    @State private var scrollTracker = ScrollProgressTracker()
    @State private var visibleBlockTracker = VisibleBlockTracker()
    private var headings: [HeadingItem] {
        snapshot.document.children.enumerated().compactMap { index, block in
            guard let heading = block as? Heading, let range = snapshot.range(heading) else { return nil }
            return HeadingItem(id: index, level: heading.level, title: heading.plainText, sourceRange: range)
        }
    }

    init(document: Binding<MarkdownDocument>, fileURL: URL?) {
        self._document = document
        self.fileURL = fileURL
        self._snapshot = State(initialValue: MarkdownSnapshot(document.wrappedValue.text))
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

    private func startFileMonitoring() {
        fileMonitor?.stop()
        fileMonitor = nil
        externalText = nil
        guard let fileURL else { return }
        lastKnownDiskText = try? String(contentsOf: fileURL, encoding: .utf8)
        if let lastKnownDiskText { document.revision.accept(lastKnownDiskText) }
        fileMonitor = FileChangeMonitor(fileURL: fileURL) { newText in
            if newText == document.text || document.revision.knows(newText) {
                document.revision.accept(newText)
                lastKnownDiskText = newText
                externalText = nil
            } else if document.text == lastKnownDiskText {
                document.revision.accept(newText)
                document.text = newText
                lastKnownDiskText = newText
                externalText = nil
            } else {
                document.revision.recordConflict(newText)
                externalText = newText
            }
        }
    }

    private func replace(_ expected: String, _ replacements: [MarkdownReplacement]) -> Bool {
        guard document.text == expected else { return false }
        let result = NSMutableString(string: expected)
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            guard NSMaxRange(replacement.range) <= result.length else { return false }
            result.replaceCharacters(in: replacement.range, with: replacement.text)
        }
        let updated = result as String
        if updated != expected { document.text = updated }
        return true
    }

    private func showTableEditor() {
        func candidates(in node: Markup) -> [TableCandidate] {
            if node is Markdown.Table, let range = snapshot.range(node),
               let table = MarkdownTableFormatter.parse((snapshot.source as NSString).substring(with: range)) {
                return [TableCandidate(range: range, table: table)]
            }
            return node.children.flatMap(candidates)
        }
        let tables = candidates(in: snapshot.document)
        if !tables.isEmpty { tableSession = TableEditorSession(source: snapshot.source, candidates: tables) }
    }

    private func toggleEditing() {
        focusBlock = isPreviewing ? visibleBlockTracker.blockID ?? 0 : nil
        isPreviewing.toggle()
    }

    private func zoomIn() { zoom = min(2.5, zoom + 0.1) }
    private func zoomOut() { zoom = max(0.5, zoom - 0.1) }
    private func resetZoom() { zoom = 1 }

    private func refreshFind() {
        findState.setContext(snapshot)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            OutlineSidebarView(headings: headings, visibleBlockTracker: visibleBlockTracker) { blockID in
                scrollTarget = blockID
            }
            .navigationSplitViewColumnWidth(220)
        } detail: {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        if snapshot.document.isEmpty {
                            InlineText(children: [], emptySource: snapshot.document)
                                .centeredReadingColumn(maxWidth: settingsStore.readingWidth)
                                .environment(\.markdownBlockIndex, 0)
                                .padding(32)
                        } else {
                            MarkdownRenderer(snapshot: snapshot)
                                .padding(32)
                                .background(ScrollPositionObserver { progress in scrollTracker.progress = progress })
                        }
                    }
                    .environment(\.markdownEditing, MarkdownEditing(snapshot: snapshot, isEditing: !isPreviewing,
                                                                     focusBlock: focusBlock, replace: replace))
                    .environment(\.markdownFontScale, zoom)
                    .environment(\.markdownBodySize, settingsStore.baseFontSize * zoom)
                    .environment(\.markdownTheme, settingsStore.theme)
                    .environment(\.markdownFontFamily, settingsStore.fontFamily)
                    .environment(\.markdownReadingWidth, settingsStore.readingWidth)
                    .environment(\.markdownTableWidth, settingsStore.tableWidth)
                    .environment(\.markdownBaseURL, fileURL?.deletingLastPathComponent())
                    .environment(\.markdownHighlightQuery, isFindBarVisible ? findState.normalizedQuery : nil)
                    .environment(\.markdownActiveMatch, isFindBarVisible ? findState.activeMatch : nil)
                    .foregroundStyle(settingsStore.theme.id == "system" ? Color.primary : settingsStore.theme.foreground)
                    .background(settingsStore.theme.background)
                    .modifier(ReadingProgressObserver(tracker: scrollTracker))
                    .scrollPosition(
                        id: Binding(get: { visibleBlockTracker.blockID }, set: { visibleBlockTracker.blockID = $0 }),
                        anchor: .top
                    )
                    .onChange(of: findState.activeMatch) { _, match in
                        guard let match else { return }
                        proxy.scrollTo(match.block, anchor: .center)
                    }
                    .task(id: scrollTarget) {
                        guard let target = scrollTarget else { return }
                        proxy.scrollTo(target, anchor: .top)
                        scrollTarget = nil
                    }
                    .overlay(alignment: .topTrailing) {
                        if isFindBarVisible {
                            FindBar(state: findState) { isFindBarVisible = false }
                        }
                    }
                }
                .background(WindowAppearanceSetter(colorScheme: settingsStore.theme.colorScheme))

                Divider()
                StatusBarView(
                    wordCount: wordCount,
                    characterCount: characterCount,
                    scrollTracker: scrollTracker
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if externalText != nil {
                HStack {
                    Label("File Changed on Disk", systemImage: "exclamationmark.circle")
                    Spacer()
                    Button("Review…") { showExternalVersion = true }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            }
        }
        .animation(.spring(duration: 0.3), value: updateStore.state)
        .task(id: fileURL) { startFileMonitoring() }
        .onAppear { refreshFind() }
        .onDisappear { fileMonitor?.stop(); fileMonitor = nil }
        .onChange(of: document.text) { _, newText in
            snapshot = MarkdownSnapshot(newText)
            refreshFind()
        }
        .focusedSceneValue(\.folioFind, FindCommands(
            toggleEditing: toggleEditing,
            zoomIn: zoomIn, zoomOut: zoomOut, resetZoom: resetZoom,
            show: { isFindBarVisible = true },
            next: { isFindBarVisible = true; findState.next() },
            previous: { isFindBarVisible = true; findState.previous() }
        ))
        .sheet(item: $tableSession) { session in
            TableEditorSheet(candidates: session.candidates) { changes in
                let original = session.source as NSString
                let operations = changes.flatMap { change in
                    MarkdownTableFormatter.replacements(in: original.substring(with: change.range),
                                                        at: change.range.location, with: change.table)
                }
                if replace(session.source, operations) { tableSession = nil }
                else { NSSound.beep() }
            } onCancel: {
                tableSession = nil
            }
        }
        .sheet(isPresented: $showSource) {
            VStack(alignment: .trailing, spacing: 0) {
                MarkdownEditorView(text: $document.text, fontSize: settingsStore.baseFontSize * zoom,
                                   fontFamily: settingsStore.fontFamily, theme: settingsStore.theme,
                                   onTextViewReady: { _ in }, onSelectionChange: { _, _ in })
                Divider()
                Button("Done") { showSource = false }.keyboardShortcut(.defaultAction).padding()
            }
            .frame(minWidth: 620, minHeight: 440)
        }
        .sheet(isPresented: $showExternalVersion) {
            VStack(alignment: .leading, spacing: 16) {
                SwiftUI.Text("The file changed on disk").font(.headline)
                SwiftUI.Text("Save your edits to a new file to keep both versions.")
                HStack {
                    Button("Cancel") { showExternalVersion = false }
                    Button("Reload Disk Version", role: .destructive) {
                        if let externalText {
                            document.revision.accept(externalText)
                            document.text = externalText
                            lastKnownDiskText = externalText
                        }
                        externalText = nil
                        showExternalVersion = false
                    }
                    Button("Save Local Copy…") {
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = exportBaseName + " (Folio edits).md"
                        guard panel.runModal() == .OK, let url = panel.url else { return }
                        guard url.resolvingSymlinksInPath() != fileURL?.resolvingSymlinksInPath() else {
                            NSApp.presentError(CocoaError(.fileWriteFileExists, userInfo: [
                                NSLocalizedDescriptionKey: "Choose a different location to keep both versions."
                            ]))
                            return
                        }
                        do {
                            try document.text.write(to: url, atomically: true, encoding: .utf8)
                            if let externalText {
                                document.revision.accept(externalText)
                                document.text = externalText
                                lastKnownDiskText = externalText
                            }
                            externalText = nil
                            showExternalVersion = false
                        } catch { NSApp.presentError(error) }
                    }
                }
            }.padding(24)
        }
        .toolbar(id: "folio.document.toolbar.v2") {
            ToolbarItem(id: "mode") {
                Picker("Mode", selection: Binding(get: { isPreviewing }, set: { if $0 != isPreviewing { toggleEditing() } })) {
                    SwiftUI.Text("Read").tag(true)
                    SwiftUI.Text("Edit").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItem(id: "find") {
                Button {
                    isFindBarVisible.toggle()
                } label: {
                    Label("Find in Document", systemImage: "magnifyingglass")
                }
                .labelStyle(.iconOnly)
            }
            ToolbarItem(id: "open-in") {
                Menu {
                    if let fileURL {
                        ForEach(ExternalEditor.allCases.filter { $0.appURL != nil }, id: \.self) { editor in
                            Button(editor.title) { editor.open(fileURL) }
                        }
                        Divider()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                        }
                    }
                } label: {
                    Label("Open In", systemImage: "arrow.up.forward.app")
                }
                .labelStyle(.iconOnly)
                .help("Open In")
                .disabled(fileURL == nil)
            }
            ToolbarItem(id: "share-as") {
                Menu {
                    if let fileURL {
                        ShareLink(item: fileURL) {
                            Label("Share Markdown File…", systemImage: "doc")
                        }
                        Divider()
                    }
                    Button("Export as HTML…") {
                        ExportManager.exportHTML(markdown: document.text, suggestedName: exportBaseName, fileURL: fileURL)
                    }
                    Button("Export as PDF…") {
                        ExportManager.exportPDF(markdown: document.text, suggestedName: exportBaseName, fileURL: fileURL)
                    }
                } label: {
                    Label("Share As", systemImage: "square.and.arrow.up")
                }
                .labelStyle(.iconOnly)
                .help("Share As")
            }
            ToolbarItem(id: "zoom-out", showsByDefault: false) {
                Button(action: zoomOut) { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
            }
            ToolbarItem(id: "actual-size", showsByDefault: false) {
                Button(action: resetZoom) { Label("Actual Size", systemImage: "1.magnifyingglass") }
            }
            ToolbarItem(id: "zoom-in", showsByDefault: false) {
                Button(action: zoomIn) { Label("Zoom In", systemImage: "plus.magnifyingglass") }
            }
            ToolbarItem(id: "document-actions") {
                Menu {
                    Button(isPreviewing ? "Edit" : "Read", action: toggleEditing)
                    Button("Edit Source…") { showSource = true }
                    Button("Edit Tables…", action: showTableEditor)
                        .disabled(!snapshot.document.children.contains { $0 is Markdown.Table })
                    Divider()
                    Button("Zoom In", action: zoomIn)
                    Button("Zoom Out", action: zoomOut)
                    Button("Actual Size", action: resetZoom)
                } label: {
                    Label("Document Actions", systemImage: "ellipsis")
                }
                .labelStyle(.iconOnly)
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
