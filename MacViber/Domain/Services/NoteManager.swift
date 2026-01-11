import Foundation
import Combine

class NoteManager: ObservableObject {
    static let shared = NoteManager()

    @Published private(set) var notes: [Note] = []
    @Published var selectedNoteId: UUID?

    private let notesDirectoryURL: URL
    private let legacyNoteURL: URL  // For migration

    // Computed property for currently selected note
    var selectedNote: Note? {
        guard let id = selectedNoteId else { return nil }
        return notes.first { $0.id == id }
    }

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let macViberDir = appSupport.appendingPathComponent("MacViber")

        self.notesDirectoryURL = macViberDir.appendingPathComponent("notes")
        self.legacyNoteURL = macViberDir.appendingPathComponent("note.md")

        // Create notes directory if needed
        try? FileManager.default.createDirectory(
            at: notesDirectoryURL,
            withIntermediateDirectories: true
        )

        // Migrate legacy note if exists
        migrateFromLegacyNote()

        // Load all notes
        loadAll()

        // Auto-select first note if none selected
        if selectedNoteId == nil && !notes.isEmpty {
            selectedNoteId = notes.first?.id
        }
    }

    // MARK: - Migration

    private func migrateFromLegacyNote() {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: legacyNoteURL.path) else {
            return
        }

        do {
            let content = try String(contentsOf: legacyNoteURL, encoding: .utf8)

            // Only migrate if there's actual content
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                // Remove empty legacy file
                try? fileManager.removeItem(at: legacyNoteURL)
                return
            }

            // Create new note with legacy content
            let note = Note(content: content)
            saveNote(note)

            // Remove legacy file after successful migration
            try fileManager.removeItem(at: legacyNoteURL)

            Logger.shared.info("Migrated legacy note to new format")
        } catch {
            Logger.shared.error("Failed to migrate legacy note: \(error)")
        }
    }

    // MARK: - CRUD Operations

    func loadAll() {
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(
            at: notesDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            notes = []
            return
        }

        var loadedNotes: [Note] = []

        for fileURL in contents where fileURL.pathExtension == "md" {
            if let note = loadNote(from: fileURL) {
                loadedNotes.append(note)
            }
        }

        // Sort by lastModified (most recent first)
        notes = loadedNotes.sorted { $0.lastModified > $1.lastModified }
    }

    private func loadNote(from fileURL: URL) -> Note? {
        // Extract UUID from filename
        let filename = fileURL.deletingPathExtension().lastPathComponent
        guard let uuid = UUID(uuidString: filename) else {
            Logger.shared.warning("Invalid note filename: \(filename)")
            return nil
        }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let modificationDate = attributes[.modificationDate] as? Date ?? Date()
            let creationDate = attributes[.creationDate] as? Date ?? Date()

            return Note(
                id: uuid,
                title: "",  // Will use displayTitle computed property
                content: content,
                createdAt: creationDate,
                lastModified: modificationDate
            )
        } catch {
            Logger.shared.error("Failed to load note \(filename): \(error)")
            return nil
        }
    }

    @discardableResult
    func createNote(title: String = "", content: String = "") -> Note {
        let note = Note(
            title: title,
            content: content,
            createdAt: Date(),
            lastModified: Date()
        )

        saveNote(note)
        notes.insert(note, at: 0)  // Add to beginning (most recent)
        selectedNoteId = note.id

        Logger.shared.info("Created new note: \(note.id)")
        return note
    }

    private func saveNote(_ note: Note) {
        let fileURL = notesDirectoryURL.appendingPathComponent(note.filename)

        do {
            try note.content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            Logger.shared.error("Failed to save note \(note.id): \(error)")
        }
    }

    func save(_ note: Note) {
        saveNote(note)

        // Update in-memory array
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            var updatedNote = note
            updatedNote.lastModified = Date()
            notes[index] = updatedNote
        }

        Logger.shared.info("Saved note: \(note.id)")
    }

    func updateNote(_ id: UUID, content: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }

        var note = notes[index]
        note.content = content
        note.lastModified = Date()

        save(note)
    }

    func updateNoteTitle(_ id: UUID, title: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }

        notes[index].title = title
        notes[index].lastModified = Date()
        save(notes[index])
    }

    func deleteNote(_ id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }

        let fileURL = notesDirectoryURL.appendingPathComponent(note.filename)

        do {
            try FileManager.default.removeItem(at: fileURL)
            notes.removeAll { $0.id == id }

            // Select another note if current was deleted
            if selectedNoteId == id {
                selectedNoteId = notes.first?.id
            }

            Logger.shared.info("Deleted note: \(id)")
        } catch {
            Logger.shared.error("Failed to delete note \(id): \(error)")
        }
    }

    func selectNote(_ id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        selectedNoteId = id
    }

    func note(for id: UUID) -> Note? {
        notes.first { $0.id == id }
    }
}
