import XCTest
@testable import HelioCore

final class HuamiAuthTests: XCTestCase {
    private func smallKey(_ v: UInt8) -> [UInt8] {
        var k = [UInt8](repeating: 0, count: 24); k[0] = v; return k
    }
    private let authKey = (0..<16).map { UInt8($0) }

    func test_publicKeyMessageFormat() {
        let auth = HuamiAuth(authKey: authKey, privateKey: smallKey(5))
        let msg = auth.sendPublicKeyPayload()
        XCTAssertEqual(msg.count, 52)                       // 4-byte command + 48-byte pubkey
        XCTAssertEqual(Array(msg.prefix(4)), [0x04, 0x02, 0x00, 0x02])
    }

    func test_keyResponseProducesConfirmationAndSessionKey() {
        let auth = HuamiAuth(authKey: authKey, privateKey: smallKey(5))
        let remoteRandom = (0..<16).map { UInt8(0xA0 + $0) }
        let remotePublic = B163.publicKey(privateKey: smallKey(7))
        let payload = [0x10, 0x04, 0x01].map { UInt8($0) } + remoteRandom + remotePublic

        let outcome = auth.handle(payload)
        guard case let .sendConfirmation(reply) = outcome else {
            return XCTFail("expected confirmation, got \(outcome)")
        }
        XCTAssertEqual(reply.count, 33)                     // 0x05 + two AES-128 blocks
        XCTAssertEqual(reply[0], 0x05)
        XCTAssertEqual(auth.sessionKey.count, 16)
        XCTAssertNotEqual(auth.sessionKey, Array(repeating: 0, count: 16))
    }

    func test_successAndFailureReplies() {
        let auth = HuamiAuth(authKey: authKey, privateKey: smallKey(5))
        XCTAssertEqual(auth.handle([0x10, 0x05, 0x01]), .authenticated)
        XCTAssertEqual(auth.handle([0x10, 0x05, 0x25]),
                       .failed("authentication rejected — wrong auth key?"))
        XCTAssertEqual(auth.handle([0x99, 0x00, 0x00]), .failed("unexpected auth payload"))
    }
}
