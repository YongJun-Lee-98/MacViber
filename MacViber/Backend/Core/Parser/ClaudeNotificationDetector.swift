import Foundation

class ClaudeNotificationDetector {

    // MARK: - Cached Pattern Structure
    private struct CachedPattern {
        let regex: NSRegularExpression
        let type: NotificationType
    }

    private let customPatternMatcher = CustomPatternMatcher()

    // MARK: - Pre-compiled Regex Patterns (static for one-time compilation)

    /// Main detection patterns - compiled once at class load
    private static let cachedPatterns: [CachedPattern] = {
        let definitions: [(String, NotificationType)] = [
            // Question patterns
            ("\\?\\s*$", .question),
            ("\\(y/n\\)", .question),
            ("\\[Y/n\\]", .question),
            ("\\[yes/no\\]", .question),
            ("Press Enter to continue", .question),
            ("Enter your choice", .question),

            // Permission request patterns (Claude Code specific)
            ("Allow\\s+.*\\?", .permissionRequest),
            ("Do you want to", .permissionRequest),
            ("Proceed\\?", .permissionRequest),
            ("\\b(approve|deny)\\b", .permissionRequest),
            ("(approve or deny)", .permissionRequest),
            ("\\(approve/deny\\)", .permissionRequest),
            ("\\[approve\\|deny\\]", .permissionRequest),

            // Completion patterns
            ("✓.*completed", .completion),
            ("Done\\.", .completion),
            ("Successfully", .completion),
            ("finished", .completion),

            // Error patterns
            ("Error:", .error),
            ("Failed:", .error),
            ("✗", .error),
            ("FAILED", .error),
        ]

        return definitions.compactMap { (pattern, type) in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                Logger.shared.error("Failed to compile pattern: \(pattern)")
                return nil
            }
            return CachedPattern(regex: regex, type: type)
        }
    }()

    /// Claude prompt patterns - compiled once
    private static let claudePromptRegexes: [NSRegularExpression] = {
        let patterns = [
            "❯",
            "claude>",
            "\\[Claude\\]",
            ">>> ",
            "\\.\\.\\. ",
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// Slash command menu patterns - compiled once
    private static let slashCommandRegexes: [NSRegularExpression] = {
        let patterns = [
            "\\[3C\\[1B",
            "\\[17C",
            "\\[\\d+C\\[1B",
            "\\[94m.*\\[39m",
            "\\[37m.*\\[39m",
            "(\\[3C\\[1B.*){2,}",
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// Permission indicators - compiled once
    private static let permissionRegexes: [NSRegularExpression] = {
        let indicators = [
            "allow",
            "permission",
            "access",
            "proceed",
            "continue",
            "confirm",
            "\\?",
            "do you want",
            "would you like",
            "may i",
            "can i",
        ]
        return indicators.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    /// ANSI strip regex - compiled once
    private static let ansiStripRegex: NSRegularExpression? = {
        let patterns = [
            "\u{001B}\\[[0-9;]*[A-Za-z]",
            "\u{001B}\\[\\?[0-9;]*[A-Za-z]",
            "\u{001B}\\[[0-9;]*[>=<]",
            "\u{001B}\\].*?\u{0007}",
            "\u{001B}\\].*?\u{001B}\\\\",
            "\u{001B}[()][AB012]",
            "\u{001B}=",
            "\u{001B}>",
        ]
        return try? NSRegularExpression(pattern: patterns.joined(separator: "|"))
    }()

    // MARK: - Instance Properties

    private var lastDetectionTime: Date?
    private let debounceInterval: TimeInterval = 0.5
    private var outputBuffer: String = ""
    private let bufferMaxSize = 10000
    private var lastMatchedKey: String?

    // MARK: - Public Methods

    func appendOutput(_ text: String) {
        outputBuffer += text
        if outputBuffer.count > bufferMaxSize {
            let startIndex = outputBuffer.index(outputBuffer.endIndex, offsetBy: -bufferMaxSize)
            outputBuffer = String(outputBuffer[startIndex...])
        }
    }

    func detect(in text: String, sessionId: UUID) -> ClaudeNotification? {
        appendOutput(text)

        // Debounce check
        if let lastTime = lastDetectionTime,
           Date().timeIntervalSince(lastTime) < debounceInterval {
            return nil
        }

        // Check if this is slash command menu - if so, skip detection
        if isSlashCommandMenu(text) {
            return nil
        }

        // Strip ANSI escape sequences for pattern matching
        let cleanText = stripANSI(text)

        // Pattern matching using cached regexes
        for pattern in Self.cachedPatterns {
            if pattern.regex.firstMatch(in: cleanText, range: NSRange(cleanText.startIndex..., in: cleanText)) != nil {

                // Additional validation for permission requests
                if pattern.type == .permissionRequest {
                    if !looksLikePermissionRequest(cleanText) {
                        continue
                    }
                }

                // 중복 알림 방지
                let matchKey = "\(pattern.type.rawValue):\(sessionId)"
                if matchKey == lastMatchedKey {
                    return nil
                }

                lastMatchedKey = matchKey
                lastDetectionTime = Date()
                let message = extractMessage(from: cleanText)
                let context = getRecentContext()

                return ClaudeNotification(
                    sessionId: sessionId,
                    type: pattern.type,
                    message: message,
                    context: context
                )
            }
        }

        // Check for Claude prompt waiting
        if isClaudePromptWaiting(cleanText) {
            let matchKey = "claudePrompt:\(sessionId)"
            if matchKey == lastMatchedKey {
                return nil
            }

            lastMatchedKey = matchKey
            lastDetectionTime = Date()

            return ClaudeNotification(
                sessionId: sessionId,
                type: .question,
                message: "Claude is waiting for input",
                context: getRecentContext()
            )
        }

        // Check for custom pattern matches
        if let customMatch = customPatternMatcher.match(in: cleanText) {
            let matchKey = "custom:\(customMatch.pattern.id):\(sessionId)"
            if matchKey == lastMatchedKey {
                return nil
            }

            lastMatchedKey = matchKey
            lastDetectionTime = Date()
            let message = extractMessage(from: cleanText)
            let context = getRecentContext()
            let shouldAutoPin = customMatch.pattern.autoPin

            return ClaudeNotification(
                sessionId: sessionId,
                type: .custom,
                message: message,
                context: context,
                isPinned: shouldAutoPin,
                pinnedAt: shouldAutoPin ? Date() : nil,
                matchedPatternId: customMatch.pattern.id,
                matchedPatternName: customMatch.pattern.name
            )
        }

        return nil
    }

    func reset() {
        outputBuffer = ""
        lastDetectionTime = nil
        lastMatchedKey = nil
    }

    func resetLastMatch() {
        lastMatchedKey = nil
    }

    // MARK: - Private Methods (using cached regexes)

    private func stripANSI(_ text: String) -> String {
        guard let regex = Self.ansiStripRegex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private func isSlashCommandMenu(_ rawText: String) -> Bool {
        var patternMatchCount = 0

        for regex in Self.slashCommandRegexes {
            if regex.firstMatch(in: rawText, range: NSRange(rawText.startIndex..., in: rawText)) != nil {
                patternMatchCount += 1
            }
        }

        return patternMatchCount >= 2
    }

    private func looksLikePermissionRequest(_ cleanText: String) -> Bool {
        for regex in Self.permissionRegexes {
            if regex.firstMatch(in: cleanText, range: NSRange(cleanText.startIndex..., in: cleanText)) != nil {
                return true
            }
        }
        return false
    }

    private func isClaudePromptWaiting(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        guard let lastLine = lines.last?.trimmingCharacters(in: .whitespaces),
              !lastLine.isEmpty else {
            return false
        }

        for regex in Self.claudePromptRegexes {
            if regex.firstMatch(in: lastLine, range: NSRange(lastLine.startIndex..., in: lastLine)) != nil {
                return true
            }
        }

        return false
    }

    private func extractMessage(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)

        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed.count > 5 {
                return String(trimmed.prefix(200))
            }
        }

        return String(text.prefix(200))
    }

    private func getRecentContext() -> String {
        return ""
    }
}
