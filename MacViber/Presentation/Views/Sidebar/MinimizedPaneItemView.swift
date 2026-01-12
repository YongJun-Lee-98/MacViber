import SwiftUI

struct MinimizedPaneItemView: View {
    let minimizedPane: MinimizedPane
    let session: TerminalSession?
    let onRestore: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Minimized icon
            Image(systemName: "rectangle.compress.vertical")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                // Session name
                Text(session?.displayName ?? "Unknown")
                    .font(.headline)
                    .lineLimit(1)

                // Working directory
                if let session = session {
                    Text(session.workingDirectory.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Action buttons (show on hover)
            if isHovered {
                HStack(spacing: 4) {
                    // Restore button
                    Button(action: onRestore) {
                        Image(systemName: "rectangle.expand.vertical")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Restore Pane")

                    // Close button
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close Permanently")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            onRestore()
        }
    }
}

#Preview {
    let pane = MinimizedPane(
        paneId: UUID(),
        sessionId: UUID()
    )

    return MinimizedPaneItemView(
        minimizedPane: pane,
        session: nil,
        onRestore: {},
        onClose: {}
    )
    .frame(width: 250)
    .padding()
}
