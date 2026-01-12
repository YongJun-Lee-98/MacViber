//
//  MinimizedPane.swift
//  MacViber
//
//  최소화된 Pane 정보를 저장하는 모델
//

import Foundation

/// 최소화된 Pane 정보
struct MinimizedPane: Identifiable, Equatable {
    /// Pane ID (복원 시 새 ID 생성될 수 있음)
    let id: UUID

    /// 연결된 세션 ID
    let sessionId: UUID

    /// 최소화 시점
    let minimizedAt: Date

    /// 원래 속해 있던 split node ID (복원 위치 힌트)
    var parentSplitId: UUID?

    /// 부모 내 위치 (0 = first, 1 = second)
    var positionInParent: Int?

    init(paneId: UUID, sessionId: UUID, parentSplitId: UUID? = nil, positionInParent: Int? = nil) {
        self.id = paneId
        self.sessionId = sessionId
        self.minimizedAt = Date()
        self.parentSplitId = parentSplitId
        self.positionInParent = positionInParent
    }
}
