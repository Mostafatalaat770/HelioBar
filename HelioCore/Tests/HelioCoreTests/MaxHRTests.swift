import XCTest
@testable import HelioCore

final class MaxHRTests: XCTestCase {
    func test_typicalAge() { XCTAssertEqual(maxHR(forAge: 30), 190) }
    func test_youngestStepperValue() { XCTAssertEqual(maxHR(forAge: 10), 210) }
    func test_oldestStepperValueHitsFloorExactly() { XCTAssertEqual(maxHR(forAge: 100), 120) }
    func test_beyondStepperRangeIsFloored() { XCTAssertEqual(maxHR(forAge: 140), 120) }
}
