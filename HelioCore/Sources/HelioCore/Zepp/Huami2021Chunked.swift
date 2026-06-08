import Foundation

/// The Huami2021 / ZeppOS "chunked transfer" framing carried over BLE
/// characteristics 0x0016 (write) and 0x0017 (read). A logical message
/// (type + payload) is split into MTU-sized chunks; this encodes/decodes the
/// *unencrypted* path, which is what the ECDH auth exchange itself uses.
///
/// Chunk layout (non-extended header, 4 bytes):
///   [0] 0x03   [1] flags   [2] writeHandle   [3] count
/// On the first chunk only, after the header: 4-byte little-endian total
/// payload length, then 2-byte little-endian message type.
/// flags: 0x01 = first chunk, 0x06 = last chunk, 0x08 = encrypted (unused here).
///
/// Encrypted post-auth payloads (sequence number + CRC32 + AES with
/// messageKey[i] = sessionKey[i] ^ writeHandle) are intentionally not handled
/// yet — see docs/superpowers/plans/2026-06-08-zeppos-ble-spike.md.
public enum Huami2021Chunked {
    static let startByte: UInt8 = 0x03
    static let flagFirst: UInt8 = 0x01
    static let flagLast: UInt8 = 0x06

    /// Split a message into chunks that each fit `mtu`.
    public static func encode(type: UInt16, handle: UInt8, payload: [UInt8],
                              mtu: Int = 23, extendedFlags: Bool = false) -> [[UInt8]] {
        let headerSize = extendedFlags ? 5 : 4
        let perChunk = max(1, mtu - 3 - headerSize)   // data bytes available per chunk
        var chunks: [[UInt8]] = []
        var offset = 0, count: UInt8 = 0

        repeat {
            let isFirst = count == 0
            let room = isFirst ? perChunk - 6 : perChunk   // first chunk spends 6 bytes on length+type
            let take = Swift.min(Swift.max(0, room), payload.count - offset)

            var chunk: [UInt8] = [startByte, 0]            // [0]=0x03, [1]=flags (filled below)
            if extendedFlags { chunk.append(0) }
            chunk.append(handle)
            chunk.append(count)
            if isFirst {
                let len = UInt32(payload.count)
                chunk.append(contentsOf: [UInt8(len & 0xff), UInt8((len >> 8) & 0xff),
                                          UInt8((len >> 16) & 0xff), UInt8((len >> 24) & 0xff)])
                chunk.append(contentsOf: [UInt8(type & 0xff), UInt8((type >> 8) & 0xff)])
            }
            chunk.append(contentsOf: payload[offset ..< offset + take])

            let isLast = offset + take >= payload.count
            chunk[1] = (isFirst ? flagFirst : 0) | (isLast ? flagLast : 0)
            chunks.append(chunk)

            offset += take
            count &+= 1
        } while offset < payload.count
        return chunks
    }

    /// Reassembles chunks into complete (type, payload) messages.
    public struct Decoder {
        private let headerSize: Int
        private var buffer: [UInt8] = []
        private var expectedLength: Int?
        private var type: UInt16 = 0

        public init(extendedFlags: Bool = false) {
            headerSize = extendedFlags ? 5 : 4
        }

        /// Feed one chunk. Returns the message once its final chunk arrives.
        public mutating func receive(_ chunk: [UInt8]) -> (type: UInt16, payload: [UInt8])? {
            guard chunk.first == startByte, chunk.count > headerSize else { return nil }
            var p = headerSize
            if chunk[1] & flagFirst != 0 {
                guard chunk.count >= headerSize + 6 else { return nil }
                buffer = []
                expectedLength = Int(chunk[p]) | Int(chunk[p + 1]) << 8
                    | Int(chunk[p + 2]) << 16 | Int(chunk[p + 3]) << 24
                type = UInt16(chunk[p + 4]) | UInt16(chunk[p + 5]) << 8
                p += 6
            }
            buffer.append(contentsOf: chunk[p...])
            guard let expected = expectedLength, buffer.count >= expected else { return nil }
            let message = (type, Array(buffer.prefix(expected)))
            buffer = []; expectedLength = nil
            return message
        }
    }
}
