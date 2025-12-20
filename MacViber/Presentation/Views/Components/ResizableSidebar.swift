import SwiftUI

struct ResizableSidebar<Content: View>: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let content: () -> Content

    @State private var isDragging = false

    init(
        width: Binding<CGFloat>,
        minWidth: CGFloat = 150,
        maxWidth: CGFloat = 600,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._width = width
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.content = content
    }

    var body: some View {
        HStack(spacing: 0) {
            // Drag handle (left edge)
            Rectangle()
                .fill(isDragging ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.01))
                .frame(width: 6)
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
                            let newWidth = width - delta
                            width = min(max(newWidth, minWidth), maxWidth)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )

            Divider()

            // Content
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width)
    }
}
