import Foundation

struct CustomPatternMatch {
    let pattern: CustomPattern
    let matchedText: String
}

final class CustomPatternMatcher {
    private let preferencesManager: NotificationPreferencesManager

    // Regex cache to avoid recompiling on every match
    private var regexCache: [UUID: NSRegularExpression] = [:]
    private var cachePatternHashes: [UUID: Int] = [:]  // Track pattern changes

    init(preferencesManager: NotificationPreferencesManager = .shared) {
        self.preferencesManager = preferencesManager
    }

    func match(in text: String) -> CustomPatternMatch? {
        let enabledPatterns = preferencesManager.getEnabledCustomPatterns()

        for pattern in enabledPatterns {
            if matchesWithCache(pattern: pattern, text: text) {
                return CustomPatternMatch(pattern: pattern, matchedText: text)
            }
        }

        return nil
    }

    func matchAll(in text: String) -> [CustomPatternMatch] {
        let enabledPatterns = preferencesManager.getEnabledCustomPatterns()
        var matches: [CustomPatternMatch] = []

        for pattern in enabledPatterns {
            if matchesWithCache(pattern: pattern, text: text) {
                matches.append(CustomPatternMatch(pattern: pattern, matchedText: text))
            }
        }

        return matches
    }

    // MARK: - Private Methods

    private func matchesWithCache(pattern: CustomPattern, text: String) -> Bool {
        guard pattern.isEnabled, !pattern.pattern.isEmpty else { return false }

        switch pattern.matchMode {
        case .keyword:
            return text.localizedCaseInsensitiveContains(pattern.pattern)

        case .regex:
            guard let regex = getCachedRegex(for: pattern) else { return false }
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }

    private func getCachedRegex(for pattern: CustomPattern) -> NSRegularExpression? {
        let patternHash = pattern.pattern.hashValue

        // Check if pattern changed (invalidate cache)
        if let cachedHash = cachePatternHashes[pattern.id], cachedHash != patternHash {
            regexCache.removeValue(forKey: pattern.id)
        }

        // Return cached regex if available
        if let cached = regexCache[pattern.id] {
            return cached
        }

        // Compile and cache new regex
        guard let regex = try? NSRegularExpression(pattern: pattern.pattern, options: .caseInsensitive) else {
            return nil
        }

        regexCache[pattern.id] = regex
        cachePatternHashes[pattern.id] = patternHash
        return regex
    }

    /// Clear cache when patterns are updated
    func invalidateCache() {
        regexCache.removeAll()
        cachePatternHashes.removeAll()
    }
}
