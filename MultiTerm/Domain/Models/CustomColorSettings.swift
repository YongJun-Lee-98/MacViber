import Foundation
import AppKit

// MARK: - Custom Color Settings Model

struct CustomColorSettings: Codable, Equatable {
    var useCustomColors: Bool = false
    var backgroundColor: TerminalTheme.ThemeColor?
    var foregroundColor: TerminalTheme.ThemeColor?
    var commandHighlightColor: TerminalTheme.ThemeColor?

    static let `default` = CustomColorSettings()

    // MARK: - Convenience initializers

    init(
        useCustomColors: Bool = false,
        backgroundColor: TerminalTheme.ThemeColor? = nil,
        foregroundColor: TerminalTheme.ThemeColor? = nil,
        commandHighlightColor: TerminalTheme.ThemeColor? = nil
    ) {
        self.useCustomColors = useCustomColors
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.commandHighlightColor = commandHighlightColor
    }
}

// MARK: - ThemeColor Extensions for SwiftUI Color

extension TerminalTheme.ThemeColor {
    /// Initialize from NSColor
    init(nsColor: NSColor) {
        // Convert to sRGB color space for consistent values
        let color = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        self.red = Double(color.redComponent)
        self.green = Double(color.greenComponent)
        self.blue = Double(color.blueComponent)
    }

    /// Convert to hex string (e.g., "#FF5500")
    var hexString: String {
        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
