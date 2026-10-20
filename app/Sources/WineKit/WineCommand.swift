import Foundation

/// A fully resolved process to start: everything goes through `scripts/wrun` except `wineserver`, which wrun
/// would hand to Wine as a Windows program.
public struct WineCommand: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]
    /// Added to the manager's own environment.
    public var environment: [String: String]
    public var currentDirectory: URL?

    public init(executable: URL, arguments: [String], environment: [String: String] = [:], currentDirectory: URL? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.currentDirectory = currentDirectory
    }

    /// Shell-style rendering for logs and "copy command".
    public var displayString: String {
        let env = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\(Self.shellQuote($0.value))" }
        return (env + ([executable.path] + arguments).map(Self.shellQuote)).joined(separator: " ")
    }

    static func shellQuote(_ s: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:=,+@%")
        if !s.isEmpty, s.unicodeScalars.allSatisfy(safe.contains) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Builds wrun command lines for one bottle.
public struct WineLauncher: Sendable {
    public var paths: WinePaths
    public var bottle: Bottle
    public var config: BottleConfig

    public init(paths: WinePaths, bottle: Bottle, config: BottleConfig) {
        self.paths = paths
        self.bottle = bottle
        self.config = config
    }

    /// wrun options shared by every run in this bottle.
    var wrunOptions: [String] {
        var opts = ["-p", bottle.url.path]
        if config.graphics == .dxvk {
            let hud = config.dxvkHUD.trimmingCharacters(in: .whitespaces)
            opts += hud.isEmpty ? ["--dxvk"] : ["--hud", hud]
        }
        if config.debugLog { opts.append("-v") }
        return opts
    }

    var environment: [String: String] {
        var env = ["WB_ROOT": paths.root.path]
        for v in config.environment where v.isValid { env[v.name] = v.value }
        return env
    }

    private func wrun(_ args: [String], options: [String]? = nil, in dir: URL? = nil) -> WineCommand {
        WineCommand(executable: paths.wrun, arguments: (options ?? wrunOptions) + ["--"] + args,
                    environment: environment, currentDirectory: dir)
    }

    /// Runs a Windows program from its own directory (or the given one), which many games rely on.
    public func run(executable: URL, arguments: String = "", workingDirectory: URL? = nil) -> WineCommand {
        wrun([executable.path] + Self.splitWindowsCommandLine(arguments),
             in: workingDirectory ?? executable.deletingLastPathComponent())
    }

    public func run(_ app: WinApp) -> WineCommand {
        run(executable: app.executable, arguments: app.arguments, workingDirectory: app.workingDirectory)
    }

    /// Installer or any file the user drops on the window: .msi through msiexec, batch files through cmd.
    public func open(file: URL) -> WineCommand {
        switch file.pathExtension.lowercased() {
        case "msi", "msp": wrun(["msiexec", "/i", file.path], in: file.deletingLastPathComponent())
        case "bat", "cmd": wrun(["cmd", "/c", file.path], in: file.deletingLastPathComponent())
        case "lnk": wrun(["start", "/unix", file.path])
        default: run(executable: file)
        }
    }

    /// Built-in Wine programs (winecfg, regedit, taskmgr, ...). Graphics flags don't matter for these.
    public func builtin(_ program: String, _ args: [String] = []) -> WineCommand {
        wrun([program] + args, options: ["-p", bottle.url.path])
    }

    public func initialize() -> WineCommand {
        WineCommand(executable: paths.wrun, arguments: ["-p", bottle.url.path, "init"], environment: environment)
    }

    public func setRegistryValue(key: String, name: String, value: String) -> WineCommand {
        builtin("reg", ["add", key, "/v", name, "/t", "REG_SZ", "/d", value, "/f"])
    }

    public func deleteRegistryValue(key: String, name: String) -> WineCommand {
        builtin("reg", ["delete", key, "/v", name, "/f"])
    }

    /// Stops every process in the bottle.
    public func killAll() -> WineCommand {
        WineCommand(executable: paths.wineserver, arguments: ["-k"],
                    environment: ["WINEPREFIX": bottle.url.path, "DYLD_FALLBACK_LIBRARY_PATH": paths.dyldFallbackPath])
    }

    /// Splits a Windows command line into argv the way the MS C runtime does (quotes group, `\"` is a literal
    /// quote, backslashes elsewhere are literal). Wine re-quotes argv when it rebuilds the command line.
    public static func splitWindowsCommandLine(_ line: String) -> [String] {
        var args: [String] = []
        var cur = ""
        var inArg = false
        var quoted = false
        var backslashes = 0
        for c in line {
            if c == "\\" { backslashes += 1; inArg = true; continue }
            if c == "\"" {
                cur += String(repeating: "\\", count: backslashes / 2)
                if backslashes % 2 == 1 { cur.append("\"") } else { quoted.toggle() }
                backslashes = 0
                inArg = true
                continue
            }
            cur += String(repeating: "\\", count: backslashes)
            backslashes = 0
            if (c == " " || c == "\t") && !quoted {
                if inArg { args.append(cur); cur = ""; inArg = false }
                continue
            }
            cur.append(c)
            inArg = true
        }
        cur += String(repeating: "\\", count: backslashes)
        if inArg { args.append(cur) }
        return args
    }
}

public extension WineLauncher {
    static let wineKey = #"HKCU\Software\Wine"#
    static let dllOverridesKey = #"HKCU\Software\Wine\DllOverrides"#
    static let macDriverKey = #"HKCU\Software\Wine\Mac Driver"#
}
