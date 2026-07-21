import HighlightSwift
import Markdown
import SwiftUI

private struct MarkdownFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

private struct MarkdownThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .system
}

private struct MarkdownFontFamilyKey: EnvironmentKey {
    static let defaultValue: String = ""
}

private struct MarkdownReadingWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = CGFloat(SettingsStore.Defaults.readingWidth)
}

private struct MarkdownTableWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = CGFloat(SettingsStore.Defaults.readingWidth * SettingsStore.Defaults.tableWidthRatio)
}

/// Mermaid rendering loads mermaid.js from a CDN, which requires network access. The app
/// is unsandboxed so this is fine, but the sandboxed Quick Look extension has no network
/// entitlement, so it sets this to false and falls back to a plain code block.
private struct MarkdownMermaidEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var markdownFontScale: CGFloat {
        get { self[MarkdownFontScaleKey.self] }
        set { self[MarkdownFontScaleKey.self] = newValue }
    }
    var markdownTheme: Theme {
        get { self[MarkdownThemeKey.self] }
        set { self[MarkdownThemeKey.self] = newValue }
    }
    var markdownFontFamily: String {
        get { self[MarkdownFontFamilyKey.self] }
        set { self[MarkdownFontFamilyKey.self] = newValue }
    }
    var markdownReadingWidth: CGFloat {
        get { self[MarkdownReadingWidthKey.self] }
        set { self[MarkdownReadingWidthKey.self] = newValue }
    }
    var markdownTableWidth: CGFloat {
        get { self[MarkdownTableWidthKey.self] }
        set { self[MarkdownTableWidthKey.self] = newValue }
    }
    var markdownMermaidEnabled: Bool {
        get { self[MarkdownMermaidEnabledKey.self] }
        set { self[MarkdownMermaidEnabledKey.self] = newValue }
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
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownFontFamily) private var fontFamily
    @Environment(\.markdownReadingWidth) private var readingWidth
    @Environment(\.markdownTableWidth) private var tableWidth
    @Environment(\.markdownMermaidEnabled) private var mermaidEnabled

    var body: some View {
        switch block {
        case let heading as Heading:
            InlineText(children: Array(heading.children))
                .font(fontForHeading(heading.level, scale: fontScale))
                .padding(.top, 20 * fontScale)
                .centeredReadingColumn(maxWidth: readingWidth)
        case let paragraph as Paragraph:
            ParagraphView(paragraph: paragraph)
                .centeredReadingColumn(maxWidth: readingWidth)
        case let codeBlock as CodeBlock:
            if (codeBlock.language ?? "").lowercased() == "mermaid" && mermaidEnabled {
                CodeBlockView(codeBlock: codeBlock)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                CodeBlockView(codeBlock: codeBlock)
                    .centeredReadingColumn(maxWidth: readingWidth)
            }
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
                Rectangle().fill(theme.secondary).frame(width: 3)
            }
            .centeredReadingColumn(maxWidth: readingWidth)
        case let table as Markdown.Table:
            TableView(table: table)
                .focusable(false)
                .accessibilityElement(children: .combine)
                .centeredReadingColumn(maxWidth: tableWidth)
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
        return fontFamily.isEmpty
            ? .system(size: size, weight: .semibold)
            : .custom(fontFamily, size: size).weight(.semibold)
    }
}

struct ParagraphView: View {
    let paragraph: Paragraph

