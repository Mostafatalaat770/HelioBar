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
        case startDate(expectedBytes: Int, success: Bool, startDate: Date?)
        case fetchData(success: Bool, crc32: UInt32?)
        case ackAcknowledged
        case unknown
    }

    /// Parse the 8-byte MINUTES-precision date the device echoes in the start
    /// response: year(LE) · month · day · hour · minute · 0 · tz(quarter-hours).
    public static func parseMinutesDate(_ b: [UInt8]) -> Date? {
        guard b.count >= 8 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: Int(Int8(bitPattern: b[7])) * 900) ?? .gmt
        var c = DateComponents()
        c.year = Int(b[0]) | Int(b[1]) << 8
        c.month = Int(b[2]); c.day = Int(b[3]); c.hour = Int(b[4]); c.minute = Int(b[5])
        return cal.date(from: c)
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
            let start = bytes.count >= 15 ? parseMinutesDate(Array(bytes[7..<15])) : nil
            return .startDate(expectedBytes: len, success: ok, startDate: start)
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
        return stride(from: 0, to: buffer.count, by: 6).map { i in
            RestingHRSample(date: u32Date(buffer, i),
                            hr: Int(buffer[i + 5]),
                            utcOffsetQuarterHours: Int(Int8(bitPattern: buffer[i + 4])))
        }
    }

    public struct Spo2Sample: Equatable {
        public let date: Date
        public let spo2: Int
        public let automatic: Bool
    }

    /// SpO2: 1 version byte (=2), then 65-byte records `[ts u32][spo2 i8: <0 ⇒
    /// +128 = automatic][60 unused]`.
    public static func parseSpo2(_ buffer: [UInt8]) -> [Spo2Sample]? {
        guard buffer.count >= 1, (buffer.count - 1) % 65 == 0, buffer[0] == 2 else { return nil }
        return stride(from: 1, to: buffer.count, by: 65).map { i in
            let raw = Int8(bitPattern: buffer[i + 4])
            return Spo2Sample(date: u32Date(buffer, i),
                              spo2: Int(raw < 0 ? Int(raw) + 128 : Int(raw)),
                              automatic: raw < 0)
        }
    }

    public struct RespiratoryRateSample: Equatable {
        public let date: Date
        public let rate: Int
        public let utcOffsetQuarterHours: Int
    }

    /// Sleep respiratory rate: 8-byte records `[ts u32][tz i8][rate u8][_][_]`.
    public static func parseRespiratoryRate(_ buffer: [UInt8]) -> [RespiratoryRateSample]? {
        guard buffer.count % 8 == 0 else { return nil }
        return stride(from: 0, to: buffer.count, by: 8).map { i in
            RespiratoryRateSample(date: u32Date(buffer, i),
                                  rate: Int(buffer[i + 5]),
                                  utcOffsetQuarterHours: Int(Int8(bitPattern: buffer[i + 4])))
        }
    }

    public struct StressSample: Equatable {
        public let date: Date
        public let stress: Int
    }

    /// Automatic stress: one byte per minute starting at `since`; `0xFF` = a gap
    /// (no measurement) that still advances the clock.
    public static func parseStress(_ buffer: [UInt8], since: Date) -> [StressSample] {
        var out: [StressSample] = []
        var time = since
        for b in buffer {
            if b != 0xFF { out.append(StressSample(date: time, stress: Int(b))) }
            time.addTimeInterval(60)
        }
        return out
    }

    private static func u32Date(_ b: [UInt8], _ i: Int) -> Date {
        let ts = UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }
}
