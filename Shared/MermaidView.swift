import AppKit
import SwiftUI
import WebKit

private final class NonFocusableWebView: WKWebView {
    override var acceptsFirstResponder: Bool { false }
}

struct MermaidView: NSViewRepresentable {
    let code: String
    @Binding var height: CGFloat
    var themeName: String = "system"
    var themeVariables: [String: String]? = nil

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "heightHandler")
        MarkdownWebAssets.install(MarkdownWebAssets.mermaid, in: contentController)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = NonFocusableWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.lastCode = code
        context.coordinator.lastTheme = themeName
        load(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastCode != code || context.coordinator.lastTheme != themeName else { return }
        context.coordinator.lastCode = code
        context.coordinator.lastTheme = themeName
        load(in: webView)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "heightHandler")
        view.stopLoading()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    private func load(in webView: WKWebView) {
        let resolvedTheme = themeName == "system"
            ? (NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "default")
            : themeName

        var initializeOptions = "{ startOnLoad: false, securityLevel: \"strict\", suppressErrorRendering: true, theme: \"\(resolvedTheme)\""
        if let themeVariables, !themeVariables.isEmpty {
            let variables = themeVariables.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ")
            initializeOptions += ", themeVariables: { \(variables) }"
        }
        initializeOptions += " }"

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:">
        <style>
        html, body { margin: 0; padding: 8px; background: transparent; }
        .mermaid svg { width: 100%; max-width: none; height: auto; }
        </style>
        </head>
        <body>
        <pre class="mermaid">\(htmlEscape(code))</pre>
        <script>
        const target = document.querySelector('.mermaid');
        async function render() {
          try {
            mermaid.initialize(\(initializeOptions));
            await mermaid.run({nodes: [target]});
          } catch {
            const note = document.createElement('p');
            note.textContent = 'Diagram could not be rendered';
            target.before(note);
          }
          new ResizeObserver(() => {
            window.webkit.messageHandlers.heightHandler.postMessage(document.body.getBoundingClientRect().height);
          }).observe(document.body);
        }
        render();
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

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var height: Binding<CGFloat>
        var lastCode: String?
        var lastTheme: String?

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            action.request.url?.absoluteString == "about:blank" ? .allow : .cancel
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
