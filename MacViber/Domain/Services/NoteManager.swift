import Foundation
import Combine

class NoteManager: ObservableObject {
    static let shared = NoteManager()

    @Published var note: Note

    private let fileURL: URL

    private init() {
        // ~/Library/Application Support/MacViber/note.md
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let multiTermDir = appSupport.appendingPathComponent("MacViber")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: multiTermDir, withIntermediateDirectories: true)

        self.fileURL = multiTermDir.appendingPathComponent("note.md")
        self.note = Note()

        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            note = Note(content: content, lastModified: Date())
        } catch {
            Logger.shared.error("Failed to load note: \(error)")
        }
    }

    func save() {
        do {
            try note.content.write(to: fileURL, atomically: true, encoding: .utf8)
            note.lastModified = Date()
        } catch {
            Logger.shared.error("Failed to save note: \(error)")
        }
    }
}
