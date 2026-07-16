import AppKit

enum ExternalEditor: String, CaseIterable {
    case xcode = "com.apple.dt.Xcode"
    case vscode = "com.microsoft.VSCode"
    case textEdit = "com.apple.TextEdit"

    var title: String {
        switch self {
        case .xcode: return "Xcode"
        case .vscode: return "Code"
        case .textEdit: return "TextEdit"
        }
    }

    var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue)
    }

    var icon: NSImage? {
        guard let appURL else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    func open(_ fileURL: URL) {
        guard let appURL else { return }
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
