import Foundation
import CoreBluetooth
import HelioCore

// ZeppSpike — drives the Huami2021 ECDH auth handshake against the Helio Strap
// using the verified HelioCore crypto. Prints a verbose trace; on success the
// strap is authenticated (proving the whole Path-B stack end to end).
//
// The 16-byte auth key comes from the KEY environment variable (the run script
// exports it from .env). Run via: ./scripts/zepp-spike.sh

let authService = CBUUID(string: "FEE1")
let hrService = CBUUID(string: "180D")
let chunkedWrite = CBUUID(string: "00000016-0000-3512-2118-0009AF100700")
let chunkedRead = CBUUID(string: "00000017-0000-3512-2118-0009AF100700")
let fetchControl = CBUUID(string: "00000004-0000-3512-2118-0009AF100700")
let fetchData = CBUUID(string: "00000005-0000-3512-2118-0009AF100700")
let authEndpoint: UInt16 = 0x0082

func log(_ s: String) { print(s); fflush(stdout) }
func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined() }

let metricName = (ProcessInfo.processInfo.environment["METRIC"] ?? "restinghr").lowercased()
func metricType(_ name: String) -> (type: UInt8, label: String) {
    switch name {
    case "spo2":               return (HuamiActivityFetch.typeSpo2, "SpO2")
    case "stress":             return (HuamiActivityFetch.typeStressAuto, "stress")
    case "respiratory", "resp": return (HuamiActivityFetch.typeRespiratoryRate, "respiratory rate")
    case "activity":           return (HuamiActivityFetch.typeActivity, "activity (HR + sleep stages)")
    default:                   return (HuamiActivityFetch.typeRestingHeartRate, "resting HR")
    }
}

func loadAuthKey() -> [UInt8]? {
    var raw: String?
    if let env = ProcessInfo.processInfo.environment["KEY"] { raw = env }
    else if let file = try? String(contentsOfFile: ".env", encoding: .utf8) {
        raw = file.split(separator: "\n").first { $0.hasPrefix("KEY=") }.map { String($0.dropFirst(4)) }
    }
    guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
    if s.hasPrefix("0x") || s.hasPrefix("0X") { s = String(s.dropFirst(2)) }
    let nibbles = s.compactMap { $0.hexDigitValue }   // drops quotes/CR/colons/spaces
    log("Auth key: \(nibbles.count) hex digits parsed (expect 32)")
    guard nibbles.count == 32 else { return nil }
    return stride(from: 0, to: 32, by: 2).map { UInt8(nibbles[$0] << 4 | nibbles[$0 + 1]) }
}

