import Foundation

/// Arithmetic in the binary field GF(2^163) used by the sect163k1 curve (the
/// curve behind the Huami2021 BLE auth handshake). Reduction polynomial:
///   f(x) = x^163 + x^7 + x^6 + x^3 + 1
///
/// Elements are 163-bit polynomials held in three little-endian 64-bit limbs
/// (bits 128..162 occupy the low 35 bits of limb 2). Addition is XOR.
public struct GF163: Equatable, Sendable {
    var limbs: [UInt64]   // count 3

    init() { limbs = [0, 0, 0] }
    init(_ limbs: [UInt64]) { precondition(limbs.count == 3); self.limbs = limbs }

    public static let zero = GF163()
    public static let one = GF163([1, 0, 0])

    /// The monomial x^i (0 ≤ i ≤ 162).
    static func monomial(_ i: Int) -> GF163 {
        var e = GF163()
        e.limbs[i >> 6] |= (1 << UInt64(i & 63))
        return e
    }

    func testBit(_ i: Int) -> Bool { (limbs[i >> 6] >> UInt64(i & 63)) & 1 == 1 }
    var isZero: Bool { limbs[0] == 0 && limbs[1] == 0 && limbs[2] == 0 }

    public static func + (l: GF163, r: GF163) -> GF163 {
        GF163([l.limbs[0] ^ r.limbs[0], l.limbs[1] ^ r.limbs[1], l.limbs[2] ^ r.limbs[2]])
    }

    public static func * (x: GF163, y: GF163) -> GF163 {
        // Carry-less product into a 384-bit (6-limb) accumulator via Horner over
        // the bits of x (high to low: acc = acc·t + x_i·y), then reduce mod f.
        var acc = [UInt64](repeating: 0, count: 6)
        for i in stride(from: 162, through: 0, by: -1) {
            shiftLeft1(&acc)
            if x.testBit(i) {
                acc[0] ^= y.limbs[0]; acc[1] ^= y.limbs[1]; acc[2] ^= y.limbs[2]
            }
        }
        return reduce(acc)
    }

    /// Squaring spreads each bit i to bit 2i (linear in GF(2^m)), then reduces.
    func squared() -> GF163 {
        var acc = [UInt64](repeating: 0, count: 6)
        for i in 0..<163 where testBit(i) {
            let p = 2 * i
            acc[p >> 6] |= (1 << UInt64(p & 63))
        }
        return GF163.reduce(acc)
    }

    /// Multiplicative inverse via Fermat: a^(2^163 − 2). Undefined for zero.
    func inverse() -> GF163 {
        // exponent 2^163 − 2 has bits 1...162 set, bit 0 clear.
        var result = GF163.one
        var base = self
        for i in 0..<163 {
            if i >= 1 { result = result * base }
            base = base.squared()
        }
        return result
    }

    // MARK: - internals

    /// acc <<= 1 across 6 limbs (low-to-high limb order).
    private static func shiftLeft1(_ acc: inout [UInt64]) {
        for j in stride(from: 5, through: 1, by: -1) {
            acc[j] = (acc[j] << 1) | (acc[j - 1] >> 63)
        }
        acc[0] <<= 1
    }

    /// Reduce a 6-limb (≤325-bit) value mod f. For each set bit p ≥ 163,
    /// x^p ≡ x^(p−156) + x^(p−157) + x^(p−160) + x^(p−163); fold high→low so
    /// reductions that land back in [163, p) are themselves reduced.
    private static func reduce(_ value: [UInt64]) -> GF163 {
        var t = value
        for p in stride(from: 324, through: 163, by: -1) where (t[p >> 6] >> UInt64(p & 63)) & 1 == 1 {
            t[p >> 6] ^= (1 << UInt64(p & 63))                     // clear bit p
            for q in [p - 156, p - 157, p - 160, p - 163] {        // fold the reduction
                t[q >> 6] ^= (1 << UInt64(q & 63))
            }
        }
        return GF163([t[0], t[1], t[2] & 0x7_FFFF_FFFF])           // mask bits 128..162
    }
}
