import Foundation

/// Where the winebuild checkout lives and the files the manager needs from it.
public struct WinePaths: Equatable, Sendable {
    public var root: URL

    public init(root: URL) { self.root = root.standardizedFileURL }

    public static var defaultRoot: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("winebuild") }

    public var wrun: URL { root.appendingPathComponent("scripts/wrun") }
    public var wine: URL { root.appendingPathComponent("dist/wine/bin/wine") }
    public var wineserver: URL { root.appendingPathComponent("dist/wine/bin/wineserver") }
    public var dxvk: URL { root.appendingPathComponent("dist/dxvk") }
    public var prefixes: URL { root.appendingPathComponent("prefixes") }
    public var versionsEnv: URL { root.appendingPathComponent("scripts/versions.env") }

    /// Same value `wrun` exports; needed when calling Wine binaries directly (e.g. `wineserver -k`).
    public var dyldFallbackPath: String {
        [root.appendingPathComponent("dist/wine/lib").path, root.appendingPathComponent("deps/x86_64/lib").path,
         "/usr/local/lib", "/usr/lib"].joined(separator: ":")
    }

    public var isBuilt: Bool { FileManager.default.isExecutableFile(atPath: wine.path) }
    public var hasDXVK: Bool { FileManager.default.fileExists(atPath: dxvk.appendingPathComponent("x64/d3d11.dll").path) }

    /// `WINE_TAG=...` from versions.env (the pinned source tag, e.g. `wine-11.0`); cheaper than running
    /// `wine --version`.
    public var wineVersion: String? {
        guard let text = try? String(contentsOf: versionsEnv, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("WINE_TAG=") {
            return line.dropFirst("WINE_TAG=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        return nil
    }
}

/// A Wine prefix under `prefixes/`, plus the manager's settings for it in `<prefix>/.winebuild/`.
public struct Bottle: Identifiable, Hashable, Sendable {
    public var url: URL
    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public init(url: URL) { self.url = url.standardizedFileURL }

    public var driveC: URL { url.appendingPathComponent("drive_c") }
    public var metadataDir: URL { url.appendingPathComponent(".winebuild") }
    public var configURL: URL { metadataDir.appendingPathComponent("bottle.json") }
    public var logsDir: URL { metadataDir.appendingPathComponent("logs") }
    public var userReg: URL { url.appendingPathComponent("user.reg") }
    public var systemReg: URL { url.appendingPathComponent("system.reg") }

    /// wineboot has run at least once.
    public var isInitialized: Bool { FileManager.default.fileExists(atPath: systemReg.path) }
    public var hasDXVKInstalled: Bool { FileManager.default.fileExists(atPath: url.appendingPathComponent(".wrun-dxvk").path) }

    public func loadConfig() -> BottleConfig {
        guard let data = try? Data(contentsOf: configURL) else { return BottleConfig() }
        return (try? JSONDecoder().decode(BottleConfig.self, from: data)) ?? BottleConfig()
    }

    public func saveConfig(_ config: BottleConfig) throws {
        try FileManager.default.createDirectory(at: metadataDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(config).write(to: configURL, options: .atomic)
    }

    public func registry() -> RegistryFile { RegistryFile(contentsOf: userReg) }

    /// Maps a Windows path (`C:\foo\bar.exe`) to the Unix path inside this prefix, following `dosdevices/x:`.
    public func unixPath(forWindowsPath path: String) -> URL? {
        let p = path.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        guard p.count >= 2, p.dropFirst().first == ":", let letter = p.first?.lowercased() else { return nil }
        let device = url.appendingPathComponent("dosdevices/\(letter):")
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: device.path) else {
            return letter == "c" ? Self.append(p.dropFirst(2), to: driveC) : nil
        }
        let base = dest.hasPrefix("/") ? URL(fileURLWithPath: dest) : device.deletingLastPathComponent().appendingPathComponent(dest)
        return Self.append(p.dropFirst(2), to: base.standardizedFileURL)
    }

    /// Inverse of `unixPath(forWindowsPath:)` for paths under drive_c; anything else is reached through Z:.
    public func windowsPath(forUnixPath unix: URL) -> String {
        let p = unix.standardizedFileURL.path
        let c = driveC.path
        if p == c || p.hasPrefix(c + "/") {
            return "C:" + p.dropFirst(c.count).replacingOccurrences(of: "/", with: "\\").ifEmpty("\\")
        }
        return "Z:" + p.replacingOccurrences(of: "/", with: "\\")
    }

    private static func append(_ rest: Substring, to base: URL) -> URL {
        rest.split(whereSeparator: { $0 == "\\" || $0 == "/" })
            .reduce(base) { $0.appendingPathComponent(String($1)) }
            .standardizedFileURL
    }
}

private extension String {
    func ifEmpty(_ s: String) -> String { isEmpty ? s : self }
}

public enum BottleStore {
    /// Bottles are the directories under `prefixes/` (sorted by name). Hidden directories are skipped.
    public static func bottles(in paths: WinePaths) -> [Bottle] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: paths.prefixes, includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(Bottle.init(url:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Bottle names become directory names and appear in wrun command lines, so keep them plain.
    public static func isValidName(_ name: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return !name.isEmpty && name.count <= 64 && !name.hasPrefix(".")
            && name.unicodeScalars.allSatisfy { allowed.contains($0) && $0.isASCII }
    }
}
