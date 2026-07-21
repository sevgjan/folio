import HighlightSwift
import SwiftUI

/// A named color/typography palette for the preview and editor. `.system` is a
/// passthrough that reproduces today's exact dynamic system colors — every other
/// theme uses fixed colors and forces its own light/dark appearance.
struct Theme: Identifiable, Equatable, @unchecked Sendable {
    let id: String
    let name: String
    let swatch: Color
    let colorScheme: ColorScheme?

    let background: Color
    let foreground: Color
    let secondary: Color
    let muted: Color
    let accent: Color
    let mathAccent: Color
    let codeBackground: Color
    let tableBorder: Color

    let highlightColors: CodeTextColors
    /// "system" is a sentinel meaning "derive default/dark from the app's effective appearance",
    /// matching MermaidView's original behavior. Any other value is a real mermaid.js theme name.
    let mermaidTheme: String
    let mermaidThemeVariables: [String: String]?

    static let system = Theme(
        id: "system",
        name: "System",
        swatch: .accentColor,
        colorScheme: nil,
        background: .clear,
        foreground: .primary,
        secondary: .secondary,
        muted: Color(nsColor: .tertiaryLabelColor),
        accent: .accentColor,
        mathAccent: Color(nsColor: .systemPurple),
        codeBackground: Color(nsColor: NSColor.textBackgroundColor.blended(withFraction: 0.08, of: .labelColor) ?? .clear),
        tableBorder: .secondary,
        highlightColors: .theme(.xcode),
        mermaidTheme: "system",
        mermaidThemeVariables: nil
    )

    static let githubLight = Theme(
        id: "githubLight", name: "GitHub Light", swatch: Color(hex: "#0969DA"), colorScheme: .light,
        background: Color(hex: "#FFFFFF"), foreground: Color(hex: "#1F2328"), secondary: Color(hex: "#656D76"),
        muted: Color(hex: "#8C959F"), accent: Color(hex: "#0969DA"), mathAccent: Color(hex: "#8250DF"),
        codeBackground: Color(hex: "#F6F8FA"), tableBorder: Color(hex: "#D0D7DE"),
        highlightColors: .theme(.github), mermaidTheme: "default", mermaidThemeVariables: nil
    )

    static let githubDark = Theme(
        id: "githubDark", name: "GitHub Dark", swatch: Color(hex: "#4493F8"), colorScheme: .dark,
        background: Color(hex: "#0D1117"), foreground: Color(hex: "#E6EDF3"), secondary: Color(hex: "#8B949E"),
        muted: Color(hex: "#6E7681"), accent: Color(hex: "#4493F8"), mathAccent: Color(hex: "#A371F7"),
        codeBackground: Color(hex: "#161B22"), tableBorder: Color(hex: "#30363D"),
        highlightColors: .theme(.github), mermaidTheme: "dark", mermaidThemeVariables: nil
    )

    static let solarizedLight = Theme(
        id: "solarizedLight", name: "Solarized Light", swatch: Color(hex: "#268BD2"), colorScheme: .light,
        background: Color(hex: "#FDF6E3"), foreground: Color(hex: "#586E75"), secondary: Color(hex: "#93A1A1"),
        muted: Color(hex: "#B0AB9A"), accent: Color(hex: "#268BD2"), mathAccent: Color(hex: "#D33682"),
        codeBackground: Color(hex: "#EEE8D5"), tableBorder: Color(hex: "#D3CBB7"),
        highlightColors: .theme(.solarized), mermaidTheme: "neutral", mermaidThemeVariables: nil
    )

    static let solarizedDark = Theme(
        id: "solarizedDark", name: "Solarized Dark", swatch: Color(hex: "#268BD2"), colorScheme: .dark,
        background: Color(hex: "#002B36"), foreground: Color(hex: "#839496"), secondary: Color(hex: "#586E75"),
        muted: Color(hex: "#4E6A72"), accent: Color(hex: "#268BD2"), mathAccent: Color(hex: "#D33682"),
        codeBackground: Color(hex: "#073642"), tableBorder: Color(hex: "#0A4652"),
        highlightColors: .theme(.solarized), mermaidTheme: "dark", mermaidThemeVariables: nil
    )

    static let dracula = Theme(
        id: "dracula", name: "Dracula", swatch: Color(hex: "#BD93F9"), colorScheme: .dark,
        background: Color(hex: "#282A36"), foreground: Color(hex: "#F8F8F2"), secondary: Color(hex: "#6272A4"),
        muted: Color(hex: "#4D5372"), accent: Color(hex: "#BD93F9"), mathAccent: Color(hex: "#FF79C6"),
        codeBackground: Color(hex: "#21222C"), tableBorder: Color(hex: "#44475A"),
        highlightColors: .theme(.atomOne), mermaidTheme: "dark", mermaidThemeVariables: nil
    )

