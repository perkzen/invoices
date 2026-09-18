import Foundation

/// A minimal ZIP writer — enough to build an .xlsx, which is a ZIP of XML
/// parts. Entries are *stored* (method 0, no compression): the parts of a
/// year overview are a few kilobytes, so the bytes saved are not worth
/// linking a compressor, and Excel reads stored entries fine.
nonisolated enum ZIPArchive {
    struct Entry {
        var path: String
        var data: Data
    }

    /// CRC-32 (reflected polynomial 0xEDB88320), as required by the ZIP spec.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1)))
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    static func archive(_ entries: [Entry]) -> Data {
        var payload = Data()
        var directory = Data()

        for entry in entries {
            let name = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(payload.count)

            // Local file header.
            payload.append(uint32: 0x0403_4B50)
            payload.append(uint16: 20)          // version needed
            payload.append(uint16: 0x0800)      // UTF-8 names
            payload.append(uint16: 0)           // stored
            payload.append(uint16: 0)           // mod time
            payload.append(uint16: 0x0021)      // mod date: 1980-01-01
            payload.append(uint32: crc)
            payload.append(uint32: size)        // compressed
            payload.append(uint32: size)        // uncompressed
            payload.append(uint16: UInt16(name.count))
            payload.append(uint16: 0)           // extra field length
            payload.append(name)
            payload.append(entry.data)

            // Matching central directory record.
            directory.append(uint32: 0x0201_4B50)
            directory.append(uint16: 20)        // version made by
            directory.append(uint16: 20)        // version needed
            directory.append(uint16: 0x0800)
            directory.append(uint16: 0)
            directory.append(uint16: 0)
            directory.append(uint16: 0x0021)
            directory.append(uint32: crc)
            directory.append(uint32: size)
            directory.append(uint32: size)
            directory.append(uint16: UInt16(name.count))
            directory.append(uint16: 0)         // extra
            directory.append(uint16: 0)         // comment
            directory.append(uint16: 0)         // disk number
            directory.append(uint16: 0)         // internal attributes
            directory.append(uint32: 0)         // external attributes
            directory.append(uint32: offset)
            directory.append(name)
        }

        var archive = payload
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.append(uint32: 0x0605_4B50)     // end of central directory
        archive.append(uint16: 0)
        archive.append(uint16: 0)
        archive.append(uint16: UInt16(entries.count))
        archive.append(uint16: UInt16(entries.count))
        archive.append(uint32: UInt32(directory.count))
        archive.append(uint32: directoryOffset)
        archive.append(uint16: 0)               // comment length
        return archive
    }
}

nonisolated private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func append(uint32 value: UInt32) {
        append(contentsOf: (0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) })
    }
}
