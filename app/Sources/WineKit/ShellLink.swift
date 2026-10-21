import Foundation

/// The parts of a Windows shortcut (.lnk, MS-SHLLINK) needed to launch its target.
public struct ShellLink: Equatable, Sendable {
    /// Windows path of the target, e.g. `C:\Program Files (x86)\Notepad++\notepad++.exe`.
    public var targetPath: String
    public var arguments: String = ""
    public var workingDirectory: String = ""
    public var name: String = ""
    public var relativePath: String = ""
    public var iconLocation: String = ""

    public init(targetPath: String) { self.targetPath = targetPath }

    private struct Flags: OptionSet {
        let rawValue: UInt32
        static let hasTargetIDList = Flags(rawValue: 1 << 0)
        static let hasLinkInfo = Flags(rawValue: 1 << 1)
        static let hasName = Flags(rawValue: 1 << 2)
        static let hasRelativePath = Flags(rawValue: 1 << 3)
        static let hasWorkingDir = Flags(rawValue: 1 << 4)
        static let hasArguments = Flags(rawValue: 1 << 5)
        static let hasIconLocation = Flags(rawValue: 1 << 6)
        static let isUnicode = Flags(rawValue: 1 << 7)
    }

    public static func parse(contentsOf url: URL) -> ShellLink? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    public static func parse(_ data: Data) -> ShellLink? {
        let r = ByteReader(data)
        // Header: size 0x4C, then the LinkCLSID 00021401-0000-0000-C000-000000000046.
        let clsid: [UInt8] = [0x01, 0x14, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0, 0, 0, 0, 0, 0, 0x46]
        guard r.u32(0) == 0x4C, r.slice(4, 16) == clsid, let rawFlags = r.u32(0x14) else { return nil }
        let flags = Flags(rawValue: rawFlags)
        var p = 0x4C

        if flags.contains(.hasTargetIDList) {
            guard let size = r.u16(p) else { return nil }
            p += 2 + Int(size)
        }

        var target = ""
        if flags.contains(.hasLinkInfo) {
            guard let size = r.u32(p), let headerSize = r.u32(p + 4), let infoFlags = r.u32(p + 8) else { return nil }
            let hasLocalPath = infoFlags & 1 != 0
            if hasLocalPath {
                var base = ""
                var suffix = ""
                if headerSize >= 0x24, let bo = r.u32(p + 0x1C), let so = r.u32(p + 0x20) {
                    base = r.wideCString(p + Int(bo)) ?? ""
                    suffix = r.wideCString(p + Int(so)) ?? ""
                }
                if base.isEmpty, let bo = r.u32(p + 0x10), let so = r.u32(p + 0x18) {
                    base = r.cString(p + Int(bo)) ?? ""
                    suffix = r.cString(p + Int(so)) ?? ""
                }
                target = joinWindowsPath(base, suffix)
            }
            p += Int(size)
        }

        // StringData, in this fixed order, each a u16 character count then the characters.
        let unicode = flags.contains(.isUnicode)
        func readString() -> String? {
            guard let n = r.u16(p) else { return nil }
            let chars = Int(n)
            let s: String?
            if unicode {
                s = r.wideString(p + 2, chars: chars)
                p += 2 + chars * 2
            } else {
                s = r.slice(p + 2, chars).flatMap { String(bytes: $0, encoding: .isoLatin1) }
                p += 2 + chars
            }
            // Wine counts the terminating NUL in these lengths.
            return s.map { String($0.prefix { $0 != "\0" }) }
        }
        var link = ShellLink(targetPath: target)
        if flags.contains(.hasName) { link.name = readString() ?? "" }
        if flags.contains(.hasRelativePath) { link.relativePath = readString() ?? "" }
        if flags.contains(.hasWorkingDir) { link.workingDirectory = readString() ?? "" }
        if flags.contains(.hasArguments) { link.arguments = readString() ?? "" }
        if flags.contains(.hasIconLocation) { link.iconLocation = readString() ?? "" }

        if link.targetPath.isEmpty, !link.relativePath.isEmpty, !link.workingDirectory.isEmpty {
            link.targetPath = joinWindowsPath(link.workingDirectory, link.relativePath)
        }
        return link.targetPath.isEmpty ? nil : link
    }

    static func joinWindowsPath(_ base: String, _ suffix: String) -> String {
        guard !suffix.isEmpty else { return base }
        guard !base.isEmpty else { return suffix }
        var rel = suffix
        while rel.hasPrefix(".\\") { rel.removeFirst(2) }
        return base.hasSuffix("\\") ? base + rel : base + "\\" + rel
    }
}
