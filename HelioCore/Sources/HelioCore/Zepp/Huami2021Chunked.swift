import Foundation

/// Standard IEEE CRC-32 (reflected, poly 0xEDB88320) — matches Gadgetbridge's
/// `CheckSums.getCRC32` (java.util.zip.CRC32), used in the encrypted payload.
public enum CRC32 {
    public static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}

/// The Huami2021 / ZeppOS "chunked transfer" framing over BLE characteristics
/// 0x0016 (write) and 0x0017 (read). Handles both the unencrypted path (the auth
/// exchange) and the encrypted post-auth path.
///
/// Chunk layout (extended header, 5 bytes): `[0]=0x03 [1]=flags [2]=0x00
/// [3]=writeHandle [4]=count`. First chunk then carries 4-byte LE *plaintext*
/// length + 2-byte LE message type. flags: 0x01=first, 0x06=last, 0x08=encrypted.
///
/// Encrypted payload (flag 0x08): `data + seqNo(4 LE) + CRC32(data+seqNo)(4 LE)`,
/// zero-padded to 16, AES-ECB with `messageKey[i] = sessionKey[i] ^ writeHandle`.
public enum Huami2021Chunked {
    static let startByte: UInt8 = 0x03
    static let flagFirst: UInt8 = 0x01
    static let flagLast: UInt8 = 0x06
    static let flagEncrypted: UInt8 = 0x08

    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }

    /// Split a message into BLE-sized chunks. When `encrypt` is set, `sessionKey`
    /// must be the 16-byte derived session key.
    public static func encode(type: UInt16, handle: UInt8, payload: [UInt8],
                              mtu: Int = 23, extendedFlags: Bool = false,
                              encrypt: Bool = false, sessionKey: [UInt8]? = nil,
                              sequenceNumber: UInt32 = 0) -> [[UInt8]] {
        let lengthField = payload.count       // header length is always the plaintext length
        var data = payload
        var encFlag: UInt8 = 0
        if encrypt, let key = sessionKey {
            encFlag = flagEncrypted
            let messageKey = key.map { $0 ^ handle }
            var wrapped = payload + le32(sequenceNumber)
            wrapped += le32(CRC32.checksum(wrapped[...]))       // CRC over payload + seqNo
            while wrapped.count % 16 != 0 { wrapped.append(0) } // zero-pad to a block
            data = [UInt8](AESECB.encrypt(Data(wrapped), key: Data(messageKey)) ?? Data())
        }

        let headerSize = extendedFlags ? 5 : 4
        let perChunk = max(1, mtu - 3 - headerSize)
        var chunks: [[UInt8]] = []
        var offset = 0, count: UInt8 = 0

        repeat {
            let isFirst = count == 0
            let room = isFirst ? perChunk - 6 : perChunk
            let take = Swift.min(Swift.max(0, room), data.count - offset)

            var chunk: [UInt8] = [startByte, 0]
            if extendedFlags { chunk.append(0) }
            chunk.append(handle)
            chunk.append(count)
            if isFirst {
                let len = UInt32(lengthField)
                chunk.append(contentsOf: le32(len))
                chunk.append(contentsOf: [UInt8(type & 0xff), UInt8((type >> 8) & 0xff)])
            }
            chunk.append(contentsOf: data[offset ..< offset + take])

            let isLast = offset + take >= data.count
            chunk[1] = (isFirst ? flagFirst : 0) | (isLast ? flagLast : 0) | encFlag
            chunks.append(chunk)
            offset += take
            count &+= 1
        } while offset < data.count
        return chunks
    }

    /// Reassembles (and decrypts) chunks into complete (type, payload) messages.
    public struct Decoder {
        private let headerSize: Int
        /// Session key for decrypting incoming encrypted messages (set after auth).
        public var sessionKey: [UInt8]?
        private var buffer: [UInt8] = []
        private var plaintextLength = 0
        private var expectedBytes: Int?
        private var encrypted = false
        private var handle: UInt8 = 0
        private var type: UInt16 = 0

        public init(extendedFlags: Bool = false, sessionKey: [UInt8]? = nil) {
            headerSize = extendedFlags ? 5 : 4
            self.sessionKey = sessionKey
        }

        public mutating func receive(_ chunk: [UInt8]) -> (type: UInt16, payload: [UInt8])? {
            guard chunk.first == startByte, chunk.count > headerSize else { return nil }
            var p = headerSize
            handle = chunk[headerSize - 2]
            if chunk[1] & flagFirst != 0 {
                guard chunk.count >= headerSize + 6 else { return nil }
                buffer = []
                plaintextLength = Int(chunk[p]) | Int(chunk[p + 1]) << 8
                    | Int(chunk[p + 2]) << 16 | Int(chunk[p + 3]) << 24
                type = UInt16(chunk[p + 4]) | UInt16(chunk[p + 5]) << 8
                encrypted = chunk[1] & flagEncrypted != 0
                // encrypted wire length = roundUp(plaintext + seqNo(4) + crc(4), 16)
                expectedBytes = encrypted ? ((plaintextLength + 8 + 15) / 16) * 16 : plaintextLength
                p += 6
            }
            buffer.append(contentsOf: chunk[p...])
            guard let expected = expectedBytes, buffer.count >= expected else { return nil }

            var message = Array(buffer.prefix(expected))
            buffer = []; expectedBytes = nil
            if encrypted {
                guard let key = sessionKey,
                      let clear = AESECB.decrypt(Data(message), key: Data(key.map { $0 ^ handle })) else {
                    return nil   // encrypted but no/invalid key → can't decode
                }
                message = Array([UInt8](clear).prefix(plaintextLength))
            }
            return (type, message)
        }
    }
}
