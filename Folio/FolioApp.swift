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
            CommandGroup(after: .pasteboard) {
                FindMenuButtons()
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

/// The editor is a plain NSTextView, which already implements find/replace via the modern
/// find bar (NSTextFinder) — it just needs menu items wired to `performFindPanelAction(_:)`
/// with the right tag, the same way AppKit apps have exposed Find since forever. Declaring
/// these through SwiftUI's own Commands (rather than mutating NSApp.mainMenu directly) avoids
/// a race where SwiftUI rebuilds the Edit menu after launch and silently drops manual edits.
private struct FindMenuButtons: View {
    var body: some View {
        Divider()
        Button("Find…") { performFind(.showFindInterface) }
            .keyboardShortcut("f", modifiers: .command)
        Button("Find Next") { performFind(.nextMatch) }
            .keyboardShortcut("g", modifiers: .command)
        Button("Find Previous") { performFind(.previousMatch) }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        // No keyboard shortcut: ⌘E is already Folio's Preview/Edit toggle.
        Button("Use Selection for Find") { performFind(.setSearchString) }
    }

    private func performFind(_ action: NSTextFinder.Action) {
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: sender)
    }
}
