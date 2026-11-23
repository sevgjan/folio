import Foundation
import Markdown
import Observation

@MainActor
@Observable
final class FindState {
    var query = "" { didSet { updateMatches() } }
    private(set) var matches: [RenderedSearchMatch] = []
    private(set) var currentIndex = 0
    private var units: [(block: Int, source: Int, text: String)] = []

    var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var activeMatch: RenderedSearchMatch? { matches.indices.contains(currentIndex) ? matches[currentIndex] : nil }
    var matchDescription: String { matches.isEmpty ? "No matches" : "\(currentIndex + 1) of \(matches.count)" }

    func setContext(_ snapshot: MarkdownSnapshot) {
        units.removeAll()
        func visit(_ node: Markup, block: Int) {
            if node is Heading || node is Paragraph || node is Markdown.Table.Cell || node is CodeBlock {
                guard let source = snapshot.range(node.child(at: 0) ?? node)?.location else { return }
                units.append((block, source, renderedString(node)))
            } else {
                for child in node.children { visit(child, block: block) }
            }
        }
        for (index, node) in snapshot.document.children.enumerated() { visit(node, block: index) }
        updateMatches()
    }

    func next() { if !matches.isEmpty { currentIndex = (currentIndex + 1) % matches.count } }
    func previous() { if !matches.isEmpty { currentIndex = (currentIndex + matches.count - 1) % matches.count } }

    private func updateMatches() {
        let previous = activeMatch
        guard !normalizedQuery.isEmpty,
              let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: normalizedQuery), options: .caseInsensitive) else {
            matches = []
            currentIndex = 0
            return
        }
        matches = units.flatMap { unit in
            regex.matches(in: unit.text, range: NSRange(location: 0, length: unit.text.utf16.count)).map {
                RenderedSearchMatch(block: unit.block, source: unit.source, range: $0.range)
            }
        }
        currentIndex = previous.flatMap { matches.firstIndex(of: $0) } ?? 0
    }

    private func renderedString(_ node: Markup) -> String {
        switch node {
        case let text as Markdown.Text: return text.string
        case let code as InlineCode: return code.code
        case let code as CodeBlock: return code.language?.lowercased() == "mermaid" ? "" : code.code
        case is SoftBreak, is LineBreak: return "\n"
        default: return node.children.map(renderedString).joined()
        }
    }
}
