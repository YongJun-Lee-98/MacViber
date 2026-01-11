import SwiftUI

struct NotesListView: View {
    let notes: [Note]
    let selectedNoteId: UUID?
    @Binding var searchText: String
    let onSelectNote: (UUID) -> Void
    let onCreateNote: () -> Void
    let onDeleteNote: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and add button
            HStack {
                Text("Notes")
                    .font(.headline)

                Spacer()

                Button(action: onCreateNote) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("New Note")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                TextField("Search notes...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Notes list
            if notes.isEmpty {
                emptyListView
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(notes) { note in
                            NoteRowView(
                                note: note,
                                isSelected: note.id == selectedNoteId,
                                onSelect: { onSelectNote(note.id) },
                                onDelete: { onDeleteNote(note.id) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyListView: some View {
        VStack(spacing: 8) {
            Text(searchText.isEmpty ? "No notes yet" : "No matching notes")
                .font(.caption)
                .foregroundColor(.secondary)

            if searchText.isEmpty {
                Button("Create First Note", action: onCreateNote)
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoteRowView: View {
    let note: Note
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: note.lastModified, relativeTo: Date())
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundColor(isSelected ? .white : .secondary)
                    .font(.system(size: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.displayTitle)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)

                    Text(formattedDate)
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }

                Spacer()

                if isHovering && !isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : (isHovering ? Color.gray.opacity(0.1) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
