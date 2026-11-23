import AppKit
import Markdown
import UniformTypeIdentifiers
import WebKit

@MainActor
enum ExportManager {
    static func exportHTML(markdown: String, suggestedName: String, fileURL: URL?) {
        guard let url = savePanel(suggestedName: "\(suggestedName).html", allowedType: .html) else { return }
        let html = htmlDocument(from: markdown, title: suggestedName, fileURL: fileURL)
        ExportJob.export(html: html, to: url, baseURL: fileURL?.deletingLastPathComponent(), pdf: false)
    }

    static func exportPDF(markdown: String, suggestedName: String, fileURL: URL?) {
        guard let url = savePanel(suggestedName: "\(suggestedName).pdf", allowedType: .pdf) else { return }
        let html = htmlDocument(from: markdown, title: suggestedName, fileURL: fileURL)
        ExportJob.export(html: html, to: url, baseURL: fileURL?.deletingLastPathComponent(), pdf: true)
    }

    private static func savePanel(suggestedName: String, allowedType: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [allowedType]
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func htmlDocument(from markdown: String, title: String, fileURL: URL?) -> String {
        let body = MarkdownWebAssets.body(markdown)
        let base = fileURL.map { "<base href=\"\(escape($0.deletingLastPathComponent().absoluteString))\">" } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; font-src data:; img-src file: data: https: http:; base-uri file:">

        <title>\(escape(title))</title>
        \(base)
        <style>
        \(MarkdownWebAssets.mathCSS)\n        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 24px; line-height: 1.6; color: #1a1a1a; }
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
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

@MainActor
private final class ExportJob: NSObject, WKNavigationDelegate {
    private static var jobs: [UUID: ExportJob] = [:]
    private let id = UUID()
    private let destination: URL
    private let webView: WKWebView
    private let pdf: Bool

    private init(destination: URL, pdf: Bool) {
        self.destination = destination
        self.pdf = pdf
        let configuration = WKWebViewConfiguration()
        MarkdownWebAssets.installMath(in: configuration.userContentController)
        MarkdownWebAssets.install(MarkdownWebAssets.mermaid, in: configuration.userContentController)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 816, height: 1056), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    static func export(html: String, to url: URL, baseURL: URL?, pdf: Bool) {
        let job = ExportJob(destination: url, pdf: pdf)
        jobs[job.id] = job
        job.webView.loadHTMLString(html, baseURL: baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task {
            defer { Self.jobs[id] = nil }
            do {
                let html = try await webView.callAsyncJavaScript(MarkdownWebAssets.mathRendering + #"""

                if (window.mermaid) {
                    mermaid.initialize({startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true});
                    let index = 0;
                    for (const code of document.querySelectorAll('pre > code.language-mermaid')) {
                        try {
                            const result = await mermaid.render('folio-chart-' + ++index, code.textContent);
                            const figure = document.createElement('figure');
                            figure.innerHTML = result.svg;
                            code.parentElement.replaceWith(figure);
                        } catch {}
                    }
                }
                return '<!doctype html>' + document.documentElement.outerHTML;
                """#, arguments: [:], in: nil, contentWorld: .page)
                if pdf {
                    try await webView.pdf().write(to: destination, options: .atomic)
                } else if let html = html as? String {
                    try html.write(to: destination, atomically: true, encoding: .utf8)
                } else {
                    throw CocoaError(.fileWriteUnknown)
                }
            } catch { NSApp.presentError(error) }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        action.navigationType == .other ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Self.jobs[id] = nil
        NSApp.presentError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }
}
