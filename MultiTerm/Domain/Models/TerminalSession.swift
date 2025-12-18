import Foundation

enum SessionStatus: String, Codable {
    case idle
    case running
    case waitingForInput
    case terminated
}

struct TerminalSession: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var alias: String?
    var workingDirectory: URL
    var status: SessionStatus
    var hasUnreadNotification: Bool
    var isLocked: Bool
    var lastActivity: Date
    let createdAt: Date

    var displayName: String {
        alias ?? name
    }

    init(
        id: UUID = UUID(),
        name: String,
        alias: String? = nil,
        workingDirectory: URL,
        status: SessionStatus = .idle,
        hasUnreadNotification: Bool = false,
        isLocked: Bool = false,
        lastActivity: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.alias = alias
        self.workingDirectory = workingDirectory
        self.status = status
        self.hasUnreadNotification = hasUnreadNotification
        self.isLocked = isLocked
        self.lastActivity = lastActivity
        self.createdAt = createdAt
    }

    static func == (lhs: TerminalSession, rhs: TerminalSession) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
