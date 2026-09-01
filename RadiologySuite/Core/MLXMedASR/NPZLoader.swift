import Foundation
import MLX

/// mlx-swift `loadArrays` only accepts `.safetensors`. Hugging Face ships MedASR as `.npz`
/// (a ZIP of `.npy` files, stored uncompressed).
enum NPZLoader {
    static func load(url: URL) throws -> [String: MLXArray] {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try load(data: data)
    }

    static func load(data: Data) throws -> [String: MLXArray] {
        var arrays = [String: MLXArray]()
        for entry in try zipEntries(data) {
            var name = entry.name
            if name.hasSuffix(".npy") { name.removeLast(4) }
            guard !name.isEmpty, !name.hasSuffix("/") else { continue }
            arrays[name] = try npyArray(entry.bytes)
        }
        if arrays.isEmpty { throw AppError.modelMissing }
        return arrays
    }

    private struct ZipEntry {
        let name: String
        let bytes: Data
    }

    private static func zipEntries(_ data: Data) throws -> [ZipEntry] {
        guard let eocd = findEOCD(data) else {
            throw NPZError.invalidZip("missing end of central directory")
        }
        let count = Int(u16(data, eocd + 10))
        var offset = Int(u32(data, eocd + 16))
        var entries = [ZipEntry]()
        entries.reserveCapacity(count)
        for _ in 0..<count {
            guard u32(data, offset) == 0x02014B50 else {
                throw NPZError.invalidZip("bad central directory signature")
            }
            let method = Int(u16(data, offset + 10))
            var size = Int(u32(data, offset + 24)) // uncompressed size in central directory
            if size == 0xFFFF_FFFF { size = Int(u32(data, offset + 20)) }
            let nameLen = Int(u16(data, offset + 28))
            let extraLen = Int(u16(data, offset + 30))
            let commentLen = Int(u16(data, offset + 32))
            var localOffset = Int(u32(data, offset + 42))
            if localOffset == 0xFFFF_FFFF || size == 0xFFFF_FFFF {
                let extra = extraField(data, at: offset + 46 + nameLen, length: extraLen)
                if size == 0xFFFF_FFFF, let zip64Size = extra.uncompressed ?? extra.compressed {
                    size = zip64Size
                }
                if localOffset == 0xFFFF_FFFF, let zip64Local = extra.localOffset {
                    localOffset = zip64Local
                }
            }
            let nameData = data.subdata(in: (offset + 46)..<(offset + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? ""
            offset += 46 + nameLen + extraLen + commentLen

            guard method == 0 else {
                throw NPZError.invalidZip("compressed npz entries are not supported")
            }
            guard u32(data, localOffset) == 0x04034B50 else {
                throw NPZError.invalidZip("bad local header for \(name)")
            }
            let localNameLen = Int(u16(data, localOffset + 26))
            let localExtraLen = Int(u16(data, localOffset + 28))
            let dataStart = localOffset + 30 + localNameLen + localExtraLen
            let dataEnd = dataStart + size
            guard dataStart >= 0, dataEnd <= data.count, dataStart <= dataEnd else {
                throw NPZError.invalidZip("entry \(name) out of range \(dataStart)+\(size)")
            }
            let bytes = data.subdata(in: dataStart..<dataEnd)
            entries.append(ZipEntry(name: name, bytes: bytes))
        }
        return entries
    }

    private struct Zip64Extra {
        var uncompressed: Int?
        var compressed: Int?
        var localOffset: Int?
    }

    /// ZIP64 extra field (id 0x0001). Numpy `savez` writes 0xFFFFFFFF in 32-bit size slots.
    private static func extraField(_ data: Data, at start: Int, length: Int) -> Zip64Extra {
        var result = Zip64Extra()
        var i = start
        let end = start + length
        while i + 4 <= end {
            let id = Int(u16(data, i))
            let sz = Int(u16(data, i + 2))
            i += 4
            guard i + sz <= end else { break }
            if id == 0x0001 {
                var p = i
                if sz >= 8 { result.uncompressed = Int(u64(data, p)); p += 8 }
                if sz >= 16 { result.compressed = Int(u64(data, p)); p += 8 }
                if sz >= 24 { result.localOffset = Int(u64(data, p)) }
            }
            i += sz
        }
        return result
    }

    private static func findEOCD(_ data: Data) -> Int? {
        let sig: UInt32 = 0x06054B50
        let minEOCD = 22
        guard data.count >= minEOCD else { return nil }
        let start = max(0, data.count - 65_535 - minEOCD)
        var i = data.count - minEOCD
        while i >= start {
            if u32(data, i) == sig { return i }
            i -= 1
        }
        return nil
    }

    private static func npyArray(_ npy: Data) throws -> MLXArray {
        guard npy.count >= 10,
              npy[0] == 0x93,
              npy[1] == 0x4E, npy[2] == 0x55, npy[3] == 0x4D,
              npy[4] == 0x50, npy[5] == 0x59 else {
            throw NPZError.invalidNpy("bad magic")
        }
        let major = Int(npy[6])
        let headerLen: Int
        let headerStart: Int
        if major == 1 {
            headerLen = Int(u16(npy, 8))
            headerStart = 10
        } else {
            headerLen = Int(u32(npy, 8))
            headerStart = 12
        }
        let headerEnd = headerStart + headerLen
        guard headerEnd <= npy.count else { throw NPZError.invalidNpy("truncated header") }
        let header = String(data: npy.subdata(in: headerStart..<headerEnd), encoding: .ascii) ?? ""
        let descr = pythonStringValue(header, key: "descr") ?? "<f4"
        let fortran = pythonBoolValue(header, key: "fortran_order") ?? false
        let shape = pythonTupleInts(header, key: "shape") ?? []
        let payload = npy.subdata(in: headerEnd..<npy.count)
        let dtype = try dtype(from: descr)
        let dims = shape.isEmpty ? [payload.count / max(dtype.size, 1)] : shape
        // 1-D fortran_order is the same layout as C-order. Rank >= 2 is stored
        // column-major; load with reversed shape then transpose back.
        if fortran, dims.count > 1 {
            let cOrderShape = Array(dims.reversed())
            let array = MLXArray(payload, cOrderShape, dtype: dtype)
            return array.transposed(axes: Array((0..<dims.count).reversed()))
        }
        return MLXArray(payload, dims, dtype: dtype)
    }

    private static func dtype(from descr: String) throws -> DType {
        let code = descr.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
        switch code {
        case "f2": return .float16
        case "f4": return .float32
        case "f8": return .float32
        case "i4": return .int32
        case "i8": return .int64
        case "u1": return .uint8
        case "b1", "b": return .bool
        default: throw NPZError.invalidNpy("unsupported dtype \(descr)")
        }
    }

    private static func pythonStringValue(_ header: String, key: String) -> String? {
        guard let range = header.range(of: "'\(key)':") else { return nil }
        let rest = header[range.upperBound...]
        guard let q1 = rest.firstIndex(of: "'") else { return nil }
        let after = rest.index(after: q1)
        guard let q2 = rest[after...].firstIndex(of: "'") else { return nil }
        return String(rest[after..<q2])
    }

    private static func pythonBoolValue(_ header: String, key: String) -> Bool? {
        guard let range = header.range(of: "'\(key)':") else { return nil }
        let rest = header[range.upperBound...].trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("True") { return true }
        if rest.hasPrefix("False") { return false }
        return nil
    }

    private static func pythonTupleInts(_ header: String, key: String) -> [Int]? {
        guard let keyRange = header.range(of: "'\(key)':") else { return nil }
        let rest = header[keyRange.upperBound...]
        guard let open = rest.firstIndex(of: "("),
              let close = rest[open...].firstIndex(of: ")") else { return [] }
        let inner = rest[rest.index(after: open)..<close]
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.compactMap { Int($0) }
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func u64(_ data: Data, _ offset: Int) -> UInt64 {
        UInt64(u32(data, offset)) | UInt64(u32(data, offset + 4)) << 32
    }
}

enum NPZError: Error, LocalizedError {
    case invalidZip(String)
    case invalidNpy(String)
    var errorDescription: String? {
        switch self {
        case .invalidZip(let msg): return "Invalid npz: \(msg)"
        case .invalidNpy(let msg): return "Invalid npy: \(msg)"
        }
    }
}
