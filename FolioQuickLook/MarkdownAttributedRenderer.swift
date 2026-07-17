import AppKit
import Markdown

enum MarkdownAttributedRenderer {
    static func render(_ markdown: String) -> NSAttributedString {
        let document = Document(parsing: markdown)
        let result = NSMutableAttributedString()
        for block in document.children {
            result.append(renderBlock(block, quoteDepth: 0))
        }
        return result
    }

    private static func paragraphStyle(spacingAfter: CGFloat, indent: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = spacingAfter
        style.headIndent = indent
        style.firstLineHeadIndent = indent
        style.lineSpacing = 3
        return style
    }

    private static func renderBlock(_ markup: Markup, quoteDepth: Int) -> NSAttributedString {
        let indent = CGFloat(quoteDepth) * 16
        switch markup {
        case let heading as Heading:
            let sizes: [Int: CGFloat] = [1: 26, 2: 21, 3: 18, 4: 16, 5: 15, 6: 14]
            let size = sizes[heading.level] ?? 14
            let font = NSFont.systemFont(ofSize: size, weight: .semibold)
            let text = NSMutableAttributedString(inlineChildren: Array(heading.children), baseFont: font)
            text.addAttribute(.paragraphStyle, value: paragraphStyle(spacingAfter: 10, indent: indent), range: NSRange(location: 0, length: text.length))
            text.append(NSAttributedString(string: "\n"))
            return text
        case let paragraph as Paragraph:
            let font = NSFont.systemFont(ofSize: 14)
            let text = NSMutableAttributedString(inlineChildren: Array(paragraph.children), baseFont: font)
            text.addAttribute(.paragraphStyle, value: paragraphStyle(spacingAfter: 12, indent: indent), range: NSRange(location: 0, length: text.length))
            text.append(NSAttributedString(string: "\n"))
            return text
        case let codeBlock as CodeBlock:
            let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            let style = paragraphStyle(spacingAfter: 12, indent: indent + 10)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor(white: 0.5, alpha: 0.12),
                .paragraphStyle: style
            ]
            let code = codeBlock.code.trimmingCharacters(in: .newlines)
            let result = NSMutableAttributedString(string: code + "\n", attributes: attrs)
            result.append(NSAttributedString(string: "\n"))
            return result
        case let list as UnorderedList:
            let result = NSMutableAttributedString()
            for item in list.children.compactMap({ $0 as? ListItem }) {
                result.append(renderListItem(item, prefix: "•  ", indent: indent))
            }
            return result
        case let list as OrderedList:
            let result = NSMutableAttributedString()
            for (index, item) in list.children.compactMap({ $0 as? ListItem }).enumerated() {
                result.append(renderListItem(item, prefix: "\(index + 1).  ", indent: indent))
            }
            return result
        case let quote as BlockQuote:
            let result = NSMutableAttributedString()
            for child in quote.children {
                let rendered = renderBlock(child, quoteDepth: quoteDepth + 1)
                let mutable = NSMutableAttributedString(attributedString: rendered)
                mutable.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: 0, length: mutable.length))
                result.append(mutable)
            }
            return result
        case let table as Table:
            return renderTable(table, indent: indent)
        case is ThematicBreak:
            let style = paragraphStyle(spacingAfter: 12, indent: indent)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.separatorColor,
                .paragraphStyle: style
            ]
            return NSAttributedString(string: "―――――――――――――――――\n\n", attributes: attrs)
        default:
            let font = NSFont.systemFont(ofSize: 14)
            let text = NSMutableAttributedString(string: markup.format() + "\n", attributes: [.font: font])
            return text
        }
    }

    private static func renderListItem(_ item: ListItem, prefix: String, indent: CGFloat) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 14)
        let result = NSMutableAttributedString()
        var isFirst = true
        for child in item.children {
            if let paragraph = child as? Paragraph {
                let line = NSMutableAttributedString(string: isFirst ? prefix : "", attributes: [.font: font])
                line.append(NSAttributedString(inlineChildren: Array(paragraph.children), baseFont: font))
                line.addAttribute(.paragraphStyle, value: paragraphStyle(spacingAfter: 6, indent: indent + 18), range: NSRange(location: 0, length: line.length))
                line.append(NSAttributedString(string: "\n"))
                result.append(line)
                isFirst = false
            } else {
                result.append(renderBlock(child, quoteDepth: 0))
            }
        }
        return result
    }

    private static func renderTable(_ table: Table, indent: CGFloat) -> NSAttributedString {
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let style = paragraphStyle(spacingAfter: 4, indent: indent)
        let result = NSMutableAttributedString()

        let headerCells = table.head.children.compactMap { $0 as? Table.Cell }
        let headerLine = NSMutableAttributedString()
        for (index, cell) in headerCells.enumerated() {
            if index > 0 { headerLine.append(NSAttributedString(string: "   |   ", attributes: [.font: headerFont, .foregroundColor: NSColor.separatorColor])) }
            headerLine.append(NSAttributedString(inlineChildren: Array(cell.children), baseFont: headerFont))
        }
        headerLine.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: headerLine.length))
        headerLine.append(NSAttributedString(string: "\n"))
        result.append(headerLine)

        let ruleWidth = max(20, headerLine.length)
        result.append(NSAttributedString(
            string: String(repeating: "―", count: min(ruleWidth, 60)) + "\n",
            attributes: [.font: bodyFont, .foregroundColor: NSColor.separatorColor, .paragraphStyle: style]))

        for row in table.body.children.compactMap({ $0 as? Table.Row }) {
            let rowLine = NSMutableAttributedString()
            for (index, cell) in row.children.compactMap({ $0 as? Table.Cell }).enumerated() {
                if index > 0 { rowLine.append(NSAttributedString(string: "   |   ", attributes: [.font: bodyFont, .foregroundColor: NSColor.separatorColor])) }
                rowLine.append(NSAttributedString(inlineChildren: Array(cell.children), baseFont: bodyFont))
            }
            rowLine.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: rowLine.length))
            rowLine.append(NSAttributedString(string: "\n"))
            result.append(rowLine)
        }
        result.append(NSAttributedString(string: "\n"))
        return result
    }
}

