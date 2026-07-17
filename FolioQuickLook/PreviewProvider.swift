import Cocoa
import QuickLookUI

final class PreviewProvider: NSViewController, @MainActor QLPreviewingController {
    private let textView = NSTextView()

    override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 820, height: 1040))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 28, height: 28)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        view = scrollView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            textView.textStorage?.setAttributedString(MarkdownAttributedRenderer.render(text))
            handler(nil)
        } catch {
            handler(error)
        }
    }
}
