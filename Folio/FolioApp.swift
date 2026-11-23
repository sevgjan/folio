import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct FolioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var updateStore = UpdateStore()
    @State private var settingsStore = SettingsStore()

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
                }
        }
        .defaultSize(width: 900, height: 988)
        .commands {
            ToolbarCommands()
            CommandGroup(after: .toolbar) {
                ZoomMenuButtons()
            }
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

struct FindCommands {
    let toggleEditing: () -> Void
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let resetZoom: () -> Void
    let show: () -> Void
    let next: () -> Void
    let previous: () -> Void
}

extension FocusedValues {
    @Entry var folioFind: FindCommands? = nil
}

private struct ZoomMenuButtons: View {
    @FocusedValue(\.folioFind) private var commands

    var body: some View {
        Divider()
        Button("Zoom In") { commands?.zoomIn() }.keyboardShortcut("+").disabled(commands == nil)
        Button("Zoom Out") { commands?.zoomOut() }.keyboardShortcut("-").disabled(commands == nil)
        Button("Actual Size") { commands?.resetZoom() }.keyboardShortcut("0").disabled(commands == nil)
    }
}

private struct FindMenuButtons: View {
    @FocusedValue(\.folioFind) private var commands

    var body: some View {
        Divider()
        Button("Toggle Read/Edit") { commands?.toggleEditing() }
            .keyboardShortcut("e")
            .disabled(commands == nil)
        Button("Find…") { commands?.show() }
            .keyboardShortcut("f")
            .disabled(commands == nil)
        Button("Find Next") { commands?.next() }
            .keyboardShortcut("g")
            .disabled(commands == nil)
        Button("Find Previous") { commands?.previous() }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(commands == nil)
    }
}
