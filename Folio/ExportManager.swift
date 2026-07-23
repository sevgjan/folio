import AppKit
import Markdown
import UniformTypeIdentifiers
import WebKit

enum ExportManager {
    static func exportHTML(markdown: String, suggestedName: String) {
        guard let url = savePanel(suggestedName: "\(suggestedName).html", allowedType: .html) else { return }
        let html = htmlDocument(from: markdown, title: suggestedName)
        try? html.write(to: url, atomically: true, encoding: .utf8)
    }

    static func exportPDF(markdown: String, suggestedName: String) {
        guard let url = savePanel(suggestedName: "\(suggestedName).pdf", allowedType: .pdf) else { return }
        let html = htmlDocument(from: markdown, title: suggestedName)
        PDFExporter.shared.export(html: html, to: url)
    }

    private static func savePanel(suggestedName: String, allowedType: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [allowedType]
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func htmlDocument(from markdown: String, title: String) -> String {
        let document = Document(parsing: markdown)
        let body = HTMLFormatter.format(document)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(title)</title>
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 24px; line-height: 1.6; color: #1a1a1a; }
        pre { background: #f5f5f5; padding: 12px 16px; border-radius: 6px; overflow-x: auto; }
        code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
        pre code { background: none; padding: 0; }
        :not(pre) > code { background: #f0f0f0; padding: 2px 5px; border-radius: 4px; }
        blockquote { border-left: 3px solid #ccc; margin-left: 0; padding-left: 16px; color: #555; }
        table { border-collapse: collapse; width: 100%; margin: 16px 0; }
        th, td { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }
        img { max-width: 100%; }
        hr { border: none; border-top: 1px solid #ddd; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}

// Holds the offscreen WKWebView alive until its PDF snapshot completes.
private final class PDFExporter: NSObject, WKNavigationDelegate {
    static let shared = PDFExporter()

    private var webView: WKWebView?
    private var destinationURL: URL?

    func export(html: String, to url: URL) {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 816, height: 1056))
        webView.navigationDelegate = self
        self.webView = webView
        self.destinationURL = url
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let destinationURL else { return }
        webView.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
            if case .success(let data) = result {
                try? data.write(to: destinationURL)
            }
            self?.webView = nil
            self?.destinationURL = nil
        }
    }
}
