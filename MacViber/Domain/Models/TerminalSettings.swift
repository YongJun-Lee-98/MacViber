import Foundation

struct TerminalSettings: Codable, Equatable {
    /// Output buffer flush delay (in seconds)
    /// Default: 0.016 (16ms, synced with 60fps display updates)
    /// Range: 0.01 ~ 0.5
    var outputFlushDelay: Double = 0.016

    // MARK: - Fast Output Collapse (Developer Test Mode)
    /// Enable fast output collapse mode (test feature)
    var fastOutputCollapseEnabled: Bool = false
    /// Number of lines threshold within time window to trigger collapse
    var fastOutputThresholdLines: Int = 10
    /// Time window in milliseconds for threshold detection
    var fastOutputThresholdMs: Double = 100
    /// Number of visible lines when collapsed
    var fastOutputVisibleLines: Int = 4

    static let `default` = TerminalSettings()

    // Value range limits
    static let minFlushDelay: Double = 0.01  // 10ms
    static let maxFlushDelay: Double = 0.5   // 500ms
}
