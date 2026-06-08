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
let authEndpoint: UInt16 = 0x0082

func log(_ s: String) { print(s); fflush(stdout) }
func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined() }

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
    private var notifyRequested = false
    private var handshakeStarted = false
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
        }
        if let r = readChar, writeChar != nil, !notifyRequested {
            notifyRequested = true
            p.setNotifyValue(true, for: r)   // wait for confirmation before sending
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == chunkedRead, ch.isNotifying, !handshakeStarted else { return }
        handshakeStarted = true
        mtu = p.maximumWriteValueLength(for: .withoutResponse) + 3   // negotiated by now
        log("Notify on (write MTU \(mtu)). Sending our public key…")
        send(payload: auth.sendPublicKeyPayload())
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
        log("← \(hex(bytes))")
        guard let (type, payload) = decoder.receive(bytes), type == authEndpoint else { return }
        switch auth.handle(payload) {
        case .sendConfirmation(let reply):
            log("Got remote key — sending confirmation…"); send(payload: reply)
        case .authenticated:
            log("\n✅ AUTH OK — handshake succeeded. Path B is real."); exit(0)
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
