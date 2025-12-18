import Foundation
import AppKit

struct TerminalConfiguration {
    var fontName: String = "SF Mono"
    var fontSize: CGFloat = 13
    var foregroundColor: NSColor = ThemeManager.shared.currentTheme.foregroundNSColor
    var backgroundColor: NSColor = ThemeManager.shared.currentTheme.backgroundNSColor
    var cursorColor: NSColor = .white
    var selectionColor: NSColor = NSColor.selectedTextBackgroundColor

    var shell: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LC_ALL"] = "en_US.UTF-8"
        return env
    }

    var font: NSFont {
        NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    static let `default` = TerminalConfiguration()
}

// Color scheme presets
extension TerminalConfiguration {
    static let dark = TerminalConfiguration(
        foregroundColor: NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0),
        backgroundColor: NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
    )

    static let light = TerminalConfiguration(
        foregroundColor: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0),
        backgroundColor: NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
    )

    static let solarizedDark = TerminalConfiguration(
        foregroundColor: NSColor(red: 0.51, green: 0.58, blue: 0.59, alpha: 1.0),
        backgroundColor: NSColor(red: 0.0, green: 0.17, blue: 0.21, alpha: 1.0)
    )

    static let monokai = TerminalConfiguration(
        foregroundColor: NSColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1.0),
        backgroundColor: NSColor(red: 0.15, green: 0.16, blue: 0.13, alpha: 1.0)
    )
}
