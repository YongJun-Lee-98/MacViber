import Foundation

class ClaudeNotificationDetector {

    private struct Pattern {
        let regex: String
        let type: NotificationType
    }

    private let customPatternMatcher = CustomPatternMatcher()

    private let patterns: [Pattern] = [
        // Question patterns
        Pattern(regex: "\\?\\s*$", type: .question),
        Pattern(regex: "\\(y/n\\)", type: .question),
        Pattern(regex: "\\[Y/n\\]", type: .question),
        Pattern(regex: "\\[yes/no\\]", type: .question),
        Pattern(regex: "Press Enter to continue", type: .question),
        Pattern(regex: "Enter your choice", type: .question),

        // Permission request patterns (Claude Code specific)
        Pattern(regex: "Allow\\s+.*\\?", type: .permissionRequest),
        Pattern(regex: "Do you want to", type: .permissionRequest),
        Pattern(regex: "Proceed\\?", type: .permissionRequest),
        // More specific patterns with word boundaries
        Pattern(regex: "\\b(approve|deny)\\b", type: .permissionRequest),
        Pattern(regex: "(approve or deny)", type: .permissionRequest),
        Pattern(regex: "\\(approve/deny\\)", type: .permissionRequest),
        Pattern(regex: "\\[approve\\|deny\\]", type: .permissionRequest),

        // Completion patterns
        Pattern(regex: "✓.*completed", type: .completion),
        Pattern(regex: "Done\\.", type: .completion),
        Pattern(regex: "Successfully", type: .completion),
        Pattern(regex: "finished", type: .completion),

        // Error patterns
        Pattern(regex: "Error:", type: .error),
        Pattern(regex: "Failed:", type: .error),
        Pattern(regex: "✗", type: .error),
        Pattern(regex: "FAILED", type: .error),
    ]

    private let claudePromptPatterns: [String] = [
        "❯",
        "claude>",
        "\\[Claude\\]",
        ">>> ",
        "\\.\\.\\. ",
    ]

    private var lastDetectionTime: Date?
    private let debounceInterval: TimeInterval = 0.5
    private var outputBuffer: String = ""
    private let bufferMaxSize = 10000

    // ANSI patterns that indicate slash command menu display
    private let slashCommandMenuPatterns: [String] = [
        // Cursor movement patterns common in interactive menus
        "\\[3C\\[1B",           // Move right 3, down 1 (typical menu navigation)
        "\\[17C",               // Move right 17 (column alignment in menu)
        "\\[\\d+C\\[1B",        // Generic: move right N, down 1

        // Color patterns for menu items
        "\\[94m.*\\[39m",       // Blue text (94m) reset (39m) - menu highlights
        "\\[37m.*\\[39m",       // White text - menu items

        // Multiple consecutive lines with same pattern (menu structure)
        "(\\[3C\\[1B.*){2,}",   // At least 2 lines with this pattern
    ]

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

        // Pattern matching
        for pattern in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern.regex, options: .caseInsensitive)
                if regex.firstMatch(in: cleanText, range: NSRange(cleanText.startIndex..., in: cleanText)) != nil {

                    // Additional validation for permission requests
                    if pattern.type == .permissionRequest {
                        // Ensure this looks like an actual permission request
                        if !looksLikePermissionRequest(cleanText) {
                            continue  // Skip this match
                        }
                    }

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
            } catch {
                Logger.shared.error("Invalid regex pattern '\(pattern.regex)': \(error)")
            }
        }

        // Check for Claude prompt waiting
        if isClaudePromptWaiting(cleanText) {
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

    private func stripANSI(_ text: String) -> String {
        // 포괄적인 ANSI/터미널 제어 시퀀스 패턴
        let patterns = [
            "\u{001B}\\[[0-9;]*[A-Za-z]",           // 기본 CSI 시퀀스 (색상, 커서 등)
            "\u{001B}\\[\\?[0-9;]*[A-Za-z]",        // DEC Private Mode (?포함)
            "\u{001B}\\[[0-9;]*[>=<]",              // DA 및 기타 제어
            "\u{001B}\\].*?\u{0007}",               // OSC 시퀀스 (BEL로 종료)
            "\u{001B}\\].*?\u{001B}\\\\",           // OSC 시퀀스 (ST로 종료)
            "\u{001B}[()][AB012]",                  // 문자셋 지정
            "\u{001B}=",                            // Application Keypad Mode
            "\u{001B}>",                            // Normal Keypad Mode
        ]
        let combined = patterns.joined(separator: "|")

        do {
            let regex = try NSRegularExpression(pattern: combined)
            let range = NSRange(text.startIndex..., in: text)
            return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        } catch {
            Logger.shared.error("Failed to create ANSI strip regex: \(error)")
            return text
        }
    }

    /// Detects if the output appears to be from Claude Code's slash command menu
    /// by looking for characteristic ANSI patterns in the raw (non-stripped) text
    private func isSlashCommandMenu(_ rawText: String) -> Bool {
        // Check if text contains multiple menu-like ANSI patterns
        var patternMatchCount = 0

        for pattern in slashCommandMenuPatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                if regex.firstMatch(in: rawText, range: NSRange(rawText.startIndex..., in: rawText)) != nil {
                    patternMatchCount += 1
                }
            } catch {
                // Invalid pattern, skip
                continue
            }
        }

        // If we find 2 or more menu patterns, it's likely a slash command menu
        return patternMatchCount >= 2
    }

    /// Additional validation to ensure text looks like an actual permission request
    private func looksLikePermissionRequest(_ cleanText: String) -> Bool {
        let permissionIndicators = [
            "allow",
            "permission",
            "access",
            "proceed",
            "continue",
            "confirm",
            "\\?",  // Question mark
            "do you want",
            "would you like",
            "may i",
            "can i",
        ]

        // Check if text contains permission-related context
        for indicator in permissionIndicators {
            do {
                let regex = try NSRegularExpression(pattern: indicator, options: .caseInsensitive)
                if regex.firstMatch(in: cleanText, range: NSRange(cleanText.startIndex..., in: cleanText)) != nil {
                    return true
                }
            } catch {
                continue
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

        for pattern in claudePromptPatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern)
                if regex.firstMatch(in: lastLine, range: NSRange(lastLine.startIndex..., in: lastLine)) != nil {
                    return true
                }
            } catch {
                Logger.shared.error("Invalid Claude prompt pattern '\(pattern)': \(error)")
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
        // 원시 터미널 버퍼는 키 입력 에코, 백스페이스 등 노이즈가 많아 context 비활성화
        // message 필드가 핵심 정보를 이미 제공함
        return ""
    }

    func reset() {
        outputBuffer = ""
        lastDetectionTime = nil
    }
}
