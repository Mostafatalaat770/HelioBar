import XCTest
@testable import HelioCore

final class AESECBTests: XCTestCase {
    // FIPS-197 Appendix C.1 AES-128 known-answer vector.
    private let key = Data(hex: "000102030405060708090a0b0c0d0e0f")
    private let plaintext = Data(hex: "00112233445566778899aabbccddeeff")
    private let ciphertext = Data(hex: "69c4e0d86a7b0430d8cdb78070b4c55a")

    func test_encryptMatchesKnownVector() {
        XCTAssertEqual(AESECB.encrypt(plaintext, key: key), ciphertext)
    }

    func test_decryptMatchesKnownVector() {
        XCTAssertEqual(AESECB.decrypt(ciphertext, key: key), plaintext)
    }

    func test_roundTrip() {
        let block = Data(hex: "0123456789abcdef0123456789abcdef")
        let enc = AESECB.encrypt(block, key: key)!
        XCTAssertEqual(AESECB.decrypt(enc, key: key), block)
    }

    func test_rejectsWrongKeySize() {
        XCTAssertNil(AESECB.encrypt(plaintext, key: Data(hex: "0011")))
    }

    func test_rejectsNonBlockSizedInput() {
        XCTAssertNil(AESECB.encrypt(Data(hex: "001122"), key: key))
    }
}

extension Data {
    /// Test helper: build Data from a hex string (ignores non-hex separators).
    init(hex: String) {
        var bytes = [UInt8]()
        var iter = hex.unicodeScalars.makeIterator()
        func nibble(_ s: Unicode.Scalar) -> UInt8? {
            switch s {
            case "0"..."9": return UInt8(s.value - 48)
            case "a"..."f": return UInt8(s.value - 87)
            case "A"..."F": return UInt8(s.value - 55)
            default:        return nil
            }
        }
        var high: UInt8?
        while let s = iter.next() {
            guard let n = nibble(s) else { continue }
            if let h = high { bytes.append((h << 4) | n); high = nil }
            else { high = n }
        }
        self = Data(bytes)
    }
}
