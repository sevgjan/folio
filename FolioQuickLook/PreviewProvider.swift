import Cocoa
import QuickLookUI
import SwiftUI

final class PreviewProvider: NSViewController, @MainActor QLPreviewingController {
    private var hostingView: NSHostingView<AnyView>!

    override func loadView() {
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        hostingView.frame = NSRect(x: 0, y: 0, width: 820, height: 1040)
        view = hostingView
        // quicklookd sizes the preview panel from this, not from the view's own frame.
        preferredContentSize = hostingView.frame.size
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            hostingView.rootView = AnyView(PreviewContent(markdown: text))
            handler(nil)
        } catch {
            handler(error)
        }
    }
}

/// Quick Look runs in a sandboxed extension that can't share the app's UserDefaults
/// without an App Group (which needs a paid developer account), so it always renders
/// with the app's fixed defaults rather than the user's saved theme/font settings.
private struct PreviewContent: View {
    let markdown: String

    private let theme = Theme.system
    private let fontFamily = SettingsStore.Defaults.fontFamily
    private let baseFontSize = SettingsStore.Defaults.baseFontSize
    private let readingWidth = SettingsStore.Defaults.readingWidth
    private let tableWidthRatio = SettingsStore.Defaults.tableWidthRatio

    var body: some View {
        ScrollView {
            MarkdownRenderer(markdown: markdown)
                .font(fontFamily.isEmpty ? .system(size: baseFontSize) : .custom(fontFamily, size: baseFontSize))
                .environment(\.markdownTheme, theme)
                .environment(\.markdownFontFamily, fontFamily)
                .environment(\.markdownReadingWidth, CGFloat(readingWidth))
                .environment(\.markdownTableWidth, CGFloat(readingWidth * tableWidthRatio))
                .environment(\.markdownMermaidEnabled, false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(32)
                .textSelection(.enabled)
        }
        .background(theme.background)
    }
}
