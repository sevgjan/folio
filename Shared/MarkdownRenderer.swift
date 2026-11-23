import AppKit
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

private struct MarkdownMermaidEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

private struct MarkdownHighlightQueryKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    @Entry var markdownSnapshot: MarkdownSnapshot? = nil

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
    var markdownHighlightQuery: String? {
        get { self[MarkdownHighlightQueryKey.self] }
        set { self[MarkdownHighlightQueryKey.self] = newValue }
    }
}

extension View {
    func centeredReadingColumn(maxWidth: CGFloat) -> some View {
        self.frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct MarkdownRenderer: View {
    let snapshot: MarkdownSnapshot

    init(markdown: String) {
        snapshot = MarkdownSnapshot(markdown)
    }

    init(snapshot: MarkdownSnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(snapshot.document.children.enumerated()), id: \.offset) { offset, block in
                BlockView(block: block)
                    .id(offset)
                    .environment(\.markdownBlockIndex, offset)
            }
        }
        .scrollTargetLayout()
        .environment(\.markdownSnapshot, snapshot)

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
        Group {
            switch block {
            case let heading as Heading:
                InlineText(children: Array(heading.children), headingLevel: heading.level)
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
                ListView(items: Array(list.children.compactMap { $0 as? ListItem }), start: nil)
                    .centeredReadingColumn(maxWidth: readingWidth)
            case let list as OrderedList:
                ListView(items: Array(list.children.compactMap { $0 as? ListItem }), start: list.startIndex)
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
                    .centeredReadingColumn(maxWidth: tableWidth)
            case is ThematicBreak:
                Divider()
            default:
                InlineText(children: [block])
                    .centeredReadingColumn(maxWidth: readingWidth)
            }
        }
    }


}

struct ParagraphView: View {
    let paragraph: Paragraph
    @Environment(\.markdownBaseURL) private var baseURL

    @Environment(\.markdownSnapshot) private var snapshot
    @Environment(\.markdownBodySize) private var bodySize
    @Environment(\.markdownFontFamily) private var family
    @Environment(\.markdownTheme) private var theme
    @State private var equationHeight: CGFloat = 40

