import Foundation

enum PatternMatchMode: String, Codable, CaseIterable {
    case keyword
    case regex

    var displayName: String {
        switch self {
        case .keyword: return "Keyword"
        case .regex: return "Regular Expression"
        }
    }
}

struct CustomPattern: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var pattern: String
    var matchMode: PatternMatchMode
    var isEnabled: Bool
    var autoPin: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        pattern: String,
        matchMode: PatternMatchMode = .keyword,
        isEnabled: Bool = true,
        autoPin: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.matchMode = matchMode
        self.isEnabled = isEnabled
        self.autoPin = autoPin
        self.createdAt = createdAt
    }

    var isValidPattern: Bool {
        guard matchMode == .regex else { return true }
        guard !pattern.isEmpty else { return false }
        do {
            _ = try NSRegularExpression(pattern: pattern)
            return true
        } catch {
            return false
        }
    }

    func matches(_ text: String) -> Bool {
        guard isEnabled, !pattern.isEmpty else { return false }

        switch matchMode {
        case .keyword:
            return text.localizedCaseInsensitiveContains(pattern)
        case .regex:
            guard isValidPattern else { return false }
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(text.startIndex..., in: text)
                return regex.firstMatch(in: text, options: [], range: range) != nil
            } catch {
                return false
            }
        }
    }
}
