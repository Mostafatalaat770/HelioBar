import SwiftUI
import HelioCore

/// Design tokens for the HelioBar UI. Single source of truth for color,
/// spacing, radii, and typography across every surface.
enum Theme {
    // Zone color ramp
    static let resting  = Color(red: 0.20, green: 0.78, blue: 0.35) // #34C759
    static let elevated = Color(red: 1.00, green: 0.62, blue: 0.04) // #FF9F0A
    static let high     = Color(red: 1.00, green: 0.27, blue: 0.23) // #FF453A

    static func color(for zone: HRZone?) -> Color {
        switch zone {
        case .resting:  return resting
        case .elevated: return elevated
        case .high:     return high
        case nil:       return .secondary
        }
    }

    // Spacing
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20

    // Radii
    static let cardRadius: CGFloat = 13
    static let popoverRadius: CGFloat = 22
    static let pillRadius: CGFloat = 8

    // Typography
    /// The app's single rounded-font constructor. Every view routes through this
    /// (or the named roles below) so size/weight choices stay centralized.
    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func bpmFont(_ size: CGFloat) -> Font {
        rounded(size, weight: .bold).monospacedDigit()
    }
    static let statValueFont = rounded(20, weight: .bold).monospacedDigit()
    static let cardTitleFont = rounded(11, weight: .semibold)
    static let captionFont   = rounded(11)
}

extension View {
    /// Standard translucent card surface with a hairline stroke.
    func cardSurface(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background(.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.09))
            )
    }
}
