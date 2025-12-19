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

        // Sync content changes to NoteManager with debounced save
        $content
            .dropFirst() // Skip initial value
            .removeDuplicates()
            .sink { [weak self] newContent in
                self?.noteManager.updateContent(newContent)
            }
            .store(in: &cancellables)

        // Listen for external note changes
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
}
