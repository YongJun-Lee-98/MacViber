import Foundation
import SwiftTerm
import AppKit

// MARK: - Syntax Highlighting Colors

struct SyntaxHighlightColors: Codable, Equatable {
    let command: TerminalTheme.ThemeColor       // ls, git 등 명령어
    let builtin: TerminalTheme.ThemeColor       // cd, echo 등 내장 명령어
    let alias: TerminalTheme.ThemeColor         // 사용자 별칭
    let function: TerminalTheme.ThemeColor      // 함수명
    let reservedWord: TerminalTheme.ThemeColor  // if, for, while 등
    let path: TerminalTheme.ThemeColor          // 파일 경로
    let globbing: TerminalTheme.ThemeColor      // *.txt 와일드카드
    let singleQuoted: TerminalTheme.ThemeColor  // 'string'
    let doubleQuoted: TerminalTheme.ThemeColor  // "string"
    let option: TerminalTheme.ThemeColor        // -o, --option
    let error: TerminalTheme.ThemeColor         // unknown-token
    let comment: TerminalTheme.ThemeColor       // # 주석
}

// MARK: - Terminal Theme Model

struct TerminalTheme: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let foreground: ThemeColor
    let background: ThemeColor
    let ansiColors: [ThemeColor]  // 16 colors (8 normal + 8 bright)
    let syntaxColors: SyntaxHighlightColors

    struct ThemeColor: Codable, Equatable {
        let red: Double    // 0.0-1.0
        let green: Double
        let blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// Initialize from hex color string (e.g., "#282C34" or "282C34")
        init(hex: String) {
            var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

            var rgb: UInt64 = 0
            Scanner(string: hexSanitized).scanHexInt64(&rgb)

            self.red = Double((rgb & 0xFF0000) >> 16) / 255.0
            self.green = Double((rgb & 0x00FF00) >> 8) / 255.0
            self.blue = Double(rgb & 0x0000FF) / 255.0
        }

        var nsColor: NSColor {
            // Use deviceRGB color space for compatibility with SwiftTerm's getTerminalColor()
            NSColor(deviceRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1.0)
        }

        var swiftTermColor: Color {
            Color(red: UInt16(red * 65535), green: UInt16(green * 65535), blue: UInt16(blue * 65535))
        }
    }

    var foregroundNSColor: NSColor { foreground.nsColor }
    var backgroundNSColor: NSColor { background.nsColor }
    var ansiSwiftTermColors: [Color] { ansiColors.map { $0.swiftTermColor } }
}

// MARK: - Predefined Themes

extension TerminalTheme {

    // MARK: One Dark (Default)
    static let oneDark = TerminalTheme(
        id: "one-dark",
        name: "One Dark",
        foreground: ThemeColor(hex: "#E6E6E6"),
        background: ThemeColor(hex: "#282C34"),
        ansiColors: [
            // Normal colors (0-7)
            ThemeColor(hex: "#282C34"),  // 0: Black
            ThemeColor(hex: "#E06C75"),  // 1: Red
            ThemeColor(hex: "#98C379"),  // 2: Green
            ThemeColor(hex: "#E5C07B"),  // 3: Yellow
            ThemeColor(hex: "#61AFEF"),  // 4: Blue
            ThemeColor(hex: "#C678DD"),  // 5: Magenta
            ThemeColor(hex: "#56B6C2"),  // 6: Cyan
            ThemeColor(hex: "#ABB2BF"),  // 7: White
            // Bright colors (8-15)
            ThemeColor(hex: "#5C6370"),  // 8: Bright Black
            ThemeColor(hex: "#E06C75"),  // 9: Bright Red
            ThemeColor(hex: "#98C379"),  // 10: Bright Green
            ThemeColor(hex: "#E5C07B"),  // 11: Bright Yellow
            ThemeColor(hex: "#61AFEF"),  // 12: Bright Blue
            ThemeColor(hex: "#C678DD"),  // 13: Bright Magenta
            ThemeColor(hex: "#56B6C2"),  // 14: Bright Cyan
            ThemeColor(hex: "#FFFFFF"),  // 15: Bright White
        ],
        syntaxColors: SyntaxHighlightColors(
            command: ThemeColor(hex: "#61AFEF"),     // Blue
            builtin: ThemeColor(hex: "#61AFEF"),     // Blue
            alias: ThemeColor(hex: "#56B6C2"),       // Cyan
            function: ThemeColor(hex: "#C678DD"),    // Purple
            reservedWord: ThemeColor(hex: "#C678DD"),// Purple
            path: ThemeColor(hex: "#98C379"),        // Green
            globbing: ThemeColor(hex: "#E5C07B"),    // Yellow
            singleQuoted: ThemeColor(hex: "#98C379"),// Green
            doubleQuoted: ThemeColor(hex: "#98C379"),// Green
            option: ThemeColor(hex: "#ABB2BF"),      // Light gray
            error: ThemeColor(hex: "#E06C75"),       // Red
            comment: ThemeColor(hex: "#5C6370")      // Gray
        )
    )

