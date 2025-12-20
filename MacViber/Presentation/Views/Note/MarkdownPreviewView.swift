import SwiftUI
import MarkdownUI

struct MarkdownPreviewView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            Markdown(markdown)
                .markdownBulletedListMarker(
                    BlockStyle { _ in
                        Text("•")
                            .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
                    }
                )
                .markdownBlockStyle(\.taskListMarker) { configuration in
                    if configuration.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
                    } else {
                        Text("•")
                            .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
                    }
                }
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

#Preview {
    MarkdownPreviewView(markdown: """
        # Heading 1

        ## Heading 2

        This is a paragraph with **bold** and *italic* text.

        - List item 1
        - List item 2
        - List item 3

        `inline code`

        ```
        code block
        ```
        """)
        .frame(width: 300, height: 400)
}
