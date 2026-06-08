import Foundation

/// Heart-rate zone for menu bar tinting.
public enum HRZone: String, Sendable {
    case resting, elevated, high

    /// Zone by fraction of max HR: <60% resting, 60–80% elevated, ≥80% high.
    public static func zone(for bpm: Int, maxHR: Int) -> HRZone {
        zone(forFraction: Double(bpm) / Double(Swift.max(maxHR, 1)))
    }

    /// Zone using heart-rate reserve (Karvonen) when a resting HR is known:
    /// fraction = (bpm − rest) / (max − rest). This is more personal than %max —
    /// the same bpm reads "lower" for someone with a low resting HR. Falls back
    /// to plain %max when `restingHR` is nil or invalid (rest ≥ max).
    public static func zone(for bpm: Int, maxHR: Int, restingHR: Int?) -> HRZone {
        guard let restingHR, maxHR > restingHR else {
            return zone(for: bpm, maxHR: maxHR)
        }
        let reserve = Double(maxHR - restingHR)
        return zone(forFraction: Double(bpm - restingHR) / reserve)
    }

    private static func zone(forFraction fraction: Double) -> HRZone {
        switch fraction {
        case ..<0.60:      return .resting
        case 0.60..<0.80:  return .elevated
        default:           return .high
        }
    }
}

/// Estimated maximum heart rate for an age (the common `220 − age` formula),
/// floored at 120 so very high ages still yield sane zones. Single source of
/// truth: both the menu-bar app and the Settings readout call this.
public func maxHR(forAge age: Int) -> Int {
    Swift.max(120, 220 - age)
}

/// Heart-rate source freshness for honest UI rendering.
public enum SourceStatus: Equatable, Sendable {
    case idle               // never received data
    case live               // streaming
    case stale              // had data, now dropped
    case error(String)      // failure with message
}