    var body: some View {
        let raw = snapshot.flatMap { snapshot in
            snapshot.range(paragraph).map { (snapshot.source as NSString).substring(with: $0) }
        } ?? paragraph.format()
        Group {
            if !markdownMathRanges(raw).isEmpty {
                EquationView(html: MarkdownWebAssets.body(raw), pointSize: bodySize, family: family,
                             foreground: theme.id == "system" ? Color(nsColor: .labelColor) : theme.foreground,
                             height: $equationHeight)
                    .frame(height: equationHeight)
                    .modifier(RichSourceEditing(markup: paragraph, title: "Edit Equation"))
            } else if paragraph.childCount == 1,
                      let image = paragraph.child(at: 0) as? Markdown.Image,
                      let source = image.source,
                      let url = documentURL(source, relativeTo: baseURL) {
                DocumentImage(url: url, label: image.plainText)
                    .modifier(RichSourceEditing(markup: paragraph, title: "Edit Image"))
            } else {
                InlineText(children: Array(paragraph.children))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func markdownMathRanges(_ raw: String) -> [NSRange] {
    let pattern = #"(?s)(?<!\x5c)[$][$].+?[$][$]|\x5c\[.+?\x5c\]|(?<![\x5c$])[$](?![$\s])[^$\r\n]+?(?<!\s)[$](?![$\d])|\x5c\(.+?\x5c\)|(\x60+).*?\1"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    return regex.matches(in: raw, range: NSRange(location: 0, length: raw.utf16.count))
        .filter { $0.range(at: 1).location == NSNotFound }.map(\.range)
}

struct CodeBlockView: View {
    let codeBlock: CodeBlock
    @Environment(\.markdownFontScale) private var fontScale
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownMermaidEnabled) private var mermaidEnabled
    @Environment(\.markdownEditing) private var editing
    @Environment(\.markdownBlockIndex) private var block
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.markdownActiveMatch) private var activeMatch
    @Environment(\.markdownHighlightQuery) private var highlightQuery
    @State private var mermaidHeight: CGFloat = 420
    @State private var highlighted: AttributedString?
    private static let highlighter = Highlight()

    private let mermaidMaxHeight: CGFloat = 1400

    var body: some View {
        let isDiagram = codeBlock.language?.lowercased() == "mermaid" && mermaidEnabled
        let plainCode = codeBlock.code.hasSuffix("\n") ? String(codeBlock.code.dropLast()) : codeBlock.code
        rendered.modifier(RichSourceEditing(markup: codeBlock,
                                            title: isDiagram ? "Edit Diagram" : "Edit Code",
                                            sourceRange: isDiagram ? codeRuns(plainCode).first?.source : nil,
                                            enabled: isDiagram || codeRuns(plainCode).isEmpty))
    }

    @ViewBuilder private var rendered: some View {
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
            let code = codeBlock.code.hasSuffix("\n") ? String(codeBlock.code.dropLast()) : codeBlock.code
            RenderedTextView(content: codeContent(code), runs: codeRuns(code), editing: editing,
                             focus: block != nil && editing?.focusBlock == block, isTableCell: false)
                .frame(minHeight: ceil(16 * fontScale))
                .padding(12)
                .background(theme.codeBackground, in: RoundedRectangle(cornerRadius: 8))
                .task(id: HighlightInput(code: code, colors: highlightColors)) {
                    let mode: HighlightMode = codeBlock.language.map { .languageAlias($0) } ?? .automatic
                    let result = try? await Self.highlighter.request(code, mode: mode, colors: highlightColors)
                    if !Task.isCancelled { highlighted = result?.attributedText }
                }
        }
    }

    private struct HighlightInput: Equatable {
        let code: String
        let colors: HighlightColors
    }

    private var highlightColors: HighlightColors {
        colorScheme == .dark ? theme.highlightColors.dark : theme.highlightColors.light
    }

    private func codeContent(_ code: String) -> NSAttributedString {
        let styled = highlighted.map { NSAttributedString($0) }
        let result = NSMutableAttributedString(string: code, attributes: [
            .foregroundColor: theme.id == "system" ? NSColor.labelColor : NSColor(theme.foreground)
        ])
        if let styled, styled.string == code { result.setAttributedString(styled) }
        let range = NSRange(location: 0, length: result.length)
        result.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13 * fontScale, weight: .regular), range: range)
        if let highlightQuery, !highlightQuery.isEmpty,
           let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: highlightQuery), options: .caseInsensitive) {
            for match in regex.matches(in: code, range: range) {
                let start = editing?.snapshot.range(codeBlock)?.location
                let active = activeMatch?.source == start && activeMatch?.range == match.range
                result.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(active ? 0.85 : 0.35), range: match.range)
            }
        }
        return result
    }

    private func codeRuns(_ code: String) -> [RenderedTextRun] {
        guard let snapshot = editing?.snapshot, let blockRange = snapshot.range(codeBlock),
              let range = Range(blockRange, in: snapshot.source) else { return [] }
        let raw = snapshot.source[range]
        let trimmed = raw.drop(while: { $0 == " " || $0 == "\t" })
        let body: Substring
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            guard let lineBreak = raw.firstIndex(where: \.isNewline) else { return [] }
            body = raw[raw.index(after: lineBreak)...]
        } else { body = raw }
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix(code),
              let offsets = RenderedTextRun.offsets(source: String(body.prefix(code.count)), displayed: code, parseEscapes: false)
        else { return [] }
        let source = NSRange(location: blockRange.location + raw[..<body.startIndex].utf16.count, length: offsets.last ?? 0)
        return [RenderedTextRun(display: NSRange(location: 0, length: code.utf16.count), source: source,
                                offsets: offsets, code: true, blockCode: true)]
    }
}

