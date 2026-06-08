import XCTest
@testable import HelioCore

final class Huami2021ChunkedTests: XCTestCase {
    private func roundTrip(type: UInt16, handle: UInt8, payload: [UInt8],
                           mtu: Int, extended: Bool) -> (type: UInt16, payload: [UInt8])? {
        let chunks = Huami2021Chunked.encode(type: type, handle: handle, payload: payload,
                                             mtu: mtu, extendedFlags: extended)
        var decoder = Huami2021Chunked.Decoder(extendedFlags: extended)
        var result: (type: UInt16, payload: [UInt8])?
        for chunk in chunks { result = decoder.receive(chunk) }
        return result
    }

    func test_singleChunkRoundTrip() {
        let payload: [UInt8] = [0xAA, 0xBB, 0xCC]
        let out = roundTrip(type: 0x0082, handle: 0x01, payload: payload, mtu: 247, extended: false)
        XCTAssertEqual(out?.type, 0x0082)
        XCTAssertEqual(out?.payload, payload)
    }

    func test_multiChunkRoundTripAtMinimumMTU() {
        // 100 bytes over the 23-byte BLE minimum MTU forces several chunks.
        let payload = (0..<100).map { UInt8($0) }
        let chunks = Huami2021Chunked.encode(type: 0x1234, handle: 0x82, payload: payload, mtu: 23)
        XCTAssertGreaterThan(chunks.count, 1)
        let out = roundTrip(type: 0x1234, handle: 0x82, payload: payload, mtu: 23, extended: false)
        XCTAssertEqual(out?.type, 0x1234)
        XCTAssertEqual(out?.payload, payload)
    }

    func test_firstChunkCarriesLengthAndType() {
        let payload = (0..<40).map { UInt8($0) }
        let chunks = Huami2021Chunked.encode(type: 0xABCD, handle: 0x05, payload: payload, mtu: 23)
        let first = chunks[0]
        XCTAssertEqual(first[0], 0x03)
        XCTAssertEqual(first[1] & 0x01, 0x01)                 // first-chunk flag
        XCTAssertEqual(first[2], 0x05)                        // handle
        XCTAssertEqual(first[3], 0x00)                        // count 0
        XCTAssertEqual(Int(first[4]) | Int(first[5]) << 8, 40)  // length LE
        XCTAssertEqual(UInt16(first[8]) | UInt16(first[9]) << 8, 0xABCD)  // type LE
        XCTAssertEqual(chunks.last![1] & 0x06, 0x06)          // last-chunk flag
    }

    func test_emptyPayloadProducesOneChunk() {
        let chunks = Huami2021Chunked.encode(type: 0x0001, handle: 0x01, payload: [], mtu: 23)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0][1], 0x07)                    // first | last
        let out = roundTrip(type: 0x0001, handle: 0x01, payload: [], mtu: 23, extended: false)
        XCTAssertEqual(out?.payload, [])
    }

    func test_extendedHeaderRoundTrip() {
        let payload = (0..<60).map { UInt8(($0 * 7) & 0xff) }
        let out = roundTrip(type: 0x0010, handle: 0x82, payload: payload, mtu: 23, extended: true)
        XCTAssertEqual(out?.type, 0x0010)
        XCTAssertEqual(out?.payload, payload)
    }
}