    static let nord = Theme(
        id: "nord", name: "Nord", swatch: Color(hex: "#88C0D0"), colorScheme: .dark,
        background: Color(hex: "#2E3440"), foreground: Color(hex: "#D8DEE9"), secondary: Color(hex: "#4C566A"),
        muted: Color(hex: "#3B4252"), accent: Color(hex: "#88C0D0"), mathAccent: Color(hex: "#B48EAD"),
        codeBackground: Color(hex: "#3B4252"), tableBorder: Color(hex: "#434C5E"),
        highlightColors: .theme(.horizon), mermaidTheme: "dark", mermaidThemeVariables: nil
    )

    static let oneDark = Theme(
        id: "oneDark", name: "One Dark", swatch: Color(hex: "#61AFEF"), colorScheme: .dark,
        background: Color(hex: "#282C34"), foreground: Color(hex: "#ABB2BF"), secondary: Color(hex: "#5C6370"),
        muted: Color(hex: "#4B5263"), accent: Color(hex: "#61AFEF"), mathAccent: Color(hex: "#C678DD"),
        codeBackground: Color(hex: "#21252B"), tableBorder: Color(hex: "#3E4451"),
        highlightColors: .theme(.tokyoNight), mermaidTheme: "dark", mermaidThemeVariables: nil
    )

    static let catppuccinMocha = Theme(
        id: "catppuccinMocha", name: "Catppuccin Mocha", swatch: Color(hex: "#CBA6F7"), colorScheme: .dark,
        background: Color(hex: "#1E1E2E"), foreground: Color(hex: "#CDD6F4"), secondary: Color(hex: "#A6ADC8"),
        muted: Color(hex: "#6C7086"), accent: Color(hex: "#CBA6F7"), mathAccent: Color(hex: "#F5C2E7"),
        codeBackground: Color(hex: "#313244"), tableBorder: Color(hex: "#45475A"),
        highlightColors: .theme(.pandaSyntax), mermaidTheme: "dark", mermaidThemeVariables: nil
    )

    static let tokyoNight = Theme(
        id: "tokyoNight", name: "Tokyo Night", swatch: Color(hex: "#7AA2F7"), colorScheme: .dark,
        background: Color(hex: "#1A1B26"), foreground: Color(hex: "#C0CAF5"), secondary: Color(hex: "#565F89"),
        muted: Color(hex: "#414868"), accent: Color(hex: "#7AA2F7"), mathAccent: Color(hex: "#BB9AF7"),
        codeBackground: Color(hex: "#16161E"), tableBorder: Color(hex: "#292E42"),
        highlightColors: .theme(.tokyoNight), mermaidTheme: "dark", mermaidThemeVariables: nil
    )

    static let hackTheBox = Theme(
        id: "hackthebox", name: "HackTheBox", swatch: Color(hex: "#9FEF00"), colorScheme: .dark,
        background: Color(hex: "#141D2B"), foreground: Color(hex: "#A4B1CD"), secondary: Color(hex: "#6C7A94"),
        muted: Color(hex: "#4C5872"), accent: Color(hex: "#9FEF00"), mathAccent: Color(hex: "#4CD3C2"),
        codeBackground: Color(hex: "#0D131D"), tableBorder: Color(hex: "#24304A"),
        highlightColors: .custom(
            dark: .custom(css: Theme.hackTheBoxHighlightCSS, background: "#0D131D"),
            light: .custom(css: Theme.hackTheBoxHighlightCSS, background: "#0D131D")
        ),
        mermaidTheme: "base",
        mermaidThemeVariables: [
            "primaryColor": "#1B2436",
            "primaryTextColor": "#A4B1CD",
            "primaryBorderColor": "#9FEF00",
            "lineColor": "#9FEF00",
            "background": "#141D2B",
            "mainBkg": "#1B2436",
            "textColor": "#A4B1CD"
        ]
    )

    private static let hackTheBoxHighlightCSS =
        "pre code.hljs{display:block;overflow-x:auto;padding:1em}code.hljs{padding:3px 5px}" +
        ".hljs{color:#A4B1CD}" +
        ".hljs-comment,.hljs-quote{color:#5C6B84;font-style:italic}" +
        ".hljs-keyword,.hljs-selector-tag,.hljs-literal,.hljs-section,.hljs-link{color:#9FEF00}" +
        ".hljs-string,.hljs-addition,.hljs-attr,.hljs-bullet{color:#B4F468}" +
        ".hljs-number,.hljs-built_in,.hljs-type,.hljs-symbol{color:#4CD3C2}" +
        ".hljs-title,.hljs-name,.hljs-selector-id,.hljs-selector-class,.hljs-attribute{color:#E9EEF7}" +
        ".hljs-variable,.hljs-template-variable,.hljs-meta{color:#9FEF00}" +
        ".hljs-deletion{color:#FF6B6B}" +
        ".hljs-emphasis{font-style:italic}.hljs-strong{font-weight:700}"

    static let builtIn: [Theme] = [
        .system, .githubLight, .githubDark, .solarizedLight, .solarizedDark,
        .dracula, .nord, .oneDark, .catppuccinMocha, .tokyoNight, .hackTheBox
    ]

    static func resolve(id: String) -> Theme {
        builtIn.first { $0.id == id } ?? .system
    }
}

extension Color {
    init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString.removeAll { $0 == "#" }
        var value: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
