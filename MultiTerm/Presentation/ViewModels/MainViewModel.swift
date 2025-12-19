import Foundation
import Combine
import SwiftUI
import AppKit

class MainViewModel: ObservableObject {
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var showNotificationGrid: Bool = false
    @Published var showRightSidebar: Bool = false
    @Published var focusedPaneId: UUID?
    @Published var showKeyboardShortcuts: Bool = false
    @Published private(set) var selectedSessionId: UUID?

    private let sessionManager: SessionManager
    private var cancellables = Set<AnyCancellable>()
    private var isUpdatingFromSessionManager = false
    private var previousNotificationCount: Int = 0

    var selectedSession: TerminalSession? {
        guard let id = selectedSessionId else { return nil }
        return sessionManager.session(for: id)
    }

    func selectSession(_ id: UUID?) {
        guard !isUpdatingFromSessionManager else { return }
        selectedSessionId = id
        if let id = id {
            sessionManager.selectedSessionId = id
        }
    }

    var sessions: [TerminalSession] {
        sessionManager.sessions
    }

    var activeNotifications: [ClaudeNotification] {
        sessionManager.activeNotifications
    }

    var hasActiveNotifications: Bool {
        sessionManager.hasActiveNotifications
    }

    var unreadNotificationCount: Int {
        sessionManager.unreadNotificationCount
    }

    // MARK: - Split View Properties

    var splitViewState: SplitViewState {
        sessionManager.splitViewState
    }

    var splitViewRoot: SplitNode? {
        sessionManager.splitViewState.rootNode
    }

    var isSplitViewActive: Bool {
        sessionManager.splitViewState.isActive
    }

    var canSplit: Bool {
        sessionManager.splitViewState.canSplit
    }

    init(sessionManager: SessionManager = .shared) {
        self.sessionManager = sessionManager

        // Sync initial selectedSessionId
        self.selectedSessionId = sessionManager.selectedSessionId

        // Setup notification observers
        setupNotificationObservers()

        // Subscribe to selectedSessionId changes from SessionManager
        sessionManager.$selectedSessionId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newId in
                guard let self = self else { return }
                self.isUpdatingFromSessionManager = true
                self.selectedSessionId = newId
                self.isUpdatingFromSessionManager = false
            }
            .store(in: &cancellables)