    // MARK: Dracula
    static let dracula = TerminalTheme(
        id: "dracula",
        name: "Dracula",
        foreground: ThemeColor(hex: "#F8F8F2"),
        background: ThemeColor(hex: "#282A36"),
        ansiColors: [
            // Normal colors (0-7)
            ThemeColor(hex: "#21222C"),  // 0: Black
            ThemeColor(hex: "#FF5555"),  // 1: Red
            ThemeColor(hex: "#50FA7B"),  // 2: Green
            ThemeColor(hex: "#F1FA8C"),  // 3: Yellow
            ThemeColor(hex: "#BD93F9"),  // 4: Blue
            ThemeColor(hex: "#FF79C6"),  // 5: Magenta
            ThemeColor(hex: "#8BE9FD"),  // 6: Cyan
            ThemeColor(hex: "#F8F8F2"),  // 7: White
            // Bright colors (8-15)
            ThemeColor(hex: "#6272A4"),  // 8: Bright Black
            ThemeColor(hex: "#FF6E6E"),  // 9: Bright Red
            ThemeColor(hex: "#69FF94"),  // 10: Bright Green
            ThemeColor(hex: "#FFFFA5"),  // 11: Bright Yellow
            ThemeColor(hex: "#D6ACFF"),  // 12: Bright Blue
            ThemeColor(hex: "#FF92DF"),  // 13: Bright Magenta
            ThemeColor(hex: "#A4FFFF"),  // 14: Bright Cyan
            ThemeColor(hex: "#FFFFFF"),  // 15: Bright White
        ],
        syntaxColors: SyntaxHighlightColors(
            command: ThemeColor(hex: "#8BE9FD"),     // Cyan
            builtin: ThemeColor(hex: "#8BE9FD"),     // Cyan
            alias: ThemeColor(hex: "#50FA7B"),       // Green
            function: ThemeColor(hex: "#BD93F9"),    // Purple
            reservedWord: ThemeColor(hex: "#FF79C6"),// Pink
            path: ThemeColor(hex: "#50FA7B"),        // Green
            globbing: ThemeColor(hex: "#F1FA8C"),    // Yellow
            singleQuoted: ThemeColor(hex: "#F1FA8C"),// Yellow
            doubleQuoted: ThemeColor(hex: "#F1FA8C"),// Yellow
            option: ThemeColor(hex: "#FFB86C"),      // Orange
            error: ThemeColor(hex: "#FF5555"),       // Red
            comment: ThemeColor(hex: "#6272A4")      // Gray
        )
    )

    // MARK: Monokai
    static let monokai = TerminalTheme(
        id: "monokai",
        name: "Monokai",
        foreground: ThemeColor(hex: "#F8F8F2"),
        background: ThemeColor(hex: "#272822"),
        ansiColors: [
            // Normal colors (0-7)
            ThemeColor(hex: "#333333"),  // 0: Black
            ThemeColor(hex: "#C4265E"),  // 1: Red
            ThemeColor(hex: "#86B42B"),  // 2: Green
            ThemeColor(hex: "#B3B42B"),  // 3: Yellow
            ThemeColor(hex: "#6A7EC8"),  // 4: Blue
            ThemeColor(hex: "#8C6BC8"),  // 5: Magenta
            ThemeColor(hex: "#56ADBC"),  // 6: Cyan
            ThemeColor(hex: "#E3E3DD"),  // 7: White
            // Bright colors (8-15)
            ThemeColor(hex: "#666666"),  // 8: Bright Black
            ThemeColor(hex: "#F92672"),  // 9: Bright Red
            ThemeColor(hex: "#A6E22E"),  // 10: Bright Green
            ThemeColor(hex: "#E2E22E"),  // 11: Bright Yellow
            ThemeColor(hex: "#819AFF"),  // 12: Bright Blue
            ThemeColor(hex: "#AE81FF"),  // 13: Bright Magenta
            ThemeColor(hex: "#66D9EF"),  // 14: Bright Cyan
            ThemeColor(hex: "#F8F8F2"),  // 15: Bright White
        ],
        syntaxColors: SyntaxHighlightColors(
            command: ThemeColor(hex: "#66D9EF"),     // Cyan
            builtin: ThemeColor(hex: "#66D9EF"),     // Cyan
            alias: ThemeColor(hex: "#A6E22E"),       // Green
            function: ThemeColor(hex: "#AE81FF"),    // Purple
            reservedWord: ThemeColor(hex: "#F92672"),// Pink
            path: ThemeColor(hex: "#A6E22E"),        // Green
            globbing: ThemeColor(hex: "#E6DB74"),    // Yellow
            singleQuoted: ThemeColor(hex: "#E6DB74"),// Yellow
            doubleQuoted: ThemeColor(hex: "#E6DB74"),// Yellow
            option: ThemeColor(hex: "#FD971F"),      // Orange
            error: ThemeColor(hex: "#F92672"),       // Pink
            comment: ThemeColor(hex: "#75715E")      // Gray
        )
    )

