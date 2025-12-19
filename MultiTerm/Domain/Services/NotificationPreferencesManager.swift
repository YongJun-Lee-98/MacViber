import Foundation
import Combine

final class NotificationPreferencesManager: ObservableObject {
    static let shared = NotificationPreferencesManager()

    @Published private(set) var preferences: NotificationPreferences

    private let userDefaultsKey = "MultiTerm.NotificationPreferences"
    private let preferencesChangedSubject = PassthroughSubject<NotificationPreferences, Never>()

    var preferencesChanged: AnyPublisher<NotificationPreferences, Never> {
        preferencesChangedSubject.eraseToAnyPublisher()
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let prefs = try? JSONDecoder().decode(NotificationPreferences.self, from: data) {
            self.preferences = prefs
        } else {
            self.preferences = .default
        }
    }

    // MARK: - Type Filters

    func setTypeEnabled(_ type: NotificationType, enabled: Bool) {
        preferences.setTypeEnabled(type, enabled: enabled)
        save()
    }

    func isTypeEnabled(_ type: NotificationType) -> Bool {
        preferences.isTypeEnabled(type)
    }

    // MARK: - Auto-Pin Settings

    func setAutoPinForType(_ type: NotificationType, enabled: Bool) {
        preferences.setAutoPin(type, enabled: enabled)
        save()
    }

    func shouldAutoPin(_ type: NotificationType) -> Bool {
        preferences.shouldAutoPin(type)
    }

    // MARK: - System Settings

    func setSystemNotificationsEnabled(_ enabled: Bool) {
        preferences.systemNotificationsEnabled = enabled
        save()
    }

    func setDockBadgeEnabled(_ enabled: Bool) {
        preferences.dockBadgeEnabled = enabled
        save()
    }

    // MARK: - Custom Patterns

    func addCustomPattern(_ pattern: CustomPattern) {
        preferences.customPatterns.append(pattern)
        save()
        Logger.shared.info("Added custom pattern: \(pattern.name)")
    }

    func updateCustomPattern(_ pattern: CustomPattern) {
        if let index = preferences.customPatterns.firstIndex(where: { $0.id == pattern.id }) {
            preferences.customPatterns[index] = pattern
            save()
            Logger.shared.info("Updated custom pattern: \(pattern.name)")
        }
    }

    func removeCustomPattern(_ id: UUID) {
        preferences.customPatterns.removeAll { $0.id == id }
        save()
        Logger.shared.info("Removed custom pattern")
    }

    func getEnabledCustomPatterns() -> [CustomPattern] {
        preferences.customPatterns.filter { $0.isEnabled }
    }

    func moveCustomPattern(from source: IndexSet, to destination: Int) {
        preferences.customPatterns.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Convenience Methods

    func shouldShowNotification(type: NotificationType) -> Bool {
        isTypeEnabled(type)
    }

    func shouldAutoPinNotification(type: NotificationType, matchedPattern: CustomPattern? = nil) -> Bool {
        if let pattern = matchedPattern, pattern.autoPin {
            return true
        }
        return shouldAutoPin(type)
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(preferences)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            preferencesChangedSubject.send(preferences)
        } catch {
            Logger.shared.error("Failed to save notification preferences: \(error)")
        }
    }

    func resetToDefaults() {
        preferences = .default
        save()
        Logger.shared.info("Reset notification preferences to defaults")
    }
}
