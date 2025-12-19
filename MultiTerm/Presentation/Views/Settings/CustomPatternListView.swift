import SwiftUI

struct CustomPatternListView: View {
    let patterns: [CustomPattern]
    let onEdit: (CustomPattern) -> Void
    let onDelete: (CustomPattern) -> Void
    let onToggleEnabled: (CustomPattern) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(patterns) { pattern in
                CustomPatternRowView(
                    pattern: pattern,
                    onEdit: { onEdit(pattern) },
                    onDelete: { onDelete(pattern) },
                    onToggleEnabled: { onToggleEnabled(pattern) }
                )
            }
        }
    }
}

struct CustomPatternRowView: View {
    let pattern: CustomPattern
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleEnabled: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { pattern.isEnabled },
                set: { _ in onToggleEnabled() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pattern.name)
                        .fontWeight(.medium)
                        .foregroundColor(pattern.isEnabled ? .primary : .secondary)

                    if pattern.autoPin {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                HStack(spacing: 4) {
                    Text(pattern.matchMode.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)

                    Text(pattern.pattern)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isHovered {
                HStack(spacing: 8) {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Edit pattern")

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete pattern")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }
}

#Preview {
    VStack {
        CustomPatternListView(
            patterns: [
                CustomPattern(name: "Build Success", pattern: "Build succeeded", matchMode: .keyword, autoPin: false),
                CustomPattern(name: "Test Failed", pattern: "FAILED", matchMode: .keyword, autoPin: true),
                CustomPattern(name: "Deploy Complete", pattern: "deployed.*successfully", matchMode: .regex),
            ],
            onEdit: { _ in },
            onDelete: { _ in },
            onToggleEnabled: { _ in }
        )
        .padding()
    }
    .frame(width: 450)
}
