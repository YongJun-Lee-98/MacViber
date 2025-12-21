import Foundation
import Combine

final class TerminalSettingsManager: ObservableObject {
    static let shared = TerminalSettingsManager()

    @Published private(set) var settings: TerminalSettings

    private let userDefaultsKey = "MacViber.TerminalSettings"
    let settingsChanged = PassthroughSubject<TerminalSettings, Never>()

    private init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(TerminalSettings.self, from: data) {
            self.settings = saved
        } else {
            self.settings = .default
        }
    }

    var outputFlushDelay: TimeInterval {
        settings.outputFlushDelay
    }

    func setOutputFlushDelay(_ value: Double) {
        let clamped = min(max(value, TerminalSettings.minFlushDelay),
                          TerminalSettings.maxFlushDelay)
        settings.outputFlushDelay = clamped
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            settingsChanged.send(settings)
        } catch {
            Logger.shared.error("Failed to save terminal settings: \(error)")
        }
    }

    func resetToDefaults() {
        settings = .default
        save()
        Logger.shared.info("Reset terminal settings to defaults")
    }
}
