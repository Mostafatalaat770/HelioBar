import XCTest
@testable import HelioCore

final class Sect163k1Tests: XCTestCase {
    // MARK: Fast structural checks (run on every `swift test`)

    func test_basePointIsOnCurve() {
        XCTAssertTrue(Sect163k1.isOnCurve(Sect163k1.G))
    }

    func test_doubleStaysOnCurve() {
        XCTAssertTrue(Sect163k1.isOnCurve(Sect163k1.double(Sect163k1.G)))
    }

    /// Group law on small multiples: 2G on curve, and G + 2G == 3G.
    func test_smallMultiplesObeyGroupLaw() {
        let g = Sect163k1.G
        let two = Sect163k1.double(g)
        let three = Sect163k1.scalarMul([3, 0, 0], g)
        XCTAssertTrue(Sect163k1.isOnCurve(two))
        XCTAssertTrue(Sect163k1.isOnCurve(three))
        XCTAssertEqual(Sect163k1.add(g, two), three)
    }

    /// ECDH agreement with small scalars: 5·(7G) == 7·(5G). Validates
    /// scalarMul + the shared-secret derivation without full-size cost.
    func test_diffieHellmanSymmetrySmallScalars() {
        let dA: [UInt64] = [5, 0, 0], dB: [UInt64] = [7, 0, 0]
        let qA = Sect163k1.scalarMul(dA, Sect163k1.G)
        let qB = Sect163k1.scalarMul(dB, Sect163k1.G)
        XCTAssertFalse(qA.isInfinity)
        XCTAssertTrue(Sect163k1.isOnCurve(qA))
        let sharedAB = Sect163k1.sharedSecretX(privateScalar: dA, peerPublic: qB)
        let sharedBA = Sect163k1.sharedSecretX(privateScalar: dB, peerPublic: qA)
        XCTAssertEqual(sharedAB, sharedBA)
        XCTAssertFalse(sharedAB.isZero)
    }

    // MARK: Rigorous full-size checks — slow (~30s, affine). Opt-in:
    //   RUN_EC_SLOW_TESTS=1 swift test --filter Sect163k1Tests

    private func requireSlow() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_EC_SLOW_TESTS"] != nil,
                          "set RUN_EC_SLOW_TESTS=1 to run the full-size EC correctness checks")
    }

    /// The defining property of the group order: n·G is the point at infinity.
    /// Exercises the full field + curve stack against the SEC2 parameters.
    func test_orderTimesBaseIsInfinity() throws {
        try requireSlow()
        XCTAssertTrue(Sect163k1.scalarMul(Sect163k1.order, Sect163k1.G).isInfinity)
    }

    /// ECDH symmetry with full-size (163-bit) private scalars.
    func test_diffieHellmanSymmetryFullScalars() throws {
        try requireSlow()
        let dA: [UInt64] = [0x0123_4567_89AB_CDEF, 0xFEDC_BA98_7654_3210, 0x0000_0001]
        let dB: [UInt64] = [0xCAFE_BABE_DEAD_BEEF, 0x0BAD_F00D_1234_5678, 0x0000_0002]
        let qA = Sect163k1.scalarMul(dA, Sect163k1.G)
        let qB = Sect163k1.scalarMul(dB, Sect163k1.G)
        let sharedAB = Sect163k1.sharedSecretX(privateScalar: dA, peerPublic: qB)
        let sharedBA = Sect163k1.sharedSecretX(privateScalar: dB, peerPublic: qA)
        XCTAssertEqual(sharedAB, sharedBA)
        XCTAssertFalse(sharedAB.isZero)
    }
}
