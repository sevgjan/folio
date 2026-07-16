import HighlightSwift
import LaTeXSwiftUI
import Markdown
import SwiftUI

private struct MarkdownFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var markdownFontScale: CGFloat {
        get { self[MarkdownFontScaleKey.self] }
        set { self[MarkdownFontScaleKey.self] = newValue }
    }
}

extension View {
    func centeredReadingColumn(maxWidth: CGFloat) -> some View {
        self.frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct MarkdownRenderer: View {
    let markdown: String

    var body: some View {
        let document = Markdown.Document(parsing: markdown)
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(document.children.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
    }
}

struct BlockView: View {
    let block: Markup
    @Environment(\.markdownFontScale) private var fontScale

    private let readingWidth: CGFloat = 680

    var body: some View {
        switch block {
        case let heading as Heading:
            InlineText(children: Array(heading.children))
                .font(fontForHeading(heading.level, scale: fontScale))
                .padding(.top, 8 * fontScale)
                .centeredReadingColumn(maxWidth: readingWidth)
        case let paragraph as Paragraph:
            ParagraphView(paragraph: paragraph)
                .centeredReadingColumn(maxWidth: readingWidth)
        case let codeBlock as CodeBlock:
            CodeBlockView(codeBlock: codeBlock)
                .centeredReadingColumn(maxWidth: readingWidth)
        case let list as UnorderedList:
            ListView(items: Array(list.children.compactMap { $0 as? ListItem }), ordered: false)
                .centeredReadingColumn(maxWidth: readingWidth)
        case let list as OrderedList:
            ListView(items: Array(list.children.compactMap { $0 as? ListItem }), ordered: true)
                .centeredReadingColumn(maxWidth: readingWidth)
        case let quote as BlockQuote:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(quote.children.enumerated()), id: \.offset) { _, child in
                    BlockView(block: child)
                }
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle().fill(.secondary).frame(width: 3)
            }
            .centeredReadingColumn(maxWidth: readingWidth)
        case let table as Markdown.Table:
            TableView(table: table)
                .frame(maxWidth: .infinity, alignment: .leading)
        case is ThematicBreak:
            Divider()
        default:
            InlineText(children: [block])
                .centeredReadingColumn(maxWidth: readingWidth)
        }
    }

    private func fontForHeading(_ level: Int, scale: CGFloat) -> Font {
        let baseSizes: [Int: CGFloat] = [1: 28, 2: 22, 3: 19, 4: 17, 5: 16, 6: 15]
        let size = (baseSizes[level] ?? 15) * scale
        return .system(size: size, weight: .semibold)
    }
}

struct ParagraphView: View {
    let paragraph: Paragraph

    var body: some View {
        let raw = paragraph.format()
        Group {
            if raw.contains("$") || raw.contains("\\(") || raw.contains("\\[") {
                LaTeX(raw)
            } else {
                InlineText(children: Array(paragraph.children))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CodeBlockView: View {
    let codeBlock: CodeBlock
    @Environment(\.markdownFontScale) private var fontScale

    var body: some View {
        if (codeBlock.language ?? "").lowercased() == "mermaid" {
            MermaidView(code: codeBlock.code)
                .frame(minHeight: 160)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            CodeText(codeBlock.code)
                .codeTextStyle(.card)
                .font(.system(size: 13 * fontScale, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ListView: View {
    let items: [ListItem]
    let ordered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 6) {
                    SwiftUI.Text(ordered ? "\(index + 1)." : "\u{2022}")
                        .foregroundColor(.secondary)
                        .frame(minWidth: 14, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                            BlockView(block: child)
                        }
                    }
                }
            }
        }
    }
}

struct TableView: View {
    let table: Markdown.Table

    private var bodyRows: [Markdown.Table.Row] {
        table.body.children.compactMap { $0 as? Markdown.Table.Row }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TableRowView(cells: Array(table.head.children.compactMap { $0 as? Markdown.Table.Cell }), isHeader: true)
                .background(Color.secondary.opacity(0.1))

            ForEach(Array(bodyRows.enumerated()), id: \.offset) { index, row in
                Divider()
                TableRowView(cells: Array(row.children.compactMap { $0 as? Markdown.Table.Cell }), isHeader: false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct TableRowView: View {
    let cells: [Markdown.Table.Cell]
    let isHeader: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                InlineText(children: Array(cell.children))
                    .fontWeight(isHeader ? .semibold : .regular)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct InlineText: View {
    let children: [Markup]
    @Environment(\.markdownFontScale) private var fontScale

    var body: some View {
        children.reduce(SwiftUI.Text("")) { partial, child in
            partial + inlineText(for: child)
        }
        .lineSpacing(6 * fontScale)
    }

    private func inlineText(for node: Markup) -> SwiftUI.Text {
        switch node {
        case let text as Markdown.Text:
            return SwiftUI.Text(text.string)
        case let emphasis as Emphasis:
            return emphasis.children.reduce(SwiftUI.Text("")) { $0 + inlineText(for: $1) }.italic()
        case let strong as Strong:
            return strong.children.reduce(SwiftUI.Text("")) { $0 + inlineText(for: $1) }.bold()
        case let code as InlineCode:
            return SwiftUI.Text(code.code).font(.system(size: 14 * fontScale, design: .monospaced))
        case let link as Markdown.Link:
            let label = plainString(link)
            if let destination = link.destination, let url = URL(string: destination) {
                var attributed = AttributedString(label)
                attributed.link = url
                attributed.foregroundColor = .accentColor
                attributed.underlineStyle = .single
                return SwiftUI.Text(attributed)
            }
            return SwiftUI.Text(label).foregroundColor(.accentColor).underline()
        case is SoftBreak:
            return SwiftUI.Text("\n")
        case is LineBreak:
            return SwiftUI.Text("\n")
        default:
            return SwiftUI.Text(node.format())
        }
    }

    private func plainString(_ node: Markup) -> String {
        if let text = node as? Markdown.Text {
            return text.string
        }
        if let code = node as? InlineCode {
            return code.code
        }
        if node is SoftBreak {
            return " "
        }
        if node is LineBreak {
            return "\n"
        }
        return node.children.map(plainString).joined()
    }
}
