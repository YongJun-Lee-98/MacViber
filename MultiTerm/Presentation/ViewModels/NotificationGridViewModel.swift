import Foundation
import Combine
import SwiftUI

class NotificationGridViewModel: ObservableObject {
    private let sessionManager: SessionManager
    private var cancellables = Set<AnyCancellable>()

    // Cached sorted notifications to avoid re-sorting on every render
    @Published private(set) var sortedNotifications: [ClaudeNotification] = []

    var activeNotifications: [ClaudeNotification] {
        sessionManager.activeNotifications
    }

    var notificationCount: Int {
        sortedNotifications.count
    }

    init(sessionManager: SessionManager = .shared) {
        self.sessionManager = sessionManager

        // Debounce objectWillChange to reduce CPU usage
        sessionManager.objectWillChange
            .debounce(for: .milliseconds(16), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSortedNotifications()
            }
            .store(in: &cancellables)

        // Initial sort
        updateSortedNotifications()
    }

    private func updateSortedNotifications() {
        let newSorted = activeNotifications.sorted { a, b in
            // Pinned notifications come first
            if a.isPinned != b.isPinned {
                return a.isPinned
            }
            // Then sort by timestamp (newest first)
            return a.timestamp > b.timestamp
        }

        // Only update if changed to avoid unnecessary view updates
        if newSorted.map(\.id) != sortedNotifications.map(\.id) {
            sortedNotifications = newSorted
        }
    }

    func sessionName(for notification: ClaudeNotification) -> String {
        sessionManager.session(for: notification.sessionId)?.name ?? "Unknown"
    }

    func respond(to notification: ClaudeNotification, with response: String) {
        sessionManager.respondToNotification(notification.id, response: response)
    }

    func dismiss(_ notification: ClaudeNotification) {
        sessionManager.dismissNotification(notification.id)
    }

    func markAsRead(_ notification: ClaudeNotification) {
        sessionManager.markNotificationAsRead(notification.id)
    }

    func navigateToSession(_ notification: ClaudeNotification) {
        sessionManager.navigateToSession(notification.sessionId)
        // 핀 알림이 아닌 경우에만 삭제
        if !notification.isPinned {
            sessionManager.dismissNotification(notification.id)
        }
        // 알림 그리드 숨기기 (터미널 포커스)
        NotificationCenter.default.post(name: .hideNotificationGrid, object: nil)
    }

    func togglePin(_ notification: ClaudeNotification) {
        sessionManager.toggleNotificationPin(notification.id)
    }

    func calculateGridLayout(count: Int, size: CGSize) -> GridLayout {
        switch count {
        case 1:
            return GridLayout(columns: 1, itemHeight: size.height - 32)
        case 2:
            return GridLayout(columns: 2, itemHeight: size.height - 32)
        case 3...4:
            return GridLayout(columns: 2, itemHeight: (size.height - 48) / 2)
        case 5...6:
            return GridLayout(columns: 3, itemHeight: (size.height - 48) / 2)
        case 7...9:
            return GridLayout(columns: 3, itemHeight: (size.height - 64) / 3)
        default:
            let cols = Int(ceil(sqrt(Double(count))))
            let rows = Int(ceil(Double(count) / Double(cols)))
            return GridLayout(
                columns: cols,
                itemHeight: (size.height - CGFloat(rows + 1) * 16) / CGFloat(rows)
            )
        }
    }
}

struct GridLayout {
    let columns: Int
    let itemHeight: CGFloat
}
