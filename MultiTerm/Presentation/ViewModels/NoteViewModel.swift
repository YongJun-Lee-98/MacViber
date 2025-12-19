import Foundation
import Combine

class NoteViewModel: ObservableObject {
    enum Tab: String, CaseIterable {
        case edit = "Edit"
        case preview = "Preview"
    }

    @Published var selectedTab: Tab = .edit
    @Published var content: String

    private let noteManager: NoteManager
    private var cancellables = Set<AnyCancellable>()

    init(noteManager: NoteManager = .shared) {
        self.noteManager = noteManager
        self.content = noteManager.note.content

        // Listen for external note changes (e.g., after save or reload)
        noteManager.$note
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self = self else { return }
                if self.content != note.content {
                    self.content = note.content
                }
            }
            .store(in: &cancellables)
    }

    /// Manual save - call this when the user clicks the save button
    func saveNote() {
        noteManager.note.content = content
        noteManager.save()
    }
}
