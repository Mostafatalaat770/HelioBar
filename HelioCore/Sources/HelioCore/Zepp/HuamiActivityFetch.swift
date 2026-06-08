import Foundation

/// The Huami/ZeppOS legacy activity-fetch protocol over BLE characteristics
/// 0x0004 (control) / 0x0005 (data). After auth, this is how the rich history
/// (resting HR, SpO2, stress, respiratory rate, HRV-in-activity) is read.
///
/// Flow: write `startCommand` to 0x0004 → device replies with a metadata
/// response (expected byte count + start date) → write `fetchDataCommand` →
/// device streams counter-prefixed packets over 0x0005 → device replies with a
/// fetch response (optional CRC32 over the buffer) → write `ackCommand`.
/// Commands + parsers are pure; the BLE I/O and packet counter live in the caller.
public enum HuamiActivityFetch {
    // Control commands (HuamiService)
    static let cmdStartDate: UInt8 = 0x01
    static let cmdFetchData: UInt8 = 0x02
    static let cmdAck: UInt8 = 0x03
    static let response: UInt8 = 0x10
    static let success: UInt8 = 0x01

    // Fetch data types (HuamiFetchDataType)
    public static let typeActivity: UInt8 = 0x01      // carries HRV
    public static let typeStressAuto: UInt8 = 0x13
    public static let typeSpo2: UInt8 = 0x25
    public static let typeRespiratoryRate: UInt8 = 0x38
    public static let typeRestingHeartRate: UInt8 = 0x3a

    /// 8-byte "since" timestamp (MINUTES precision, as ZeppOS fetch uses):
    /// year(LE) · month · day · hour · minute · 0 · tz(quarter-hours).
    public static func minutesTimeBytes(since date: Date, timeZone: TimeZone) -> [UInt8] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let year = c.year ?? 2000
        let tz = Int8(truncatingIfNeeded: timeZone.secondsFromGMT(for: date) / 900)
        return [UInt8(year & 0xff), UInt8((year >> 8) & 0xff),
                UInt8(c.month ?? 1), UInt8(c.day ?? 1),
                UInt8(c.hour ?? 0), UInt8(c.minute ?? 0),
                0, UInt8(bitPattern: tz)]
    }

    public static func startCommand(dataType: UInt8, since: Date, timeZone: TimeZone) -> [UInt8] {
        [cmdStartDate, dataType] + minutesTimeBytes(since: since, timeZone: timeZone)
    }

    public static func fetchDataCommand() -> [UInt8] { [cmdFetchData] }

    /// keepOnDevice: 0x09 keeps data flagged unsaved; 0x01 marks it saved (dropped).
    public static func ackCommand(keepOnDevice: Bool) -> [UInt8] {
        [cmdAck, keepOnDevice ? 0x09 : 0x01]
    }

    public enum ControlResponse: Equatable {
        case startDate(expectedBytes: Int, success: Bool)
        case fetchData(success: Bool, crc32: UInt32?)
        case ackAcknowledged
        case unknown
    }

    /// Parse a notification from the control characteristic (0x0004).
    public static func parseControl(_ bytes: [UInt8]) -> ControlResponse {
        guard bytes.count >= 3, bytes[0] == response else { return .unknown }
        switch bytes[1] {
        case cmdStartDate:
            let ok = bytes[2] == success
            let len = bytes.count >= 7
                ? Int(bytes[3]) | Int(bytes[4]) << 8 | Int(bytes[5]) << 16 | Int(bytes[6]) << 24
                : 0
            return .startDate(expectedBytes: len, success: ok)
        case cmdFetchData:
            let ok = bytes[2] == success
            let crc: UInt32? = bytes.count >= 7
                ? UInt32(bytes[3]) | UInt32(bytes[4]) << 8 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 24
                : nil
            return .fetchData(success: ok, crc32: crc)
        case cmdAck:
            return .ackAcknowledged
        default:
            return .unknown
        }
    }

    public struct RestingHRSample: Equatable {
        public let date: Date
        public let hr: Int
        public let utcOffsetQuarterHours: Int
    }

    /// Parse the assembled resting-HR buffer: 6-byte records of
    /// `[timestamp u32 LE seconds][utcOffset i8 quarter-hours][hr u8]`.
    public static func parseRestingHR(_ buffer: [UInt8]) -> [RestingHRSample]? {
        guard buffer.count % 6 == 0 else { return nil }
        var out: [RestingHRSample] = []
        var i = 0
        while i < buffer.count {
            let ts = UInt32(buffer[i]) | UInt32(buffer[i + 1]) << 8
                | UInt32(buffer[i + 2]) << 16 | UInt32(buffer[i + 3]) << 24
            let offset = Int(Int8(bitPattern: buffer[i + 4]))
            out.append(RestingHRSample(date: Date(timeIntervalSince1970: TimeInterval(ts)),
                                       hr: Int(buffer[i + 5]),
                                       utcOffsetQuarterHours: offset))
            i += 6
        }
        return out
    }
}
