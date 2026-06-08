import Foundation

/// A point on the B-163 curve, affine or the point at infinity.
public struct ECPoint: Equatable, Sendable {
    var isInfinity: Bool
    var x: GF163
    var y: GF163

    static let infinity = ECPoint(isInfinity: true, x: .zero, y: .zero)
    init(isInfinity: Bool, x: GF163, y: GF163) { self.isInfinity = isInfinity; self.x = x; self.y = y }
    init(x: GF163, y: GF163) { self.init(isInfinity: false, x: x, y: y) }
}

/// Binary curve **B-163 / sect163r2**: y² + xy = x³ + ax² + b over GF(2^163),
/// a = 1. This is the curve the Huami2021 BLE ECDH handshake uses — parameters
/// taken verbatim from Gadgetbridge's `ECDH_B163` (which is sect163r2, NOT the
/// Koblitz K-163/sect163k1). Keys are 24-byte little-endian scalars; public keys
/// and shared secrets are 48 bytes = x‖y, each coordinate 24-byte little-endian.
public enum B163 {
    static let a = GF163.one
    static let b = GF163([0x512F_7874_4A32_05FD, 0xB8C9_53CA_1481_EB10, 0x0000_0002_0A60_1907])
    static let G = ECPoint(
        x: GF163([0xD499_4637_E834_3E36, 0x86A2_D57E_A099_1168, 0x0000_0003_F0EB_A162]),
        y: GF163([0xB11C_5C0C_7973_24F1, 0x71A0_094F_A2CD_D545, 0x0000_0000_D51F_BC6C]))
    static let order: [UInt64] = [0x77E7_0C12_A423_4C33, 0x0000_0000_0002_92FE, 0x0000_0004_0000_0000]

    static func add(_ p: ECPoint, _ q: ECPoint) -> ECPoint {
        if p.isInfinity { return q }
        if q.isInfinity { return p }
        if p.x == q.x {
            if p.y == q.y { return double(p) }
            return .infinity
        }
        let s = (p.y + q.y) * (p.x + q.x).inverse()
        let x3 = s.squared() + s + p.x + q.x + a
        let y3 = s * (p.x + x3) + x3 + p.y
        return ECPoint(x: x3, y: y3)
    }

    static func double(_ p: ECPoint) -> ECPoint {
        if p.isInfinity || p.x.isZero { return .infinity }
        let s = p.x + p.y * p.x.inverse()
        let x3 = s.squared() + s + a
        let y3 = p.x.squared() + (s + .one) * x3
        return ECPoint(x: x3, y: y3)
    }

    /// k·P. The scalar is up to 192 bits (24-byte keys are not reduced mod n).
    static func scalarMul(_ k: [UInt64], _ p: ECPoint) -> ECPoint {
        var result = ECPoint.infinity
        for i in stride(from: 191, through: 0, by: -1) {
            result = double(result)
            if (k[i >> 6] >> UInt64(i & 63)) & 1 == 1 { result = add(result, p) }
        }
        return result
    }

    static func isOnCurve(_ p: ECPoint) -> Bool {
        if p.isInfinity { return true }
        let lhs = p.y.squared() + p.x * p.y
        let rhs = p.x * p.x.squared() + a * p.x.squared() + b
        return lhs == rhs
    }

    // MARK: - byte (de)serialization matching ECDH_B163

    /// 24 little-endian bytes → three 64-bit limbs (no field masking; scalars use
    /// the full 192 bits).
    static func scalar(fromLE bytes: ArraySlice<UInt8>) -> [UInt64] {
        var w = [UInt64](repeating: 0, count: 3)
        let start = bytes.startIndex
        for i in 0..<Swift.min(24, bytes.count) {
            w[i >> 3] |= UInt64(bytes[start + i]) << UInt64((i & 7) * 8)
        }
        return w
    }

    static func gf(fromLE bytes: ArraySlice<UInt8>) -> GF163 {
        let w = scalar(fromLE: bytes)
        return GF163([w[0], w[1], w[2] & 0x7_FFFF_FFFF])
    }

    static func leBytes(_ e: GF163) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 24)
        for limb in 0..<3 {
            for byte in 0..<8 {
                out[limb * 8 + byte] = UInt8((e.limbs[limb] >> UInt64(byte * 8)) & 0xff)
            }
        }
        return out
    }

    // MARK: - ECDH (mirrors ECDH_B163.ecdh_generate_public / _shared)

    /// Public key (48 bytes, x‖y little-endian) for a 24-byte private scalar.
    public static func publicKey(privateKey: [UInt8]) -> [UInt8] {
        let q = scalarMul(scalar(fromLE: privateKey[...]), G)
        return leBytes(q.x) + leBytes(q.y)
    }

    /// Shared point (48 bytes, x‖y) = privateKey · remotePublic.
    public static func sharedSecret(privateKey: [UInt8], remotePublic: [UInt8]) -> [UInt8] {
        let rx = gf(fromLE: remotePublic[0..<24])
        let ry = gf(fromLE: remotePublic[24..<48])
        let p = scalarMul(scalar(fromLE: privateKey[...]), ECPoint(x: rx, y: ry))
        return leBytes(p.x) + leBytes(p.y)
    }
}
