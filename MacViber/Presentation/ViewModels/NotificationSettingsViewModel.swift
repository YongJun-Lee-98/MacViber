import Foundation
import Combine

class NotificationSettingsViewModel: ObservableObject {
    private let preferencesManager: NotificationPreferencesManager
    private var cancellables = Set<AnyCancellable>()

    @Published var preferences: NotificationPreferences
    @Published var editingPattern: CustomPattern?
    @Published var showPatternEditor = false

    init(preferencesManager: NotificationPreferencesManager = .shared) {
        self.preferencesManager = preferencesManager
        self.preferences = preferencesManager.preferences

        preferencesManager.preferencesChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPrefs in
                self?.preferences = newPrefs
            }
            .store(in: &cancellables)
    }

    // MARK: - Type Filters

    func isTypeEnabled(_ type: NotificationType) -> Bool {
        preferences.isTypeEnabled(type)
    }

    func setTypeEnabled(_ type: NotificationType, enabled: Bool) {
        preferencesManager.setTypeEnabled(type, enabled: enabled)
    }

    // MARK: - Auto-Pin

    func shouldAutoPin(_ type: NotificationType) -> Bool {
        preferences.shouldAutoPin(type)
    }

    func setAutoPin(_ type: NotificationType, enabled: Bool) {
        preferencesManager.setAutoPinForType(type, enabled: enabled)
    }

    // MARK: - System Settings

    var systemNotificationsEnabled: Bool {
        get { preferences.systemNotificationsEnabled }
        set { preferencesManager.setSystemNotificationsEnabled(newValue) }
    }

    var dockBadgeEnabled: Bool {
        get { preferences.dockBadgeEnabled }
        set { preferencesManager.setDockBadgeEnabled(newValue) }
    }

    // MARK: - Custom Patterns

    var customPatterns: [CustomPattern] {
        preferences.customPatterns
    }

    func addNewPattern() {
        editingPattern = CustomPattern(
            name: "New Pattern",
            pattern: "",
            matchMode: .keyword
        )
        showPatternEditor = true
    }

    func editPattern(_ pattern: CustomPattern) {
        editingPattern = pattern
        showPatternEditor = true
    }

    func savePattern(_ pattern: CustomPattern) {
        if preferences.customPatterns.contains(where: { $0.id == pattern.id }) {
            preferencesManager.updateCustomPattern(pattern)
        } else {
            preferencesManager.addCustomPattern(pattern)
        }
        showPatternEditor = false
        editingPattern = nil
    }

    func deletePattern(_ pattern: CustomPattern) {
        preferencesManager.removeCustomPattern(pattern.id)
    }

    func togglePatternEnabled(_ pattern: CustomPattern) {
        var updatedPattern = pattern
        updatedPattern.isEnabled.toggle()
        preferencesManager.updateCustomPattern(updatedPattern)
    }

    func movePatterns(from source: IndexSet, to destination: Int) {
        preferencesManager.moveCustomPattern(from: source, to: destination)
    }

    // MARK: - Reset

    func resetToDefaults() {
        preferencesManager.resetToDefaults()
    }
}
