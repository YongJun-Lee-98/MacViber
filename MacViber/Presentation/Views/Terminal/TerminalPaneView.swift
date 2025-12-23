import SwiftUI

struct TerminalPaneView: View {
    let paneId: UUID
    let sessionId: UUID
    let isFocused: Bool
    let onFocus: () -> Void
    let onSplitHorizontal: (CGSize) -> Void
    let onSplitVertical: (CGSize) -> Void
    let onClose: () -> Void

    @EnvironmentObject var sessionManager: SessionManager
    @State private var isHovered = false

    private var session: TerminalSession? {
        sessionManager.session(for: sessionId)
    }

    private var controller: TerminalController? {
        sessionManager.controller(for: sessionId)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Pane header
                paneHeader(geometry: geometry)

                Divider()

                // Terminal content
                if let session = session, let controller = controller {
                    TerminalView(controller: controller, workingDirectory: session.workingDirectory, isFocused: isFocused)
                        .id(sessionId)
                        .contentShape(Rectangle())
                        .onTapGesture { onFocus() }
                        .onChange(of: isFocused) { oldValue, newValue in
                            Logger.shared.debug("[FOCUS] TerminalPaneView.onChange - paneId: \(paneId), old: \(oldValue), new: \(newValue)")
                            if newValue && !oldValue {
                                // 포커스 획득 시 키보드 포커스도 설정
                                Logger.shared.debug("[FOCUS] → calling controller.requestFocus()")
                                controller.requestFocus()
                            }
                        }
                } else {
                    Text("Terminal not found")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(
                Rectangle()
                    .stroke(isFocused ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .onHover { isHovered = $0 }
        }
    }

    private func paneHeader(geometry: GeometryProxy) -> some View {
        HStack(spacing: 8) {
            // Status indicator
            if let session = session {
                Circle()
                    .fill(statusColor(for: session.status))
                    .frame(width: 8, height: 8)

                Text(session.displayName)
                    .font(.caption)
                    .fontWeight(isFocused ? .semibold : .regular)
                    .lineLimit(1)

                if session.alias != nil {
                    Image(systemName: "tag.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Pane controls (show on hover or when focused)
            if isHovered || isFocused {
                paneControls(geometry: geometry)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isFocused ? Color.blue.opacity(0.08) : Color(nsColor: .windowBackgroundColor))
    }

    private func paneControls(geometry: GeometryProxy) -> some View {
        HStack(spacing: 4) {
            // Split horizontal button
            Button(action: {
                onSplitHorizontal(geometry.size)
            }) {
                Image(systemName: "rectangle.split.2x1")
            }
            .buttonStyle(.plain)
            .help("Split Horizontal (Cmd+D)")

            // Split vertical button
            Button(action: {
                onSplitVertical(geometry.size)
            }) {
                Image(systemName: "rectangle.split.1x2")
            }
            .buttonStyle(.plain)
            .help("Split Vertical (Cmd+Shift+D)")

            // Close pane button
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close Pane")
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private func statusColor(for status: SessionStatus) -> Color {
        switch status {
        case .idle: return .gray
        case .running: return .green
        case .waitingForInput: return .orange
        case .terminated: return .red
        }
    }
}

