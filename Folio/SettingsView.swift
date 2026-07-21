import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        TabView {
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            TypographyTab()
                .tabItem { Label("Typography", systemImage: "textformat") }
            LayoutTab()
                .tabItem { Label("Layout", systemImage: "rectangle.split.3x1") }
        }
        .environment(settings)
        .frame(width: 480, height: 340)
    }
}

private struct AppearanceTab: View {
    @Environment(SettingsStore.self) private var settings
    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

    var body: some View {
        @Bindable var settings = settings
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Theme.builtIn) { theme in
                    ThemeSwatch(theme: theme, isSelected: settings.selectedThemeID == theme.id) {
                        settings.selectedThemeID = theme.id
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct ThemeSwatch: View {
    let theme: Theme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.id == "system" ? Color(nsColor: .windowBackgroundColor) : theme.background)
                    .frame(height: 44)
                    .overlay(alignment: .bottomLeading) {
                        Circle()
                            .fill(theme.swatch)
                            .frame(width: 12, height: 12)
                            .padding(6)
                    }
                Text(theme.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TypographyTab: View {
    @Environment(SettingsStore.self) private var settings
    private let fontFamilies = ["", "New York", "Georgia", "Avenir Next", "Helvetica Neue", "Menlo"]

    var body: some View {
        @Bindable var settings = settings
        Form {
            Picker("Font Family", selection: $settings.fontFamily) {
                ForEach(fontFamilies, id: \.self) { family in
                    Text(family.isEmpty ? "System" : family).tag(family)
                }
            }

            HStack {
                Text("Font Size")
                Slider(value: $settings.baseFontSize, in: 12...24, step: 1)
                Text("\(Int(settings.baseFontSize)) pt")
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(20)
    }
}

private struct LayoutTab: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            HStack {
                Text("Reading Width")
                Slider(value: $settings.readingWidth, in: 480...1400, step: 20)
                Text("\(Int(settings.readingWidth)) pt")
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }

            HStack {
                Text("Table Width")
                Slider(value: $settings.tableWidthRatio, in: 1.0...1.6, step: 0.05)
                Text("×\(settings.tableWidthRatio, specifier: "%.2f")")
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }

            Button("Reset to Defaults") {
                settings.resetToDefaults()
            }
            .padding(.top, 8)
        }
        .padding(20)
    }
}
