import AppKit
import SwiftUI
import WebKit

struct MermaidView: NSViewRepresentable {
    let code: String
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "heightHandler")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.lastCode = code
        load(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastCode != code else { return }
        context.coordinator.lastCode = code
        load(in: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
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
        var attempts = 0;
        var timer = setInterval(function () {
          attempts++;
          var svg = document.querySelector('.mermaid svg');
          if (svg || attempts > 100) {
            clearInterval(timer);
            window.webkit.messageHandlers.heightHandler.postMessage(document.body.scrollHeight);
          }
        }, 50);
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

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var height: Binding<CGFloat>
        var lastCode: String?

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let number = message.body as? NSNumber else { return }
            let value = CGFloat(truncating: number)
            DispatchQueue.main.async {
                self.height.wrappedValue = value
            }
        }
    }
}
