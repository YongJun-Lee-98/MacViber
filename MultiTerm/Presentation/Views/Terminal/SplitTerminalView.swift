import SwiftUI

struct SplitTerminalView: View {
    let node: SplitNode
    @Binding var focusedPaneId: UUID?
    let onSplitPane: (UUID, SplitDirection, CGSize) -> Void
    let onRemovePane: (UUID) -> Void

    var body: some View {
        renderNode(node)
    }

    @ViewBuilder
    private func renderNode(_ node: SplitNode) -> some View {
        switch node {
        case .terminal(let paneId, let sessionId, _):
            TerminalPaneView(
                paneId: paneId,
                sessionId: sessionId,
                isFocused: focusedPaneId == paneId,
                onFocus: { focusedPaneId = paneId },
                onSplitHorizontal: { size in
                    onSplitPane(paneId, .horizontal, size)
                },
                onSplitVertical: { size in
                    onSplitPane(paneId, .vertical, size)
                },
                onClose: { onRemovePane(paneId) }
            )

        case .split(_, let direction, let first, let second, _):
            if direction == .horizontal {
                HSplitView {
                    SplitTerminalView(
                        node: first,
                        focusedPaneId: $focusedPaneId,
                        onSplitPane: onSplitPane,
                        onRemovePane: onRemovePane
                    )
                    .frame(minWidth: 150)

                    SplitTerminalView(
                        node: second,
                        focusedPaneId: $focusedPaneId,
                        onSplitPane: onSplitPane,
                        onRemovePane: onRemovePane
                    )
                    .frame(minWidth: 150)
                }
            } else {
                VSplitView {
                    SplitTerminalView(
                        node: first,
                        focusedPaneId: $focusedPaneId,
                        onSplitPane: onSplitPane,
                        onRemovePane: onRemovePane
                    )
                    .frame(minHeight: 100)

                    SplitTerminalView(
                        node: second,
                        focusedPaneId: $focusedPaneId,
                        onSplitPane: onSplitPane,
                        onRemovePane: onRemovePane
                    )
                    .frame(minHeight: 100)
                }
            }
        }
    }
}

#Preview {
    let node = SplitNode.split(
        id: UUID(),
        direction: .horizontal,
        first: .terminal(id: UUID(), sessionId: UUID(), size: PaneSize(width: 400, height: 600)),
        second: .terminal(id: UUID(), sessionId: UUID(), size: PaneSize(width: 400, height: 600)),
        ratio: 0.5
    )

    return SplitTerminalView(
        node: node,
        focusedPaneId: .constant(nil),
        onSplitPane: { _, _, _ in },
        onRemovePane: { _ in }
    )
    .environmentObject(SessionManager.shared)
    .frame(width: 800, height: 600)
}
