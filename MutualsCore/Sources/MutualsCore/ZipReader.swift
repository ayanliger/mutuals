import Foundation

/// Reads single entries from a ZIP archive without extracting the rest.
///
/// An Instagram export can carry gigabytes of photos next to the few hundred
/// kilobytes of JSON this app reads, so the reader parses the central directory
/// and inflates only the entries asked for. iOS has no public unzip API, which
/// is why this exists instead of a call into Foundation. Handles stored and
/// deflated entries and ZIP64 archives. Encrypted and multi-disk archives are
/// rejected.
public final class ZipReader {
    public struct Entry: Hashable, Sendable {
        public let path: String
        public let method: UInt16
        public let flags: UInt16
        public let crc32: UInt32
        public let compressedSize: UInt64
        public let uncompressedSize: UInt64
        public let localHeaderOffset: UInt64
        public let modified: Date?

        public var isDirectory: Bool { path.hasSuffix("/") }
    }

    public enum Failure: Error, Equatable, Sendable, CustomStringConvertible {
        case notAZip
        case damaged(String)
        case unsupportedCompression(UInt16)
        case encrypted
        case entryTooLarge(UInt64)

        public var description: String {
            switch self {
            case .notAZip: "not a zip file"
            case .damaged(let detail): detail
            case .unsupportedCompression(let method): "compression method \(method) is not supported"
            case .encrypted: "the archive is encrypted"
            case .entryTooLarge(let size): "an entry of \(size) bytes is too large"
            }
        }
    }

    public let entries: [Entry]
    private let handle: FileHandle
    private let fileSize: UInt64

    public init(url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        do {
            let size = try handle.seekToEnd()
            self.entries = try Self.centralDirectory(handle: handle, fileSize: size)
            self.handle = handle
            self.fileSize = size
        } catch {
            try? handle.close()
            throw error
        }
    }

    deinit {
        try? handle.close()
    }

    /// Returns the uncompressed bytes of `entry`, checked against its CRC-32.
    ///
    /// - Parameter limit: largest uncompressed size accepted. Relationship
    ///   files are small; the cap keeps a malformed archive from exhausting memory.
    public func data(for entry: Entry, limit: UInt64 = 256 << 20) throws -> Data {
        guard entry.flags & 0x1 == 0 else { throw Failure.encrypted }
        guard entry.uncompressedSize <= limit else { throw Failure.entryTooLarge(entry.uncompressedSize) }

        var header = ByteReader(try Self.read(handle, at: entry.localHeaderOffset, count: 30))
        guard try header.u32() == 0x0403_4B50 else { throw Failure.damaged("missing local header for \(entry.path)") }
        try header.skip(22)
        let nameLength = UInt64(try header.u16())
        let extraLength = UInt64(try header.u16())
        let start = entry.localHeaderOffset + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= fileSize else { throw Failure.damaged("\(entry.path) runs past the end of the archive") }

        let raw = try Self.read(handle, at: start, count: Int(entry.compressedSize))
        let output: Data
        switch entry.method {
        case 0:
            output = raw
        case 8:
            output = entry.uncompressedSize == 0 ? Data() : try Self.inflate(raw, path: entry.path)
        default:
            throw Failure.unsupportedCompression(entry.method)
        }
        guard UInt64(output.count) == entry.uncompressedSize, CRC32.checksum(output) == entry.crc32 else {
            throw Failure.damaged("\(entry.path) failed its checksum")
        }
        return output
    }

    // MARK: - Central directory

