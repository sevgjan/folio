import AppKit
import SwiftUI

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var fontFamily: String = ""
    var theme: Theme = .system
    var onTextViewReady: (MarkdownTextView) -> Void = { _ in }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.baseFontSize = fontSize
        textView.fontFamily = fontFamily
        textView.theme = theme
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 32, height: 24)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        textView.restyle()
        onTextViewReady(textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? MarkdownTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.restyle()
        }
        if textView.baseFontSize != fontSize {
            textView.baseFontSize = fontSize
        }
        if textView.fontFamily != fontFamily {
            textView.fontFamily = fontFamily
        }
        if textView.theme != theme {
            textView.theme = theme
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            text.wrappedValue = textView.string
            textView.restyle()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            textView.handleSelectionChange()
        }
    }
}

final class MarkdownTextView: NSTextView {
    var baseFontSize: CGFloat = 16 {
        didSet { restyle() }
    }
    var fontFamily: String = "" {
        didSet { restyle() }
    }
    var theme: Theme = .system {
        didSet { applyThemeChrome(); restyle() }
    }

    private var lastActiveLineLocation: Int?

    private func applyThemeChrome() {
        if theme.id == "system" {
            drawsBackground = true
            backgroundColor = .textBackgroundColor
            appearance = nil
        } else {
            drawsBackground = true
            backgroundColor = NSColor(theme.background)
            appearance = NSAppearance(named: theme.colorScheme == .light ? .aqua : .darkAqua)
        }
    }

    private func themedFont(ofSize size: CGFloat) -> NSFont {
        fontFamily.isEmpty ? .systemFont(ofSize: size) : (NSFont(name: fontFamily, size: size) ?? .systemFont(ofSize: size))
    }

    private func themedBoldFont(ofSize size: CGFloat) -> NSFont {
        fontFamily.isEmpty
            ? .boldSystemFont(ofSize: size)
            : NSFontManager.shared.convert(themedFont(ofSize: size), toHaveTrait: .boldFontMask)
    }

    func handleSelectionChange() {
        let cursorLocation = selectedRange().location

        guard let textStorage else { return }
        let activeLineLocation = (textStorage.string as NSString).lineRange(for: selectedRange()).location
        guard activeLineLocation != lastActiveLineLocation else { return }

        let previousLocation = lastActiveLineLocation
        lastActiveLineLocation = activeLineLocation

        if let previousLocation,
           let oldBlock = stableBlockRange(containing: previousLocation),
           let newBlock = stableBlockRange(containing: cursorLocation),
           oldBlock == newBlock {
            return
        }

        restyle()
    }

    /// A table or fenced code block: ranges where per-line active-line styling never differs,
    /// so moving the cursor between lines inside the same one shouldn't trigger a restyle.
    private func stableBlockRange(containing location: Int) -> NSRange? {
        if let table = tableBlockRange(containing: location) { return table }
        return codeFenceBlockRange(containing: location)
    }

    private func codeFenceBlockRange(containing location: Int) -> NSRange? {
        guard let textStorage else { return nil }
        let nsText = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0, location >= 0, location <= nsText.length else { return nil }

        var fenceStart: Int?
        var result: NSRange?

        nsText.enumerateSubstrings(in: fullRange, options: [.byLines]) { line, lineRange, enclosingRange, stop in
            guard let line else { return }
            let lineNS = line as NSString
            guard MarkdownStyleRegex.codeFence.firstMatch(in: line, range: NSRange(location: 0, length: lineNS.length)) != nil else { return }

            if let start = fenceStart {
                let blockEnd = enclosingRange.location + enclosingRange.length
                let range = NSRange(location: start, length: blockEnd - start)
                if location >= range.location && location <= blockEnd {
                    result = range
                    stop.pointee = true
                }
                fenceStart = nil
            } else {
                fenceStart = lineRange.location
            }
        }

        return result
    }

