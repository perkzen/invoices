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

// MARK: Reading

nonisolated extension ZIPArchive {
    enum ReadError: Error, Equatable {
        case notAnArchive
        case truncated
        case unsupportedCompression(method: Int)
        case corruptEntry(path: String)
    }

    /// The entries of an archive, inflated. Stored and deflated entries are
    /// read — the two methods every spreadsheet program writes — and the
    /// central directory is trusted for sizes, because a local header may
    /// carry zeros and defer them to a descriptor after the data.
    static func entries(in archive: Data) throws(ReadError) -> [Entry] {
        let bytes = Data(archive)  // rebased, so offsets start at 0
        guard bytes.count >= 22 else { throw .notAnArchive }

        // The end-of-central-directory record sits at the very end, behind
        // an optional comment; scan backwards for its signature.
        var eocd: Int?
        var index = bytes.count - 22
        while index >= max(0, bytes.count - 22 - 65_535) {
            if bytes.uint32(at: index) == 0x0605_4B50 { eocd = index; break }
            index -= 1
        }
        guard let eocd else { throw .notAnArchive }

        let count = Int(bytes.uint16(at: eocd + 10))
        var record = Int(bytes.uint32(at: eocd + 16))
        var entries: [Entry] = []
        entries.reserveCapacity(count)

        for _ in 0..<count {
            guard record + 46 <= bytes.count, bytes.uint32(at: record) == 0x0201_4B50 else { throw .truncated }
            let method = Int(bytes.uint16(at: record + 10))
            let compressedSize = Int(bytes.uint32(at: record + 20))
            let size = Int(bytes.uint32(at: record + 24))
            let nameLength = Int(bytes.uint16(at: record + 28))
            let extraLength = Int(bytes.uint16(at: record + 30))
            let commentLength = Int(bytes.uint16(at: record + 32))
            let localHeader = Int(bytes.uint32(at: record + 42))
            guard record + 46 + nameLength <= bytes.count else { throw .truncated }
            let path = String(decoding: bytes[(record + 46)..<(record + 46 + nameLength)], as: UTF8.self)
            record += 46 + nameLength + extraLength + commentLength

            // The local header repeats the name and may carry a different
            // extra field, so the data offset comes from its own lengths.
            guard localHeader + 30 <= bytes.count, bytes.uint32(at: localHeader) == 0x0403_4B50 else { throw .truncated }
            let start = localHeader + 30
                + Int(bytes.uint16(at: localHeader + 26))
                + Int(bytes.uint16(at: localHeader + 28))
            guard start + compressedSize <= bytes.count else { throw .truncated }
            let raw = bytes[start..<(start + compressedSize)]

            let data: Data
            switch method {
            case 0:
                data = Data(raw)
            case 8:
                // ZIP's deflate is the raw RFC 1951 stream, which is what
                // Foundation calls zlib here — no header, no checksum.
                guard let inflated = try? (Data(raw) as NSData).decompressed(using: .zlib) as Data,
                      inflated.count == size
                else { throw .corruptEntry(path: path) }
                data = inflated
            default:
                throw .unsupportedCompression(method: method)
            }
            entries.append(Entry(path: path, data: data))
        }
        return entries
    }
}

nonisolated private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(uint16(at: offset)) | UInt32(uint16(at: offset + 2)) << 16
    }
}
