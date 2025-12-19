import Foundation

struct Note: Codable, Equatable {
    var content: String
    var lastModified: Date

    init(content: String = "", lastModified: Date = Date()) {
        self.content = content
        self.lastModified = lastModified
    }
}
