import Foundation
import Combine

class TerminalListViewModel: ObservableObject {
    private let sessionManager: SessionManager
    private var cancellables = Set<AnyCancellable>()

    var sessions: [TerminalSession] {
        sessionManager.sessions
    }

    var selectedSessionId: UUID? {
        get { sessionManager.selectedSessionId }
        set { sessionManager.selectedSessionId = newValue }
    }

    init(sessionManager: SessionManager = .shared) {
        self.sessionManager = sessionManager

        // Forward changes from sessionManager
        sessionManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func selectSession(_ sessionId: UUID) {
        sessionManager.navigateToSession(sessionId)
    }

    func closeSession(_ session: TerminalSession) {
        sessionManager.closeSession(session.id)
    }

    func renameSession(_ session: TerminalSession, newName: String) {
        sessionManager.renameSession(session.id, newName: newName)
    }

    func duplicateSession(_ session: TerminalSession) {
        sessionManager.duplicateSession(session.id)
    }

    func toggleLock(_ session: TerminalSession) {
        sessionManager.toggleSessionLock(session.id)
    }

    func setAlias(_ session: TerminalSession, alias: String?) {
        sessionManager.setSessionAlias(session.id, alias: alias)
    }

    func move(from source: IndexSet, to destination: Int) {
        // Reordering sessions - would need to implement in SessionManager
        // For now, this is a placeholder
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            sessionManager.closeSession(session.id)
        }
    }
}
