import Foundation

enum MarkdownTableFormatter {
    enum ColumnAlignment {
        case left, right, center
    }

    struct ParsedTable: Equatable {
        var rows: [[String]]
        var alignments: [ColumnAlignment]
    }

    static func align(_ block: String) -> String? {
        guard let parsed = parse(block) else { return nil }
        return serialize(parsed)
    }

    static func parse(_ block: String) -> ParsedTable? {
        let lines = block.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).map(String.init)
        guard lines.count >= 2 else { return nil }

        let allRows = lines.map(parseRow)
        guard let separatorRow = allRows[safe: 1], isSeparatorRow(separatorRow) else { return nil }

        let columnCount = allRows[0].count
        guard columnCount > 0, separatorRow.count == columnCount,
              allRows.allSatisfy({ $0.count <= columnCount }) else { return nil }

        let alignments = (0..<columnCount).map { columnAlignment(for: separatorRow[safe: $0] ?? "---") }
        let dataRows = allRows.enumerated().filter { $0.offset != 1 }.map { padRow($0.element, to: columnCount) }

        return ParsedTable(rows: dataRows, alignments: alignments)
    }

    static func replacements(in raw: String, at location: Int, with table: ParsedTable) -> [MarkdownReplacement] {
        guard let original = parse(raw), original != table else { return [] }
        let source = raw as NSString
        var lines: [NSRange] = []
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: .byLines) { _, range, _, _ in
            if range.length > 0 { lines.append(range) }
        }
        let updated = serialize(table).components(separatedBy: "\n")
        if original.rows.count == table.rows.count, original.alignments == table.alignments,
           lines.count == updated.count {
            return table.rows.indices.compactMap { index in
                guard original.rows[index] != table.rows[index] else { return nil }
                let line = lines[index == 0 ? 0 : index + 1]
                return MarkdownReplacement(range: NSRange(location: location + line.location, length: line.length),
                                           text: updated[index == 0 ? 0 : index + 1])
            }
        }
        guard let last = lines.last else { return [] }
        let newline = raw.contains("\r\n") ? "\r\n" : (raw.contains("\r") ? "\r" : "\n")
        return [MarkdownReplacement(range: NSRange(location: location, length: NSMaxRange(last)),
                                    text: updated.joined(separator: newline))]
    }

    static func serialize(_ table: ParsedTable) -> String {
        let columnCount = table.alignments.count
        guard columnCount > 0, !table.rows.isEmpty else { return "" }

        var widths = [Int](repeating: 3, count: columnCount)
        for row in table.rows {
            for column in 0..<columnCount {
                widths[column] = max(widths[column], (row[safe: column] ?? "").count)
            }
        }

        var lines = [formatDataRow(table.rows[0], widths: widths, alignments: table.alignments, columnCount: columnCount)]
        lines.append(formatSeparatorRow(widths: widths, alignments: table.alignments))
        for row in table.rows.dropFirst() {
            lines.append(formatDataRow(row, widths: widths, alignments: table.alignments, columnCount: columnCount))
        }

        return lines.joined(separator: "\n")
    }

    private static func padRow(_ row: [String], to columnCount: Int) -> [String] {
        var row = row
        while row.count < columnCount {
            row.append("")
        }
        return Array(row.prefix(columnCount))
    }

    private static func parseRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        var cells = [""]
        var escaped = false
        for character in trimmed {
            if character == "|" && !escaped {
                cells.append("")
            } else {
                cells[cells.count - 1].append(character)
            }
            escaped = character == "\\" && !escaped
        }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isSeparatorRow(_ cells: [String]) -> Bool {
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" }
        }
    }

    private static func columnAlignment(for separatorCell: String) -> ColumnAlignment {
        let left = separatorCell.hasPrefix(":")
        let right = separatorCell.hasSuffix(":")
        if left && right { return .center }
        if right { return .right }
        return .left
    }

    private static func formatDataRow(_ row: [String], widths: [Int], alignments: [ColumnAlignment], columnCount: Int) -> String {
        let cells = (0..<columnCount).map { column -> String in
            let value = row[safe: column] ?? ""
            var content = ""
            var escaped = false
            for character in value {
                if character == "|" && !escaped { content.append("\\") }
                content.append(character)
                escaped = character == "\\" && !escaped
            }
            return pad(content, to: widths[column], alignment: alignments[column])
        }
        return "| " + cells.joined(separator: " | ") + " |"
    }

    private static func formatSeparatorRow(widths: [Int], alignments: [ColumnAlignment]) -> String {
        let cells = widths.enumerated().map { index, width -> String in
            switch alignments[index] {
            case .left:
                return String(repeating: "-", count: width)
            case .right:
                return String(repeating: "-", count: max(1, width - 1)) + ":"
            case .center:
                return ":" + String(repeating: "-", count: max(1, width - 2)) + ":"
            }
        }
        return "| " + cells.joined(separator: " | ") + " |"
    }

    private static func pad(_ content: String, to width: Int, alignment: ColumnAlignment) -> String {
        let deficit = max(0, width - content.count)
        switch alignment {
        case .left:
            return content + String(repeating: " ", count: deficit)
        case .right:
            return String(repeating: " ", count: deficit) + content
        case .center:
            let left = deficit / 2
            let right = deficit - left
            return String(repeating: " ", count: left) + content + String(repeating: " ", count: right)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
