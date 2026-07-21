import AppKit
import SwiftUI

private struct TableEditorSession: Identifiable {
    let id = UUID()
    let candidates: [TableCandidate]
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

    init(document: Binding<MarkdownDocument>, fileURL: URL?) {
        self._document = document
        self.fileURL = fileURL
        // A brand-new, unsaved document has no fileURL — start it in edit mode
        // instead of previewing blank content.
        self._isPreviewing = State(initialValue: fileURL != nil)
    }

    private var finderIcon: NSImage {
        NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
    }

    private func themedFont(size: CGFloat) -> Font {
        settingsStore.fontFamily.isEmpty ? .system(size: size) : .custom(settingsStore.fontFamily, size: size)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isPreviewing {
                    ScrollView {
                        MarkdownRenderer(markdown: document.text)
                            .font(themedFont(size: settingsStore.baseFontSize * zoom))
                            .foregroundStyle(settingsStore.theme.id == "system" ? Color.primary : settingsStore.theme.foreground)
                            .environment(\.markdownFontScale, zoom)
                            .environment(\.markdownTheme, settingsStore.theme)
                            .environment(\.markdownFontFamily, settingsStore.fontFamily)
                            .environment(\.markdownReadingWidth, CGFloat(settingsStore.readingWidth))
                            .environment(\.markdownTableWidth, CGFloat(settingsStore.tableWidth))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(32)
                            .textSelection(.enabled)
                    }
                    .background(settingsStore.theme.background)
                    .onTapGesture(count: 3) {
                        isPreviewing = false
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
                    }
                    .background(settingsStore.theme.background)
                }
            }
            .background(WindowAppearanceSetter(colorScheme: settingsStore.theme.colorScheme))
        }
        .overlay(alignment: .top) {
            if updateStore.state != .none {
                UpdateBannerView(store: updateStore)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: updateStore.state)
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