    // MARK: Solarized Dark
    static let solarizedDark = TerminalTheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        foreground: ThemeColor(hex: "#839496"),
        background: ThemeColor(hex: "#002B36"),
        ansiColors: [
            // Normal colors (0-7)
            ThemeColor(hex: "#073642"),  // 0: Black
            ThemeColor(hex: "#DC322F"),  // 1: Red
            ThemeColor(hex: "#859900"),  // 2: Green
            ThemeColor(hex: "#B58900"),  // 3: Yellow
            ThemeColor(hex: "#268BD2"),  // 4: Blue
            ThemeColor(hex: "#D33682"),  // 5: Magenta
            ThemeColor(hex: "#2AA198"),  // 6: Cyan
            ThemeColor(hex: "#EEE8D5"),  // 7: White
            // Bright colors (8-15)
            ThemeColor(hex: "#002B36"),  // 8: Bright Black
            ThemeColor(hex: "#CB4B16"),  // 9: Bright Red
            ThemeColor(hex: "#586E75"),  // 10: Bright Green
            ThemeColor(hex: "#657B83"),  // 11: Bright Yellow
            ThemeColor(hex: "#839496"),  // 12: Bright Blue
            ThemeColor(hex: "#6C71C4"),  // 13: Bright Magenta
            ThemeColor(hex: "#93A1A1"),  // 14: Bright Cyan
            ThemeColor(hex: "#FDF6E3"),  // 15: Bright White
        ],
        syntaxColors: SyntaxHighlightColors(
            command: ThemeColor(hex: "#268BD2"),     // Blue
            builtin: ThemeColor(hex: "#268BD2"),     // Blue
            alias: ThemeColor(hex: "#2AA198"),       // Cyan
            function: ThemeColor(hex: "#6C71C4"),    // Violet
            reservedWord: ThemeColor(hex: "#859900"),// Green
            path: ThemeColor(hex: "#859900"),        // Green
            globbing: ThemeColor(hex: "#B58900"),    // Yellow
            singleQuoted: ThemeColor(hex: "#2AA198"),// Cyan
            doubleQuoted: ThemeColor(hex: "#2AA198"),// Cyan
            option: ThemeColor(hex: "#93A1A1"),      // Base1
            error: ThemeColor(hex: "#DC322F"),       // Red
            comment: ThemeColor(hex: "#586E75")      // Base01
        )
    )

    // MARK: Nord
    static let nord = TerminalTheme(
        id: "nord",
        name: "Nord",
        foreground: ThemeColor(hex: "#D8DEE9"),
        background: ThemeColor(hex: "#2E3440"),
        ansiColors: [
            // Normal colors (0-7)
            ThemeColor(hex: "#3B4252"),  // 0: Black
            ThemeColor(hex: "#BF616A"),  // 1: Red
            ThemeColor(hex: "#A3BE8C"),  // 2: Green
            ThemeColor(hex: "#EBCB8B"),  // 3: Yellow
            ThemeColor(hex: "#81A1C1"),  // 4: Blue
            ThemeColor(hex: "#B48EAD"),  // 5: Magenta
            ThemeColor(hex: "#88C0D0"),  // 6: Cyan
            ThemeColor(hex: "#E5E9F0"),  // 7: White
            // Bright colors (8-15)
            ThemeColor(hex: "#4C566A"),  // 8: Bright Black
            ThemeColor(hex: "#BF616A"),  // 9: Bright Red
            ThemeColor(hex: "#A3BE8C"),  // 10: Bright Green
            ThemeColor(hex: "#EBCB8B"),  // 11: Bright Yellow
            ThemeColor(hex: "#81A1C1"),  // 12: Bright Blue
            ThemeColor(hex: "#B48EAD"),  // 13: Bright Magenta
            ThemeColor(hex: "#8FBCBB"),  // 14: Bright Cyan
            ThemeColor(hex: "#ECEFF4"),  // 15: Bright White
        ],
        syntaxColors: SyntaxHighlightColors(
            command: ThemeColor(hex: "#81A1C1"),     // Frost Blue
            builtin: ThemeColor(hex: "#81A1C1"),     // Frost Blue
            alias: ThemeColor(hex: "#88C0D0"),       // Frost Cyan
            function: ThemeColor(hex: "#B48EAD"),    // Aurora Purple
            reservedWord: ThemeColor(hex: "#5E81AC"),// Frost Dark Blue
            path: ThemeColor(hex: "#A3BE8C"),        // Aurora Green
            globbing: ThemeColor(hex: "#EBCB8B"),    // Aurora Yellow
            singleQuoted: ThemeColor(hex: "#A3BE8C"),// Aurora Green
            doubleQuoted: ThemeColor(hex: "#A3BE8C"),// Aurora Green
            option: ThemeColor(hex: "#D8DEE9"),      // Snow Storm
            error: ThemeColor(hex: "#BF616A"),       // Aurora Red
            comment: ThemeColor(hex: "#4C566A")      // Polar Night
        )
    )

    // MARK: GitHub Dark
    static let githubDark = TerminalTheme(
        id: "github-dark",
        name: "GitHub Dark",
        foreground: ThemeColor(hex: "#C9D1D9"),
        background: ThemeColor(hex: "#0D1117"),
        ansiColors: [
            // Normal colors (0-7)
            ThemeColor(hex: "#484F58"),  // 0: Black
            ThemeColor(hex: "#FF7B72"),  // 1: Red
            ThemeColor(hex: "#3FB950"),  // 2: Green
            ThemeColor(hex: "#D29922"),  // 3: Yellow
            ThemeColor(hex: "#58A6FF"),  // 4: Blue
            ThemeColor(hex: "#BC8CFF"),  // 5: Magenta
            ThemeColor(hex: "#39C5CF"),  // 6: Cyan
            ThemeColor(hex: "#B1BAC4"),  // 7: White
            // Bright colors (8-15)
            ThemeColor(hex: "#6E7681"),  // 8: Bright Black
            ThemeColor(hex: "#FFA198"),  // 9: Bright Red
            ThemeColor(hex: "#56D364"),  // 10: Bright Green
            ThemeColor(hex: "#E3B341"),  // 11: Bright Yellow
            ThemeColor(hex: "#79C0FF"),  // 12: Bright Blue
            ThemeColor(hex: "#D2A8FF"),  // 13: Bright Magenta
            ThemeColor(hex: "#56D4DD"),  // 14: Bright Cyan
            ThemeColor(hex: "#F0F6FC"),  // 15: Bright White
        ],
        syntaxColors: SyntaxHighlightColors(
            command: ThemeColor(hex: "#58A6FF"),     // Blue
            builtin: ThemeColor(hex: "#58A6FF"),     // Blue
            alias: ThemeColor(hex: "#39C5CF"),       // Cyan
            function: ThemeColor(hex: "#BC8CFF"),    // Purple
            reservedWord: ThemeColor(hex: "#FF7B72"),// Red
            path: ThemeColor(hex: "#3FB950"),        // Green
            globbing: ThemeColor(hex: "#D29922"),    // Yellow
            singleQuoted: ThemeColor(hex: "#A5D6FF"),// Light Blue
            doubleQuoted: ThemeColor(hex: "#A5D6FF"),// Light Blue
            option: ThemeColor(hex: "#8B949E"),      // Gray
            error: ThemeColor(hex: "#FF7B72"),       // Red
            comment: ThemeColor(hex: "#6E7681")      // Dark Gray
        )
    )

    // MARK: All Themes
    static let allThemes: [TerminalTheme] = [
        .oneDark,
        .dracula,
        .monokai,
        .solarizedDark,
        .nord,
        .githubDark
    ]

    static let defaultTheme: TerminalTheme = .oneDark
}
