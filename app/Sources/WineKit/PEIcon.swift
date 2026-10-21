import Foundation

/// Pulls the first icon group out of a Windows PE file (.exe/.dll) and returns it as .ico data, which
/// NSImage can load directly.
public enum PEIcon {
    private static let rtIcon: UInt32 = 3
    private static let rtGroupIcon: UInt32 = 14

    public static func icoData(contentsOf url: URL) -> Data? {
        // Large game executables can be hundreds of MB; map rather than read.
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return icoData(fromPE: data)
    }

    public static func icoData(fromPE data: Data) -> Data? {
        let r = ByteReader(data)
        guard r.u16(0) == 0x5A4D, let peOff = r.u32(0x3C).map(Int.init), r.u32(peOff) == 0x0000_4550,
              let sectionCount = r.u16(peOff + 6), let optSize = r.u16(peOff + 20) else { return nil }
        let opt = peOff + 24
        let dirBase: Int
        switch r.u16(opt) {
        case 0x10B: dirBase = opt + 96   // PE32
        case 0x20B: dirBase = opt + 112  // PE32+
        default: return nil
        }
        guard let rsrcRVA = r.u32(dirBase + 2 * 8), rsrcRVA != 0 else { return nil }

        struct Section { let va, size, raw: UInt32 }
        let sectionTable = opt + Int(optSize)
        var sections: [Section] = []
        for i in 0..<Int(sectionCount) {
            let s = sectionTable + i * 40
            guard let vsize = r.u32(s + 8), let va = r.u32(s + 12), let rawSize = r.u32(s + 16),
                  let raw = r.u32(s + 20) else { return nil }
            sections.append(Section(va: va, size: max(vsize, rawSize), raw: raw))
        }
        func offset(ofRVA rva: UInt32) -> Int? {
            for s in sections where rva >= s.va && rva < s.va &+ s.size {
                return Int(s.raw) + Int(rva - s.va)
            }
            return nil
        }
        guard let root = offset(ofRVA: rsrcRVA) else { return nil }

        // A resource directory: 16-byte header, then (named + id) entries of 8 bytes each.
        func entries(_ dir: Int) -> [(id: UInt32?, offset: UInt32, isDir: Bool)] {
            guard let named = r.u16(dir + 12), let ids = r.u16(dir + 14) else { return [] }
            return (0..<min(Int(named) + Int(ids), 4096)).compactMap { i in
                let e = dir + 16 + i * 8
                guard let name = r.u32(e), let off = r.u32(e + 4) else { return nil }
                return (name & 0x8000_0000 == 0 ? name : nil, off & 0x7FFF_FFFF, off & 0x8000_0000 != 0)
            }
        }
        /// Data of the first language under `type`/`id` (or the first id when nil).
        func resource(type: UInt32, id: UInt32?) -> [UInt8]? {
            guard let typeDir = entries(root).first(where: { $0.id == type && $0.isDir }) else { return nil }
            let names = entries(root + Int(typeDir.offset))
            guard let nameDir = (id == nil ? names.first : names.first(where: { $0.id == id })), nameDir.isDir,
                  let lang = entries(root + Int(nameDir.offset)).first, !lang.isDir else { return nil }
            let entry = root + Int(lang.offset)
            guard let dataRVA = r.u32(entry), let size = r.u32(entry + 4), let at = offset(ofRVA: dataRVA)
            else { return nil }
            return r.slice(at, Int(size))
        }

        guard let group = resource(type: rtGroupIcon, id: nil) else { return nil }
        let g = ByteReader(Data(group))
        guard let count = g.u16(4), count > 0 else { return nil }

        // GRPICONDIRENTRY is 14 bytes (ends in a resource id); ICONDIRENTRY is 16 (ends in a file offset).
        var images: [(entry: [UInt8], data: [UInt8])] = []
        for i in 0..<Int(count) {
            let e = 6 + i * 14
            guard let head = g.slice(e, 12), let iconID = g.u16(e + 12),
                  let image = resource(type: rtIcon, id: UInt32(iconID)) else { continue }
            images.append((head, image))
        }
        guard !images.isEmpty else { return nil }

        var ico = Data([0, 0, 1, 0, UInt8(images.count & 0xFF), UInt8(images.count >> 8)])
        var dataOffset = 6 + images.count * 16
        for img in images {
            var head = img.entry
            let size = UInt32(img.data.count)
            head.replaceSubrange(8..<12, with: withUnsafeBytes(of: size.littleEndian, Array.init))
            ico.append(contentsOf: head)
            ico.append(contentsOf: withUnsafeBytes(of: UInt32(dataOffset).littleEndian, Array.init))
            dataOffset += img.data.count
        }
        for img in images { ico.append(contentsOf: img.data) }
        return ico
    }
}
