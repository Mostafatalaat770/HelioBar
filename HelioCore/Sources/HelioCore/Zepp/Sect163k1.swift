import Foundation

/// A point on sect163k1, affine or the point at infinity.
public struct ECPoint: Equatable, Sendable {
    var isInfinity: Bool
    var x: GF163
    var y: GF163

    static let infinity = ECPoint(isInfinity: true, x: .zero, y: .zero)
    init(isInfinity: Bool, x: GF163, y: GF163) { self.isInfinity = isInfinity; self.x = x; self.y = y }
    init(x: GF163, y: GF163) { self.init(isInfinity: false, x: x, y: y) }
}

/// The Koblitz curve sect163k1 (NIST K-163): y² + xy = x³ + ax² + b over
/// GF(2^163), with a = b = 1. This is the curve the Huami2021 BLE handshake uses
/// for its ECDH key agreement. SEC2 domain parameters baked in below.
public enum Sect163k1 {
    static let a = GF163.one          // curve coefficient a = 1
    // Base point G (SEC2 sect163k1), stored as little-endian 64-bit limbs.
    static let G = ECPoint(
        x: GF163([0xDE4E_6D5E_5C94_EEE8, 0x7BBC_11AC_AA07_D793, 0x0000_0002_FE13_C053]),
        y: GF163([0x0536_D538_CCDA_A3D9, 0x5D38_FF58_321F_2E80, 0x0000_0002_8907_0FB0]))
    // Group order n = 0x04000000000000000000020108A2E0CC0D99F8A5EF.
    static let order: [UInt64] = [0xA2E0_CC0D_99F8_A5EF, 0x0000_0000_0002_0108, 0x0000_0004_0000_0000]

    /// P + Q on the curve.
    static func add(_ p: ECPoint, _ q: ECPoint) -> ECPoint {
        if p.isInfinity { return q }
        if q.isInfinity { return p }
        if p.x == q.x {
            if p.y == q.y { return double(p) }   // P == Q
            return .infinity                      // P == −Q
        }
        let s = (p.y + q.y) * (p.x + q.x).inverse()
        let x3 = s.squared() + s + p.x + q.x + a
        let y3 = s * (p.x + x3) + x3 + p.y
        return ECPoint(x: x3, y: y3)
    }

    /// 2P on the curve.
    static func double(_ p: ECPoint) -> ECPoint {
        if p.isInfinity || p.x.isZero { return .infinity }   // x = 0 is 2-torsion
        let s = p.x + p.y * p.x.inverse()                    // s = x + y/x
        let x3 = s.squared() + s + a
        let y3 = p.x.squared() + (s + .one) * x3
        return ECPoint(x: x3, y: y3)
    }

    /// Scalar multiple k·P via double-and-add over the scalar's 163 bits.
    static func scalarMul(_ k: [UInt64], _ p: ECPoint) -> ECPoint {
        var result = ECPoint.infinity
        for i in stride(from: 162, through: 0, by: -1) {
            result = double(result)
            if (k[i >> 6] >> UInt64(i & 63)) & 1 == 1 { result = add(result, p) }
        }
        return result
    }

    /// Whether P satisfies the curve equation (or is infinity).
    static func isOnCurve(_ p: ECPoint) -> Bool {
        if p.isInfinity { return true }
        let lhs = p.y.squared() + p.x * p.y                       // y² + xy
        let rhs = p.x * p.x.squared() + a * p.x.squared() + .one  // x³ + ax² + b
        return lhs == rhs
    }

    /// ECDH shared secret: the x-coordinate of (privateScalar · peerPublic).
    static func sharedSecretX(privateScalar: [UInt64], peerPublic: ECPoint) -> GF163 {
        scalarMul(privateScalar, peerPublic).x
    }
}
