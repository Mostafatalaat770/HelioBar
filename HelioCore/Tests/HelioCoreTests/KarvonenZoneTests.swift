import XCTest
@testable import HelioCore

final class KarvonenZoneTests: XCTestCase {
    // rest 60, max 190 -> reserve 130. Boundaries land at:
    //   60% HRR = 60 + 0.60*130 = 138 bpm
    //   80% HRR = 60 + 0.80*130 = 164 bpm

    func test_nilRestingFallsBackToPercentMax() {
        // 120/190 = 63% of max -> elevated under %max
        XCTAssertEqual(HRZone.zone(for: 120, maxHR: 190, restingHR: nil), .elevated)
        XCTAssertEqual(HRZone.zone(for: 120, maxHR: 190, restingHR: nil),
                       HRZone.zone(for: 120, maxHR: 190))
    }

    func test_invalidRestingAtOrAboveMaxFallsBack() {
        XCTAssertEqual(HRZone.zone(for: 120, maxHR: 190, restingHR: 190), .elevated)
        XCTAssertEqual(HRZone.zone(for: 120, maxHR: 190, restingHR: 200), .elevated)
    }

    func test_reserveLowersTheZoneVsPercentMax() {
        // Same 120 bpm: 63% of max (elevated) but only 46% HRR -> resting.
        XCTAssertEqual(HRZone.zone(for: 120, maxHR: 190, restingHR: 60), .resting)
    }

    func test_boundaries() {
        XCTAssertEqual(HRZone.zone(for: 137, maxHR: 190, restingHR: 60), .resting)   // <60% HRR
        XCTAssertEqual(HRZone.zone(for: 138, maxHR: 190, restingHR: 60), .elevated)  // =60% HRR
        XCTAssertEqual(HRZone.zone(for: 163, maxHR: 190, restingHR: 60), .elevated)  // <80% HRR
        XCTAssertEqual(HRZone.zone(for: 164, maxHR: 190, restingHR: 60), .high)      // =80% HRR
    }

    func test_belowRestingIsResting() {
        XCTAssertEqual(HRZone.zone(for: 50, maxHR: 190, restingHR: 60), .resting)   // negative HRR
    }
}
