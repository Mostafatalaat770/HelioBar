import XCTest
@testable import HelioCore

final class B163Tests: XCTestCase {
    // MARK: Fast structural checks

    func test_basePointIsOnCurve() {
        // Validates the B-163 base point AND the b coefficient assembly.
        XCTAssertTrue(B163.isOnCurve(B163.G))
    }

    func test_doubleStaysOnCurve() {
        XCTAssertTrue(B163.isOnCurve(B163.double(B163.G)))
    }

    func test_smallMultiplesObeyGroupLaw() {
        let g = B163.G
        let two = B163.double(g)
        let three = B163.scalarMul([3, 0, 0], g)
        XCTAssertTrue(B163.isOnCurve(three))
        XCTAssertEqual(B163.add(g, two), three)
    }

    func test_diffieHellmanSymmetrySmallScalars() {
        let dA: [UInt64] = [5, 0, 0], dB: [UInt64] = [7, 0, 0]
        let qA = B163.scalarMul(dA, B163.G)
        let qB = B163.scalarMul(dB, B163.G)
        let sharedAB = B163.scalarMul(dA, qB)
        let sharedBA = B163.scalarMul(dB, qA)
        XCTAssertEqual(sharedAB, sharedBA)
        XCTAssertFalse(sharedAB.x.isZero)
    }

    func test_byteSerializationRoundTrips() {
        // Small LE key (= 5) so scalarMul is fast; validates serialization layout.
        var priv = [UInt8](repeating: 0, count: 24); priv[0] = 5
        let pub = B163.publicKey(privateKey: priv)
        XCTAssertEqual(pub.count, 48)
        let x = B163.gf(fromLE: pub[0..<24])
        let y = B163.gf(fromLE: pub[24..<48])
        XCTAssertTrue(B163.isOnCurve(ECPoint(x: x, y: y)))
        // leBytes ∘ gf is identity on a field element
        XCTAssertEqual(B163.leBytes(x), Array(pub[0..<24]))
    }

    func test_ecdhAgreementViaByteAPI() {
        var a = [UInt8](repeating: 0, count: 24); a[0] = 5      // small keys → fast
        var bKey = [UInt8](repeating: 0, count: 24); bKey[0] = 7
        let pubA = B163.publicKey(privateKey: a)
        let pubB = B163.publicKey(privateKey: bKey)
        let sharedAB = B163.sharedSecret(privateKey: a, remotePublic: pubB)
        let sharedBA = B163.sharedSecret(privateKey: bKey, remotePublic: pubA)
        XCTAssertEqual(sharedAB, sharedBA)        // both sides derive the same point
        XCTAssertEqual(sharedAB.count, 48)
    }

    // MARK: Rigorous full-size check — slow (~30s). Opt-in:
    //   RUN_EC_SLOW_TESTS=1 swift test --filter B163Tests

    func test_orderTimesBaseIsInfinity() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_EC_SLOW_TESTS"] != nil,
                          "set RUN_EC_SLOW_TESTS=1 to run the full-size EC correctness check")
        // n·G = ∞ proves the B-163 base point, order, and a-coefficient are all
        // mutually consistent with the field + point arithmetic.
        XCTAssertTrue(B163.scalarMul(B163.order, B163.G).isInfinity)
    }
}
