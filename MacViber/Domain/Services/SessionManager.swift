import Foundation
import Combine
import UserNotifications
import AppKit

class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published private(set) var sessions: [TerminalSession] = []
    @Published private(set) var activeNotifications: [ClaudeNotification] = []
    @Published var selectedSessionId: UUID?
    @Published var splitViewState: SplitViewState = SplitViewState()

    private var controllers: [UUID: TerminalController] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var notificationsEnabled = false
    private let preferencesManager = NotificationPreferencesManager.shared

    var unreadNotificationCount: Int {
        activeNotifications.filter { !$0.isRead }.count
    }

    var hasActiveNotifications: Bool {
        !activeNotifications.isEmpty
    }

    private init() {
        requestNotificationPermission()
    }

    // MARK: - Session Management

    @discardableResult
    func createSession(name: String, workingDirectory: URL) -> TerminalSession {
        let session = TerminalSession(
            name: name,
            workingDirectory: workingDirectory,
            status: .running
        )

        let controller = TerminalController(sessionId: session.id)

        // Subscribe to notifications from this controller
        controller.notificationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleNotification(notification)
            }
            .store(in: &cancellables)

        // Subscribe to running state changes (dropFirst to ignore initial false value)
        controller.$isRunning
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRunning in
                self?.updateSessionStatus(session.id, isRunning: isRunning)
            }
            .store(in: &cancellables)

        controllers[session.id] = controller
        sessions.append(session)

        // Auto-select if first session
        if sessions.count == 1 {
            selectedSessionId = session.id
        }

        return session
    }

    func controller(for sessionId: UUID) -> TerminalController? {
        controllers[sessionId]
    }

    func session(for sessionId: UUID) -> TerminalSession? {
        sessions.first { $0.id == sessionId }
    }

    func closeSession(_ sessionId: UUID) {
        controllers[sessionId]?.terminate()
        controllers.removeValue(forKey: sessionId)
        sessions.removeAll { $0.id == sessionId }
        activeNotifications.removeAll { $0.sessionId == sessionId }

        // Split view에서 해당 세션의 pane 제거
        if let paneId = findPaneIdForSession(sessionId) {
            removePaneFromSplit(paneId)
        }

        // Select another session if current was closed
        if selectedSessionId == sessionId {
            selectedSessionId = sessions.first?.id
        }
    }

    func renameSession(_ sessionId: UUID, newName: String) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].name = newName
        }
    }

    func duplicateSession(_ sessionId: UUID) {
        guard let original = session(for: sessionId) else { return }
        createSession(
            name: "\(original.name) (copy)",
            workingDirectory: original.workingDirectory
        )
    }

    func toggleSessionLock(_ sessionId: UUID) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].isLocked.toggle()
        }
    }

    func setSessionAlias(_ sessionId: UUID, alias: String?) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            // Set to nil if empty string
            sessions[index].alias = alias?.isEmpty == true ? nil : alias
        }
    }

    private func updateSessionStatus(_ sessionId: UUID, isRunning: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        if isRunning {
            sessions[index].status = .running
        } else {
            sessions[index].status = .terminated
        }
        sessions[index].lastActivity = Date()
    }

    // MARK: - Notification Management

    private func handleNotification(_ notification: ClaudeNotification) {
        let prefs = preferencesManager.preferences

        // Type filter check
        guard prefs.isTypeEnabled(notification.type) else { return }

        // Apply auto-pin settings
        var modifiedNotification = notification
        if prefs.shouldAutoPin(notification.type) && !modifiedNotification.isPinned {
            modifiedNotification.isPinned = true
            modifiedNotification.pinnedAt = Date()
        }

        activeNotifications.append(modifiedNotification)

        // Update session status
        if let index = sessions.firstIndex(where: { $0.id == notification.sessionId }) {
            sessions[index].hasUnreadNotification = true
            sessions[index].status = .waitingForInput
            sessions[index].lastActivity = Date()
        }

        // Send system notification (if enabled)
        if prefs.systemNotificationsEnabled {
            sendSystemNotification(modifiedNotification)
        }

        // Update dock badge (if enabled)
        if prefs.dockBadgeEnabled {
            updateDockBadge()
        }
    }

    private func updateDockBadge() {
        let unreadCount = activeNotifications.filter { !$0.isRead }.count
        if unreadCount > 0 {
            NSApp.dockTile.badgeLabel = "\(unreadCount)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    func markNotificationAsRead(_ notificationId: UUID) {
        guard let index = activeNotifications.firstIndex(where: { $0.id == notificationId }) else { return }
        activeNotifications[index].isRead = true

        // Update session badge
        let sessionId = activeNotifications[index].sessionId
        let hasUnread = activeNotifications.contains { $0.sessionId == sessionId && !$0.isRead }

        if let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[sessionIndex].hasUnreadNotification = hasUnread
        }
    }

    func dismissNotification(_ notificationId: UUID) {
        guard let notification = activeNotifications.first(where: { $0.id == notificationId }) else { return }

        // Pinned notifications cannot be dismissed without unpinning first
        if notification.isPinned {
            Logger.shared.warning("Cannot dismiss pinned notification. Unpin first.")
            return
        }

        activeNotifications.removeAll { $0.id == notificationId }

        // Update session badge
        let hasUnread = activeNotifications.contains { $0.sessionId == notification.sessionId && !$0.isRead }
        if let sessionIndex = sessions.firstIndex(where: { $0.id == notification.sessionId }) {
            sessions[sessionIndex].hasUnreadNotification = hasUnread
        }

        // Update dock badge
        if preferencesManager.preferences.dockBadgeEnabled {
            updateDockBadge()
        }
    }

    func toggleNotificationPin(_ notificationId: UUID) {
        guard let index = activeNotifications.firstIndex(where: { $0.id == notificationId }) else { return }

        if activeNotifications[index].isPinned {
            activeNotifications[index].isPinned = false
            activeNotifications[index].pinnedAt = nil
        } else {
            activeNotifications[index].isPinned = true
            activeNotifications[index].pinnedAt = Date()
        }
    }

    func unpinAndDismissNotification(_ notificationId: UUID) {
        guard let index = activeNotifications.firstIndex(where: { $0.id == notificationId }) else { return }

        // Unpin first
        activeNotifications[index].isPinned = false
        activeNotifications[index].pinnedAt = nil

        // Then dismiss
        dismissNotification(notificationId)
    }

    func respondToNotification(_ notificationId: UUID, response: String) {
        guard let notification = activeNotifications.first(where: { $0.id == notificationId }),
              let controller = controllers[notification.sessionId] else { return }

        controller.sendInput(response + "\n")
        dismissNotification(notificationId)

        // Update session status
        if let index = sessions.firstIndex(where: { $0.id == notification.sessionId }) {
            sessions[index].status = .running
        }
    }

    func navigateToSession(_ sessionId: UUID) {
        selectedSessionId = sessionId

        // Mark all notifications for this session as read
        for (index, notification) in activeNotifications.enumerated() {
            if notification.sessionId == sessionId {
                activeNotifications[index].isRead = true
            }
        }

        // Update session status and badge
        if let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }) {
            // waitingForInput 상태면 running으로 변경
            if sessions[sessionIndex].status == .waitingForInput {
                sessions[sessionIndex].status = .running
            }
            sessions[sessionIndex].hasUnreadNotification = false
        }
    }

    // MARK: - System Notifications

    private func requestNotificationPermission() {
        // Check if we're running as an app bundle
        guard Bundle.main.bundleIdentifier != nil else {
            Logger.shared.warning("Not running as app bundle - system notifications disabled")
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.notificationsEnabled = granted
                if let error = error {
                    Logger.shared.warning("Notification permission not granted: \(error.localizedDescription)")
                }
            }
        }
    }

    private func sendSystemNotification(_ notification: ClaudeNotification) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Claude Code - \(notification.type.displayName)"
        content.body = notification.message
        content.sound = .default
        content.userInfo = [
            "notificationId": notification.id.uuidString,
            "sessionId": notification.sessionId.uuidString
        ]

        let request = UNNotificationRequest(
            identifier: notification.id.uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.shared.error("Failed to send notification: \(error)")
            }
        }
    }

    // MARK: - Split View Management

    /// Split view에 표시되지 않은 세션 중 가장 최근에 사용된 세션 반환
    func getUnusedSession() -> TerminalSession? {
        // 현재 split에 표시된 sessionId들 수집
        let usedSessionIds: Set<UUID>
        if let root = splitViewState.rootNode {
            usedSessionIds = Set(root.allSessionIds)
        } else if let selectedId = selectedSessionId {
            usedSessionIds = [selectedId]
        } else {
            usedSessionIds = []
        }

        // 미사용 세션 중 lastActivity 기준 최신 것 선택
        return sessions
            .filter { !usedSessionIds.contains($0.id) }
            .max(by: { $0.lastActivity < $1.lastActivity })
    }

    func setSplitViewRoot(_ node: SplitNode?) {
        var newState = splitViewState
        newState.rootNode = node
        splitViewState = newState
    }

    func setFocusedPane(_ paneId: UUID?) {
        var newState = splitViewState
        newState.focusedPaneId = paneId
        splitViewState = newState
    }

    func splitPane(_ paneId: UUID, direction: SplitDirection, newSessionId: UUID, currentSize: CGSize) {
        guard var root = splitViewState.rootNode else { return }
        guard splitViewState.canSplit else { return }

        // 전달받은 크기 직접 사용
        let currentPaneSize = PaneSize(width: currentSize.width, height: currentSize.height)

        // Split 후 각 pane의 예상 크기 계산
        let splitSize = currentPaneSize.half(for: direction)

        // 최소 크기 검증
        guard splitSize.meetsMinimum() else {
            Logger.shared.warning("Split would result in panes smaller than minimum size")
            return
        }

        let newPaneId = UUID()
        root = performSplit(on: root, paneId: paneId, direction: direction,
                           newSessionId: newSessionId, newPaneId: newPaneId,
                           splitSize: splitSize)

        var newState = splitViewState
        newState.rootNode = root
        newState.focusedPaneId = newPaneId
        splitViewState = newState
    }

    private func performSplit(on node: SplitNode, paneId: UUID, direction: SplitDirection, newSessionId: UUID, newPaneId: UUID, splitSize: PaneSize) -> SplitNode {
        switch node {
        case .terminal(let id, let sessionId, _):
            if id == paneId {
                // Found the pane to split
                // 원본 터미널과 새 터미널 모두 split 후 크기로 설정
                return .split(
                    id: UUID(),
                    direction: direction,
                    first: .terminal(id: id, sessionId: sessionId, size: splitSize),
                    second: .terminal(id: newPaneId, sessionId: newSessionId, size: splitSize),
                    ratio: 0.5
                )
            }
            return node

        case .split(let id, let dir, let first, let second, let ratio):
            return .split(
                id: id,
                direction: dir,
                first: performSplit(on: first, paneId: paneId, direction: direction, newSessionId: newSessionId, newPaneId: newPaneId, splitSize: splitSize),
                second: performSplit(on: second, paneId: paneId, direction: direction, newSessionId: newSessionId, newPaneId: newPaneId, splitSize: splitSize),
                ratio: ratio
            )
        }
    }

    func removePaneFromSplit(_ paneId: UUID) {
        guard let root = splitViewState.rootNode else { return }

        let result = removePane(from: root, paneId: paneId)

        var newState = splitViewState
        newState.rootNode = result

        // Update focused pane if needed
        if newState.focusedPaneId == paneId {
            newState.focusedPaneId = newState.allPaneIds.first
        }
        splitViewState = newState
    }

    private func removePane(from node: SplitNode, paneId: UUID) -> SplitNode? {
        switch node {
        case .terminal(let id, _, _):
            return id == paneId ? nil : node

        case .split(let id, let direction, let first, let second, let ratio):
            let newFirst = removePane(from: first, paneId: paneId)
            let newSecond = removePane(from: second, paneId: paneId)

            // If both children still exist, keep the split
            if let f = newFirst, let s = newSecond {
                return .split(id: id, direction: direction, first: f, second: s, ratio: ratio)
            }
            // If only one child remains, promote it
            return newFirst ?? newSecond
        }
    }

    func updatePaneSession(_ paneId: UUID, newSessionId: UUID) {
        guard let root = splitViewState.rootNode else { return }

        let updatedRoot = updateSessionInNode(root, paneId: paneId, newSessionId: newSessionId)

        var newState = splitViewState
        newState.rootNode = updatedRoot
        splitViewState = newState
    }

    private func updateSessionInNode(_ node: SplitNode, paneId: UUID, newSessionId: UUID) -> SplitNode {
        switch node {
        case .terminal(let id, _, let size):
            if id == paneId {
                return .terminal(id: id, sessionId: newSessionId, size: size)
            }
            return node

        case .split(let id, let direction, let first, let second, let ratio):
            return .split(
                id: id,
                direction: direction,
                first: updateSessionInNode(first, paneId: paneId, newSessionId: newSessionId),
                second: updateSessionInNode(second, paneId: paneId, newSessionId: newSessionId),
                ratio: ratio
            )
        }
    }

    func focusNextPane() {
        var newState = splitViewState
        newState.focusedPaneId = newState.nextPaneId(after: newState.focusedPaneId)
        splitViewState = newState
    }

    func focusPreviousPane() {
        var newState = splitViewState
        newState.focusedPaneId = newState.previousPaneId(before: newState.focusedPaneId)
        splitViewState = newState
    }

    /// Find the pane ID that is currently displaying a specific session
    func findPaneIdForSession(_ sessionId: UUID) -> UUID? {
        guard let root = splitViewState.rootNode else { return nil }
        return findPaneInNode(root, sessionId: sessionId)
    }

    private func findPaneInNode(_ node: SplitNode, sessionId: UUID) -> UUID? {
        switch node {
        case .terminal(let paneId, let nodeSessionId, _):
            return nodeSessionId == sessionId ? paneId : nil
        case .split(_, _, let first, let second, _):
            if let found = findPaneInNode(first, sessionId: sessionId) {
                return found
            }
            return findPaneInNode(second, sessionId: sessionId)
        }
    }

    /// Swap sessions between two panes
    func swapPaneSessions(_ paneId1: UUID, _ paneId2: UUID) {
        guard let root = splitViewState.rootNode else { return }

        // Get session IDs for both panes
        guard let sessionId1 = root.sessionId(for: paneId1),
              let sessionId2 = root.sessionId(for: paneId2) else { return }

        // Update both panes with swapped sessions
        var updatedRoot = updateSessionInNode(root, paneId: paneId1, newSessionId: sessionId2)
        updatedRoot = updateSessionInNode(updatedRoot, paneId: paneId2, newSessionId: sessionId1)

        var newState = splitViewState
        newState.rootNode = updatedRoot
        splitViewState = newState
    }

    // MARK: - Clipboard Operations

    /// Get the currently active session ID (from split view focus or selected session)
    var activeSessionId: UUID? {
        // If in split view, use focused pane's session
        if splitViewState.isActive,
           let paneId = splitViewState.focusedPaneId,
           let sessionId = splitViewState.rootNode?.sessionId(for: paneId) {
            return sessionId
        }
        // Otherwise use selected session
        return selectedSessionId
    }

    /// Copy selection from the active terminal
    func copyFromActiveTerminal() {
        guard let sessionId = activeSessionId else {
            return
        }

        guard let controller = controllers[sessionId] else {
            return
        }

        controller.copySelection()
    }

    /// Paste to the active terminal
    func pasteToActiveTerminal() {
        guard let sessionId = activeSessionId else {
            return
        }

        guard let controller = controllers[sessionId] else {
            return
        }

        controller.pasteFromClipboard()
    }

    /// Select all text in the active terminal
    func selectAllInActiveTerminal() {
        guard let sessionId = activeSessionId else {
            return
        }

        guard let controller = controllers[sessionId] else {
            return
        }

        controller.selectAllText()
    }

    // MARK: - App Lifecycle

    /// 앱 종료 시 모든 터미널 세션 종료
    func terminateAllSessions() {
        Logger.shared.info("Terminating all \(controllers.count) terminal sessions")

        for (_, controller) in controllers {
            controller.terminate()
        }

        controllers.removeAll()
        sessions.removeAll()
        activeNotifications.removeAll()

        // Clear dock badge
        NSApp.dockTile.badgeLabel = nil
    }
}
