import SwiftUI

struct NotesDivider: View {
    @Binding var height: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat

    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 4)
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
                        let newHeight = height + value.translation.height
                        height = min(max(newHeight, minHeight), maxHeight)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
