import Foundation
import Compression

/// A minimal, dependency-free ZIP archive reader. Supports the two methods
/// `.xlsx` files use: stored (0) and deflate (8). Apple's `COMPRESSION_ZLIB`
/// is raw DEFLATE (exactly ZIP method 8), so inflate is a single system call.
struct ZipArchive {
    private let data: Data
    private(set) var entries: [String: Entry] = [:]

    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    init?(data: Data) {
        self.data = data
        guard let central = Self.findEndOfCentralDirectory(data) else { return nil }
        let entryCount = Self.u16(data, central + 10)
        var offset = Int(Self.u32(data, central + 16))
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, Self.u32(data, offset) == 0x02014b50 else { break }
            let method = UInt16(Self.u16(data, offset + 10))
            let compressedSize = Int(Self.u32(data, offset + 20))
            let uncompressedSize = Int(Self.u32(data, offset + 24))
            let nameLength = Self.u16(data, offset + 28)
            let extraLength = Self.u16(data, offset + 30)
            let commentLength = Self.u16(data, offset + 32)
            let localOffset = Int(Self.u32(data, offset + 42))
            guard offset + 46 + nameLength <= data.count else { break }
            let name = String(decoding: data.subdata(in: (offset + 46)..<(offset + 46 + nameLength)), as: UTF8.self)
            entries[name] = Entry(name: name, method: method, compressedSize: compressedSize, uncompressedSize: uncompressedSize, localHeaderOffset: localOffset)
            offset += 46 + nameLength + extraLength + commentLength
        }
    }

    func entry(_ name: String) -> Data? {
        guard let entry = entries[name], data.count >= entry.localHeaderOffset + 30 else { return nil }
        let base = entry.localHeaderOffset
        guard Self.u32(data, base) == 0x04034b50 else { return nil }
        let nameLength = Self.u16(data, base + 26)
        let extraLength = Self.u16(data, base + 28)
        let start = base + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else { return nil }
        let payload = data.subdata(in: start..<(start + entry.compressedSize))
        switch entry.method {
        case 0: return payload
        case 8: return Self.rawInflate(payload, expectedSize: entry.uncompressedSize)
        default: return nil
        }
    }

    // MARK: Raw DEFLATE via the system Compression framework

    private static func rawInflate(_ input: Data, expectedSize: Int) -> Data? {
        guard !input.isEmpty else { return Data() }
        var capacity = max(expectedSize, input.count * 3, 1024)
        for _ in 0..<8 {
            var output = Data(count: capacity)
            let written = output.withUnsafeMutableBytes { outPtr -> Int in
                input.withUnsafeBytes { inPtr -> Int in
                    guard let outBase = outPtr.bindMemory(to: UInt8.self).baseAddress,
                          let inBase = inPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(outBase, capacity, inBase, input.count, nil, COMPRESSION_ZLIB)
                }
            }
            if written > 0 { return output.prefix(written) }
            capacity *= 2
        }
        return nil
    }

    // MARK: Little-endian helpers

    private static func u16(_ data: Data, _ offset: Int) -> Int {
        guard offset + 2 <= data.count else { return 0 }
        return Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private static func findEndOfCentralDirectory(_ data: Data) -> Int? {
        let signature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        guard data.count >= 22 else { return nil }
        var index = data.count - 22
        while index >= 0 {
            if data[index] == signature[0], data[index + 1] == signature[1],
               data[index + 2] == signature[2], data[index + 3] == signature[3] {
                return index
            }
            index -= 1
        }
        return nil
    }
}
