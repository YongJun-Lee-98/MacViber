import SwiftUI

struct NotificationGridView: View {
    @ObservedObject var viewModel: NotificationGridViewModel

    var body: some View {
        GeometryReader { geometry in
            if viewModel.activeNotifications.isEmpty {
                emptyState
            } else {
                gridContent(in: geometry.size)
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Active Notifications")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Claude Code notifications will appear here")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func gridContent(in size: CGSize) -> some View {
        let layout = viewModel.calculateGridLayout(count: viewModel.notificationCount, size: size)

        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: layout.columns),
                spacing: 12
            ) {
                ForEach(viewModel.activeNotifications) { notification in
                    NotificationCardView(
                        notification: notification,
                        sessionName: viewModel.sessionName(for: notification),
                        onRespond: { response in
                            viewModel.respond(to: notification, with: response)
                        },
                        onDismiss: {
                            viewModel.dismiss(notification)
                        },
                        onNavigate: {
                            viewModel.navigateToSession(notification)
                        }
                    )
                    .frame(minHeight: min(layout.itemHeight, 200))
                }
            }
        }
    }
}

#Preview {
    NotificationGridView(viewModel: NotificationGridViewModel())
        .frame(width: 800, height: 600)
}
