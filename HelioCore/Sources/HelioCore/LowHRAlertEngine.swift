import Foundation

/// Config for the low-HR (bradycardia) alert.
public struct LowHRConfig: Equatable, Sendable {
    public var enabled: Bool
    public var threshold: Int          // bpm
    public var duration: TimeInterval  // seconds the HR must stay low
    public init(enabled: Bool = false, threshold: Int = 45, duration: TimeInterval = 120) {
        self.enabled = enabled; self.threshold = threshold; self.duration = duration
    }
}

/// Fires when HR stays at/below `threshold` continuously for `duration` — a
/// low-resting-HR / bradycardia nudge. Mirrors the elevated-HR engine (shared
/// once-per-episode core), inverted: re-arms when HR rises back above threshold.
public final class LowHRAlertEngine {
    public var config: LowHRConfig
    private let trigger = SustainedTrigger()

    public init(config: LowHRConfig = .init()) { self.config = config }

    /// Call on each HR sample. Returns true exactly once when the alert should fire.
    public func evaluate(bpm: Int, now: Date) -> Bool {
        guard config.enabled else { trigger.reset(); return false }
        return trigger.evaluate(bpm <= config.threshold, now: now, duration: config.duration)
    }
}
