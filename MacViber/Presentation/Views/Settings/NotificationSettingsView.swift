import SwiftUI

struct NotificationSettingsView: View {
    @StateObject private var viewModel = NotificationSettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    typeFilterSection
                    autoPinSection
                    systemNotificationSection
                    customPatternSection
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
        .sheet(isPresented: $viewModel.showPatternEditor) {
            if let pattern = viewModel.editingPattern {
                CustomPatternEditorView(
                    pattern: pattern,
                    onSave: { viewModel.savePattern($0) },
                    onCancel: { viewModel.showPatternEditor = false }
                )
            }
        }
    }

    private var headerView: some View {
        HStack {
            Text("Notification Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.return)
        }
        .padding()
    }

    private var typeFilterSection: some View {
        GroupBox("Notification Types") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(NotificationType.filterableCases, id: \.self) { type in
                    Toggle(isOn: Binding(
                        get: { viewModel.isTypeEnabled(type) },
                        set: { viewModel.setTypeEnabled(type, enabled: $0) }
                    )) {
                        HStack {
                            Image(systemName: type.iconName)
                                .foregroundColor(type.color)
                                .frame(width: 20)

                            Text(type.displayName)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var autoPinSection: some View {
        GroupBox("Auto-Pin") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Automatically pin notifications of these types:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(NotificationType.filterableCases, id: \.self) { type in
                    Toggle(isOn: Binding(
                        get: { viewModel.shouldAutoPin(type) },
                        set: { viewModel.setAutoPin(type, enabled: $0) }
                    )) {
                        HStack {
                            Image(systemName: type.iconName)
                                .foregroundColor(type.color)
                                .frame(width: 20)

                            Text(type.displayName)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var systemNotificationSection: some View {
        GroupBox("System Notifications") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $viewModel.systemNotificationsEnabled) {
                    HStack {
                        Image(systemName: "bell.badge")
                            .frame(width: 20)

                        VStack(alignment: .leading) {
                            Text("macOS Notification Center")
                            Text("Show notifications in macOS Notification Center")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Toggle(isOn: $viewModel.dockBadgeEnabled) {
                    HStack {
                        Image(systemName: "app.badge")
                            .frame(width: 20)

                        VStack(alignment: .leading) {
                            Text("Dock Badge")
                            Text("Show unread count on Dock icon")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var customPatternSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Custom Patterns")
                        .font(.headline)

                    Spacer()

                    Button {
                        viewModel.addNewPattern()
                    } label: {
                        Label("Add Pattern", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }

                Text("Create custom patterns to trigger notifications when specific text appears in terminal output.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if viewModel.customPatterns.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "star")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No custom patterns")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                } else {
                    CustomPatternListView(
                        patterns: viewModel.customPatterns,
                        onEdit: { viewModel.editPattern($0) },
                        onDelete: { viewModel.deletePattern($0) },
                        onToggleEnabled: { viewModel.togglePatternEnabled($0) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    NotificationSettingsView()
}
