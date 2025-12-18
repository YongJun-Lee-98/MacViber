import SwiftUI

struct NotificationCardView: View {
    let notification: ClaudeNotification
    let sessionName: String
    let onRespond: (String) -> Void
    let onDismiss: () -> Void
    let onNavigate: () -> Void

    @State private var isHovered = false
    @State private var customResponse = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            header

            Divider()

            // Message
            messageSection

            // Context
            if !notification.context.isEmpty {
                contextSection
            }

            Spacer(minLength: 0)

            // Actions
            actionsSection
        }
        .padding()
        .background(cardBackground)
        .overlay(cardBorder)
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { onNavigate() }
    }

    private var header: some View {
        HStack {
            Image(systemName: notification.type.iconName)
                .foregroundColor(notification.type.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.type.displayName)
                    .font(.headline)

                Text(sessionName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(notification.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !notification.isRead {
                    Circle()
                        .fill(notification.type.color)
                        .frame(width: 8, height: 8)
                }
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var messageSection: some View {
        Text(notification.message)
            .font(.body)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contextSection: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(notification.context)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 80)
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }

    private var actionsSection: some View {
        HStack(spacing: 8) {
            if notification.type == .permissionRequest {
                Button("Allow") {
                    onRespond("y")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button("Deny") {
                    onRespond("n")
                }
                .buttonStyle(.bordered)
            } else if notification.type == .question {
                TextField("Response...", text: $customResponse)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !customResponse.isEmpty {
                            onRespond(customResponse)
                            customResponse = ""
                        }
                    }

                Button("Send") {
                    if !customResponse.isEmpty {
                        onRespond(customResponse)
                        customResponse = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(customResponse.isEmpty)
            }

            Spacer()

            Button {
                onNavigate()
            } label: {
                Label("View Terminal", systemImage: "terminal")
            }
            .buttonStyle(.borderless)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(nsColor: .controlBackgroundColor))
            .shadow(
                color: .black.opacity(isHovered ? 0.15 : 0.08),
                radius: isHovered ? 8 : 4,
                y: isHovered ? 4 : 2
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                notification.isRead ? Color.secondary.opacity(0.2) : notification.type.color.opacity(0.5),
                lineWidth: isHovered ? 2 : 1
            )
    }
}

#Preview {
    VStack(spacing: 20) {
        NotificationCardView(
            notification: ClaudeNotification(
                sessionId: UUID(),
                type: .permissionRequest,
                message: "Allow Claude to modify /Users/dev/project/main.swift?",
                context: "func main() {\n    print(\"Hello\")\n}"
            ),
            sessionName: "MyProject",
            onRespond: { _ in },
            onDismiss: {},
            onNavigate: {}
        )

        NotificationCardView(
            notification: ClaudeNotification(
                sessionId: UUID(),
                type: .question,
                message: "Which database would you like to use?",
                context: "Options: PostgreSQL, MySQL, SQLite"
            ),
            sessionName: "Backend",
            onRespond: { _ in },
            onDismiss: {},
            onNavigate: {}
        )
    }
    .padding()
    .frame(width: 400, height: 500)
}
