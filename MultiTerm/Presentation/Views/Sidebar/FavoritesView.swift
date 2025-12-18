import SwiftUI

struct FavoritesView: View {
    @ObservedObject var favoritesManager = FavoritesManager.shared
    var onOpenTerminal: (URL) -> Void
    var onAddFavorite: () -> Void

    var body: some View {
        Section {
            if favoritesManager.favorites.isEmpty {
                Button(action: onAddFavorite) {
                    Label("Add Favorite Folder", systemImage: "plus")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            } else {
                ForEach(favoritesManager.favorites) { favorite in
                    FavoriteRowView(
                        favorite: favorite,
                        onOpen: { onOpenTerminal(favorite.url) },
                        onRemove: { favoritesManager.remove(favorite.id) }
                    )
                }
                .onMove { source, destination in
                    favoritesManager.move(from: source, to: destination)
                }

                Button(action: onAddFavorite) {
                    Label("Add Folder", systemImage: "plus")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        } header: {
            HStack {
                Text("Favorites")
                Spacer()
            }
        }
    }
}

struct FavoriteRowView: View {
    let favorite: FavoriteFolder
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 1) {
                    Text(favorite.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Text(shortenedPath(favorite.path))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isHovering {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isHovering ? Color.gray.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Open in New Terminal") {
                onOpen()
            }

            Divider()

            Button("Remove from Favorites", role: .destructive) {
                onRemove()
            }

            Divider()

            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: favorite.path)
            }
        }
    }

    private func shortenedPath(_ path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homePath) {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }
}
