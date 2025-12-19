import SwiftUI

struct RightSidebarView: View {
    @StateObject private var viewModel = NoteViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header with tab picker
            HStack {
                Text("Notes")
                    .font(.headline)

                Spacer()

                Picker("Mode", selection: $viewModel.selectedTab) {
                    ForEach(NoteViewModel.Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content
            Group {
                switch viewModel.selectedTab {
                case .edit:
                    MarkdownEditorView(text: $viewModel.content)
                case .preview:
                    MarkdownPreviewView(markdown: viewModel.content)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 200, idealWidth: 300, maxWidth: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    RightSidebarView()
        .frame(height: 500)
}
