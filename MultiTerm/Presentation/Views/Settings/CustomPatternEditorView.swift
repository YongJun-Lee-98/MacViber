import SwiftUI

struct CustomPatternEditorView: View {
    let pattern: CustomPattern
    let onSave: (CustomPattern) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var patternText: String
    @State private var matchMode: PatternMatchMode
    @State private var autoPin: Bool
    @State private var testText: String = ""
    @State private var validationError: String?

    init(pattern: CustomPattern, onSave: @escaping (CustomPattern) -> Void, onCancel: @escaping () -> Void) {
        self.pattern = pattern
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: pattern.name)
        _patternText = State(initialValue: pattern.pattern)
        _matchMode = State(initialValue: pattern.matchMode)
        _autoPin = State(initialValue: pattern.autoPin)
    }

    private var isValid: Bool {
        !name.isEmpty && !patternText.isEmpty && validationError == nil
    }

    private var testPattern: CustomPattern {
        CustomPattern(
            id: pattern.id,
            name: name,
            pattern: patternText,
            matchMode: matchMode,
            isEnabled: true,
            autoPin: autoPin
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()

            Form {
                Section {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    Picker("Match Mode", selection: $matchMode) {
                        ForEach(PatternMatchMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pattern")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField(matchMode == .keyword ? "Enter keyword..." : "Enter regex pattern...", text: $patternText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: patternText) { _, _ in
                                validatePattern()
                            }
                            .onChange(of: matchMode) { _, _ in
                                validatePattern()
                            }

                        if let error = validationError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    Toggle("Auto-pin when matched", isOn: $autoPin)
                }

                Section("Test Pattern") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter sample text to test the pattern:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Sample text...", text: $testText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        if !testText.isEmpty {
                            HStack {
                                if testPattern.matches(testText) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Pattern matches!")
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                    Text("No match")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    savePattern()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 400, height: 450)
        .onAppear {
            validatePattern()
        }
    }

    private var headerView: some View {
        HStack {
            Text(pattern.pattern.isEmpty ? "New Pattern" : "Edit Pattern")
                .font(.title3)
                .fontWeight(.semibold)

            Spacer()
        }
        .padding()
    }

    private func validatePattern() {
        if matchMode == .regex && !patternText.isEmpty {
            do {
                _ = try NSRegularExpression(pattern: patternText)
                validationError = nil
            } catch {
                validationError = "Invalid regex: \(error.localizedDescription)"
            }
        } else {
            validationError = nil
        }
    }

    private func savePattern() {
        let updatedPattern = CustomPattern(
            id: pattern.id,
            name: name,
            pattern: patternText,
            matchMode: matchMode,
            isEnabled: pattern.isEnabled,
            autoPin: autoPin,
            createdAt: pattern.createdAt
        )
        onSave(updatedPattern)
    }
}

#Preview {
    CustomPatternEditorView(
        pattern: CustomPattern(name: "", pattern: ""),
        onSave: { _ in },
        onCancel: {}
    )
}
