import Foundation

/// Direction of split view
enum SplitDirection: String, Codable {
    case horizontal  // Side by side (left | right)
    case vertical    // Stacked (top / bottom)
}

/// Size information for a terminal pane
struct PaneSize: Codable, Equatable {
    var width: CGFloat
    var height: CGFloat

    // 적절한 최소 터미널 크기 (약 40 cols x 12 rows에 해당)
    static let minimum = PaneSize(width: 300, height: 200)

    // 크기가 최소값 이상인지 확인
    func meetsMinimum() -> Bool {
        return width >= Self.minimum.width && height >= Self.minimum.height
    }

    // 특정 방향으로 절반 크기 계산
    func half(for direction: SplitDirection) -> PaneSize {
        switch direction {
        case .horizontal:
            return PaneSize(width: width / 2, height: height)
        case .vertical:
            return PaneSize(width: width, height: height / 2)
        }
    }
}

/// Represents the split view layout as a binary tree
indirect enum SplitNode: Identifiable, Equatable {
    case terminal(id: UUID, sessionId: UUID, size: PaneSize?)
    case split(id: UUID, direction: SplitDirection, first: SplitNode, second: SplitNode, ratio: CGFloat)

    var id: UUID {
        switch self {
        case .terminal(let id, _, _):
            return id
        case .split(let id, _, _, _, _):
            return id
        }
    }

    /// Returns all terminal session IDs in this node tree
    var allSessionIds: [UUID] {
        switch self {
        case .terminal(_, let sessionId, _):
            return [sessionId]
        case .split(_, _, let first, let second, _):
            return first.allSessionIds + second.allSessionIds
        }
    }

    /// Returns all pane IDs in this node tree
    var allPaneIds: [UUID] {
        switch self {
        case .terminal(let id, _, _):
            return [id]
        case .split(_, _, let first, let second, _):
            return first.allPaneIds + second.allPaneIds
        }
    }

    /// Find session ID for a given pane ID
    func sessionId(for paneId: UUID) -> UUID? {
        switch self {
        case .terminal(let id, let sessionId, _):
            return id == paneId ? sessionId : nil
        case .split(_, _, let first, let second, _):
            return first.sessionId(for: paneId) ?? second.sessionId(for: paneId)
        }
    }

    /// Count total number of terminal panes
    var paneCount: Int {
        switch self {
        case .terminal:
            return 1
        case .split(_, _, let first, let second, _):
            return first.paneCount + second.paneCount
        }
    }
}

/// State for split view mode
struct SplitViewState: Equatable {
    var rootNode: SplitNode?
    var focusedPaneId: UUID?
    var maxPaneCount: Int = 9
    var minimizedPanes: [MinimizedPane] = []

    var isActive: Bool {
        rootNode != nil
    }

    var paneCount: Int {
        rootNode?.paneCount ?? 0
    }

    var canSplit: Bool {
        paneCount < maxPaneCount
    }

    var allPaneIds: [UUID] {
        rootNode?.allPaneIds ?? []
    }

    var hasMinimizedPanes: Bool {
        !minimizedPanes.isEmpty
    }

    var minimizedPaneCount: Int {
        minimizedPanes.count
    }

    /// 최소화된 pane들의 세션 ID 집합
    var minimizedSessionIds: Set<UUID> {
        Set(minimizedPanes.map { $0.sessionId })
    }

    /// Get the next pane ID in sequence (for navigation)
    func nextPaneId(after currentId: UUID?) -> UUID? {
        let paneIds = allPaneIds
        guard !paneIds.isEmpty else { return nil }

        if let currentId = currentId,
           let currentIndex = paneIds.firstIndex(of: currentId) {
            let nextIndex = (currentIndex + 1) % paneIds.count
            return paneIds[nextIndex]
        }

        return paneIds.first
    }

    /// Get the previous pane ID in sequence (for navigation)
    func previousPaneId(before currentId: UUID?) -> UUID? {
        let paneIds = allPaneIds
        guard !paneIds.isEmpty else { return nil }

        if let currentId = currentId,
           let currentIndex = paneIds.firstIndex(of: currentId) {
            let prevIndex = currentIndex == 0 ? paneIds.count - 1 : currentIndex - 1
            return paneIds[prevIndex]
        }

        return paneIds.last
    }
}
