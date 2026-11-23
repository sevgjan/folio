import Markdown
import SwiftUI
import WebKit

enum MarkdownWebAssets {
    static let mermaid = "mermaid-10.9.8"
    static let mathRendering = #"""
    if (window.renderMathInElement) {
        renderMathInElement(document.body, {
            delimiters: [
                {left: '$$', right: '$$', display: true},
                {left: '\\[', right: '\\]', display: true},
                {left: '\\(', right: '\\)', display: false},
                {left: '$', right: '$', display: false}
            ],
            trust: false, maxExpand: 500, maxSize: 20, throwOnError: false
        });
    }
    """#

    @MainActor static let mathCSS: String = {
        guard let url = Bundle.main.url(forResource: "katex-0.19.1", withExtension: "css") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func body(_ source: String) -> String {
        let snapshot = MarkdownSnapshot(source)
        let edited = NSMutableString(string: source)
        var tokens: [(NSRange, String, String)] = []
        func collect(_ node: Markup) {
            if node is Paragraph, let range = snapshot.range(node) {
                let raw = (source as NSString).substring(with: range)
                for match in markdownMathRanges(raw) {
                    let token = "FolioEquation" + String(tokens.count) + "Token"
                    guard !source.contains(token) else { continue }
                    tokens.append((NSRange(location: range.location + match.location, length: match.length),
                                   token, (raw as NSString).substring(with: match)))
                }
            } else if node is InlineHTML || node is HTMLBlock {
                if let range = snapshot.range(node) { tokens.append((range, "", "")) }
            } else {
                for child in node.children { collect(child) }
            }
        }
        collect(snapshot.document)
        for (range, token, _) in tokens.reversed() { edited.replaceCharacters(in: range, with: token) }
        var html = HTMLFormatter.format(edited as String)
        for (_, token, equation) in tokens where !token.isEmpty {
            html = html.replacingOccurrences(of: token, with: escape(equation))
        }
        return html
    }

    @MainActor static func install(_ name: String, in controller: WKUserContentController) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8) else { return }
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    @MainActor static func installMath(in controller: WKUserContentController) {
        install("katex-0.19.1", in: controller)
        install("katex-auto-render-0.19.1", in: controller)
    }
}

struct EquationView: NSViewRepresentable {
    let html: String
    let pointSize: CGFloat
    let family: String
    let foreground: Color
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "equationHeight")
        MarkdownWebAssets.installMath(in: controller)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let nonce = context.coordinator.nonce
        let color = NSColor(foreground).usingColorSpace(.sRGB) ?? .black
        let cssColor = "rgb(\(Int(color.redComponent * 255)),\(Int(color.greenComponent * 255)),\(Int(color.blueComponent * 255)))"
        let cssFamily = family.isEmpty ? "-apple-system" : "\"\(family.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" })\", -apple-system"
        let page = """
        <!doctype html><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; font-src data:; script-src 'nonce-\(nonce)'">
        <style>html{overflow:hidden}body{margin:0;color:\(cssColor);font:\(pointSize)px/\(pointSize + 6)px \(cssFamily);white-space:pre-wrap}
        p{margin:0} .katex-display{margin:0.5em 0!important}\n        \(MarkdownWebAssets.mathCSS)</style><body>\(html)<script nonce="\(nonce)">
        (async () => {
            try {
                \(MarkdownWebAssets.mathRendering)
            } finally {
                new ResizeObserver(() => {
                    window.webkit.messageHandlers.equationHeight.postMessage(document.body.getBoundingClientRect().height);
                }).observe(document.body);
            }
        })();
        </script></body>
        """
        context.coordinator.height = $height
        guard context.coordinator.page != page else { return }
        context.coordinator.page = page
        view.loadHTMLString(page, baseURL: nil)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "equationHeight")
        view.stopLoading()
    }

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let nonce = UUID().uuidString
        var page: String?
        var height: Binding<CGFloat>

        init(height: Binding<CGFloat>) { self.height = height }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let value = message.body as? Double, value.isFinite, value > 0 else { return }
            height.wrappedValue = ceil(value)
        }
    }
}