    var body: some View {
        let raw = paragraph.format()
        Group {
            if raw.contains("$") || raw.contains("\\(") || raw.contains("\\[") {
                MathText(raw: raw)
                    .focusable(false)
            } else {
                InlineText(children: Array(paragraph.children))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// LaTeXSwiftUI's rasterizer (SwiftDraw) can't parse MathJax's SVG output, so
/// equations render blank or as raw fallback text inconsistently. Until that's
/// fixed upstream, show the LaTeX source itself in a clearly-distinguished style
/// rather than attempting (and silently failing) real typesetting.
private struct MathSegment {
    let text: String
    let isEquation: Bool
    let isBlock: Bool
}

private func splitMathSegments(_ raw: String) -> [MathSegment] {
    let pattern = #"\$\$[\s\S]+?\$\$|\\\[[\s\S]+?\\\]|\$[^\$\n]+?\$|\\\([\s\S]+?\\\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return [MathSegment(text: raw, isEquation: false, isBlock: false)]
    }
    let nsRaw = raw as NSString
    var segments: [MathSegment] = []
    var lastEnd = 0

    regex.enumerateMatches(in: raw, range: NSRange(location: 0, length: nsRaw.length)) { match, _, _ in
        guard let match else { return }
        let start = match.range.location
        let end = start + match.range.length

        // Skip matches wrapped in backticks (a literal `$...$` code example, not real math).
        let precededByBacktick = start > 0 && nsRaw.substring(with: NSRange(location: start - 1, length: 1)) == "`"
        let followedByBacktick = end < nsRaw.length && nsRaw.substring(with: NSRange(location: end, length: 1)) == "`"
        if precededByBacktick && followedByBacktick { return }

        if start > lastEnd {
            segments.append(MathSegment(text: nsRaw.substring(with: NSRange(location: lastEnd, length: start - lastEnd)), isEquation: false, isBlock: false))
        }
        let matched = nsRaw.substring(with: match.range)
        let isBlock = matched.hasPrefix("$$") || matched.hasPrefix("\\[")
        segments.append(MathSegment(text: stripMathDelimiters(matched), isEquation: true, isBlock: isBlock))
        lastEnd = end
    }
    if lastEnd < nsRaw.length {
        segments.append(MathSegment(text: nsRaw.substring(from: lastEnd), isEquation: false, isBlock: false))
    }
    return segments
}

private func stripMathDelimiters(_ s: String) -> String {
    if s.hasPrefix("$$") && s.hasSuffix("$$") {
        return String(s.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if s.hasPrefix("\\[") && s.hasSuffix("\\]") {
        return String(s.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if s.hasPrefix("\\(") && s.hasSuffix("\\)") {
        return String(s.dropFirst(2).dropLast(2))
    }
    if s.hasPrefix("$") && s.hasSuffix("$") {
        return String(s.dropFirst(1).dropLast(1))
    }
    return s
}

struct MathText: View {
    let raw: String
    @Environment(\.markdownFontScale) private var fontScale
    @Environment(\.markdownTheme) private var theme

    var body: some View {
        let segments = splitMathSegments(raw)
        if segments.count == 1, let only = segments.first, only.isEquation, only.isBlock {
            SwiftUI.Text(only.text)
                .font(.system(size: 14 * fontScale, design: .monospaced))
                .foregroundStyle(theme.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(theme.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            segments.reduce(SwiftUI.Text("")) { partial, segment in
                if segment.isEquation {
                    return partial + SwiftUI.Text(segment.text)
                        .font(.system(size: 14 * fontScale, design: .monospaced))
                        .foregroundStyle(theme.secondary)
                } else {
                    return partial + SwiftUI.Text(segment.text)
                }
            }
            .lineSpacing(6 * fontScale)
        }
    }
}

struct CodeBlockView: View {
    let codeBlock: CodeBlock
    @Environment(\.markdownFontScale) private var fontScale
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownMermaidEnabled) private var mermaidEnabled
    @State private var mermaidHeight: CGFloat = 420

    private let mermaidMaxHeight: CGFloat = 1400

    var body: some View {
        if (codeBlock.language ?? "").lowercased() == "mermaid" && mermaidEnabled {
            ScrollView {
                MermaidView(
                    code: codeBlock.code,
                    height: $mermaidHeight,
                    themeName: theme.mermaidTheme,
                    themeVariables: theme.mermaidThemeVariables
                )
                .frame(height: mermaidHeight)
            }
            .frame(height: min(max(mermaidHeight, 60), mermaidMaxHeight))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.disabled)
            .focusable(false)
        } else {
            CodeText(codeBlock.code)
                .codeTextStyle(.card)
                .codeTextColors(theme.highlightColors)
                .font(.system(size: 13 * fontScale, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ListView: View {
    let items: [ListItem]
    let ordered: Bool
    @Environment(\.markdownTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 6) {
                    SwiftUI.Text(ordered ? "\(index + 1)." : "\u{2022}")
                        .foregroundColor(theme.secondary)
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
    @Environment(\.markdownTheme) private var theme

    private var bodyRows: [Markdown.Table.Row] {
        table.body.children.compactMap { $0 as? Markdown.Table.Row }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TableRowView(cells: Array(table.head.children.compactMap { $0 as? Markdown.Table.Cell }), isHeader: true)
                .background(theme.tableBorder.opacity(0.1))

            ForEach(Array(bodyRows.enumerated()), id: \.offset) { index, row in
                Divider()
                TableRowView(cells: Array(row.children.compactMap { $0 as? Markdown.Table.Cell }), isHeader: false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.tableBorder.opacity(0.3), lineWidth: 1)
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
    @Environment(\.markdownTheme) private var theme

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
                attributed.foregroundColor = theme.accent
                attributed.underlineStyle = .single
                return SwiftUI.Text(attributed)
            }
            return SwiftUI.Text(label).foregroundColor(theme.accent).underline()
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
