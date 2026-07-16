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
    @State private var zoom: CGFloat = 1.0
    @State private var isPreviewing = true
    @State private var editableTextView: MarkdownTextView?
    @State private var tableEditorSession: TableEditorSession?

    private var finderIcon: NSImage {
        NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
    }

    var body: some View {
        VStack(spacing: 0) {
            if updateStore.state != .none {
                UpdateBannerView(store: updateStore)
                Divider()
            }

            Group {
                if isPreviewing {
                    ScrollView {
                        MarkdownRenderer(markdown: document.text)
                            .font(.system(size: 15 * zoom))
                            .environment(\.markdownFontScale, zoom)
                            .padding(32)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .onTapGesture(count: 3) {
                        isPreviewing = false
                    }
                } else {
                    MarkdownEditorView(text: $document.text, fontSize: 16 * zoom) { textView in
                        DispatchQueue.main.async {
                            editableTextView = textView
                        }
                    }
                }
            }
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

            ToolbarItemGroup {
                Button {
                    isPreviewing.toggle()
                } label: {
                    Image(systemName: isPreviewing ? "pencil" : "eye")
                }
                .keyboardShortcut("e", modifiers: .command)
                .help(isPreviewing ? "Edit" : "Preview")

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
