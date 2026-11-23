import AppKit
import Markdown
import SwiftUI

struct MarkdownSnapshot {
    let source: String
    let document: Markdown.Document
    private let bytes: [UInt8]
    private let lineStarts: [(byte: Int, utf16: Int)]

    init(_ source: String) {
        self.source = source
        document = Markdown.Document(parsing: source, options: .disableSmartOpts)
        bytes = Array(source.utf8)
        var starts = [(0, 0)]
        var byte = 0
        var utf16 = 0
        for scalar in source.unicodeScalars {
            byte += scalar.utf8.count
            utf16 += scalar.utf16.count
            if scalar == "\n" || (scalar == "\r" && (byte == bytes.count || bytes[byte] != 10)) {
                starts.append((byte, utf16))
            }
        }
        lineStarts = starts
    }

    func range(_ markup: Markup) -> NSRange? {
        guard let range = markup.range,
              let start = offset(range.lowerBound), let end = offset(range.upperBound),
              end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private func offset(_ position: SourceLocation) -> Int? {
        let line = position.line - 1
        guard lineStarts.indices.contains(line), position.column > 0 else { return nil }
        let start = lineStarts[line]
        let end = start.byte + position.column - 1
        let limit = line + 1 < lineStarts.count ? lineStarts[line + 1].byte : bytes.count
        guard end <= limit, let prefix = String(bytes: bytes[start.byte..<end], encoding: .utf8) else { return nil }
        return start.utf16 + prefix.utf16.count
    }
}

struct MarkdownEditing {
    let snapshot: MarkdownSnapshot
    let isEditing: Bool
    let focusBlock: Int?
    let replace: (String, [MarkdownReplacement]) -> Bool
}

extension EnvironmentValues {
    @Entry var markdownEditing: MarkdownEditing? = nil
    @Entry var markdownBlockIndex: Int? = nil
    @Entry var markdownBodySize: CGFloat = 15
    @Entry var markdownBaseURL: URL? = nil
}

struct RenderedTextRun {
    let display: NSRange
    let source: NSRange
    let offsets: [Int]
    var code = false
    var blockCode = false

    static func offsets(source: String, displayed: String, parseEscapes: Bool = true) -> [Int]? {
        if source == displayed { return Array(0...source.utf16.count) }
        let raw = Array(source.utf16)
        var decoded: [UInt16] = []
        var offsets = [0]
        var i = 0
        while i < raw.count {
            if !parseEscapes, raw[i] == 13, i + 1 < raw.count, raw[i + 1] == 10 {
                decoded.append(10)
                i += 2
            } else if parseEscapes, raw[i] == 38, i + 2 < raw.count, raw[i + 1] == 35,
               let end = raw[(i + 2)...].firstIndex(of: 59),
               let value = UInt32(String(decoding: raw[(i + 2)..<end], as: UTF16.self)),
               let scalar = UnicodeScalar(value), scalar.isASCII {
                decoded.append(UInt16(value))
                i = end + 1
            } else {
                if parseEscapes, raw[i] == 92, i + 1 < raw.count, raw[i + 1] < 128,
                   let scalar = UnicodeScalar(UInt32(raw[i + 1])),
                   CharacterSet.punctuationCharacters.union(.symbols).contains(scalar) {
                    i += 1
                }
                decoded.append(raw[i])
                i += 1
            }
            offsets.append(i)
        }
        return String(decoding: decoded, as: UTF16.self) == displayed ? offsets : nil
    }
}

struct RenderedTextView: NSViewRepresentable {
    let content: NSAttributedString
    let runs: [RenderedTextRun]
    let editing: MarkdownEditing?
    let focus: Bool
    let isTableCell: Bool

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.importsGraphics = false
        view.linkTextAttributes = [:]
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        let coordinator = context.coordinator
        let wasEditing = coordinator.parent.editing?.isEditing == true
        coordinator.parent = self
        view.isEditable = editing?.isEditing == true && !runs.isEmpty
        view.isSelectable = true
        if !view.hasMarkedText(), view.attributedString() != content {
            let selection = view.selectedRange()
            view.textStorage?.setAttributedString(content)
            let location = min(selection.location, content.length)
            view.setSelectedRange(NSRange(location: location, length: min(selection.length, content.length - location)))
        }
        if view.isEditable, !wasEditing, focus {
            DispatchQueue.main.async { [weak view] in
                guard let view, view.isEditable, let window = view.window,
                      !(window.firstResponder is NSTextView) else { return }
                // Restore the clip origin after AppKit reveals the insertion point.
                let clip = view.enclosingScrollView?.contentView
                let origin = clip?.bounds.origin
                window.makeFirstResponder(view)
                if let origin { clip?.scroll(to: origin) }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0,
              let container = nsView.textContainer, let layout = nsView.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(max(layout.usedRect(for: container).height, layout.extraLineFragmentRect.maxY)))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RenderedTextView
        private var pending: (range: NSRange, text: String)?

        init(_ parent: RenderedTextView) { self.parent = parent }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            parent.editing?.isEditing == true
        }

