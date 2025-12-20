import SwiftUI

struct MarkdownEditorView: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor))
            .padding(8)
    }
}

#Preview {
    MarkdownEditorView(text: .constant("# Hello World\n\nThis is a **markdown** preview."))
        .frame(width: 300, height: 400)
}
