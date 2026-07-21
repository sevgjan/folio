import SwiftUI
import AppKit

struct RecentDocument: Identifiable {
    let id = UUID()
    let url: URL

    var name: String { url.deletingPathExtension().lastPathComponent }
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.deletingLastPathComponent().path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct WelcomeView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openDocument) private var openDocument
    @Environment(SettingsStore.self) private var settingsStore
    @State private var recents: [RecentDocument] = []
    @State private var selfWindow: NSWindow?

    private var theme: Theme { settingsStore.theme }
    private var isSystemTheme: Bool { theme.id == "system" }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 20) {
                Spacer()
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 128, height: 128)

                VStack(spacing: 4) {
                    Text("Folio")
                        .font(.system(size: 30, weight: .semibold))
                    if !version.isEmpty {
                        Text("Version \(version)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(spacing: 10) {
                    WelcomeActionButton(systemImage: "doc.badge.plus", title: "New Document") {
                        newDocument(MarkdownDocument())
                    }
                    WelcomeActionButton(systemImage: "folder", title: "Open File…") {
                        NSDocumentController.shared.openDocument(nil)
                    }
                }
                .frame(width: 260)
                Spacer()
            }
            .frame(width: 320)
            .padding(.vertical, 32)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text("Recent")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                if recents.isEmpty {
                    Spacer()
                    Text("No recent documents")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(recents) { recent in
                                RecentRow(recent: recent) {
                                    open(recent.url)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
            .frame(width: 320)
        }
        .frame(width: 640, height: 420)
        .foregroundStyle(isSystemTheme ? Color.primary : theme.foreground)
        .background(isSystemTheme ? Color(nsColor: .windowBackgroundColor) : theme.background)
        .background(WindowAppearanceSetter(colorScheme: theme.colorScheme))
        .background(WindowCapture { window in
            selfWindow = window
            // SwiftUI can materialize this window after applicationDidFinishLaunching already
            // fired, so activating there has nothing to bring forward yet. Doing it here, right
            // when the window actually exists, is what reliably raises it on a cold launch.
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        })
        .onAppear(perform: loadRecents)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) { note in
            guard let window = note.object as? NSWindow, window !== selfWindow else { return }
            dismissWindow(id: "welcome")
        }
    }

    private func loadRecents() {
        recents = NSDocumentController.shared.recentDocumentURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(RecentDocument.init)
    }

    private func open(_ url: URL) {
        Task { try? await openDocument(at: url) }
    }
}

/// Grabs the hosting NSWindow so the Welcome view can tell its own window apart
/// from any other window becoming main, without relying on identifier strings.
private struct WindowCapture: NSViewRepresentable {
    let onCapture: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window { onCapture(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct WelcomeActionButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .controlColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(title)
    }
}

private struct RecentRow: View {
    let recent: RecentDocument
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(isHovering ? Color.white : Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(recent.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(recent.displayPath)
                        .font(.caption)
                        .foregroundStyle(isHovering ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovering ? .white : .primary)
        .background(isHovering ? Color.accentColor : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .accessibilityLabel(recent.name)
    }
}