        func textView(_ view: NSTextView, shouldChangeTextIn affected: NSRange, replacementString: String?) -> Bool {
            guard let replacementString, parent.editing?.isEditing == true else { return false }
            pending = (affected, replacementString)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, !view.hasMarkedText(),
                  let editing = parent.editing else { return }
            let original = Array(parent.content.string)
            let updated = Array(view.string)
            guard original != updated else { return }
            let prefix = zip(original, updated).prefix { $0.0 == $0.1 }.count
            let suffix = zip(original.dropFirst(prefix).reversed(), updated.dropFirst(prefix).reversed())
                .prefix { $0.0 == $0.1 }.count
            let start = String(original.prefix(prefix)).utf16.count
            let removed = String(original[prefix..<(original.count - suffix)]).utf16.count
            let replacement = String(updated[prefix..<(updated.count - suffix)])
            let affected = NSRange(location: start, length: removed)
            let overlaps = parent.runs.filter { NSIntersectionRange($0.display, affected).length > 0 }
            let insertionRun = parent.runs.first { NSLocationInRange(start, $0.display) }
                ?? parent.runs.last { NSMaxRange($0.display) == start }
            let targets = removed == 0 ? insertionRun.map { [$0] } ?? [] : overlaps
            var operations: [MarkdownReplacement] = []
            for (index, run) in targets.enumerated() {
                let intersection = removed == 0 ? affected : NSIntersectionRange(run.display, affected)
                let lower = run.offsets[intersection.location - run.display.location]
                let upper = run.offsets[NSMaxRange(intersection) - run.display.location]
                let source = NSRange(location: run.source.location + lower, length: upper - lower)
                guard index != 0 || !run.code || run.blockCode || !replacement.contains(where: { $0 == "`" || $0.isNewline }) else {
                    operations.removeAll()
                    break
                }
                operations.append(MarkdownReplacement(range: source, text: index == 0
                    ? literal(replacement, code: run.code, table: parent.isTableCell) : ""))
            }
            let covered = overlaps.reduce(0) { $0 + NSIntersectionRange($1.display, affected).length }
            if operations.isEmpty || covered != removed || !editing.replace(editing.snapshot.source, operations) {
                view.textStorage?.setAttributedString(parent.content)
                view.setSelectedRange(NSRange(location: start, length: 0))
                NSSound.beep()
            }
        }

        private func literal(_ text: String, code: Bool, table: Bool) -> String {
            if code && !table { return text }
            return text.map { character in
                if character.isNewline { return table ? " " : "\n" }
                if character == "|" && table { return "\\|" }
                guard !code, character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first,
                      scalar.isASCII, CharacterSet.punctuationCharacters.union(.symbols).contains(scalar)
                else { return String(character) }
                return "&#\(scalar.value);"
            }.joined()
        }
    }
}

struct RenderedSearchMatch: Equatable {
    let block: Int
    let source: Int
    let range: NSRange
}

extension EnvironmentValues {
    @Entry var markdownActiveMatch: RenderedSearchMatch? = nil
}
