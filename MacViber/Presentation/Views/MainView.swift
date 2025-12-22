import SwiftUI

struct MainView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var viewModel = MainViewModel()
    @StateObject private var terminalListViewModel = TerminalListViewModel()
    @State private var sidebarWidth: CGFloat = 200

    var body: some View {
        NavigationSplitView(columnVisibility: $viewModel.columnVisibility) {
            // Sidebar: Terminal List
            TerminalListView(
                viewModel: terminalListViewModel,
                onOpenFavorite: { url in
                    viewModel.addNewTerminal(at: url)
                },
                onAddFavorite: {
                    viewModel.addFavoriteFolder()
                },
                onSelectSession: { sessionId in
                    viewModel.handleTerminalSelection(sessionId)
                }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            // Main Area: Notification Grid or Terminal View + Right Sidebar
            HStack(spacing: 0) {
                detailContent

                if viewModel.showRightSidebar {
                    ResizableSidebar(width: $sidebarWidth, minWidth: 150, maxWidth: 600) {
                        RightSidebarView()
                    }
                }
            }
        }
        .toolbar {
            toolbarContent
        }
        .onAppear {
            // Create initial terminal if none exists
            // Delay slightly to ensure window is fully set up (fixes focus issues)
            if sessionManager.sessions.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    viewModel.addNewTerminalAtHome()
                }
            }
        }
        .sheet(isPresented: $viewModel.showKeyboardShortcuts) {
            KeyboardShortcutsView()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if viewModel.showNotificationGrid && viewModel.hasActiveNotifications {
            NotificationGridView(viewModel: NotificationGridViewModel())
                .transition(.opacity)
        } else if let rootNode = viewModel.splitViewRoot {
            // Split view mode: show multiple terminals
            SplitTerminalView(
                node: rootNode,
                focusedPaneId: $viewModel.focusedPaneId,
                onSplitPane: { paneId, direction, size in
                    viewModel.splitPane(paneId, direction: direction, currentSize: size)
                },
                onRemovePane: { paneId in
                    viewModel.removePane(paneId)
                }
            )
        } else if let session = viewModel.selectedSession {
            TerminalContainerView(session: session, viewModel: viewModel)
                .id(session.id)  // Force view recreation when session changes
        } else {
            EmptyStateView(onAddTerminal: viewModel.addNewTerminal)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: viewModel.addNewTerminal) {
                Image(systemName: "plus")
            }
            .help("New Terminal (Cmd+T)")

            // Split view controls
            if viewModel.isSplitViewActive {
                Menu {
                    Button(action: { viewModel.splitCurrentPane(.horizontal) }) {
                        Label("Split Horizontal", systemImage: "rectangle.split.2x1")
                    }

                    Button(action: { viewModel.splitCurrentPane(.vertical) }) {
                        Label("Split Vertical", systemImage: "rectangle.split.1x2")
                    }

                    Divider()

                    Button(action: viewModel.closeCurrentPane) {
                        Label("Close Current Pane", systemImage: "xmark.square")
                    }

                    Button(action: viewModel.exitSplitView) {
                        Label("Exit Split View", systemImage: "rectangle")
                    }
                } label: {
                    Image(systemName: "rectangle.split.3x3")
                }
                .help("Split View Options")
            } else {
                Button(action: viewModel.enterSplitView) {
                    Image(systemName: "rectangle.split.2x1")
                }
                .help("Enter Split View (Cmd+D)")
                .disabled(viewModel.selectedSession == nil)
            }

            if viewModel.hasActiveNotifications {
                Button(action: viewModel.toggleNotificationGrid) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: viewModel.showNotificationGrid ? "bell.fill" : "bell")

                        if viewModel.unreadNotificationCount > 0 {
                            Text("\(viewModel.unreadNotificationCount)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                .help("Toggle Notifications")
            }

            // Notes sidebar button
            Button(action: viewModel.toggleRightSidebar) {
                Image(systemName: viewModel.showRightSidebar ? "note.text" : "note.text.badge.plus")
            }
            .help("Toggle Notes (Shift+Cmd+M)")

            // Help button
            Button(action: { viewModel.showKeyboardShortcuts = true }) {
                Image(systemName: "questionmark.circle")
            }
            .help("Keyboard Shortcuts (Cmd+/)")
        }
    }
}

struct TerminalContainerView: View {
    let session: TerminalSession
    let viewModel: MainViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Terminal header
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(session.name)
                    .font(.headline)

                Text(session.workingDirectory.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                if session.status == .waitingForInput {
                    Label("Waiting for input", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Terminal view
            if let controller = viewModel.controller(for: session.id) {
                TerminalView(controller: controller, workingDirectory: session.workingDirectory)
            } else {
                Text("Failed to initialize terminal")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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

struct EmptyStateView: View {
    let onAddTerminal: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "terminal")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Terminal Selected")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Select a terminal from the sidebar or create a new one")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onAddTerminal) {
                Label("New Terminal", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MainView()
        .environmentObject(SessionManager.shared)
}
