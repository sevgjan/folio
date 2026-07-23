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

// Routes ⌘F/G to the editor's NSTextView find bar, and also broadcasts a notification ContentView uses to drive the preview find bar (kept to one ⌘F binding to avoid shortcut collisions).
private struct FindMenuButtons: View {
    var body: some View {
        Divider()
        Button("Find…") { performFind(.showFindInterface, notification: .folioFindShow) }
            .keyboardShortcut("f", modifiers: .command)
        Button("Find Next") { performFind(.nextMatch, notification: .folioFindNext) }
            .keyboardShortcut("g", modifiers: .command)
        Button("Find Previous") { performFind(.previousMatch, notification: .folioFindPrevious) }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        // No keyboard shortcut: ⌘E is already Folio's Preview/Edit toggle.
        Button("Use Selection for Find") { performFind(.setSearchString, notification: .folioFindSetSelection) }
    }

    private func performFind(_ action: NSTextFinder.Action, notification: Notification.Name) {
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: sender)
        NotificationCenter.default.post(name: notification, object: nil)
    }
}

extension Notification.Name {
    static let folioFindShow = Notification.Name("folioFindShow")
    static let folioFindNext = Notification.Name("folioFindNext")
    static let folioFindPrevious = Notification.Name("folioFindPrevious")
    static let folioFindSetSelection = Notification.Name("folioFindSetSelection")
}
