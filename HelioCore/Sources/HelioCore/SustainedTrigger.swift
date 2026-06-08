import Foundation

/// Shared mechanism for "fire once when a condition holds continuously for a
/// duration, then re-arm when it stops holding." Both the elevated- and low-HR
/// alert engines wrap this so the once-per-episode logic lives in exactly one place.
final class SustainedTrigger {
    private var since: Date?
    private var fired = false

    /// `holds`: whether the watched condition is currently true (e.g. bpm above a
    /// threshold). Returns true exactly once, when it has held for `duration`.
    func evaluate(_ holds: Bool, now: Date, duration: TimeInterval) -> Bool {
        guard holds else { reset(); return false }
        if since == nil { since = now }
        if !fired, let since, now.timeIntervalSince(since) >= duration {
            fired = true
            return true
        }
        return false
    }

    func reset() { since = nil; fired = false }
}
