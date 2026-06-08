import Foundation

/// Drives the Huami2021 ECDH auth handshake, ported from Gadgetbridge's
/// `InitOperation2021`. Pure logic — it produces the bytes to send and
/// interprets the device's replies; the BLE I/O and chunked framing live in the
/// caller. All messages go over the AUTH endpoint (chunked type 0x0082).
public final class HuamiAuth {
    public enum Outcome: Equatable {
        case sendConfirmation([UInt8])   // AUTH payload to write back
        case authenticated
        case failed(String)
    }

    static let response: UInt8 = 0x10    // HuamiService.RESPONSE
    static let success: UInt8 = 0x01     // HuamiService.SUCCESS

    private let authKey: [UInt8]         // 16-byte secret from huami-token
    private let privateKey: [UInt8]      // 24-byte random scalar
    public private(set) var sessionKey: [UInt8] = []
    public private(set) var sequenceNumber: UInt32 = 0

    public init(authKey: [UInt8], privateKey: [UInt8]) {
        self.authKey = authKey
        self.privateKey = privateKey
    }

    /// First AUTH message: `04 02 00 02` + our 48-byte public key.
    public func sendPublicKeyPayload() -> [UInt8] {
        [0x04, 0x02, 0x00, 0x02] + B163.publicKey(privateKey: privateKey)
    }

    /// Interpret an incoming AUTH-endpoint payload and decide the next step.
    public func handle(_ payload: [UInt8]) -> Outcome {
        guard payload.count >= 3, payload[0] == Self.response else {
            return .failed("unexpected auth payload")
        }
        switch (payload[1], payload[2]) {
        case (0x04, Self.success):
            // remote random (16 bytes) + remote public key (48 bytes)
            guard payload.count >= 67 else { return .failed("short key response") }
            let remoteRandom = Array(payload[3 ..< 19])
            let remotePublic = Array(payload[19 ..< 67])
            let shared = B163.sharedSecret(privateKey: privateKey, remotePublic: remotePublic)
            sequenceNumber = UInt32(shared[0]) | UInt32(shared[1]) << 8
                | UInt32(shared[2]) << 16 | UInt32(shared[3]) << 24
            sessionKey = (0 ..< 16).map { shared[$0 + 8] ^ authKey[$0] }
            guard let enc1 = AESECB.encrypt(Data(remoteRandom), key: Data(authKey)),
                  let enc2 = AESECB.encrypt(Data(remoteRandom), key: Data(sessionKey)) else {
                return .failed("AES encryption failed")
            }
            // 0x05 + AES(remoteRandom, authKey) + AES(remoteRandom, sessionKey)
            return .sendConfirmation([0x05] + [UInt8](enc1) + [UInt8](enc2))
        case (0x05, Self.success):
            return .authenticated
        case (0x05, 0x25):
            return .failed("authentication rejected — wrong auth key?")
        default:
            return .failed("unhandled auth reply")
        }
    }
}
