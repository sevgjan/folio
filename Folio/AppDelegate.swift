import AppKit

/// DocumentGroup normally creates a blank untitled document on launch. Suppressing
/// that is what lets the Welcome window (with its own New/Open/Recents) be the
/// first thing you see instead, matching Xcode's launcher.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }
}
