import Foundation

struct TerminalSettings: Codable, Equatable {
    /// Output buffer flush delay (in seconds)
    /// Default: 0.05 (50ms)
    /// Range: 0.01 ~ 0.5
    var outputFlushDelay: Double = 0.05

    static let `default` = TerminalSettings()

    // Value range limits
    static let minFlushDelay: Double = 0.01  // 10ms
    static let maxFlushDelay: Double = 0.5   // 500ms
}
