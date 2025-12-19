import Foundation
import SwiftUI

enum NotificationType: String, Codable, CaseIterable {
    case question
    case permissionRequest
    case completion
    case error
    case custom

    var displayName: String {
        switch self {
        case .question: return "Question"
        case .permissionRequest: return "Permission Request"
        case .completion: return "Completed"
        case .error: return "Error"
        case .custom: return "Custom"
        }
    }

    var iconName: String {
        switch self {
        case .question: return "questionmark.circle.fill"
        case .permissionRequest: return "lock.shield.fill"
        case .completion: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .custom: return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .question: return .blue
        case .permissionRequest: return .orange
        case .completion: return .green
        case .error: return .red
        case .custom: return .purple
        }
    }

    static var filterableCases: [NotificationType] {
        // question은 사용자 입력 대기이므로 항상 알림 필요 - 필터링 대상에서 제외
        [.permissionRequest, .completion, .error, .custom]
    }
}

struct ClaudeNotification: Identifiable, Equatable {
    let id: UUID
    var sessionId: UUID
    let type: NotificationType
    let message: String
    let context: String
    let timestamp: Date
    var isRead: Bool
    var isPinned: Bool
    var pinnedAt: Date?
    var matchedPatternId: UUID?
    var matchedPatternName: String?

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        type: NotificationType,
        message: String,
        context: String = "",
        timestamp: Date = Date(),
        isRead: Bool = false,
        isPinned: Bool = false,
        pinnedAt: Date? = nil,
        matchedPatternId: UUID? = nil,
        matchedPatternName: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.type = type
        self.message = message
        self.context = context
        self.timestamp = timestamp
        self.isRead = isRead
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.matchedPatternId = matchedPatternId
        self.matchedPatternName = matchedPatternName
    }

    static func == (lhs: ClaudeNotification, rhs: ClaudeNotification) -> Bool {
        lhs.id == rhs.id
    }

    var displayTypeName: String {
        if let patternName = matchedPatternName {
            return patternName
        }
        return type.displayName
    }
}
