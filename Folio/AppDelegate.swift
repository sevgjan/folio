import AppKit

/// DocumentGroup normally creates a blank untitled document on launch. Suppressing
/// that is what lets the Welcome window (with its own New/Open/Recents) be the
/// first thing you see instead, matching Xcode's launcher.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    // Suppressing the untitled document above also skips the code path that normally
    // activates the app on launch, so the Welcome window can open behind other apps
    // (or not come forward) until you click the Dock icon a second time.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
