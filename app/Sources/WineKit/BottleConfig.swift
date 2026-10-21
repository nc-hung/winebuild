import Foundation

/// Per-bottle settings kept by the manager in `<prefix>/.winebuild/bottle.json`. Settings Wine itself reads
/// (Windows version, DLL overrides, Retina) live in the prefix registry instead, so plain `wrun` sees them too.
public struct BottleConfig: Codable, Equatable, Sendable {
    public enum Graphics: String, Codable, CaseIterable, Sendable {
        case wined3d, dxvk
    }

    public var graphics: Graphics = .wined3d
    /// `DXVK_HUD` value; empty means off. Only used with `.dxvk`.
    public var dxvkHUD: String = ""
    /// Run without `WINEDEBUG=-all` (wrun `-v`).
    public var debugLog: Bool = false
    public var environment: [EnvironmentVariable] = []
    public var pinnedApps: [PinnedApp] = []
    /// Start-menu/desktop shortcuts the user removed from the list (Unix paths of the .lnk files).
    public var hiddenShortcuts: [String] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        graphics = (try? c.decodeIfPresent(Graphics.self, forKey: .graphics)) ?? .wined3d
        dxvkHUD = try c.decodeIfPresent(String.self, forKey: .dxvkHUD) ?? ""
        debugLog = try c.decodeIfPresent(Bool.self, forKey: .debugLog) ?? false
        environment = try c.decodeIfPresent([EnvironmentVariable].self, forKey: .environment) ?? []
        pinnedApps = try c.decodeIfPresent([PinnedApp].self, forKey: .pinnedApps) ?? []
        hiddenShortcuts = try c.decodeIfPresent([String].self, forKey: .hiddenShortcuts) ?? []
    }
}

public struct EnvironmentVariable: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }

    // `id` is only for SwiftUI lists; it isn't stored, so hand-edited JSON doesn't need one.
    private enum CodingKeys: String, CodingKey { case name, value }

    public var isValid: Bool {
        guard let first = name.unicodeScalars.first, !CharacterSet.decimalDigits.contains(first) else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_")
        return name.unicodeScalars.allSatisfy(allowed.contains)
    }
}

/// An executable the user added by hand (e.g. a game launcher that installs no shortcut).
public struct PinnedApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    /// Unix path of the .exe.
    public var path: String
    public var arguments: String = ""
    /// Unix path; empty means the executable's own directory.
    public var workingDirectory: String = ""

    public init(name: String, path: String, arguments: String = "", workingDirectory: String = "") {
        self.name = name
        self.path = path
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }

    private enum CodingKeys: String, CodingKey { case name, path, arguments, workingDirectory }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        arguments = try c.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        workingDirectory = try c.decodeIfPresent(String.self, forKey: .workingDirectory) ?? ""
    }
}

/// Values for `HKCU\Software\Wine` → `Version`, newest first.
public enum WindowsVersion: String, CaseIterable, Identifiable, Sendable {
    case win11, win10, win81, win8, win7, vista, winxp

    public var id: String { rawValue }
    /// Wine's default when the key is absent.
    public static let wineDefault = WindowsVersion.win10

    public var label: String {
        switch self {
        case .win11: "Windows 11"
        case .win10: "Windows 10"
        case .win81: "Windows 8.1"
        case .win8: "Windows 8"
        case .win7: "Windows 7"
        case .vista: "Windows Vista"
        case .winxp: "Windows XP"
        }
    }
}

/// A `HKCU\Software\Wine\DllOverrides` value.
public enum DLLOverrideMode: String, CaseIterable, Identifiable, Sendable {
    case nativeBuiltin = "native,builtin"
    case builtinNative = "builtin,native"
    case native
    case builtin
    case disabled = ""

    public var id: String { rawValue }

    /// Accepts the spellings Wine accepts (`n,b`, `native, builtin`, ...).
    public init?(registryValue: String) {
        let parts = registryValue.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let norm = parts.map { $0 == "n" ? "native" : $0 == "b" ? "builtin" : $0 }.joined(separator: ",")
        self.init(rawValue: norm)
    }
}

/// Override sets for problems this repo has run into (see AGENTS.md).
public struct DLLOverridePreset: Identifiable, Sendable {
    public var id: String
    public var overrides: [String: DLLOverrideMode]

    public static let cefSoftwareCompositing = DLLOverridePreset(
        id: "cef-software", overrides: ["libegl": .disabled, "libglesv2": .disabled])
}
