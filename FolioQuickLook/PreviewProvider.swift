import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest, completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void) {
        do {
            let text = try String(contentsOf: request.fileURL, encoding: .utf8)
            let html = MarkdownHTMLRenderer.render(text, title: request.fileURL.lastPathComponent)
            let data = Data(html.utf8)

            let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 820, height: 1040)) { replyToUpdate in
                replyToUpdate.stringEncoding = .utf8
                return data
            }
            handler(reply, nil)
        } catch {
            handler(nil, error)
        }
    }
}
