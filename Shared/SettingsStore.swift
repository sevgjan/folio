import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsStore {
    var selectedThemeID: String { didSet { persist() } }
    var fontFamily: String { didSet { persist() } }
    var baseFontSize: Double { didSet { persist() } }
    var readingWidth: Double { didSet { persist() } }
    var tableWidthRatio: Double { didSet { persist() } }

    var theme: Theme {
        Theme.resolve(id: selectedThemeID)
    }

    var tableWidth: Double {
        readingWidth * tableWidthRatio
    }

    enum Defaults {
        static let themeID = "system"
        static let fontFamily = ""
        static let baseFontSize: Double = 15
        static let readingWidth: Double = 760
        static let tableWidthRatio: Double = 1.3
    }

    private enum Keys {
        static let themeID = "folio.settings.themeID"
        static let fontFamily = "folio.settings.fontFamily"
        static let baseFontSize = "folio.settings.baseFontSize"
        static let readingWidth = "folio.settings.readingWidth"
        static let tableWidthRatio = "folio.settings.tableWidthRatio"
    }

    init() {
        let defaults = UserDefaults.standard
        selectedThemeID = defaults.string(forKey: Keys.themeID) ?? Defaults.themeID
        fontFamily = defaults.string(forKey: Keys.fontFamily) ?? Defaults.fontFamily
        baseFontSize = defaults.object(forKey: Keys.baseFontSize) as? Double ?? Defaults.baseFontSize
        readingWidth = defaults.object(forKey: Keys.readingWidth) as? Double ?? Defaults.readingWidth
        tableWidthRatio = defaults.object(forKey: Keys.tableWidthRatio) as? Double ?? Defaults.tableWidthRatio
    }

    func resetToDefaults() {
        selectedThemeID = Defaults.themeID
        fontFamily = Defaults.fontFamily
        baseFontSize = Defaults.baseFontSize
        readingWidth = Defaults.readingWidth
        tableWidthRatio = Defaults.tableWidthRatio
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(selectedThemeID, forKey: Keys.themeID)
        defaults.set(fontFamily, forKey: Keys.fontFamily)
        defaults.set(baseFontSize, forKey: Keys.baseFontSize)
        defaults.set(readingWidth, forKey: Keys.readingWidth)
        defaults.set(tableWidthRatio, forKey: Keys.tableWidthRatio)
    }
}