struct ListView: View {
    let items: [ListItem]
    let start: UInt?
    @Environment(\.markdownTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 6) {
                    marker(for: item, index: index)
                        .frame(minWidth: 14, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                            BlockView(block: child)
                        }
                    }
                    .opacity(item.checkbox == .checked ? 0.6 : 1)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(for item: ListItem, index: Int) -> some View {
        if let checkbox = item.checkbox {
            Image(systemName: checkbox == .checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checkbox == .checked ? theme.accent : theme.secondary)
        } else {
            SwiftUI.Text(start.map { "\($0 + UInt(index))." } ?? "•")
                .foregroundColor(theme.secondary)
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
            TableRowView(alignments: table.columnAlignments, cells: Array(table.head.children.compactMap { $0 as? Markdown.Table.Cell }), isHeader: true)
                .background(theme.tableBorder.opacity(0.1))

            ForEach(Array(bodyRows.enumerated()), id: \.offset) { index, row in
                Divider()
                TableRowView(alignments: table.columnAlignments, cells: Array(row.children.compactMap { $0 as? Markdown.Table.Cell }), isHeader: false)
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
    let alignments: [Markdown.Table.ColumnAlignment?]
    let cells: [Markdown.Table.Cell]
    let isHeader: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                InlineText(children: Array(cell.children), tableHeader: isHeader,
                           tableAlignment: index < alignments.count ? alignments[index] : nil,
                           isTableCell: true, emptySource: cell)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct InlineText: View {
    let children: [Markup]
    var headingLevel: Int? = nil
    var tableHeader = false
    var tableAlignment: Markdown.Table.ColumnAlignment? = nil
    var isTableCell = false
    var emptySource: Markup? = nil

    @Environment(\.markdownFontScale) private var zoom
    @Environment(\.markdownBodySize) private var bodySize
    @Environment(\.markdownFontFamily) private var family
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownEditing) private var editing
    @Environment(\.markdownBlockIndex) private var block
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownHighlightQuery) private var highlightQuery
    @Environment(\.markdownActiveMatch) private var activeMatch

    var body: some View {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6 * zoom
        switch tableAlignment {
        case .right: paragraph.alignment = .right
        case .center: paragraph.alignment = .center
        default: paragraph.alignment = .left
        }
        let size = headingLevel.map { [28, 22, 19, 17, 16, 15][min(6, max(1, $0)) - 1] * zoom } ?? bodySize
        let weight: NSFont.Weight = headingLevel != nil || tableHeader ? .semibold : .regular
        var font = NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
        if !family.isEmpty && weight == .semibold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        let result = NSMutableAttributedString()
        var runs: [RenderedTextRun] = []
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .paragraphStyle: paragraph,
            .foregroundColor: theme.id == "system" ? NSColor.labelColor : NSColor(theme.foreground)
        ]
        func append(_ text: String, node: Markup, attributes: [NSAttributedString.Key: Any], code: Bool = false) {
            let location = result.length
            result.append(NSAttributedString(string: text, attributes: attributes))
            guard let snapshot = editing?.snapshot, var range = snapshot.range(node),
                  let rawRange = Range(range, in: snapshot.source) else { return }
            let raw = String(snapshot.source[rawRange])
            if code, let inner = raw.range(of: text), !text.isEmpty {
                range.location += raw[..<inner.lowerBound].utf16.count
                range.length = text.utf16.count
            }
            let source = (snapshot.source as NSString).substring(with: range)
            if let offsets = RenderedTextRun.offsets(source: source, displayed: text) {
                runs.append(RenderedTextRun(display: NSRange(location: location, length: text.utf16.count),
                                            source: range, offsets: offsets, code: code))
            }
        }
        func visit(_ node: Markup, attributes inherited: [NSAttributedString.Key: Any]) {
            var attributes = inherited
            switch node {
            case let text as Markdown.Text:
                append(text.string, node: node, attributes: attributes)
                return
            case is SoftBreak, is LineBreak:
                result.append(NSAttributedString(string: "\n", attributes: attributes))
                return
            case let code as InlineCode:
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: size * 0.93, weight: .regular)
                append(code.code, node: node, attributes: attributes, code: true)
                return
            case is Strong:
                attributes[.font] = NSFontManager.shared.convert(attributes[.font] as? NSFont ?? font, toHaveTrait: .boldFontMask)
            case is Emphasis:
                attributes[.font] = NSFontManager.shared.convert(attributes[.font] as? NSFont ?? font, toHaveTrait: .italicFontMask)
            case is Strikethrough:
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            case let link as Markdown.Link:
                attributes[.foregroundColor] = NSColor(theme.accent)
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.link] = link.destination.flatMap { documentURL($0, relativeTo: baseURL) }
            default:
                if node.childCount == 0 {
                    append(node.format(), node: node, attributes: attributes)
                    return
                }
            }
            for child in node.children { visit(child, attributes: attributes) }
        }
        for child in children { visit(child, attributes: attributes) }
        if result.length == 0, let emptySource, let snapshot = editing?.snapshot,
           let range = snapshot.range(emptySource) ?? (emptySource is Markdown.Document
                        ? NSRange(location: snapshot.source.utf16.count, length: 0) : nil) {
            let source = snapshot.source as NSString
            let raw = source.substring(with: range)
            if raw.trimmingCharacters(in: .whitespaces).isEmpty {
                runs.append(RenderedTextRun(display: NSRange(location: 0, length: 0),
                    source: NSRange(location: NSMaxRange(range), length: 0), offsets: [0]))
            }
        }
        if let highlightQuery, !highlightQuery.isEmpty,
           let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: highlightQuery), options: .caseInsensitive) {
            let source = children.first.flatMap { editing?.snapshot.range($0)?.location }
            for match in regex.matches(in: result.string, range: NSRange(location: 0, length: result.length)) {
                let isActive = activeMatch?.source == source && activeMatch?.range == match.range
                result.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(isActive ? 0.85 : 0.35), range: match.range)
                if isActive { result.addAttribute(.foregroundColor, value: NSColor.black, range: match.range) }
            }
        }
        return RenderedTextView(content: result, runs: runs, editing: editing,
                                focus: block != nil && editing?.focusBlock == block, isTableCell: isTableCell)
            .frame(minHeight: ceil(size * 1.25))
    }
}

