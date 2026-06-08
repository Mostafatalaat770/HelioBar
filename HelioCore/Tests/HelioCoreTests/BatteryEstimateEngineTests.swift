import XCTest
@testable import HelioCore

final class BatteryEstimateEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)

    func test_calibratesUntilEnoughTimeAndDropObserved() {
        let e = BatteryEstimateEngine(minCalibrationDuration: 3 * 60 * 60, minPercentDrop: 2)
        XCTAssertEqual(e.record(percent: 80, date: t0), .calibrating)
        XCTAssertEqual(e.record(percent: 79, date: t0.addingTimeInterval(2 * 60 * 60)), .calibrating)
        XCTAssertEqual(e.record(percent: 78, date: t0.addingTimeInterval(3 * 60 * 60)), .ready(78 * 90 * 60))
    }

    func test_chargingResetsCalibration() {
        let e = BatteryEstimateEngine(minCalibrationDuration: 60, minPercentDrop: 1)
        XCTAssertEqual(e.record(percent: 50, date: t0), .calibrating)
        XCTAssertEqual(e.record(percent: 49, date: t0.addingTimeInterval(60)), .ready(49 * 60))
        XCTAssertEqual(e.record(percent: 80, date: t0.addingTimeInterval(120)), .calibrating)
    }

    // MARK: formatRemaining

    func test_formatRemaining_subHour() {
        XCTAssertEqual(BatteryEstimate.formatRemaining(0), "<1h")
        XCTAssertEqual(BatteryEstimate.formatRemaining(30 * 60), "<1h")
    }
    func test_formatRemaining_negativeClampsToSubHour() {
        XCTAssertEqual(BatteryEstimate.formatRemaining(-3600), "<1h")
    }
    func test_formatRemaining_hourBoundary() {
        XCTAssertEqual(BatteryEstimate.formatRemaining(3600), "1h")
        XCTAssertEqual(BatteryEstimate.formatRemaining(47 * 3600), "47h")
    }
    func test_formatRemaining_dayBoundaryAndRounding() {
        XCTAssertEqual(BatteryEstimate.formatRemaining(48 * 3600), "2d")   // 48h flips to days
        XCTAssertEqual(BatteryEstimate.formatRemaining(60 * 3600), "3d")   // 2.5d rounds up
    }
}
