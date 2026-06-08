import Foundation
import CommonCrypto

/// AES-128 in ECB mode (no IV, no padding) — the block cipher the Huami2021 BLE
/// auth handshake uses to encrypt a single 16-byte random challenge.
///
/// ECB is acceptable *only* because each call encrypts one independent 16-byte
/// block; never use it for multi-block application data.
public enum AESECB {
    public static func encrypt(_ data: Data, key: Data) -> Data? {
        crypt(data, key: key, operation: CCOperation(kCCEncrypt))
    }

    public static func decrypt(_ data: Data, key: Data) -> Data? {
        crypt(data, key: key, operation: CCOperation(kCCDecrypt))
    }

    private static func crypt(_ data: Data, key: Data, operation: CCOperation) -> Data? {
        guard key.count == kCCKeySizeAES128, !data.isEmpty,
              data.count % kCCBlockSizeAES128 == 0 else { return nil }

        var output = Data(count: data.count)
        var moved = 0
        let status = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                            keyBytes.baseAddress, key.count,
                            nil,                                   // ECB: no IV
                            input.baseAddress, data.count,
                            out.baseAddress, out.count, &moved)
                }
            }
        }
        guard status == kCCSuccess, moved == data.count else { return nil }
        return output
    }
}
