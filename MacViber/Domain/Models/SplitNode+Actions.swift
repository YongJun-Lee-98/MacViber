import Foundation

extension SplitNode {
    
    func split(
        paneId: UUID,
        direction: SplitDirection,
        newSessionId: UUID,
        newPaneId: UUID,
        splitSize: PaneSize
    ) -> SplitNode {
        switch self {
        case .terminal(let id, let sessionId, _):
            if id == paneId {
                return .split(
                    id: UUID(),
                    direction: direction,
                    first: .terminal(id: id, sessionId: sessionId, size: splitSize),
                    second: .terminal(id: newPaneId, sessionId: newSessionId, size: splitSize),
                    ratio: 0.5
                )
            }
            return self
            
        case .split(let id, let dir, let first, let second, let ratio):
            return .split(
                id: id,
                direction: dir,
                first: first.split(paneId: paneId, direction: direction, newSessionId: newSessionId, newPaneId: newPaneId, splitSize: splitSize),
                second: second.split(paneId: paneId, direction: direction, newSessionId: newSessionId, newPaneId: newPaneId, splitSize: splitSize),
                ratio: ratio
            )
        }
    }
    
    func removingPane(_ paneId: UUID) -> SplitNode? {
        switch self {
        case .terminal(let id, _, _):
            return id == paneId ? nil : self
            
        case .split(let id, let direction, let first, let second, let ratio):
            let newFirst = first.removingPane(paneId)
            let newSecond = second.removingPane(paneId)
            
            if let f = newFirst, let s = newSecond {
                return .split(id: id, direction: direction, first: f, second: s, ratio: ratio)
            }
            return newFirst ?? newSecond
        }
    }
    
    func updatingSession(paneId: UUID, newSessionId: UUID) -> SplitNode {
        switch self {
        case .terminal(let id, _, let size):
            if id == paneId {
                return .terminal(id: id, sessionId: newSessionId, size: size)
            }
            return self
            
        case .split(let id, let direction, let first, let second, let ratio):
            return .split(
                id: id,
                direction: direction,
                first: first.updatingSession(paneId: paneId, newSessionId: newSessionId),
                second: second.updatingSession(paneId: paneId, newSessionId: newSessionId),
                ratio: ratio
            )
        }
    }
    
    func paneId(for sessionId: UUID) -> UUID? {
        switch self {
        case .terminal(let paneId, let nodeSessionId, _):
            return nodeSessionId == sessionId ? paneId : nil
        case .split(_, _, let first, let second, _):
            return first.paneId(for: sessionId) ?? second.paneId(for: sessionId)
        }
    }
    
    func parentSplitInfo(of paneId: UUID) -> (splitId: UUID, position: Int)? {
        switch self {
        case .terminal:
            return nil
        case .split(let id, _, let first, let second, _):
            if case .terminal(let termId, _, _) = first, termId == paneId {
                return (id, 0)
            }
            if case .terminal(let termId, _, _) = second, termId == paneId {
                return (id, 1)
            }
            return first.parentSplitInfo(of: paneId) ?? second.parentSplitInfo(of: paneId)
        }
    }
}
