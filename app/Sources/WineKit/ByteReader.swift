import Foundation

/// Bounds-checked little-endian reads over a byte buffer. Every read returns nil past the end, so parsers of
/// untrusted files (.lnk, .exe) fail soft instead of trapping.
struct ByteReader {
    let bytes: [UInt8]

    init(_ data: Data) { bytes = [UInt8](data) }

    var count: Int { bytes.count }

    func u8(_ at: Int) -> UInt8? {
        at >= 0 && at < bytes.count ? bytes[at] : nil
    }

    func u16(_ at: Int) -> UInt16? {
        guard at >= 0, at + 2 <= bytes.count else { return nil }
        return UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    func u32(_ at: Int) -> UInt32? {
        guard at >= 0, at + 4 <= bytes.count else { return nil }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[at + $1]) << (8 * UInt32($1)) }
    }

    func slice(_ at: Int, _ length: Int) -> [UInt8]? {
        guard at >= 0, length >= 0, at + length <= bytes.count else { return nil }
        return Array(bytes[at..<(at + length)])
    }

    /// NUL-terminated 8-bit string (Windows code page; decoded as Latin-1 so it never fails).
    func cString(_ at: Int) -> String? {
        guard at >= 0, at < bytes.count else { return nil }
        var end = at
        while end < bytes.count, bytes[end] != 0 { end += 1 }
        return String(bytes: bytes[at..<end], encoding: .isoLatin1)
    }

    /// NUL-terminated UTF-16LE string.
    func wideCString(_ at: Int) -> String? {
        guard at >= 0, at < bytes.count else { return nil }
        var units: [UInt16] = []
        var p = at
        while let u = u16(p), u != 0 { units.append(u); p += 2 }
        return String(decoding: units, as: UTF16.self)
    }

    /// UTF-16LE string of `chars` code units.
    func wideString(_ at: Int, chars: Int) -> String? {
        guard let raw = slice(at, chars * 2) else { return nil }
        let units = stride(from: 0, to: raw.count, by: 2).map { UInt16(raw[$0]) | UInt16(raw[$0 + 1]) << 8 }
        return String(decoding: units, as: UTF16.self)
    }
}
