import Compression
import Foundation

/// .xlsx/.docx okumak için en küçük ZIP okuyucu: merkezi dizin, "stored" ve "deflate" girdiler.
/// Zip64 ve şifreleme desteklenmez. Açılmış boyut 100 MB ile sınırlıdır (zip bombası koruması).
struct ZipArchive {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    static let maxUncompressedSize = 100 * 1024 * 1024

    private let bytes: [UInt8]
    let entries: [String: Entry]

    init(data: Data) throws {
        bytes = [UInt8](data)
        entries = try Self.readCentralDirectory(bytes)
    }

    func contents(of name: String) throws -> Data? {
        guard let entry = entries[name] else { return nil }
        guard entry.uncompressedSize <= Self.maxUncompressedSize else { throw ImportError.tooLarge }
        let offset = entry.localHeaderOffset
        guard offset + 30 <= bytes.count, Self.uint32(bytes, offset) == 0x0403_4B50 else {
            throw ImportError.unreadable("ZIP yerel başlığı bozuk")
        }
        let start = offset + 30 + Int(Self.uint16(bytes, offset + 26)) + Int(Self.uint16(bytes, offset + 28))
        guard start + entry.compressedSize <= bytes.count else { throw ImportError.unreadable("ZIP girdisi eksik") }
        let compressed = Array(bytes[start..<start + entry.compressedSize])

        switch entry.method {
        case 0:
            return Data(compressed)
        case 8:
            guard entry.uncompressedSize > 0 else { return Data() }
            var output = [UInt8](repeating: 0, count: entry.uncompressedSize)
            let written = compressed.withUnsafeBufferPointer { source in
                output.withUnsafeMutableBufferPointer { destination in
                    compression_decode_buffer(
                        destination.baseAddress!, entry.uncompressedSize,
                        source.baseAddress!, entry.compressedSize,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            guard written == entry.uncompressedSize else { throw ImportError.unreadable("ZIP girdisi açılamadı") }
            return Data(output)
        default:
            throw ImportError.unreadable("desteklenmeyen ZIP sıkıştırması (\(entry.method))")
        }
    }

    private static func readCentralDirectory(_ bytes: [UInt8]) throws -> [String: Entry] {
        guard bytes.count >= 22 else { throw ImportError.unreadable("ZIP değil") }
        let lowerBound = max(0, bytes.count - 22 - 65_535)
        var eocd: Int?
        for index in stride(from: bytes.count - 22, through: lowerBound, by: -1) where uint32(bytes, index) == 0x0605_4B50 {
            eocd = index
            break
        }
        guard let eocd else { throw ImportError.unreadable("ZIP değil") }
        let count = Int(uint16(bytes, eocd + 10))
        var offset = Int(uint32(bytes, eocd + 16))
        var entries: [String: Entry] = [:]
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, uint32(bytes, offset) == 0x0201_4B50 else {
                throw ImportError.unreadable("ZIP dizini bozuk")
            }
            let nameLength = Int(uint16(bytes, offset + 28))
            let extraLength = Int(uint16(bytes, offset + 30))
            let commentLength = Int(uint16(bytes, offset + 32))
            guard offset + 46 + nameLength <= bytes.count else { throw ImportError.unreadable("ZIP dizini bozuk") }
            let name = String(decoding: bytes[offset + 46..<offset + 46 + nameLength], as: UTF8.self)
            entries[name] = Entry(
                name: name,
                method: uint16(bytes, offset + 10),
                compressedSize: Int(uint32(bytes, offset + 20)),
                uncompressedSize: Int(uint32(bytes, offset + 24)),
                localHeaderOffset: Int(uint32(bytes, offset + 42))
            )
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}
