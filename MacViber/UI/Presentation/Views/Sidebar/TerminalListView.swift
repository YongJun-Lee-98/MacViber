import SwiftUI

struct TerminalListView: View {
    @ObservedObject var viewModel: TerminalListViewModel
    @State private var editingSessionId: UUID?
    @State private var editingName: String = ""
    @State private var aliasSessionId: UUID?
    @State private var editingAlias: String = ""

    var onOpenFavorite: ((URL) -> Void)?
    var onAddFavorite: (() -> Void)?
    var onSelectSession: ((UUID) -> Void)?

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedSessionId },
            set: { newValue in
                if let sessionId = newValue {
                    onSelectSession?(sessionId)
                }
                viewModel.selectedSessionId = newValue
            }
        )) {
            // Favorites Section
            FavoritesView(
                onOpenTerminal: { url in
                    onOpenFavorite?(url)
                },
                onAddFavorite: {
                    onAddFavorite?()
                }
            )

            Section("Terminals") {
                ForEach(viewModel.sessions) { session in
                    TerminalListItemView(
                        session: session,
                        isEditing: editingSessionId == session.id,
                        isEditingAlias: aliasSessionId == session.id,
                        editingName: $editingName,
                        editingAlias: $editingAlias,
                        onRename: {
                            viewModel.renameSession(session, newName: editingName)
                            editingSessionId = nil
                        },
                        onSetAlias: {
                            viewModel.setAlias(session, alias: editingAlias)
                            aliasSessionId = nil
                        },
                        onToggleLock: {
                            viewModel.toggleLock(session)
                        },
                        onClose: {
                            viewModel.closeSession(session)
                        }
                    )
                    .tag(session.id)
                    .contextMenu {
                        contextMenu(for: session)
                    }
                }
            }

            // Minimized Panes Section
            if viewModel.hasMinimizedPanes {
                Section("Minimized") {
                    ForEach(viewModel.minimizedPanes) { pane in
                        MinimizedPaneItemView(
                            minimizedPane: pane,
                            session: viewModel.session(for: pane),
                            onRestore: {
                                viewModel.restoreMinimizedPane(pane.id)
                            },
                            onClose: {
                                viewModel.closeMinimizedPane(pane.id)
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    @ViewBuilder
    private func contextMenu(for session: TerminalSession) -> some View {
        Button {
            editingAlias = session.alias ?? ""
            aliasSessionId = session.id
        } label: {
            Label("Set Alias", systemImage: "tag")
        }

        if session.alias != nil {
            Button {
                viewModel.setAlias(session, alias: nil)
            } label: {
                Label("Remove Alias", systemImage: "tag.slash")
            }
        }

        Divider()

        Button {
            editingName = session.name
            editingSessionId = session.id
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            viewModel.duplicateSession(session)
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Divider()

        Button {
            viewModel.toggleLock(session)
        } label: {
            Label(session.isLocked ? "Unlock" : "Lock", systemImage: session.isLocked ? "lock.open" : "lock")
        }

        Divider()

        Button(role: .destructive) {
            viewModel.closeSession(session)
        } label: {
            Label("Close", systemImage: "xmark.circle")
        }
        .disabled(session.isLocked)
    }
}

struct TerminalListItemView: View {
    let session: TerminalSession
    let isEditing: Bool
    let isEditingAlias: Bool
    @Binding var editingName: String
    @Binding var editingAlias: String
    let onRename: () -> Void
    let onSetAlias: () -> Void
    let onToggleLock: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                // Main name (alias or name)
                if isEditing {
                    TextField("Name", text: $editingName, onCommit: onRename)
                        .textFieldStyle(.plain)
                        .font(.headline)
                } else if isEditingAlias {
                    TextField("Alias", text: $editingAlias, onCommit: onSetAlias)
                        .textFieldStyle(.plain)
                        .font(.headline)
                } else {
                    HStack(spacing: 4) {
                        Text(session.displayName)
                            .font(.headline)
                            .lineLimit(1)

                        // Show tag icon if has alias
                        if session.alias != nil {
                            Image(systemName: "tag.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Working directory path
                Text(session.workingDirectory.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Notification badge
            if session.hasUnreadNotification {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            // Status text
            if session.status == .waitingForInput {
                Text("Waiting")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(4)
            }

            // Action buttons (show on hover or when locked)
            if isHovered || session.isLocked {
                HStack(spacing: 4) {
                    // Lock button
                    Button(action: onToggleLock) {
                        Image(systemName: session.isLocked ? "lock.fill" : "lock.open")
                            .font(.caption)
                            .foregroundColor(session.isLocked ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(session.isLocked ? "Unlock terminal" : "Lock terminal")

                    // Delete button
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(session.isLocked ? .secondary.opacity(0.3) : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isLocked)
                    .help(session.isLocked ? "Unlock to close" : "Close terminal")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var statusColor: Color {
        switch session.status {
        case .idle: return .gray
        case .running: return .green
        case .waitingForInput: return .orange
        case .terminated: return .red
        }
    }
}

#Preview {
    TerminalListView(viewModel: TerminalListViewModel())
        .frame(width: 250)
}
