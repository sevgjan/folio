import AppKit
import SwiftUI
import WebKit

struct MermaidView: NSViewRepresentable {
    let code: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        load(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        load(in: webView)
    }

    private func load(in webView: WKWebView) {
        let theme = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "default"
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        <style>
        html, body { margin: 0; padding: 8px; background: transparent; }
        </style>
        </head>
        <body>
        <pre class="mermaid">\(htmlEscape(code))</pre>
        <script>
        mermaid.initialize({ startOnLoad: true, theme: "\(theme)" });
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func htmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
