import XCTest
@testable import HelioCore

final class UpdatePolicyTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: shouldAutoCheck

    func test_disabledNeverChecks() {
        XCTAssertFalse(UpdatePolicy.shouldAutoCheck(
            autoEnabled: false, lastChecked: nil, now: t0, interval: day))
    }

    func test_neverCheckedRunsImmediately() {
        XCTAssertTrue(UpdatePolicy.shouldAutoCheck(
            autoEnabled: true, lastChecked: nil, now: t0, interval: day))
    }

    func test_withinIntervalDoesNotCheck() {
        let last = t0.addingTimeInterval(-day + 1)   // 1s short of a day
        XCTAssertFalse(UpdatePolicy.shouldAutoCheck(
            autoEnabled: true, lastChecked: last, now: t0, interval: day))
    }

    func test_exactlyIntervalChecks() {
        let last = t0.addingTimeInterval(-day)
        XCTAssertTrue(UpdatePolicy.shouldAutoCheck(
            autoEnabled: true, lastChecked: last, now: t0, interval: day))
    }

    func test_beyondIntervalChecks() {
        let last = t0.addingTimeInterval(-2 * day)
        XCTAssertTrue(UpdatePolicy.shouldAutoCheck(
            autoEnabled: true, lastChecked: last, now: t0, interval: day))
    }

    // MARK: shouldSurface

    func test_newerUndismissedSurfaces() {
        XCTAssertTrue(UpdatePolicy.shouldSurface(
            fetchedVersion: "2.1.0", currentVersion: "2.0.0", dismissedVersion: nil))
    }

    func test_equalDoesNotSurface() {
        XCTAssertFalse(UpdatePolicy.shouldSurface(
            fetchedVersion: "2.0.0", currentVersion: "2.0.0", dismissedVersion: nil))
    }

    func test_olderDoesNotSurface() {
        XCTAssertFalse(UpdatePolicy.shouldSurface(
            fetchedVersion: "1.9.0", currentVersion: "2.0.0", dismissedVersion: nil))
    }

    func test_newerButDismissedDoesNotSurface() {
        XCTAssertFalse(UpdatePolicy.shouldSurface(
            fetchedVersion: "2.1.0", currentVersion: "2.0.0", dismissedVersion: "2.1.0"))
    }

    func test_newerWithDifferentDismissedStillSurfaces() {
        XCTAssertTrue(UpdatePolicy.shouldSurface(
            fetchedVersion: "2.2.0", currentVersion: "2.0.0", dismissedVersion: "2.1.0"))
    }
}
