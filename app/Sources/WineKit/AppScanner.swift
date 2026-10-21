import Foundation

/// A launchable program in a bottle: from a Start-menu/desktop shortcut, or pinned by the user.
public struct WinApp: Identifiable, Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case shortcut(URL)
        case pinned(UUID)
    }

    public var name: String
    public var executable: URL
    public var arguments: String
    public var workingDirectory: URL?
    public var source: Source

    public var id: String {
        switch source {
        case .shortcut(let url): "lnk:" + url.path
        case .pinned(let uuid): "pin:" + uuid.uuidString
        }
    }

    public var isUninstaller: Bool {
        let n = (name + " " + executable.lastPathComponent).lowercased()
        return n.contains("uninst") || n.contains("gỡ cài đặt") || n.contains("remove ")
    }
}

public enum AppScanner {
    /// Directories Wine and installers put shortcuts in, relative to drive_c. `*` is any user name.
    static let shortcutDirs = [
        "ProgramData/Microsoft/Windows/Start Menu/Programs",
        "users/*/AppData/Roaming/Microsoft/Windows/Start Menu/Programs",
        "users/*/Desktop",
        "users/Public/Desktop",
    ]

    /// Folders under Program Files that come with Wine and hold nothing to launch.
    static let builtinFolders: Set<String> = [
        "common files", "internet explorer", "windows media player", "windows nt", "windows mail",
        "windows photo viewer", "windows sidebar", "windowspowershell", "microsoft.net", "msbuild", "reference assemblies",
    ]

    /// Shortcuts whose target exists, plus pinned apps; deduplicated by target, sorted by name.
    public static func apps(in bottle: Bottle, config: BottleConfig) -> [WinApp] {
        let hidden = Set(config.hiddenShortcuts)
        var seen = Set<String>()
        var out: [WinApp] = []
        for pin in config.pinnedApps {
            let exe = URL(fileURLWithPath: pin.path)
            seen.insert(exe.standardizedFileURL.path.lowercased())
            out.append(WinApp(name: pin.name, executable: exe, arguments: pin.arguments,
                              workingDirectory: pin.workingDirectory.isEmpty ? nil : URL(fileURLWithPath: pin.workingDirectory),
                              source: .pinned(pin.id)))
        }
        for lnk in shortcutFiles(in: bottle) where !hidden.contains(lnk.path) {
            guard let link = ShellLink.parse(contentsOf: lnk),
                  let exe = bottle.unixPath(forWindowsPath: link.targetPath),
                  exe.pathExtension.lowercased() == "exe",
                  FileManager.default.fileExists(atPath: exe.path),
                  seen.insert(exe.path.lowercased()).inserted else { continue }
            let wd = link.workingDirectory.isEmpty ? nil : bottle.unixPath(forWindowsPath: link.workingDirectory)
            out.append(WinApp(name: lnk.deletingPathExtension().lastPathComponent, executable: exe,
                              arguments: link.arguments, workingDirectory: wd, source: .shortcut(lnk)))
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func shortcutFiles(in bottle: Bottle) -> [URL] {
        let fm = FileManager.default
        var dirs: [URL] = []
        for pattern in shortcutDirs {
            let parts = pattern.split(separator: "/").map(String.init)
            if let star = parts.firstIndex(of: "*") {
                let parent = parts[..<star].reduce(bottle.driveC) { $0.appendingPathComponent($1) }
                for user in (try? fm.contentsOfDirectory(atPath: parent.path)) ?? [] where user != "Public" {
                    dirs.append(parts[(star + 1)...].reduce(parent.appendingPathComponent(user)) { $0.appendingPathComponent($1) })
                }
            } else {
                dirs.append(parts.reduce(bottle.driveC) { $0.appendingPathComponent($1) })
            }
        }
        var files: [URL] = []
        for dir in dirs {
            guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in e where url.pathExtension.lowercased() == "lnk" { files.append(url) }
        }
        return files
    }

    /// Executables an installer may have left without a shortcut: everything under Program Files (and other
    /// non-Windows top-level folders of drive_c), at most `maxDepth` folders deep, uninstallers last.
    public static func candidateExecutables(in bottle: Bottle, maxDepth: Int = 4, limit: Int = 500) -> [URL] {
        let fm = FileManager.default
        let skipTop: Set<String> = ["windows", "users", "programdata"]
        let tops = ((try? fm.contentsOfDirectory(at: bottle.driveC, includingPropertiesForKeys: [.isDirectoryKey],
                                                  options: [.skipsHiddenFiles])) ?? [])
            .filter { !skipTop.contains($0.lastPathComponent.lowercased()) }
        var found: [URL] = []
        for top in tops {
            let base = top.pathComponents.count
            guard let e = fm.enumerator(at: top, includingPropertiesForKeys: [.isDirectoryKey],
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                let depth = url.pathComponents.count - base
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if depth > maxDepth || (depth == 1 && builtinFolders.contains(url.lastPathComponent.lowercased())) {
                        e.skipDescendants()
                    }
                    continue
                }
                if url.pathExtension.lowercased() == "exe" { found.append(url.standardizedFileURL) }
                if found.count >= limit { break }
            }
        }
        func rank(_ u: URL) -> (Int, Int, String) {
            let name = u.lastPathComponent.lowercased()
            let junk = ["uninst", "unins0", "crash", "report", "update", "setup", "helper", "vc_redist", "dxsetup"]
            return (junk.contains(where: name.contains) ? 1 : 0, u.pathComponents.count, name)
        }
        return found.sorted { rank($0) < rank($1) }
    }
}
