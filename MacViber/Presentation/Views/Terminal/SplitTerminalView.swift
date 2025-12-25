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

        case .split(_, let direction, let first, let second, let ratio):
            SplitContainerView(
                direction: direction,
                first: first,
                second: second,
                initialRatio: ratio,
                focusedPaneId: $focusedPaneId,
                onSplitPane: onSplitPane,
                onRemovePane: onRemovePane
            )
        }
    }
}

// MARK: - Split Container View

struct SplitContainerView: View {
    let direction: SplitDirection
    let first: SplitNode
    let second: SplitNode
    let initialRatio: CGFloat
    @Binding var focusedPaneId: UUID?
    let onSplitPane: (UUID, SplitDirection, CGSize) -> Void
    let onRemovePane: (UUID) -> Void

    @State private var ratio: CGFloat
    @State private var isDragging = false

    private let dividerWidth: CGFloat = 16
    private let visualDividerWidth: CGFloat = 4
    private let minRatio: CGFloat = 0.15
    private let maxRatio: CGFloat = 0.85

    init(
        direction: SplitDirection,
        first: SplitNode,
        second: SplitNode,
        initialRatio: CGFloat,
        focusedPaneId: Binding<UUID?>,
        onSplitPane: @escaping (UUID, SplitDirection, CGSize) -> Void,
        onRemovePane: @escaping (UUID) -> Void
    ) {
        self.direction = direction
        self.first = first
        self.second = second
        self.initialRatio = initialRatio
        self._focusedPaneId = focusedPaneId
        self.onSplitPane = onSplitPane
        self.onRemovePane = onRemovePane
        self._ratio = State(initialValue: initialRatio)
    }

    var body: some View {
        GeometryReader { geometry in
            if direction == .horizontal {
                horizontalSplit(geometry: geometry)
            } else {
                verticalSplit(geometry: geometry)
            }
        }
    }

    @ViewBuilder
    private func horizontalSplit(geometry: GeometryProxy) -> some View {
        let availableWidth = geometry.size.width - dividerWidth
        let firstWidth = availableWidth * ratio
        let secondWidth = availableWidth * (1 - ratio)

        HStack(spacing: 0) {
            SplitTerminalView(
                node: first,
                focusedPaneId: $focusedPaneId,
                onSplitPane: onSplitPane,
                onRemovePane: onRemovePane
            )
            .frame(width: firstWidth)

            // Draggable divider with expanded hit area
            Rectangle()
                .fill(Color.clear)
                .frame(width: dividerWidth)
                .overlay(
                    Rectangle()
                        .fill(isDragging ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.3))
                        .frame(width: visualDividerWidth)
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            let delta = value.translation.width
                            let newRatio = (firstWidth + delta) / availableWidth
                            ratio = min(max(newRatio, minRatio), maxRatio)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )

            SplitTerminalView(
                node: second,
                focusedPaneId: $focusedPaneId,
                onSplitPane: onSplitPane,
                onRemovePane: onRemovePane
            )
            .frame(width: secondWidth)
        }
    }

    @ViewBuilder
    private func verticalSplit(geometry: GeometryProxy) -> some View {
        let availableHeight = geometry.size.height - dividerWidth
        let firstHeight = availableHeight * ratio
        let secondHeight = availableHeight * (1 - ratio)

        VStack(spacing: 0) {
            SplitTerminalView(
                node: first,
                focusedPaneId: $focusedPaneId,
                onSplitPane: onSplitPane,
                onRemovePane: onRemovePane
            )
            .frame(height: firstHeight)

            // Draggable divider with expanded hit area
            Rectangle()
                .fill(Color.clear)
                .frame(height: dividerWidth)
                .overlay(
                    Rectangle()
                        .fill(isDragging ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.3))
                        .frame(height: visualDividerWidth)
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            let delta = value.translation.height
                            let newRatio = (firstHeight + delta) / availableHeight
                            ratio = min(max(newRatio, minRatio), maxRatio)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )

            SplitTerminalView(
                node: second,
                focusedPaneId: $focusedPaneId,
                onSplitPane: onSplitPane,
                onRemovePane: onRemovePane
            )
            .frame(height: secondHeight)
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
