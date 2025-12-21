import SwiftUI

struct TerminalSettingsView: View {
    @ObservedObject private var settingsManager = TerminalSettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var flushDelayMs: Double = 50

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    performanceSection
                }
                .padding()
            }
        }
        .frame(width: 450, height: 220)
        .onAppear {
            flushDelayMs = settingsManager.outputFlushDelay * 1000
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
}

#Preview {
    TerminalSettingsView()
}
