import Foundation

/// Handles installation and configuration of zsh-syntax-highlighting plugin
final class SyntaxHighlightingInstaller {
    static let shared = SyntaxHighlightingInstaller()

    private let zshrcPath: String
    private let markerComment = "# MultiTerm: zsh-syntax-highlighting configuration"

    private init() {
        self.zshrcPath = NSHomeDirectory() + "/.zshrc"
    }

    // MARK: - Public Interface

    /// Check if zsh-syntax-highlighting is installed
    func isInstalled() async -> Bool {
        // Check if the plugin is installed via Homebrew
        let brewCheck = await runCommand("/opt/homebrew/bin/brew", arguments: ["list", "zsh-syntax-highlighting"])
        if brewCheck.exitCode == 0 {
            return true
        }

        // Also check Intel Mac Homebrew path
        let brewCheckIntel = await runCommand("/usr/local/bin/brew", arguments: ["list", "zsh-syntax-highlighting"])
        if brewCheckIntel.exitCode == 0 {
            return true
        }

        // Check if plugin file exists in common locations
        let pluginPaths = [
            "/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh",
            "/usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh",
            NSHomeDirectory() + "/.zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
        ]

        for path in pluginPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }

        return false
    }

    /// Install zsh-syntax-highlighting and configure .zshrc
    func install(highlightColor: TerminalTheme.ThemeColor?) async throws {
        // Step 1: Install via Homebrew
        try await installViaHomebrew()

        // Step 2: Configure .zshrc
        try await configureZshrc(highlightColor: highlightColor)

        Logger.shared.info("zsh-syntax-highlighting installed and configured successfully")
    }

    /// Update the highlight color in .zshrc (legacy - single color)
    func updateHighlightColor(_ color: TerminalTheme.ThemeColor?) async throws {
        guard FileManager.default.fileExists(atPath: zshrcPath) else {
            throw InstallerError.zshrcNotFound
        }

        var content = try String(contentsOfFile: zshrcPath, encoding: .utf8)

        // Remove existing MultiTerm color configuration
        content = removeMultiTermConfig(from: content)

        // Add new configuration if color is provided
        if let color = color {
            let config = generateColorConfig(color: color)
            content += "\n" + config
        }

        try content.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
    }

    /// Update all syntax highlighting colors in .zshrc
    func updateSyntaxColors(_ colors: SyntaxHighlightColors) async throws {
        guard FileManager.default.fileExists(atPath: zshrcPath) else {
            throw InstallerError.zshrcNotFound
        }

        var content = try String(contentsOfFile: zshrcPath, encoding: .utf8)

        // Remove existing MultiTerm color configuration
        content = removeMultiTermConfig(from: content)

        // Add new configuration
        let config = generateSyntaxColorConfig(colors: colors)
        content += "\n" + config

        try content.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
        Logger.shared.info("Syntax highlighting colors updated in .zshrc")
    }

    // MARK: - Private Methods

    private func installViaHomebrew() async throws {
        // Check if Homebrew is available
        let brewPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew")
            ? "/opt/homebrew/bin/brew"
            : "/usr/local/bin/brew"

        guard FileManager.default.fileExists(atPath: brewPath) else {
            throw InstallerError.homebrewNotFound
        }

        // Install zsh-syntax-highlighting
        let result = await runCommand(brewPath, arguments: ["install", "zsh-syntax-highlighting"])

        if result.exitCode != 0 && !result.output.contains("already installed") {
            throw InstallerError.installationFailed(result.output)
        }
    }

    private func configureZshrc(highlightColor: TerminalTheme.ThemeColor?) async throws {
        var content = ""

        // Read existing .zshrc or create new
        if FileManager.default.fileExists(atPath: zshrcPath) {
            content = try String(contentsOfFile: zshrcPath, encoding: .utf8)
            // Remove existing MultiTerm configuration
            content = removeMultiTermConfig(from: content)
        }

        // Generate configuration block
        let config = generateZshrcConfig(highlightColor: highlightColor)

        // Append configuration
        if !content.isEmpty && !content.hasSuffix("\n") {
            content += "\n"
        }
        content += config

        // Write back to .zshrc
        try content.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
    }

    private func generateZshrcConfig(highlightColor: TerminalTheme.ThemeColor?) -> String {
        let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew")
            ? "/opt/homebrew"
            : "/usr/local"

        var config = """

        \(markerComment)
        # Source zsh-syntax-highlighting
        if [ -f "\(brewPrefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
            source "\(brewPrefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
        fi
        """

        if let color = highlightColor {
            config += "\n" + generateColorConfig(color: color)
        }

        config += "\n# End MultiTerm configuration\n"

        return config
    }

    private func generateColorConfig(color: TerminalTheme.ThemeColor) -> String {
        let hexColor = color.hexString.replacingOccurrences(of: "#", with: "")
        return """
        # MultiTerm: Custom command highlight color
        ZSH_HIGHLIGHT_STYLES[command]='fg=#\(hexColor)'
        ZSH_HIGHLIGHT_STYLES[builtin]='fg=#\(hexColor)'
        ZSH_HIGHLIGHT_STYLES[alias]='fg=#\(hexColor)'
        """
    }

    private func generateSyntaxColorConfig(colors: SyntaxHighlightColors) -> String {
        let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew")
            ? "/opt/homebrew"
            : "/usr/local"

        return """
        \(markerComment)
        # Source zsh-syntax-highlighting (must be before style definitions)
        if [ -f "\(brewPrefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
            source "\(brewPrefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
        fi
        # Syntax highlighting colors
        ZSH_HIGHLIGHT_STYLES[command]='fg=\(colors.command.hexString)'
        ZSH_HIGHLIGHT_STYLES[builtin]='fg=\(colors.builtin.hexString)'
        ZSH_HIGHLIGHT_STYLES[alias]='fg=\(colors.alias.hexString)'
        ZSH_HIGHLIGHT_STYLES[function]='fg=\(colors.function.hexString)'
        ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=\(colors.reservedWord.hexString)'
        ZSH_HIGHLIGHT_STYLES[path]='fg=\(colors.path.hexString),underline'
        ZSH_HIGHLIGHT_STYLES[path_prefix]='fg=\(colors.path.hexString)'
        ZSH_HIGHLIGHT_STYLES[globbing]='fg=\(colors.globbing.hexString)'
        ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=\(colors.singleQuoted.hexString)'
        ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=\(colors.doubleQuoted.hexString)'
        ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=\(colors.doubleQuoted.hexString)'
        ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=\(colors.option.hexString)'
        ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=\(colors.option.hexString)'
        ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=\(colors.error.hexString),bold'
        ZSH_HIGHLIGHT_STYLES[comment]='fg=\(colors.comment.hexString)'
        # End MultiTerm configuration
        """
    }

    private func removeMultiTermConfig(from content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var inMultiTermBlock = false
        var skipUntilEndOrNextSection = false

        for line in lines {
            // Check for any MultiTerm marker (current or legacy)
            if line.contains(markerComment) || line.contains("# MultiTerm: Custom command highlight color") {
                inMultiTermBlock = true
                skipUntilEndOrNextSection = !line.contains(markerComment) // Legacy block has no end marker
                continue
            }

            // End marker for new format
            if inMultiTermBlock && line.contains("# End MultiTerm configuration") {
                inMultiTermBlock = false
                skipUntilEndOrNextSection = false
                continue
            }

            // Legacy format: skip ZSH_HIGHLIGHT_STYLES lines until we hit a non-style line
            if skipUntilEndOrNextSection {
                if line.hasPrefix("ZSH_HIGHLIGHT_STYLES[") {
                    continue
                } else {
                    // End of legacy block
                    inMultiTermBlock = false
                    skipUntilEndOrNextSection = false
                    result.append(line)
                    continue
                }
            }

            if !inMultiTermBlock {
                result.append(line)
            }
        }

        // Remove trailing empty lines
        while result.last?.isEmpty == true {
            result.removeLast()
        }

        return result.joined(separator: "\n")
    }

    private func runCommand(_ path: String, arguments: [String]) async -> (exitCode: Int32, output: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                continuation.resume(returning: (process.terminationStatus, output))
            } catch {
                continuation.resume(returning: (-1, error.localizedDescription))
            }
        }
    }

    // MARK: - Errors

    enum InstallerError: LocalizedError {
        case homebrewNotFound
        case zshrcNotFound
        case installationFailed(String)

        var errorDescription: String? {
            switch self {
            case .homebrewNotFound:
                return "Homebrew is not installed. Please install Homebrew first: https://brew.sh"
            case .zshrcNotFound:
                return ".zshrc file not found"
            case .installationFailed(let message):
                return "Installation failed: \(message)"
            }
        }
    }
}
