import Foundation
import Combine
import AppKit

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published private(set) var currentTheme: TerminalTheme
    @Published var customColors: CustomColorSettings

    private let userDefaultsKey = "MultiTerm.SelectedThemeId"
    private let customColorsKey = "MultiTerm.CustomColorSettings"
    private let themeChangedSubject = PassthroughSubject<TerminalTheme, Never>()
    private let colorsChangedSubject = PassthroughSubject<Void, Never>()

    var themeChanged: AnyPublisher<TerminalTheme, Never> {
        themeChangedSubject.eraseToAnyPublisher()
    }

    var colorsChanged: AnyPublisher<Void, Never> {
        colorsChangedSubject.eraseToAnyPublisher()
    }

    // MARK: - Effective Colors (custom overrides theme)

    var effectiveBackgroundColor: NSColor {
        if customColors.useCustomColors, let bg = customColors.backgroundColor {
            return bg.nsColor
        }
        return currentTheme.backgroundNSColor
    }

    var effectiveForegroundColor: NSColor {
        if customColors.useCustomColors, let fg = customColors.foregroundColor {
            return fg.nsColor
        }
        return currentTheme.foregroundNSColor
    }

    var effectiveCommandHighlightColor: TerminalTheme.ThemeColor? {
        if customColors.useCustomColors {
            return customColors.commandHighlightColor
        }
        return nil
    }

    private init() {
        // Load saved theme ID from UserDefaults
        if let savedThemeId = UserDefaults.standard.string(forKey: userDefaultsKey),
           let savedTheme = TerminalTheme.allThemes.first(where: { $0.id == savedThemeId }) {
            self.currentTheme = savedTheme
        } else {
            self.currentTheme = TerminalTheme.defaultTheme
        }

        // Load custom color settings
        if let data = UserDefaults.standard.data(forKey: customColorsKey),
           let settings = try? JSONDecoder().decode(CustomColorSettings.self, from: data) {
            self.customColors = settings
        } else {
            self.customColors = .default
        }
    }

    func selectTheme(_ theme: TerminalTheme) {
        Logger.shared.debug("[THEME] selectTheme called: \(theme.name)")
        guard theme.id != currentTheme.id else {
            Logger.shared.debug("[THEME] Same theme selected, skipping")
            return
        }

        Logger.shared.debug("[THEME] Setting currentTheme to \(theme.name)")
        currentTheme = theme
        save()
        Logger.shared.debug("[THEME] Sending theme to themeChangedSubject")
        themeChangedSubject.send(theme)

        // Apply syntax highlighting colors to .zshrc
        applySyntaxColors(theme.syntaxColors)
    }

    /// Apply syntax highlighting colors to .zshrc
    func applySyntaxColors(_ colors: SyntaxHighlightColors) {
        Task {
            do {
                try await SyntaxHighlightingInstaller.shared.updateSyntaxColors(colors)
                Logger.shared.debug("[THEME] Syntax colors applied to .zshrc")
            } catch {
                Logger.shared.error("[THEME] Failed to apply syntax colors: \(error)")
            }
        }
    }

    func selectTheme(byId themeId: String) {
        if let theme = TerminalTheme.allThemes.first(where: { $0.id == themeId }) {
            selectTheme(theme)
        }
    }

    private func save() {
        UserDefaults.standard.set(currentTheme.id, forKey: userDefaultsKey)
    }

    // MARK: - Custom Colors Management

    func updateCustomColors(_ settings: CustomColorSettings) {
        customColors = settings
        saveCustomColors()
        colorsChangedSubject.send()
    }

    func setBackgroundColor(_ color: NSColor?) {
        if let color = color {
            customColors.backgroundColor = TerminalTheme.ThemeColor(nsColor: color)
        } else {
            customColors.backgroundColor = nil
        }
        saveCustomColors()
        colorsChangedSubject.send()
    }

    func setForegroundColor(_ color: NSColor?) {
        if let color = color {
            customColors.foregroundColor = TerminalTheme.ThemeColor(nsColor: color)
        } else {
            customColors.foregroundColor = nil
        }
        saveCustomColors()
        colorsChangedSubject.send()
    }

    func setCommandHighlightColor(_ color: NSColor?) {
        if let color = color {
            customColors.commandHighlightColor = TerminalTheme.ThemeColor(nsColor: color)
        } else {
            customColors.commandHighlightColor = nil
        }
        saveCustomColors()
        colorsChangedSubject.send()
    }

    func setUseCustomColors(_ enabled: Bool) {
        customColors.useCustomColors = enabled
        saveCustomColors()
        colorsChangedSubject.send()
    }

    private func saveCustomColors() {
        if let data = try? JSONEncoder().encode(customColors) {
            UserDefaults.standard.set(data, forKey: customColorsKey)
        }
    }
}
