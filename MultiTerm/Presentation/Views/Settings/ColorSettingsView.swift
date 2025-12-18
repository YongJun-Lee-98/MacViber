import SwiftUI
import AppKit

struct ColorSettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var backgroundColor: Color
    @State private var foregroundColor: Color
    @State private var commandHighlightColor: Color
    @State private var useCustomColors: Bool

    @State private var showingInstallAlert = false
    @State private var installationStatus: InstallationStatus = .notChecked

    enum InstallationStatus {
        case notChecked
        case checking
        case installed
        case notInstalled
    }

    init() {
        let settings = ThemeManager.shared.customColors
        let theme = ThemeManager.shared.currentTheme

        _useCustomColors = State(initialValue: settings.useCustomColors)
        _backgroundColor = State(initialValue: Color(settings.backgroundColor?.nsColor ?? theme.backgroundNSColor))
        _foregroundColor = State(initialValue: Color(settings.foregroundColor?.nsColor ?? theme.foregroundNSColor))
        _commandHighlightColor = State(initialValue: Color(settings.commandHighlightColor?.nsColor ?? NSColor.systemGreen))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Color Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Enable Custom Colors Toggle
                    Toggle("Use Custom Colors", isOn: $useCustomColors)
                        .onChange(of: useCustomColors) { _, newValue in
                            themeManager.setUseCustomColors(newValue)
                        }

                    if useCustomColors {
                        // Color Pickers Section
                        GroupBox("Terminal Colors") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Background")
                                        .frame(width: 120, alignment: .leading)
                                    ColorPicker("", selection: $backgroundColor, supportsOpacity: false)
                                        .labelsHidden()
                                        .onChange(of: backgroundColor) { _, newValue in
                                            themeManager.setBackgroundColor(NSColor(newValue))
                                        }
                                    Spacer()
                                    Button("Reset") {
                                        backgroundColor = Color(themeManager.currentTheme.backgroundNSColor)
                                        themeManager.setBackgroundColor(nil)
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundColor(.secondary)
                                }

                                HStack {
                                    Text("Foreground")
                                        .frame(width: 120, alignment: .leading)
                                    ColorPicker("", selection: $foregroundColor, supportsOpacity: false)
                                        .labelsHidden()
                                        .onChange(of: foregroundColor) { _, newValue in
                                            themeManager.setForegroundColor(NSColor(newValue))
                                        }
                                    Spacer()
                                    Button("Reset") {
                                        foregroundColor = Color(themeManager.currentTheme.foregroundNSColor)
                                        themeManager.setForegroundColor(nil)
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                        }

                        // Command Highlighting Section
                        GroupBox("Command Highlighting") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Highlight Color")
                                        .frame(width: 120, alignment: .leading)
                                    ColorPicker("", selection: $commandHighlightColor, supportsOpacity: false)
                                        .labelsHidden()
                                        .onChange(of: commandHighlightColor) { _, newValue in
                                            themeManager.setCommandHighlightColor(NSColor(newValue))
                                        }
                                    Spacer()
                                }

                                Divider()

                                Text("Command highlighting requires zsh-syntax-highlighting plugin.\nAfter applying color, open a new terminal tab for changes to take effect.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack {
                                    statusIndicator

                                    Spacer()

                                    Button("Check Status") {
                                        checkInstallationStatus()
                                    }
                                    .disabled(installationStatus == .checking)

                                    if installationStatus == .installed {
                                        Button("Apply Color") {
                                            applyHighlightColor()
                                        }
                                    } else {
                                        Button("Install Plugin") {
                                            showingInstallAlert = true
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }

                        // Preview Section
                        GroupBox("Preview") {
                            terminalPreview
                                .padding(.vertical, 8)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 450, height: 500)
        .onAppear {
            checkInstallationStatus()
        }
        .alert("Install zsh-syntax-highlighting", isPresented: $showingInstallAlert) {
            Button("Install") {
                installSyntaxHighlighting()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will install zsh-syntax-highlighting using Homebrew and configure your .zshrc file.")
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        HStack(spacing: 4) {
            switch installationStatus {
            case .notChecked:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
                Text("Not checked")
                    .foregroundColor(.secondary)
            case .checking:
                ProgressView()
                    .scaleEffect(0.7)
                Text("Checking...")
                    .foregroundColor(.secondary)
            case .installed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Installed")
                    .foregroundColor(.green)
            case .notInstalled:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.orange)
                Text("Not installed")
                    .foregroundColor(.orange)
            }
        }
        .font(.caption)
    }

    private var terminalPreview: some View {
        // Use explicit color to ensure proper rendering
        let fgColor = foregroundColor
        let bgColor = backgroundColor
        let cmdColor = commandHighlightColor

        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(bgColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("$")
                        .foregroundStyle(Color.green)
                    Text("ls")
                        .foregroundStyle(cmdColor)
                    Text("-la")
                        .foregroundStyle(fgColor)
                }
                HStack(spacing: 8) {
                    Text("file.txt")
                        .foregroundStyle(fgColor)
                    Text("folder/")
                        .foregroundStyle(Color.blue)
                }
                HStack(spacing: 4) {
                    Text("$")
                        .foregroundStyle(Color.green)
                    Text("echo")
                        .foregroundStyle(cmdColor)
                    Text("\"hello\"")
                        .foregroundStyle(fgColor)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(12)
        }
        .frame(height: 100)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }

    private func checkInstallationStatus() {
        installationStatus = .checking

        Task {
            let installed = await SyntaxHighlightingInstaller.shared.isInstalled()
            await MainActor.run {
                installationStatus = installed ? .installed : .notInstalled
            }
        }
    }

    private func installSyntaxHighlighting() {
        Task {
            let highlightColor = themeManager.customColors.commandHighlightColor
            do {
                try await SyntaxHighlightingInstaller.shared.install(highlightColor: highlightColor)
                await MainActor.run {
                    installationStatus = .installed
                }
            } catch {
                Logger.shared.error("Failed to install syntax highlighting: \(error)")
            }
        }
    }

    private func applyHighlightColor() {
        Task {
            let highlightColor = themeManager.customColors.commandHighlightColor
            do {
                try await SyntaxHighlightingInstaller.shared.updateHighlightColor(highlightColor)
                Logger.shared.info("Highlight color applied to .zshrc")
            } catch {
                Logger.shared.error("Failed to apply highlight color: \(error)")
            }
        }
    }
}
