import Foundation
import Observation

@MainActor
@Observable
final class FindState {
    var query: String = "" {
        didSet { updateMatches() }
    }

    private(set) var matches: [NSRange] = []
    private(set) var currentIndex: Int = -1
    private(set) var highlightedBlockID: Int?

    private var text: String = ""
    private var blockRanges: [(index: Int, range: NSRange)] = []

    var matchDescription: String {
        guard !matches.isEmpty else { return "No matches" }
        return "\(currentIndex + 1) of \(matches.count)"
    }

    func setContext(text: String, blockRanges: [(index: Int, range: NSRange)]) {
        self.text = text
        self.blockRanges = blockRanges
        updateMatches()
    }

    func next() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + 1) % matches.count
        updateHighlight()
    }

    func previous() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        updateHighlight()
    }

    func clear() {
        query = ""
        matches = []
        currentIndex = -1
        highlightedBlockID = nil
    }

    private func updateMatches() {
        matches = []
        currentIndex = -1
        highlightedBlockID = nil

        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !text.isEmpty else { return }

        let pattern = NSRegularExpression.escapedPattern(for: term)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }

        let range = NSRange(location: 0, length: (text as NSString).length)
        matches = regex.matches(in: text, options: [], range: range).map { $0.range }

        if !matches.isEmpty {
            currentIndex = 0
            updateHighlight()
        }
    }

    private func updateHighlight() {
        guard currentIndex >= 0, currentIndex < matches.count else {
            highlightedBlockID = nil
            return
        }
        let match = matches[currentIndex]
        highlightedBlockID = blockRanges.first { NSIntersectionRange(match, $0.range).length > 0 }?.index
    }
}
