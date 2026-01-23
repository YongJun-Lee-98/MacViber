import Foundation
import Combine

class NoteViewModel: ObservableObject {
    enum Tab: String, CaseIterable {
        case edit = "Edit"
        case preview = "Preview"
    }

    @Published var selectedTab: Tab = .edit
    @Published var content: String = ""
    @Published var searchText: String = ""

    private let noteManager: NoteManager
    private var cancellables = Set<AnyCancellable>()
    private var currentNoteId: UUID?

    // Computed properties from manager
    var notes: [Note] {
        noteManager.notes
    }

    var filteredNotes: [Note] {
        if searchText.isEmpty {
            return notes
        }
        return notes.filter { note in
            note.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            note.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    var selectedNoteId: UUID? {
        get { noteManager.selectedNoteId }
        set { noteManager.selectedNoteId = newValue }
    }

    var selectedNote: Note? {
        noteManager.selectedNote
    }

    var hasNotes: Bool {
        !notes.isEmpty
    }

    init(noteManager: NoteManager = .shared) {
        self.noteManager = noteManager

        // Observe selection changes
        noteManager.$selectedNoteId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newId in
                self?.onNoteSelectionChanged(newId)
            }
            .store(in: &cancellables)

        // Observe notes array changes
        noteManager.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Initialize with current selection
        if let noteId = noteManager.selectedNoteId,
           let note = noteManager.note(for: noteId) {
            self.currentNoteId = noteId
            self.content = note.content
        }
    }

    private func onNoteSelectionChanged(_ newId: UUID?) {
        // Save current note before switching
        saveCurrentNote()

        // Load new note
        if let noteId = newId, let note = noteManager.note(for: noteId) {
            currentNoteId = noteId
            content = note.content
        } else {
            currentNoteId = nil
            content = ""
        }
    }

    // MARK: - Note Operations

    func createNote() {
        // Save current note first
        saveCurrentNote()

        let note = noteManager.createNote()
        content = note.content
        currentNoteId = note.id
    }

    func selectNote(_ id: UUID) {
        noteManager.selectNote(id)
    }

    func deleteNote(_ id: UUID) {
        noteManager.deleteNote(id)
    }

    func saveNote() {
        saveCurrentNote()
    }

    private func saveCurrentNote() {
        guard let noteId = currentNoteId else { return }
        noteManager.updateNote(noteId, content: content)
    }

    /// Called when content changes in editor
    func contentDidChange(_ newContent: String) {
        content = newContent
    }
}
