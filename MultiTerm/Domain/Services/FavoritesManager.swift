import Foundation
import Combine

struct FavoriteFolder: Identifiable, Codable, Equatable {
    let id: UUID
    let path: String
    var name: String

    var url: URL {
        URL(fileURLWithPath: path)
    }

    init(id: UUID = UUID(), path: String, name: String? = nil) {
        self.id = id
        self.path = path
        self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
    }

    init(url: URL) {
        self.id = UUID()
        self.path = url.path
        self.name = url.lastPathComponent
    }
}

final class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()

    @Published private(set) var favorites: [FavoriteFolder] = []

    private let userDefaultsKey = "MultiTerm.FavoriteFolders"

    private init() {
        load()
    }

    // MARK: - Public Methods

    func add(_ url: URL) {
        guard !favorites.contains(where: { $0.path == url.path }) else {
            Logger.shared.info("Folder already in favorites: \(url.path)")
            return
        }

        let favorite = FavoriteFolder(url: url)
        favorites.append(favorite)
        save()
        Logger.shared.info("Added favorite folder: \(url.path)")
    }

    func remove(_ id: UUID) {
        favorites.removeAll { $0.id == id }
        save()
        Logger.shared.info("Removed favorite folder")
    }

    func remove(at path: String) {
        favorites.removeAll { $0.path == path }
        save()
    }

    func rename(_ id: UUID, to newName: String) {
        if let index = favorites.firstIndex(where: { $0.id == id }) {
            favorites[index].name = newName
            save()
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func contains(_ url: URL) -> Bool {
        favorites.contains { $0.path == url.path }
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(favorites)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            Logger.shared.error("Failed to save favorites: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return
        }

        do {
            favorites = try JSONDecoder().decode([FavoriteFolder].self, from: data)
        } catch {
            Logger.shared.error("Failed to load favorites: \(error)")
            favorites = []
        }
    }
}
