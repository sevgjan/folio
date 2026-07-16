import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct FolioApp: App {
    @State private var updateStore = UpdateStore()
    @AppStorage("hasSetDefaultMarkdownViewer") private var hasSetDefault = false

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
                .environment(updateStore)
                .task {
                    await updateStore.checkForUpdatesOnce()
                    setDefaultMarkdownViewerOnce()
                }
        }
        .defaultSize(width: 900, height: 988)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Set Folio as Default Markdown Viewer…") {
                    setAsDefaultMarkdownViewer()
                }
            }
        }
    }

    private func setDefaultMarkdownViewerOnce() {
        guard !hasSetDefault else { return }
        hasSetDefault = true
        setAsDefaultMarkdownViewer()
    }

    private func setAsDefaultMarkdownViewer() {
        guard let markdownType = UTType("net.daringfireball.markdown") else { return }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: markdownType) { error in
            if let error {
                NSLog("Folio: failed to set default markdown viewer: \(error)")
            }
        }
    }
}
