import XCTest
@testable import HelioCore

final class LowHRAlertEngineTests: XCTestCase {
    private func engine() -> LowHRAlertEngine {
        LowHRAlertEngine(config: .init(enabled: true, threshold: 45, duration: 120))
    }
    private let t0 = Date(timeIntervalSince1970: 0)

    func test_aboveThresholdNeverFires() {
        let e = engine()
        XCTAssertFalse(e.evaluate(bpm: 60, now: t0))
        XCTAssertFalse(e.evaluate(bpm: 46, now: t0.addingTimeInterval(600)))
    }

    func test_firesOnceAfterDuration() {
        let e = engine()
        XCTAssertFalse(e.evaluate(bpm: 40, now: t0))                      // starts low
        XCTAssertFalse(e.evaluate(bpm: 40, now: t0.addingTimeInterval(60)))  // not long enough
        XCTAssertTrue(e.evaluate(bpm: 40, now: t0.addingTimeInterval(120)))  // fires
        XCTAssertFalse(e.evaluate(bpm: 40, now: t0.addingTimeInterval(180))) // no re-fire
    }

    func test_atThresholdCountsAsLow() {
        let e = engine()
        XCTAssertFalse(e.evaluate(bpm: 45, now: t0))
        XCTAssertTrue(e.evaluate(bpm: 45, now: t0.addingTimeInterval(120)))
    }

    func test_riseAboveReArms() {
        let e = engine()
        _ = e.evaluate(bpm: 40, now: t0)
        XCTAssertTrue(e.evaluate(bpm: 40, now: t0.addingTimeInterval(120)))
        XCTAssertFalse(e.evaluate(bpm: 70, now: t0.addingTimeInterval(140)))  // rise -> re-arm
        XCTAssertFalse(e.evaluate(bpm: 40, now: t0.addingTimeInterval(150)))  // low again
        XCTAssertTrue(e.evaluate(bpm: 40, now: t0.addingTimeInterval(270)))   // fires again
    }

    func test_disabledNeverFires() {
        let e = LowHRAlertEngine(config: .init(enabled: false, threshold: 45, duration: 1))
        XCTAssertFalse(e.evaluate(bpm: 30, now: t0))
        XCTAssertFalse(e.evaluate(bpm: 30, now: t0.addingTimeInterval(100)))
    }
}