    func allTableBlocks() -> [(range: NSRange, text: String)] {
        guard let textStorage else { return [] }
        let nsText = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0 else { return [] }

        var blocks: [(NSRange, String)] = []
        var currentStart: Int?
        var currentEnd = 0

        nsText.enumerateSubstrings(in: fullRange, options: [.byLines]) { _, lineRange, enclosingRange, _ in
            if self.isTableRowLine(nsText, lineRange) {
                if currentStart == nil { currentStart = lineRange.location }
                currentEnd = enclosingRange.location + enclosingRange.length
            } else if let start = currentStart {
                let range = NSRange(location: start, length: currentEnd - start)
                blocks.append((range, nsText.substring(with: range)))
                currentStart = nil
            }
        }
        if let start = currentStart {
            let range = NSRange(location: start, length: currentEnd - start)
            blocks.append((range, nsText.substring(with: range)))
        }

        return blocks.filter { $0.1.components(separatedBy: .newlines).filter { !$0.isEmpty }.count >= 2 }
    }

    func replaceTableBlock(range: NSRange, with replacement: String) {
        var replacement = replacement
        guard let textStorage else { return }
        let nsText = textStorage.string as NSString
        let hadTrailingNewline = range.location + range.length <= nsText.length
            && nsText.substring(with: range).hasSuffix("\n")
        if hadTrailingNewline && !replacement.hasSuffix("\n") {
            replacement += "\n"
        }
        replaceRange(range, with: replacement)
    }

