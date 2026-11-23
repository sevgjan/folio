import Foundation

@main
struct TableFormatterTests {
    static func main() {
        let source = "| Name | Detail |\r\n| --- | --- |\r\n| A \\| B | keep this |\r\n"
        let table = MarkdownTableFormatter.parse(source)!
        precondition(table.rows == [["Name", "Detail"], ["A \\| B", "keep this"]])
        precondition(MarkdownTableFormatter.parse(MarkdownTableFormatter.serialize(table)) == table)
        precondition(MarkdownTableFormatter.replacements(in: source, at: 0, with: table).isEmpty)
        var revised = table
        revised.rows[1][1] = "changed"
        let result = NSMutableString(string: source)
        for edit in MarkdownTableFormatter.replacements(in: source, at: 0, with: revised).reversed() {
            result.replaceCharacters(in: edit.range, with: edit.text)
        }
        precondition((result as String).hasPrefix("| Name | Detail |\r\n| --- | --- |\r\n"))
        precondition((result as String).hasSuffix("\r\n"))
        precondition(MarkdownTableFormatter.parse(result as String) == revised)
        precondition(MarkdownTableFormatter.parse("| A |\n| --- |\n| one | extra |") == nil)
    }
}