private extension NSAttributedString {
    convenience init(inlineChildren children: [Markup], baseFont: NSFont) {
        let result = NSMutableAttributedString()
        for child in children {
            result.append(NSAttributedString.inline(for: child, baseFont: baseFont))
        }
        self.init(attributedString: result)
    }

    static func inline(for node: Markup, baseFont: NSFont) -> NSAttributedString {
        switch node {
        case let text as Markdown.Text:
            return NSAttributedString(string: text.string, attributes: [.font: baseFont])
        case let emphasis as Emphasis:
            let font = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            let result = NSMutableAttributedString()
            for child in emphasis.children { result.append(inline(for: child, baseFont: font)) }
            return result
        case let strong as Strong:
            let font = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            let result = NSMutableAttributedString()
            for child in strong.children { result.append(inline(for: child, baseFont: font)) }
            return result
        case let code as InlineCode:
            let font = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular)
            return NSAttributedString(string: code.code, attributes: [
                .font: font,
                .backgroundColor: NSColor(white: 0.5, alpha: 0.15)
            ])
        case let link as Markdown.Link:
            let result = NSMutableAttributedString()
            for child in link.children { result.append(inline(for: child, baseFont: baseFont)) }
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
            if let destination = link.destination, let url = URL(string: destination) {
                attrs[.link] = url
            }
            result.addAttributes(attrs, range: NSRange(location: 0, length: result.length))
            return result
        case is SoftBreak:
            return NSAttributedString(string: " ", attributes: [.font: baseFont])
        case is LineBreak:
            return NSAttributedString(string: "\n", attributes: [.font: baseFont])
        default:
            return NSAttributedString(string: node.format(), attributes: [.font: baseFont])
        }
    }
}
