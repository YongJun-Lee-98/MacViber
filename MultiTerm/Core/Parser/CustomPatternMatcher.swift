import Foundation

struct CustomPatternMatch {
    let pattern: CustomPattern
    let matchedText: String
}

final class CustomPatternMatcher {
    private let preferencesManager: NotificationPreferencesManager

    init(preferencesManager: NotificationPreferencesManager = .shared) {
        self.preferencesManager = preferencesManager
    }

    func match(in text: String) -> CustomPatternMatch? {
        let enabledPatterns = preferencesManager.getEnabledCustomPatterns()

        for pattern in enabledPatterns {
            if pattern.matches(text) {
                return CustomPatternMatch(pattern: pattern, matchedText: text)
            }
        }

        return nil
    }

    func matchAll(in text: String) -> [CustomPatternMatch] {
        let enabledPatterns = preferencesManager.getEnabledCustomPatterns()
        var matches: [CustomPatternMatch] = []

        for pattern in enabledPatterns {
            if pattern.matches(text) {
                matches.append(CustomPatternMatch(pattern: pattern, matchedText: text))
            }
        }

        return matches
    }
}