    private static func centralDirectory(handle: FileHandle, fileSize: UInt64) throws -> [Entry] {
        guard fileSize >= 22 else { throw Failure.notAZip }

        // The end-of-central-directory record sits in the last 22 bytes plus an
        // optional comment of up to 64 KiB, preceded by a 20-byte ZIP64 locator.
        let tailLength = Int(min(fileSize, 22 + 0xFFFF + 20))
        let tail = try read(handle, at: fileSize - UInt64(tailLength), count: tailLength)
        guard let eocd = lastSignature(0x0605_4B50, in: tail, before: tail.count - 22) else { throw Failure.notAZip }

        var record = ByteReader(tail, at: eocd + 4)
        let disk = try record.u16()
        let directoryDisk = try record.u16()
        try record.skip(2)
        var count = UInt64(try record.u16())
        var size = UInt64(try record.u32())
        var offset = UInt64(try record.u32())
        guard (disk == 0 || disk == 0xFFFF), (directoryDisk == 0 || directoryDisk == 0xFFFF) else {
            throw Failure.damaged("multi-disk archives are not supported")
        }

        if count == 0xFFFF || size == 0xFFFF_FFFF || offset == 0xFFFF_FFFF {
            guard eocd >= 20 else { throw Failure.damaged("missing ZIP64 locator") }
            var locator = ByteReader(tail, at: eocd - 20)
            guard try locator.u32() == 0x0706_4B50 else { throw Failure.damaged("missing ZIP64 locator") }
            try locator.skip(4)
            let recordOffset = try locator.u64()
            guard recordOffset + 56 <= fileSize else { throw Failure.damaged("ZIP64 record out of bounds") }
            var zip64 = ByteReader(try read(handle, at: recordOffset, count: 56))
            guard try zip64.u32() == 0x0606_4B50 else { throw Failure.damaged("bad ZIP64 record") }
            try zip64.skip(28)
            count = try zip64.u64()
            size = try zip64.u64()
            offset = try zip64.u64()
        }

        guard offset + size <= fileSize, size < 1 << 30 else { throw Failure.damaged("central directory out of bounds") }
        var directory = ByteReader(try read(handle, at: offset, count: Int(size)))
        var entries: [Entry] = []
        entries.reserveCapacity(Int(min(count, 200_000)))

        for _ in 0..<count {
            guard try directory.u32() == 0x0201_4B50 else { throw Failure.damaged("bad central directory entry") }
            try directory.skip(4)
            let flags = try directory.u16()
            let method = try directory.u16()
            let time = try directory.u16()
            let date = try directory.u16()
            let crc = try directory.u32()
            var compressed = UInt64(try directory.u32())
            var uncompressed = UInt64(try directory.u32())
            let nameLength = Int(try directory.u16())
            let extraLength = Int(try directory.u16())
            let commentLength = Int(try directory.u16())
            try directory.skip(8)
            var localOffset = UInt64(try directory.u32())
            let name = try directory.bytes(nameLength)
            let extra = try directory.bytes(extraLength)
            try directory.skip(commentLength)

            if compressed == 0xFFFF_FFFF || uncompressed == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF {
                // The ZIP64 extra field lists only the values that overflowed, in this order.
                var fields = ByteReader(extra)
                while fields.remaining >= 4 {
                    let id = try fields.u16()
                    let length = Int(try fields.u16())
                    guard id == 0x0001 else { try fields.skip(length); continue }
                    var values = ByteReader(try fields.bytes(length))
                    if uncompressed == 0xFFFF_FFFF { uncompressed = try values.u64() }
                    if compressed == 0xFFFF_FFFF { compressed = try values.u64() }
                    if localOffset == 0xFFFF_FFFF { localOffset = try values.u64() }
                    break
                }
            }

            entries.append(Entry(
                path: String(data: name, encoding: .utf8) ?? String(decoding: name, as: UTF8.self),
                method: method,
                flags: flags,
                crc32: crc,
                compressedSize: compressed,
                uncompressedSize: uncompressed,
                localHeaderOffset: localOffset,
                modified: dosDate(date: date, time: time)
            ))
        }
        return entries
    }

    private static func lastSignature(_ signature: UInt32, in data: Data, before start: Int) -> Int? {
        guard start >= 0 else { return nil }
        let bytes = [UInt8](data)
        var index = start
        while index >= 0 {
            if bytes[index] == UInt8(signature & 0xFF),
               bytes[index + 1] == UInt8(signature >> 8 & 0xFF),
               bytes[index + 2] == UInt8(signature >> 16 & 0xFF),
               bytes[index + 3] == UInt8(signature >> 24) {
                return index
            }
            index -= 1
        }
        return nil
    }

    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw Failure.damaged("unexpected end of file")
        }
        return data
    }

    private static func inflate(_ data: Data, path: String) throws -> Data {
        // NSData's zlib algorithm is raw DEFLATE (RFC 1951), which is what ZIP stores.
        do {
            return try (data as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw Failure.damaged("\(path) could not be decompressed")
        }
    }

    /// MS-DOS timestamps carry no time zone; they are read as UTC.
    private static func dosDate(date: UInt16, time: UInt16) -> Date? {
        var components = DateComponents()
        components.year = Int(date >> 9) + 1980
        components.month = Int(date >> 5 & 0x0F)
        components.day = Int(date & 0x1F)
        components.hour = Int(time >> 11)
        components.minute = Int(time >> 5 & 0x3F)
        components.second = Int(time & 0x1F) * 2
        guard (1...12).contains(components.month!), (1...31).contains(components.day!) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)
    }
}

/// Little-endian reader over a byte buffer.
struct ByteReader {
    private let bytes: [UInt8]
    private(set) var offset: Int

    init(_ data: Data, at offset: Int = 0) {
        self.bytes = [UInt8](data)
        self.offset = offset
    }

    var remaining: Int { bytes.count - offset }

    mutating func u16() throws -> UInt16 {
        try need(2)
        defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    mutating func u32() throws -> UInt32 {
        try need(4)
        defer { offset += 4 }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }

    mutating func u64() throws -> UInt64 {
        try need(8)
        defer { offset += 8 }
        return (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[offset + $1]) << (8 * UInt64($1)) }
    }

    mutating func bytes(_ count: Int) throws -> Data {
        try need(count)
        defer { offset += count }
        return Data(bytes[offset..<offset + count])
    }

    mutating func skip(_ count: Int) throws {
        try need(count)
        offset += count
    }

    private func need(_ count: Int) throws {
        guard count >= 0, offset + count <= bytes.count else { throw ZipReader.Failure.damaged("truncated record") }
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { value, _ in value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buffer in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
