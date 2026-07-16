import Markdown

enum MarkdownHTMLRenderer {
    static func render(_ markdown: String, title: String) -> String {
        let document = Document(parsing: markdown)
        let body = document.children.map(renderBlock).joined()
        return wrapHTML(body: body, title: title)
    }

    private static func renderBlock(_ markup: Markup) -> String {
        switch markup {
        case let heading as Heading:
            let level = min(max(heading.level, 1), 6)
            return "<h\(level)>\(renderInlineChildren(heading))</h\(level)>\n"
        case let paragraph as Paragraph:
            return "<p>\(renderInlineChildren(paragraph))</p>\n"
        case let codeBlock as CodeBlock:
            return "<pre><code>\(escapeHTML(codeBlock.code))</code></pre>\n"
        case let list as UnorderedList:
            let items = list.children.compactMap { $0 as? ListItem }
                .map { "<li>\($0.children.map(renderBlock).joined())</li>\n" }
                .joined()
            return "<ul>\n\(items)</ul>\n"
        case let list as OrderedList:
            let items = list.children.compactMap { $0 as? ListItem }
                .map { "<li>\($0.children.map(renderBlock).joined())</li>\n" }
                .joined()
            return "<ol>\n\(items)</ol>\n"
        case let quote as BlockQuote:
            return "<blockquote>\n\(quote.children.map(renderBlock).joined())</blockquote>\n"
        case let table as Table:
            return renderTable(table)
        case is ThematicBreak:
            return "<hr>\n"
        default:
            return "<p>\(escapeHTML(markup.format()))</p>\n"
        }
    }

    private static func renderTable(_ table: Table) -> String {
        var html = "<table>\n<thead><tr>"
        for cell in table.head.children.compactMap({ $0 as? Table.Cell }) {
            html += "<th>\(renderInlineChildren(cell))</th>"
        }
        html += "</tr></thead>\n<tbody>\n"
        for row in table.body.children.compactMap({ $0 as? Table.Row }) {
            html += "<tr>"
            for cell in row.children.compactMap({ $0 as? Table.Cell }) {
                html += "<td>\(renderInlineChildren(cell))</td>"
            }
            html += "</tr>\n"
        }
        html += "</tbody>\n</table>\n"
        return html
    }

    private static func renderInlineChildren(_ markup: Markup) -> String {
        markup.children.map(renderInline).joined()
    }

    private static func renderInline(_ markup: Markup) -> String {
        switch markup {
        case let text as Text:
            return escapeHTML(text.string)
        case let emphasis as Emphasis:
            return "<em>\(renderInlineChildren(emphasis))</em>"
        case let strong as Strong:
            return "<strong>\(renderInlineChildren(strong))</strong>"
        case let strikethrough as Strikethrough:
            return "<del>\(renderInlineChildren(strikethrough))</del>"
        case let code as InlineCode:
            return "<code>\(escapeHTML(code.code))</code>"
        case let link as Link:
            let href = escapeHTML(link.destination ?? "")
            return "<a href=\"\(href)\">\(renderInlineChildren(link))</a>"
        case is SoftBreak:
            return "<br>"
        case is LineBreak:
            return "<br>"
        default:
            return escapeHTML(markup.format())
        }
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func wrapHTML(body: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escapeHTML(title))</title>
        <style>
        :root { color-scheme: light dark; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
            font-size: 15px;
            line-height: 1.6;
            color: #1b1a17;
            background: #ffffff;
            max-width: 720px;
            margin: 0 auto;
            padding: 32px;
        }
        @media (prefers-color-scheme: dark) {
            body { color: #f1efe9; background: #1c1c1e; }
            code, pre { background: rgba(255,255,255,0.08) !important; }
            th { background: rgba(255,255,255,0.06) !important; }
            th, td { border-color: rgba(255,255,255,0.15) !important; }
        }
        h1, h2, h3, h4, h5, h6 { font-weight: 600; margin-top: 1.2em; margin-bottom: 0.4em; }
        h1 { font-size: 1.8em; }
        h2 { font-size: 1.4em; }
        h3 { font-size: 1.2em; }
        p { margin: 0.8em 0; }
        code {
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 0.9em;
            background: rgba(0,0,0,0.06);
            border-radius: 4px;
            padding: 0.15em 0.35em;
        }
        pre {
            background: rgba(0,0,0,0.06);
            border-radius: 8px;
            padding: 12px 16px;
            overflow-x: auto;
        }
        pre code { background: none; padding: 0; }
        blockquote {
            margin: 0.8em 0;
            padding-left: 12px;
            border-left: 3px solid rgba(128,128,128,0.4);
            color: #6b6b6b;
        }
        table { border-collapse: collapse; width: 100%; margin: 1em 0; }
        th, td { border: 1px solid rgba(0,0,0,0.15); padding: 8px 12px; text-align: left; }
        th { background: rgba(0,0,0,0.04); }
        a { color: #2f6fed; text-decoration: none; }
        a:hover { text-decoration: underline; }
        hr { border: none; border-top: 1px solid rgba(128,128,128,0.3); margin: 1.6em 0; }
        ul, ol { padding-left: 1.4em; }
        li { margin: 0.3em 0; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