    private func tableBlockRange(containing location: Int) -> NSRange? {
        guard let textStorage else { return nil }
        let nsText = textStorage.string as NSString
        guard location >= 0, location <= nsText.length else { return nil }

        let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
        guard isTableRowLine(nsText, lineRange) else { return nil }

        var start = lineRange.location
        var cursor = lineRange
        while cursor.location > 0 {
            let previousLineRange = nsText.lineRange(for: NSRange(location: cursor.location - 1, length: 0))
            guard isTableRowLine(nsText, previousLineRange) else { break }
            start = previousLineRange.location
            cursor = previousLineRange
        }

        var end = lineRange.location + lineRange.length
        cursor = lineRange
        while end < nsText.length {
            let nextLineRange = nsText.lineRange(for: NSRange(location: end, length: 0))
            guard isTableRowLine(nsText, nextLineRange) else { break }
            end = nextLineRange.location + nextLineRange.length
            cursor = nextLineRange
        }

        let blockRange = NSRange(location: start, length: end - start)
        let block = nsText.substring(with: blockRange)
        let lines = block.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }
        return blockRange
    }

    private func isTableRowLine(_ nsText: NSString, _ lineRange: NSRange) -> Bool {
        let line = nsText.substring(with: lineRange)
        return MarkdownStyleRegex.tableRow.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    private func replaceRange(_ range: NSRange, with replacement: String) {
        guard let textStorage else { return }
        let cursorLocation = selectedRange().location
        let delta = (replacement as NSString).length - range.length

        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage.replaceCharacters(in: range, with: replacement)
        didChangeText()

        if cursorLocation >= range.location + range.length {
            setSelectedRange(NSRange(location: max(0, cursorLocation + delta), length: 0))
        } else if cursorLocation >= range.location {
            setSelectedRange(NSRange(location: range.location, length: 0))
        }
    }

    func restyle() {
        guard let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }
        let nsText = textStorage.string as NSString
        let activeLineRange = nsText.lineRange(for: selectedRange())

        let isSystemTheme = theme.id == "system"
        let baseFont = themedFont(ofSize: baseFontSize)
        let monoFont = NSFont.monospacedSystemFont(ofSize: baseFontSize - 1, weight: .regular)
        let mutedColor: NSColor = isSystemTheme ? .tertiaryLabelColor : NSColor(theme.muted)
        let codeBackground: NSColor = isSystemTheme
            ? (NSColor.textBackgroundColor.blended(withFraction: 0.08, of: .labelColor) ?? .clear)
            : NSColor(theme.codeBackground)
        let foregroundColor: NSColor = isSystemTheme ? .labelColor : NSColor(theme.foreground)
        let secondaryColor: NSColor = isSystemTheme ? .secondaryLabelColor : NSColor(theme.secondary)
        let linkColor: NSColor = isSystemTheme ? .linkColor : NSColor(theme.accent)
        let mathColor: NSColor = isSystemTheme ? .systemPurple : NSColor(theme.mathAccent)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacingBefore = 4

        textStorage.beginEditing()
        textStorage.setAttributes([
            .font: baseFont,
            .foregroundColor: foregroundColor,
            .paragraphStyle: paragraphStyle
        ], range: fullRange)

        var inCodeFence = false

        nsText.enumerateSubstrings(in: fullRange, options: [.byLines]) { line, lineRange, _, _ in
            guard let line, lineRange.length > 0 else { return }
            let lineNS = line as NSString
            let lineFullRange = NSRange(location: 0, length: lineNS.length)

            func absolute(_ range: NSRange) -> NSRange {
                NSRange(location: lineRange.location + range.location, length: range.length)
            }

            let isActiveLine = lineRange.location == activeLineRange.location
            let markerColor: NSColor = isActiveLine ? mutedColor : .clear

            if MarkdownStyleRegex.codeFence.firstMatch(in: line, range: lineFullRange) != nil {
                inCodeFence.toggle()
                textStorage.addAttributes([.font: monoFont, .foregroundColor: mutedColor], range: lineRange)
                return
            }

            if inCodeFence {
                textStorage.addAttributes([.font: monoFont, .backgroundColor: codeBackground], range: lineRange)
                return
            }

            if let match = MarkdownStyleRegex.heading.firstMatch(in: line, range: lineFullRange) {
                let level = match.range(at: 1).length
                let size = self.baseFontSize + CGFloat(max(0, 6 - level)) * 3
                textStorage.addAttributes([.font: self.themedBoldFont(ofSize: size)], range: lineRange)
                textStorage.addAttributes([.font: NSFont.systemFont(ofSize: 11), .foregroundColor: markerColor], range: absolute(match.range(at: 0)))
            }

            if MarkdownStyleRegex.tableRow.firstMatch(in: line, range: lineFullRange) != nil {
                textStorage.addAttributes([.font: monoFont], range: lineRange)
            }

            if let match = MarkdownStyleRegex.blockquote.firstMatch(in: line, range: lineFullRange) {
                textStorage.addAttributes([.foregroundColor: secondaryColor], range: lineRange)
                textStorage.addAttributes([.foregroundColor: mutedColor], range: absolute(match.range(at: 1)))
            }

            if let match = MarkdownStyleRegex.unorderedList.firstMatch(in: line, range: lineFullRange) {
                textStorage.addAttributes([.foregroundColor: mutedColor], range: absolute(match.range(at: 1)))
            }
            if let match = MarkdownStyleRegex.orderedList.firstMatch(in: line, range: lineFullRange) {
                textStorage.addAttributes([.foregroundColor: mutedColor], range: absolute(match.range(at: 1)))
            }

            MarkdownStyleRegex.bold.enumerateMatches(in: line, range: lineFullRange) { match, _, _ in
                guard let match else { return }
                let markerLength = match.range(at: 1).length
                let content = match.range(at: 2)
                let openMarker = NSRange(location: match.range(at: 0).location, length: markerLength)
                let closeMarker = NSRange(location: content.location + content.length, length: markerLength)
                textStorage.addAttributes([.font: self.themedBoldFont(ofSize: self.baseFontSize)], range: absolute(content))
                textStorage.addAttributes([.foregroundColor: markerColor], range: absolute(openMarker))
                textStorage.addAttributes([.foregroundColor: markerColor], range: absolute(closeMarker))
            }

            MarkdownStyleRegex.italic.enumerateMatches(in: line, range: lineFullRange) { match, _, _ in
                guard let match else { return }
                let group = match.range(at: 1).location != NSNotFound ? 1 : 2
                let content = match.range(at: group)
                guard content.location != NSNotFound else { return }
                let openMarker = NSRange(location: match.range(at: 0).location, length: 1)
                let closeMarker = NSRange(location: content.location + content.length, length: 1)
                let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
                textStorage.addAttributes([.font: italicFont], range: absolute(content))
                textStorage.addAttributes([.foregroundColor: markerColor], range: absolute(openMarker))
                textStorage.addAttributes([.foregroundColor: markerColor], range: absolute(closeMarker))
            }

            MarkdownStyleRegex.strikethrough.enumerateMatches(in: line, range: lineFullRange) { match, _, _ in
                guard let match else { return }
                let content = match.range(at: 1)
                textStorage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue], range: absolute(content))
                let openMarker = NSRange(location: match.range(at: 0).location, length: 2)
                let closeMarker = NSRange(location: content.location + content.length, length: 2)
                textStorage.addAttributes([.foregroundColor: markerColor], range: absolute(openMarker))
                textStorage.addAttributes([.foregroundColor: markerColor], range: absolute(closeMarker))
            }

            MarkdownStyleRegex.inlineCode.enumerateMatches(in: line, range: lineFullRange) { match, _, _ in
                guard let match else { return }
                let content = match.range(at: 1)
                textStorage.addAttributes([.font: monoFont, .backgroundColor: codeBackground], range: absolute(content))
                let openMarker = NSRange(location: match.range(at: 0).location, length: 1)
                let closeMarker = NSRange(location: content.location + content.length, length: 1)
                textStorage.addAttributes([.foregroundColor: markerColor, .font: monoFont], range: absolute(openMarker))
                textStorage.addAttributes([.foregroundColor: markerColor, .font: monoFont], range: absolute(closeMarker))
            }

            MarkdownStyleRegex.link.enumerateMatches(in: line, range: lineFullRange) { match, _, _ in
                guard let match else { return }
                let full = match.range(at: 0)
                let textContent = match.range(at: 1)
                let contentEnd = textContent.location + textContent.length
                let prefixRange = NSRange(location: full.location, length: 1)
                let suffixRange = NSRange(location: contentEnd, length: full.location + full.length - contentEnd)
                textStorage.addAttributes([.foregroundColor: linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: absolute(textContent))
                textStorage.addAttributes([.foregroundColor: markerColor], range: absolute(prefixRange))
                textStorage.addAttributes([.foregroundColor: markerColor], range: absolute(suffixRange))
            }

            MarkdownStyleRegex.mathSpan.enumerateMatches(in: line, range: lineFullRange) { match, _, _ in
                guard let match else { return }
                textStorage.addAttributes([.font: monoFont, .foregroundColor: mathColor], range: absolute(match.range(at: 0)))
            }
        }

        textStorage.endEditing()
    }
}

enum MarkdownStyleRegex {
    static let codeFence = try! NSRegularExpression(pattern: "^\\s*```")
    static let heading = try! NSRegularExpression(pattern: "^(#{1,6})[ \\t]+")
    static let blockquote = try! NSRegularExpression(pattern: "^\\s*(>[ \\t]?)")
    static let unorderedList = try! NSRegularExpression(pattern: "^\\s*([-*+])[ \\t]+")
    static let orderedList = try! NSRegularExpression(pattern: "^\\s*(\\d+\\.)[ \\t]+")
    static let tableRow = try! NSRegularExpression(pattern: "^\\s*\\|.*\\|\\s*$")
    static let bold = try! NSRegularExpression(pattern: "(\\*\\*|__)(.+?)\\1")
    static let italic = try! NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)")
    static let strikethrough = try! NSRegularExpression(pattern: "~~(.+?)~~")
    static let inlineCode = try! NSRegularExpression(pattern: "`([^`]+?)`")
    static let link = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)")
    static let mathSpan = try! NSRegularExpression(pattern: "\\${1,2}[^$]+\\${1,2}")
}
