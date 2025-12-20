import SwiftUI

struct RightSidebarView: View {
    @StateObject private var viewModel = NoteViewModel()
    @State private var showSavedMessage = false

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

            // Save button footer
            Divider()
            HStack {
                // Saved message
                if showSavedMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                    .transition(.opacity)
                }

                Spacer()

                Button(action: {
                    viewModel.saveNote()
                    withAnimation {
                        showSavedMessage = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showSavedMessage = false
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    RightSidebarView()
        .frame(height: 500)
}
