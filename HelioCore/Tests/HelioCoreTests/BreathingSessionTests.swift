import XCTest
@testable import HelioCore

final class BreathingSessionTests: XCTestCase {
    func test_emptyHasNoStartLowOrDrop() {
        let s = BreathingSession()
        XCTAssertNil(s.start)
        XCTAssertNil(s.low)
        XCTAssertNil(s.drop)
    }

    func test_nilSampleIsIgnoredAndCannotSeedStart() {
        var s = BreathingSession()
        s.record(hr: nil)
        XCTAssertNil(s.start)
        s.record(hr: 72)
        XCTAssertEqual(s.start, 72)   // first non-nil sample seeds start
        s.record(hr: nil)             // later nils are ignored, don't disturb state
        XCTAssertEqual(s.start, 72)
        XCTAssertEqual(s.low, 72)
    }

    func test_firstSampleSeedsStartAndLow() {
        var s = BreathingSession()
        s.record(hr: 80)
        XCTAssertEqual(s.start, 80)
        XCTAssertEqual(s.low, 80)
        XCTAssertEqual(s.drop, 0)
    }

    func test_lowTracksMinimumAndDropIsStartMinusLow() {
        var s = BreathingSession()
        s.record(hr: 80)
        s.record(hr: 70)
        s.record(hr: 90)   // does not raise `low`
        XCTAssertEqual(s.start, 80)
        XCTAssertEqual(s.low, 70)
        XCTAssertEqual(s.drop, 10)
    }

    func test_dropIsNeverNegativeWhenHRRises() {
        var s = BreathingSession()
        s.record(hr: 70)
        s.record(hr: 85)
        XCTAssertEqual(s.start, 70)
        XCTAssertEqual(s.low, 70)
        XCTAssertEqual(s.drop, 0)
    }
}
