import Foundation
import SwiftUI

enum NotificationType: String, Codable {
    case question
    case permissionRequest
    case completion
    case error

    var displayName: String {
        switch self {
        case .question: return "Question"
        case .permissionRequest: return "Permission Request"
        case .completion: return "Completed"
        case .error: return "Error"
        }
    }

    var iconName: String {
        switch self {
        case .question: return "questionmark.circle.fill"
        case .permissionRequest: return "lock.shield.fill"
        case .completion: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .question: return .blue
        case .permissionRequest: return .orange
        case .completion: return .green
        case .error: return .red
        }
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

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        type: NotificationType,
        message: String,
        context: String = "",
        timestamp: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.sessionId = sessionId
        self.type = type
        self.message = message
        self.context = context
        self.timestamp = timestamp
        self.isRead = isRead
    }

    static func == (lhs: ClaudeNotification, rhs: ClaudeNotification) -> Bool {
        lhs.id == rhs.id
    }
}
