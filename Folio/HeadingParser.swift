import Foundation
import Markdown

struct HeadingItem: Identifiable {
    let id: Int
    let level: Int
    let title: String
    let sourceRange: NSRange
}

enum HeadingParser {
    static func parse(_ text: String) -> [HeadingItem] {
        let document = Document(parsing: text)
        var items: [HeadingItem] = []

        for (index, block) in document.children.enumerated() {
            guard let heading = block as? Heading else { continue }
            let title = plainText(from: heading)
            guard !title.isEmpty else { continue }
            guard let sourceRange = heading.range,
                  let range = nsRange(for: sourceRange, in: text) else { continue }
            items.append(HeadingItem(id: index, level: heading.level, title: title, sourceRange: range))
        }

        return items
    }

    static func blockRanges(in text: String) -> [(index: Int, range: NSRange)] {
        let document = Document(parsing: text)
        return document.children.enumerated().compactMap { index, block in
            guard let sourceRange = block.range,
                  let range = nsRange(for: sourceRange, in: text) else { return nil }
            return (index, range)
        }
    }

    private static func plainText(from markup: Markup) -> String {
        if let text = markup as? Markdown.Text {
            return text.string
        }
        if let code = markup as? InlineCode {
            return code.code
        }
        if markup is SoftBreak || markup is LineBreak {
            return " "
        }
        return markup.children.map(plainText).joined()
    }

    static func nsRange(for sourceRange: SourceRange, in text: String) -> NSRange? {
        guard let start = utf16Offset(for: sourceRange.lowerBound, in: text),
              let end = utf16Offset(for: sourceRange.upperBound, in: text),
              end >= start else {
            return nil
        }
        return NSRange(location: start, length: end - start)
    }

    /// SourceLocation.column is a UTF-8 byte column within the line, so we locate the
    /// line start in UTF-8 bytes, advance by the column, then convert to a UTF-16 offset.
    private static func utf16Offset(for location: SourceLocation, in text: String) -> Int? {
        let utf8 = text.utf8
        var line = 1
        var lineStart = utf8.startIndex
        var index = utf8.startIndex

        func offsetInLine(start: String.UTF8View.Index) -> Int {
            let target = utf8.index(start, offsetBy: max(0, location.column - 1), limitedBy: utf8.endIndex) ?? utf8.endIndex
            let byteOffset = utf8.distance(from: utf8.startIndex, to: target)
            return String(decoding: utf8.prefix(byteOffset), as: UTF8.self).utf16.count
        }

        while index < utf8.endIndex {
            if line == location.line {
                return offsetInLine(start: lineStart)
            }
            if utf8[index] == UInt8(ascii: "\n") {
                line += 1
                lineStart = utf8.index(after: index)
            }
            index = utf8.index(after: index)
        }

        if line == location.line {
            return offsetInLine(start: lineStart)
        }
        return nil
    }
}