final class Spike: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var readChar: CBCharacteristic?
    private var controlChar: CBCharacteristic?
    private var dataChar: CBCharacteristic?
    private var notifyRequested = false
    private var handshakeStarted = false
    private var fetchControlReady = false
    private var fetchDataReady = false
    private var fetchStarted = false
    private var fetchBuffer: [UInt8] = []
    private var lastCounter = -1
    private var fetchStartDate: Date?
    private let auth: HuamiAuth
    private var decoder = Huami2021Chunked.Decoder(extendedFlags: true)
    private var writeHandle: UInt8 = 0
    private var mtu = 23

    init(authKey: [UInt8]) {
        let privateKey = (0..<24).map { _ in UInt8.random(in: 0...255) }
        auth = HuamiAuth(authKey: authKey, privateKey: privateKey)
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn {
            log("Scanning for the strap…"); c.scanForPeripherals(withServices: [hrService])
        } else { log("Bluetooth not available: \(c.state.rawValue)"); exit(2) }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        log("Found \(p.name ?? "device") — connecting"); peripheral = p; p.delegate = self
        c.stopScan(); c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        log("Connected. Discovering all services…")
        p.discoverServices(nil)          // chunked chars may be under FEE0, not FEE1
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == chunkedWrite { writeChar = ch; log("Found 0x0016 (write) under \(s.uuid)") }
            if ch.uuid == chunkedRead { readChar = ch; log("Found 0x0017 (notify) under \(s.uuid)") }
            if ch.uuid == fetchControl { controlChar = ch }
            if ch.uuid == fetchData { dataChar = ch }
        }
        if let r = readChar, writeChar != nil, !notifyRequested {
            notifyRequested = true
            p.setNotifyValue(true, for: r)   // wait for confirmation before sending
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if ch.uuid == chunkedRead, ch.isNotifying, !handshakeStarted {
            handshakeStarted = true
            mtu = p.maximumWriteValueLength(for: .withoutResponse) + 3   // negotiated by now
            log("Notify on (write MTU \(mtu)). Sending our public key…")
            send(payload: auth.sendPublicKeyPayload())
        }
        if ch.uuid == fetchControl, ch.isNotifying { fetchControlReady = true }
        if ch.uuid == fetchData, ch.isNotifying { fetchDataReady = true }
        if fetchControlReady, fetchDataReady, !fetchStarted { startFetch() }
    }

    private func startFetch() {
        guard let p = peripheral, let ctrl = controlChar else { log("fetch control char missing"); exit(1) }
        fetchStarted = true
        fetchBuffer = []; lastCounter = -1
        let days = metricName == "activity" ? 2.0 : 100.0   // activity is per-minute → huge
        let since = Date(timeIntervalSinceNow: -days * 24 * 3600)
        let metric = metricType(metricName)
        let cmd = HuamiActivityFetch.startCommand(dataType: metric.type, since: since, timeZone: .current)
        log("Authenticated. Fetching \(metric.label) (last 100 days)…\n→ ctrl \(hex(cmd))")
        p.writeValue(Data(cmd), for: ctrl, type: .withoutResponse)
    }

    private func ctrlWrite(_ bytes: [UInt8]) {
        guard let p = peripheral, let ctrl = controlChar else { return }
        log("→ ctrl \(hex(bytes))")
        p.writeValue(Data(bytes), for: ctrl, type: .withoutResponse)
    }

    private func onControl(_ bytes: [UInt8]) {
        log("← ctrl \(hex(bytes))")
        switch HuamiActivityFetch.parseControl(bytes) {
        case .startDate(let expected, let ok, let start):
            guard ok else { log("❌ start-date rejected"); exit(1) }
            fetchStartDate = start
            if expected == 0 { log("No \(metricType(metricName).label) data in range."); ctrlWrite(HuamiActivityFetch.ackCommand(keepOnDevice: true)); return }
            log("Expecting \(expected) bytes. Requesting data…")
            ctrlWrite(HuamiActivityFetch.fetchDataCommand())
        case .fetchData(let ok, let crc):
            guard ok else { log("❌ fetch rejected"); exit(1) }
            if let crc {
                let ours = CRC32.checksum(fetchBuffer[...])
                log("CRC \(crc == ours ? "OK" : "MISMATCH (device \(crc), ours \(ours))")")
            }
            printSamples()
            ctrlWrite(HuamiActivityFetch.ackCommand(keepOnDevice: true))
        case .ackAcknowledged:
            log("\n🎉 Fetch complete — real biometric data, fully local."); exit(0)
        case .unknown:
            log("Unhandled control: \(hex(bytes))")
        }
    }

    private func printSamples() {
        let buf = fetchBuffer
        switch metricName {
        case "spo2":
            guard let s = HuamiActivityFetch.parseSpo2(buf) else { return badBuffer() }
            logSamples(s.map { "\($0.date) — \($0.spo2)%\($0.automatic ? " (auto)" : "")" })
        case "stress":
            let s = HuamiActivityFetch.parseStress(buf, since: fetchStartDate ?? Date(timeIntervalSinceNow: -100 * 24 * 3600))
            logSamples(s.map { "\($0.date) — stress \($0.stress)" })
        case "respiratory", "resp":
            guard let s = HuamiActivityFetch.parseRespiratoryRate(buf) else { return badBuffer() }
            logSamples(s.map { "\($0.date) — \($0.rate) br/min" })
        case "activity":
            guard let s = HuamiActivityFetch.parseActivity(buf) else { return badBuffer() }
            let start = fetchStartDate ?? Date()
            let withHR = s.enumerated().filter { $0.element.heartRate > 0 }
            let sleepMins = s.filter { $0.sleep > 0 || $0.deepSleep > 0 || $0.remSleep > 0 }.count
            log("\n✅ \(s.count) activity minutes — \(withHR.count) with HR, \(sleepMins) sleep-stage minutes (last 12):")
            for (i, sample) in withHR.suffix(12) {
                let t = start.addingTimeInterval(Double(i) * 60)
                let stage = sample.deepSleep > 0 ? "deep" : sample.remSleep > 0 ? "REM" : sample.sleep > 0 ? "light" : "awake"
                log("  \(t) — \(sample.heartRate) bpm · \(stage) · \(sample.steps) steps")
            }
        default:
            guard let s = HuamiActivityFetch.parseRestingHR(buf) else { return badBuffer() }
            logSamples(s.map { "\($0.date) — \($0.hr) bpm" })
        }
    }

    private func logSamples(_ lines: [String]) {
        log("\n✅ \(lines.count) \(metricType(metricName).label) samples (showing last 10):")
        for line in lines.suffix(10) { log("  \(line)") }
    }

    private func badBuffer() { log("⚠️ \(fetchBuffer.count) bytes — unexpected format for \(metricName)") }

    private func onData(_ bytes: [UInt8]) {
        guard let counter = bytes.first else { return }
        if UInt8((lastCounter + 1) & 0xff) == counter {
            lastCounter += 1
            fetchBuffer.append(contentsOf: bytes.dropFirst())
        } else {
            log("⚠️ bad packet counter \(counter), expected \((lastCounter + 1) & 0xff)")
        }
    }

    private func send(payload: [UInt8]) {
        guard let p = peripheral, let ch = writeChar else { return }
        writeHandle &+= 1
        let chunks = Huami2021Chunked.encode(type: authEndpoint, handle: writeHandle,
                                             payload: payload, mtu: mtu, extendedFlags: true)
        for chunk in chunks {
            log("→ \(hex(chunk))")
            p.writeValue(Data(chunk), for: ch, type: .withoutResponse)
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let data = ch.value else { return }
        let bytes = [UInt8](data)
        switch ch.uuid {
        case fetchControl: onControl(bytes); return
        case fetchData: onData(bytes); return
        default: break
        }
        log("← \(hex(bytes))")
        guard let (type, payload) = decoder.receive(bytes), type == authEndpoint else { return }
        switch auth.handle(payload) {
        case .sendConfirmation(let reply):
            log("Got remote key — sending confirmation…"); send(payload: reply)
        case .authenticated:
            log("\n✅ AUTH OK — handshake succeeded. Path B is real.")
            guard let ctrl = controlChar, let dat = dataChar else {
                log("fetch chars 0x0004/0x0005 missing"); exit(1)
            }
            p.setNotifyValue(true, for: dat)
            p.setNotifyValue(true, for: ctrl)   // startFetch() fires once both are on
        case .failed(let why):
            log("\n❌ \(why)"); exit(1)
        }
    }
}

guard let key = loadAuthKey() else {
    log("No 16-byte KEY found (set KEY env var or .env). Got nothing usable."); exit(2)
}
log("Auth key loaded (\(key.count) bytes). Put on the strap; make sure Zepp is closed.")
let spike = Spike(authKey: key)
withExtendedLifetime(spike) { RunLoop.main.run() }
