import SwiftUI

struct ThemePickerView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Terminal Theme")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Theme Grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(TerminalTheme.allThemes) { theme in
                        ThemePreviewCard(
                            theme: theme,
                            isSelected: theme.id == themeManager.currentTheme.id
                        ) {
                            themeManager.selectTheme(theme)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 400)
    }
}

struct ThemePreviewCard: View {
    let theme: TerminalTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                // Terminal Preview
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(theme.backgroundNSColor))

                    VStack(alignment: .leading, spacing: 4) {
                        // Sample terminal output
                        HStack(spacing: 4) {
                            Text("$")
                                .foregroundColor(Color(theme.ansiColors[2].nsColor))
                            Text("ls -la")
                                .foregroundColor(Color(theme.foregroundNSColor))
                        }
                        HStack(spacing: 8) {
                            Text("file.txt")
                                .foregroundColor(Color(theme.foregroundNSColor))
                            Text("folder/")
                                .foregroundColor(Color(theme.ansiColors[4].nsColor))
                        }
                        HStack(spacing: 4) {
                            Text("error:")
                                .foregroundColor(Color(theme.ansiColors[1].nsColor))
                            Text("not found")
                                .foregroundColor(Color(theme.foregroundNSColor))
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .padding(8)
                }
                .frame(height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )

                // Theme Name
                Text(theme.name)
                    .font(.caption)
                    .foregroundColor(isSelected ? .accentColor : .primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Submenu for Menu Bar
struct ThemeMenuContent: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        ForEach(TerminalTheme.allThemes) { theme in
            Button {
                themeManager.selectTheme(theme)
            } label: {
                HStack {
                    if theme.id == themeManager.currentTheme.id {
                        Image(systemName: "checkmark")
                    }
                    Text(theme.name)
                }
            }
        }
    }
}