        // Subscribe to sessions changes to ensure UI updates
        sessionManager.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Auto-show notification grid only when NEW notifications arrive
        previousNotificationCount = sessionManager.activeNotifications.count
        sessionManager.$activeNotifications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notifications in
                guard let self = self else { return }
                // 새로운 알림이 추가되었을 때만 auto-show (개수 증가 시)
                if notifications.count > self.previousNotificationCount && !self.showNotificationGrid {
                    withAnimation {
                        self.showNotificationGrid = true
                    }
                }
                self.previousNotificationCount = notifications.count
            }
            .store(in: &cancellables)

        // Forward split view state changes to trigger UI updates
        sessionManager.$splitViewState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.focusedPaneId = state.focusedPaneId
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .newTerminalRequested)
            .sink { [weak self] _ in
                self?.addNewTerminal()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .closeTerminalRequested)
            .sink { [weak self] _ in
                self?.closeCurrentTerminal()
            }
            .store(in: &cancellables)

        // Split view notifications
        NotificationCenter.default.publisher(for: .splitHorizontalRequested)
            .sink { [weak self] _ in
                self?.splitCurrentPane(.horizontal)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .splitVerticalRequested)
            .sink { [weak self] _ in
                self?.splitCurrentPane(.vertical)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .closePaneRequested)
            .sink { [weak self] _ in
                self?.closeCurrentPane()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .focusNextPaneRequested)
            .sink { [weak self] _ in
                self?.focusNextPane()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .focusPreviousPaneRequested)
            .sink { [weak self] _ in
                self?.focusPreviousPane()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .showKeyboardShortcuts)
            .sink { [weak self] _ in
                self?.showKeyboardShortcuts = true
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .hideNotificationGrid)
            .sink { [weak self] _ in
                withAnimation {
                    self?.showNotificationGrid = false
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleRightSidebar)
            .sink { [weak self] _ in
                self?.toggleRightSidebar()
            }
            .store(in: &cancellables)
    }

    func addNewTerminal() {
        // Capture split view state BEFORE opening modal (modal can cause state changes)
        let wasInSplitView = isSplitViewActive
        let capturedPaneId = focusedPaneId

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select working directory for new terminal"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            let session = sessionManager.createSession(
                name: url.lastPathComponent,
                workingDirectory: url
            )

            // Use captured state (not current state which may have changed during modal)
            if wasInSplitView, let paneId = capturedPaneId {
                sessionManager.updatePaneSession(paneId, newSessionId: session.id)
            } else {
                sessionManager.selectedSessionId = session.id
                selectedSessionId = session.id
            }
        }
    }

    func addNewTerminalAtHome() {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let session = sessionManager.createSession(
            name: "Terminal",
            workingDirectory: homeURL
        )

        // Check if in split view mode
        if isSplitViewActive, let paneId = focusedPaneId {
            sessionManager.updatePaneSession(paneId, newSessionId: session.id)
        } else {
            sessionManager.selectedSessionId = session.id
            selectedSessionId = session.id
        }
    }

    func addNewTerminal(at url: URL) {
        let session = sessionManager.createSession(
            name: url.lastPathComponent,
            workingDirectory: url
        )

        // Check if in split view mode
        if isSplitViewActive, let paneId = focusedPaneId {
            sessionManager.updatePaneSession(paneId, newSessionId: session.id)
        } else {
            sessionManager.selectedSessionId = session.id
            selectedSessionId = session.id
        }
    }

    func addFavoriteFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select folder to add to favorites"
        panel.prompt = "Add"

        if panel.runModal() == .OK, let url = panel.url {
            FavoritesManager.shared.add(url)
        }
    }

    func closeCurrentTerminal() {
        guard let sessionId = selectedSessionId else { return }
        sessionManager.closeSession(sessionId)
    }

    func navigateToSession(_ sessionId: UUID) {
        sessionManager.navigateToSession(sessionId)
        selectedSessionId = sessionId
        showNotificationGrid = false
    }

    /// Handle terminal selection from sidebar
    /// In split view: swaps sessions if another pane already shows the selected session, otherwise replaces
    /// In single view: switches to the selected terminal
    func handleTerminalSelection(_ sessionId: UUID) {
        if isSplitViewActive, let paneId = focusedPaneId {
            // Check if another pane is already displaying this session
            if let existingPaneId = sessionManager.findPaneIdForSession(sessionId),
               existingPaneId != paneId {
                // SWAP: another pane has this session, swap sessions between panes
                sessionManager.swapPaneSessions(paneId, existingPaneId)
            } else {
                // Simple replacement: no other pane has this session
                sessionManager.updatePaneSession(paneId, newSessionId: sessionId)
            }
        } else {
            // In single view: switch to selected terminal
            navigateToSession(sessionId)
        }
    }

    func toggleNotificationGrid() {
        withAnimation {
            showNotificationGrid.toggle()
        }
    }

    func toggleRightSidebar() {
        withAnimation {
            showRightSidebar.toggle()
        }
    }

    func controller(for sessionId: UUID) -> TerminalController? {
        sessionManager.controller(for: sessionId)
    }

    func session(for sessionId: UUID) -> TerminalSession? {
        sessionManager.session(for: sessionId)
    }

    // MARK: - Split View Methods

    func enterSplitView() {
        guard let sessionId = selectedSessionId else { return }
        let paneId = UUID()
        let node = SplitNode.terminal(id: paneId, sessionId: sessionId, size: nil)
        sessionManager.setSplitViewRoot(node)
        sessionManager.setFocusedPane(paneId)  // Must use SessionManager to properly sync state
    }

    func exitSplitView() {
        // Preserve selection from focused pane
        if let paneId = focusedPaneId,
           let sessionId = splitViewRoot?.sessionId(for: paneId) {
            sessionManager.selectedSessionId = sessionId
            selectedSessionId = sessionId
        }
        sessionManager.setSplitViewRoot(nil)
        sessionManager.setFocusedPane(nil)
    }

    func splitPane(_ paneId: UUID, direction: SplitDirection, currentSize: CGSize) {
        guard canSplit else { return }

        // Create new terminal for the split
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let newSession = sessionManager.createSession(
            name: "Terminal",
            workingDirectory: homeURL
        )
        sessionManager.splitPane(
            paneId,
            direction: direction,
            newSessionId: newSession.id,
            currentSize: currentSize
        )
    }

    func splitCurrentPane(_ direction: SplitDirection) {
        // 키보드 단축키는 현재 크기를 알 수 없으므로 fallback 사용
        let fallbackSize = CGSize(width: 800, height: 600)

        if let paneId = focusedPaneId {
            splitPane(paneId, direction: direction, currentSize: fallbackSize)
        } else if isSplitViewActive, let firstPaneId = splitViewState.allPaneIds.first {
            splitPane(firstPaneId, direction: direction, currentSize: fallbackSize)
        } else if selectedSessionId != nil {
            // Not in split view yet, enter split view first then split
            enterSplitView()
            if let paneId = focusedPaneId {
                splitPane(paneId, direction: direction, currentSize: fallbackSize)
            }
        }
    }

    func removePane(_ paneId: UUID) {
        sessionManager.removePaneFromSplit(paneId)

        // If no panes left, exit split view
        if splitViewState.paneCount == 0 {
            exitSplitView()
        } else if splitViewState.paneCount == 1 {
            // Optionally exit split view when only one pane remains
            exitSplitView()
        }
    }

    func closeCurrentPane() {
        guard let paneId = focusedPaneId else { return }
        removePane(paneId)
    }

    func focusNextPane() {
        if let nextId = splitViewState.nextPaneId(after: focusedPaneId) {
            sessionManager.setFocusedPane(nextId)
        }
    }

    func focusPreviousPane() {
        if let prevId = splitViewState.previousPaneId(before: focusedPaneId) {
            sessionManager.setFocusedPane(prevId)
        }
    }

    func addTerminalToSplit(sessionId: UUID, direction: SplitDirection) {
        guard let paneId = focusedPaneId else { return }
        // Use fallback size since we don't have access to current geometry
        let fallbackSize = CGSize(width: 800, height: 600)
        sessionManager.splitPane(paneId, direction: direction, newSessionId: sessionId, currentSize: fallbackSize)
    }

}
