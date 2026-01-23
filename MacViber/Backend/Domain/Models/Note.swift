import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var lastModified: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        createdAt: Date = Date(),
        lastModified: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.lastModified = lastModified
    }

    /// Auto-generate title from first line of content
    var displayTitle: String {
        if !title.isEmpty {
            return title
        }

        // Extract first line from content
        let firstLine = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces)
            // Remove markdown heading prefix
            .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression) ?? ""

        let trimmed = String(firstLine.prefix(50))
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }

    /// Filename for storage (UUID-based)
    var filename: String {
        "\(id.uuidString).md"
    }
}