private func documentURL(_ source: String, relativeTo base: URL?) -> URL? {
    guard let url = URL(string: source, relativeTo: base)?.absoluteURL,
          let scheme = url.scheme?.lowercased(), ["http", "https", "file", "mailto"].contains(scheme)
    else { return nil }
    return url
}

private struct DocumentImage: View {
    let url: URL
    let label: String

    var body: some View {
        if url.isFileURL {
            if let image = NSImage(contentsOf: url) {
                SwiftUI.Image(nsImage: image).resizable().scaledToFit().accessibilityLabel(label)
            } else { SwiftUI.Text(label) }
        } else if url.scheme == "https" || url.scheme == "http" {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit().accessibilityLabel(label)
            } placeholder: { SwiftUI.Text(label) }
        }
    }
}

private struct RichSourceEditing: ViewModifier {
    let markup: Markup
    let title: String
    var sourceRange: NSRange? = nil
    var enabled = true

    @Environment(\.markdownEditing) private var editing
    @FocusState private var sourceFocused: Bool
    @State private var shown = false
    @State private var draft = ""
    @State private var original = ""
    @State private var range: NSRange?
    @State private var blockRange: NSRange?

    private var previewSource: String {
        guard let blockRange, let range else { return draft }
        let raw = (original as NSString).substring(with: blockRange) as NSString
        return raw.replacingCharacters(in: NSRange(location: range.location - blockRange.location,
                                                    length: range.length), with: draft)
    }

    func body(content: Content) -> some View {
        content.overlay {
            if enabled, let editing, editing.isEditing, let fullRange = editing.snapshot.range(markup) {
                Button {
                    original = editing.snapshot.source
                    blockRange = fullRange
                    range = sourceRange ?? fullRange
                    draft = (original as NSString).substring(with: sourceRange ?? fullRange)
                    shown = true
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(title)
                .accessibilityLabel(title)
                .popover(isPresented: $shown, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 12) {
                        SwiftUI.Text(title).font(.headline)
                        TextEditor(text: $draft)
                            .font(.system(.body, design: .monospaced))
                            .focused($sourceFocused)
                            .frame(height: 135)
                            .accessibilityLabel("Source")
                        Divider()
                        ScrollView {
                            MarkdownRenderer(markdown: previewSource)
                                .environment(\.markdownEditing, nil)
                                .environment(\.markdownHighlightQuery, nil)
                                .padding(.vertical, 8)
                        }
                        .frame(height: 150)
                        .accessibilityLabel("Preview")
                        HStack {
                            Button("Cancel") { shown = false }.keyboardShortcut(.cancelAction)
                            Spacer()
                            Button("Apply") {
                                guard let range,
                                      editing.replace(original, [MarkdownReplacement(range: range, text: draft)]) else {
                                    NSSound.beep()
                                    return
                                }
                                shown = false
                            }.keyboardShortcut(.defaultAction)
                        }
                    }
                    .frame(width: 440)
                    .padding(16)
                    .onAppear { sourceFocused = true }
                }
            }
        }
    }
}
