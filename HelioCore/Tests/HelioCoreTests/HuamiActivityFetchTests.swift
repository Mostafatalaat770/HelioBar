import XCTest
@testable import HelioCore

final class HuamiActivityFetchTests: XCTestCase {
    func test_startCommandLayout() {
        let tz = TimeZone(identifier: "UTC")!
        let since = Date(timeIntervalSince1970: 1_700_000_000)   // fixed
        let cmd = HuamiActivityFetch.startCommand(dataType: HuamiActivityFetch.typeRestingHeartRate,
                                                  since: since, timeZone: tz)
        XCTAssertEqual(cmd.count, 10)
        XCTAssertEqual(cmd[0], 0x01)                              // START_DATE
        XCTAssertEqual(cmd[1], 0x3a)                              // RESTING_HEART_RATE
        XCTAssertEqual(cmd[9], 0x00)                              // UTC tz = 0 quarter-hours
    }

    func test_timeBytesEncodesYearLittleEndianAndTz() {
        // 2023-11-14 22:13 UTC
        let bytes = HuamiActivityFetch.minutesTimeBytes(since: Date(timeIntervalSince1970: 1_700_000_000),
                                                        timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(bytes.count, 8)
        XCTAssertEqual(Int(bytes[0]) | Int(bytes[1]) << 8, 2023) // year LE
        XCTAssertEqual(bytes[2], 11)                             // month (1-based)
        XCTAssertEqual(bytes[7], 0)                              // UTC → 0
    }

    func test_fetchAndAckCommands() {
        XCTAssertEqual(HuamiActivityFetch.fetchDataCommand(), [0x02])
        XCTAssertEqual(HuamiActivityFetch.ackCommand(keepOnDevice: true), [0x03, 0x09])
        XCTAssertEqual(HuamiActivityFetch.ackCommand(keepOnDevice: false), [0x03, 0x01])
    }

    func test_parseControlResponses() {
        // start-date: 0x10 0x01 0x01, len=12 (LE), then 8 date bytes
        let start: [UInt8] = [0x10, 0x01, 0x01, 0x0C, 0, 0, 0,  0xE7, 0x07, 11, 14, 22, 13, 0, 0]
        XCTAssertEqual(HuamiActivityFetch.parseControl(start), .startDate(expectedBytes: 12, success: true))

        // fetch response with CRC
        let fetch: [UInt8] = [0x10, 0x02, 0x01, 0x26, 0x39, 0xF4, 0xCB]
        XCTAssertEqual(HuamiActivityFetch.parseControl(fetch),
                       .fetchData(success: true, crc32: 0xCBF4_3926))

        XCTAssertEqual(HuamiActivityFetch.parseControl([0x10, 0x03, 0x01]), .ackAcknowledged)
    }

    func test_parseRestingHRRecords() {
        // two 6-byte records: ts=1700000000, tz=0, hr=58 ; ts=1700086400, tz=4, hr=61
        var buf: [UInt8] = []
        func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)] }
        buf += le32(1_700_000_000) + [0, 58]
        buf += le32(1_700_086_400) + [4, 61]

        let samples = HuamiActivityFetch.parseRestingHR(buf)
        XCTAssertEqual(samples?.count, 2)
        XCTAssertEqual(samples?[0].hr, 58)
        XCTAssertEqual(samples?[0].date, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(samples?[1].hr, 61)
        XCTAssertEqual(samples?[1].utcOffsetQuarterHours, 4)

        XCTAssertNil(HuamiActivityFetch.parseRestingHR([1, 2, 3]))   // not a multiple of 6
    }
}
