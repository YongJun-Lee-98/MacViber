import SwiftUI

struct TerminalSettingsView: View {
    @ObservedObject private var settingsManager = TerminalSettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var flushDelayMs: Double = 50
    @State private var fastOutputCollapseEnabled: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    performanceSection
                    developerSection
                }
                .padding()
            }
        }
        .frame(width: 450, height: 320)
        .onAppear {
            flushDelayMs = settingsManager.outputFlushDelay * 1000
            fastOutputCollapseEnabled = settingsManager.fastOutputCollapseEnabled
        }
    }

    private var headerView: some View {
        HStack {
            Text("Terminal Settings")
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

    private var performanceSection: some View {
        GroupBox("Performance") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Output Buffer Delay")
                    Spacer()
                    Text("\(Int(flushDelayMs))ms")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $flushDelayMs, in: 10...500, step: 10)
                    .onChange(of: flushDelayMs) { _, newValue in
                        settingsManager.setOutputFlushDelay(newValue / 1000.0)
                    }

                Text("Higher values reduce CPU usage but increase output latency. Default: 50ms")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                HStack {
                    Spacer()
                    Button("Reset to Default") {
                        settingsManager.resetToDefaults()
                        flushDelayMs = settingsManager.outputFlushDelay * 1000
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var developerSection: some View {
        GroupBox("Developer (Test Mode)") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Fast Output Collapse", isOn: $fastOutputCollapseEnabled)
                    .onChange(of: fastOutputCollapseEnabled) { _, newValue in
                        settingsManager.setFastOutputCollapseEnabled(newValue)
                    }

                Text("When enabled, detects fast output (>\(settingsManager.fastOutputThresholdLines) lines/\(Int(settingsManager.fastOutputThresholdMs))ms) and shows only the last \(settingsManager.fastOutputVisibleLines) lines to reduce screen flickering.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if fastOutputCollapseEnabled {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Experimental feature - check Console.app for debug logs")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    TerminalSettingsView()
}
