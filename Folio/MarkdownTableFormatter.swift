import Foundation

enum MarkdownTableFormatter {
    enum ColumnAlignment {
        case left, right, center
    }

    struct ParsedTable {
        var rows: [[String]]
        var alignments: [ColumnAlignment]
    }

    static func align(_ block: String) -> String? {
        guard let parsed = parse(block) else { return nil }
        return serialize(parsed)
    }

    static func parse(_ block: String) -> ParsedTable? {
        let lines = block.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }

        let allRows = lines.map(parseRow)
        guard let separatorRow = allRows[safe: 1], isSeparatorRow(separatorRow) else { return nil }

        let columnCount = allRows[0].count
        guard columnCount > 0 else { return nil }

        let alignments = (0..<columnCount).map { columnAlignment(for: separatorRow[safe: $0] ?? "---") }
        let dataRows = allRows.enumerated().filter { $0.offset != 1 }.map { padRow($0.element, to: columnCount) }

        return ParsedTable(rows: dataRows, alignments: alignments)
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
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
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
            let content = row[safe: column] ?? ""
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
