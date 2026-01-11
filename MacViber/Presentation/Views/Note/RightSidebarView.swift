import SwiftUI

struct RightSidebarView: View {
    @StateObject private var viewModel = NoteViewModel()
    @State private var showSavedMessage = false
    @State private var noteListHeight: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            // Notes list section
            NotesListView(
                notes: viewModel.filteredNotes,
                selectedNoteId: viewModel.selectedNoteId,
                searchText: $viewModel.searchText,
                onSelectNote: { viewModel.selectNote($0) },
                onCreateNote: { viewModel.createNote() },
                onDeleteNote: { viewModel.deleteNote($0) }
            )
            .frame(height: noteListHeight)

            // Resizable divider between list and editor
            NotesDivider(height: $noteListHeight, minHeight: 100, maxHeight: 400)

            // Editor section
            if viewModel.hasNotes {
                noteEditorSection
            } else {
                emptyStateView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var noteEditorSection: some View {
        VStack(spacing: 0) {
            // Header with tab picker
            HStack {
                if let note = viewModel.selectedNote {
                    Text(note.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer()

                Picker("Mode", selection: $viewModel.selectedTab) {
                    ForEach(NoteViewModel.Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content
            Group {
                switch viewModel.selectedTab {
                case .edit:
                    MarkdownEditorView(text: $viewModel.content)
                case .preview:
                    MarkdownPreviewView(markdown: viewModel.content)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Save button footer
            Divider()
            saveFooter
        }
    }

    private var saveFooter: some View {
        HStack {
            if showSavedMessage {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Saved")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                .transition(.opacity)
            }

            Spacer()

            Button(action: {
                viewModel.saveNote()
                withAnimation {
                    showSavedMessage = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showSavedMessage = false
                    }
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Notes")
                .font(.title3)
                .foregroundColor(.secondary)

            Button(action: viewModel.createNote) {
                Label("Create Note", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RightSidebarView()
        .frame(height: 500)
}
