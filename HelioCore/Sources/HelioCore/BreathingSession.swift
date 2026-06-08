import Foundation

/// Tracks a guided-breathing session's biofeedback: the HR it started at, the
/// lowest HR seen since, and the drop between them. A single `record(hr:)` entry
/// point seeds `start` on the first non-nil sample and keeps `low` monotonic, so
/// there is exactly one seeding path (the view previously seeded in two places).
public struct BreathingSession: Equatable, Sendable {
    public private(set) var start: Int?
    public private(set) var low: Int?

    public init() {}

    /// Drop from the starting HR to the lowest seen, never negative. `nil` until
    /// at least one sample has been recorded.
    public var drop: Int? {
        guard let start, let low else { return nil }
        return Swift.max(0, start - low)
    }

    /// Feed a sample. `nil` (no live HR yet) is ignored so it can't seed `start`.
    public mutating func record(hr: Int?) {
        guard let hr else { return }
        if start == nil { start = hr }
        low = Swift.min(low ?? hr, hr)
    }
}
