import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct FolioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var updateStore = UpdateStore()
    @State private var settingsStore = SettingsStore()
    @AppStorage("hasSetDefaultMarkdownViewer") private var hasSetDefault = false

    var body: some Scene {
        Window("Welcome to Folio", id: "welcome") {
            WelcomeView()
                .environment(settingsStore)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
                .environment(updateStore)
                .environment(settingsStore)
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
            CommandGroup(after: .newItem) {
                WelcomeMenuButton()
            }
        }

        Settings {
            SettingsView()
                .environment(settingsStore)
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

private struct WelcomeMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Welcome to Folio…") {
            openWindow(id: "welcome")
        }
        .keyboardShortcut("1", modifiers: [.command, .shift])
    }
}
