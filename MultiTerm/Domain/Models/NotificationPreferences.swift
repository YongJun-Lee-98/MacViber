import Foundation

struct NotificationPreferences: Codable, Equatable {
    var enabledTypes: Set<String>
    var autoPinTypes: Set<String>
    var systemNotificationsEnabled: Bool
    var dockBadgeEnabled: Bool
    var customPatterns: [CustomPattern]

    init(
        enabledTypes: Set<String> = Set(NotificationType.allCases.map { $0.rawValue }),
        autoPinTypes: Set<String> = ["error"],
        systemNotificationsEnabled: Bool = true,
        dockBadgeEnabled: Bool = true,
        customPatterns: [CustomPattern] = []
    ) {
        self.enabledTypes = enabledTypes
        self.autoPinTypes = autoPinTypes
        self.systemNotificationsEnabled = systemNotificationsEnabled
        self.dockBadgeEnabled = dockBadgeEnabled
        self.customPatterns = customPatterns
    }

    static let `default` = NotificationPreferences()

    func isTypeEnabled(_ type: NotificationType) -> Bool {
        enabledTypes.contains(type.rawValue)
    }

    func shouldAutoPin(_ type: NotificationType) -> Bool {
        autoPinTypes.contains(type.rawValue)
    }

    mutating func setTypeEnabled(_ type: NotificationType, enabled: Bool) {
        if enabled {
            enabledTypes.insert(type.rawValue)
        } else {
            enabledTypes.remove(type.rawValue)
        }
    }

    mutating func setAutoPin(_ type: NotificationType, enabled: Bool) {
        if enabled {
            autoPinTypes.insert(type.rawValue)
        } else {
            autoPinTypes.remove(type.rawValue)
        }
    }
}
