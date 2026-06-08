import XCTest
@testable import HelioCore

final class GF163Tests: XCTestCase {
    /// Field element with exactly the given bit positions set.
    private func g(_ bits: [Int]) -> GF163 {
        bits.reduce(GF163.zero) { $0 + GF163.monomial($1) }
    }
    private let sampleA = GF163([0xDEAD_BEEF_1234_5678, 0xCAFE_BABE_0BAD_F00D, 0x0000_0007_1234_5678])
    private let sampleB = GF163([0x0123_4567_89AB_CDEF, 0xFEDC_BA98_7654_3210, 0x0000_0001_AABB_CCDD])

    func test_addIsXorAndSelfCancels() {
        XCTAssertEqual(sampleA + sampleA, .zero)
        XCTAssertEqual(sampleA + .zero, sampleA)
    }

    func test_multiplicativeIdentity() {
        XCTAssertEqual(sampleA * .one, sampleA)
        XCTAssertEqual(GF163.one * sampleB, sampleB)
    }

    func test_smallProductsWithoutReduction() {
        XCTAssertEqual(GF163.monomial(1) * GF163.monomial(1), GF163.monomial(2))   // x·x = x²
        XCTAssertEqual(GF163.monomial(81) * GF163.monomial(81), GF163.monomial(162))
    }

    // x^163 ≡ x^7 + x^6 + x^3 + 1   (the reduction polynomial, rearranged)
    func test_reductionOfX163() {
        XCTAssertEqual(GF163.monomial(82) * GF163.monomial(81), g([7, 6, 3, 0]))
    }

    // x^164 = x·x^163 ≡ x^8 + x^7 + x^4 + x
    func test_reductionOfX164ViaSquaring() {
        XCTAssertEqual(GF163.monomial(82).squared(), g([8, 7, 4, 1]))
    }

    func test_squaringMatchesSelfMultiply() {
        XCTAssertEqual(sampleA.squared(), sampleA * sampleA)
        XCTAssertEqual(sampleB.squared(), sampleB * sampleB)
    }

    // x⁻¹ = x^162 + x^6 + x^5 + x^2  (since x·(that) ≡ 1 mod f)
    func test_inverseOfXIsKnownPolynomial() {
        XCTAssertEqual(GF163.monomial(1).inverse(), g([162, 6, 5, 2]))
    }

    func test_inverseTimesSelfIsOne() {
        XCTAssertEqual(sampleA * sampleA.inverse(), .one)
        XCTAssertEqual(sampleB * sampleB.inverse(), .one)
        XCTAssertEqual(GF163.monomial(1) * GF163.monomial(1).inverse(), .one)
    }

    func test_distributivity() {
        XCTAssertEqual(sampleA * (sampleB + GF163.one),
                       sampleA * sampleB + sampleA)
    }
}
