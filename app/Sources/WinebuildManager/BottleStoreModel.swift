import AppKit
import SwiftUI
import WineKit

struct DLLOverrideRow: Identifiable, Equatable {
    var name: String
    var mode: DLLOverrideMode
    var id: String { name.lowercased() }
}

/// State of one bottle for the detail views: its apps, manager config and the registry-backed Wine settings.
@MainActor
final class BottleStoreModel: ObservableObject {
    let bottle: Bottle
    private unowned let app: AppModel

    @Published private(set) var config: BottleConfig
    @Published private(set) var apps: [WinApp] = []
    @Published private(set) var windowsVersion: WindowsVersion = .wineDefault
    @Published private(set) var retina = false
    @Published private(set) var overrides: [DLLOverrideRow] = []
    /// Number of registry writes in flight (each is a `wine reg` run, ~1–2 s under Rosetta).
    @Published private(set) var pendingWrites = 0
    @Published private(set) var loading = false

    init(bottle: Bottle, app: AppModel) {
        self.bottle = bottle
        self.app = app
        config = bottle.loadConfig()
        refresh()
    }

    var launcher: WineLauncher { WineLauncher(paths: app.paths, bottle: bottle, config: config) }

    /// Re-reads config, shortcuts and user.reg. The scan touches the disk, so it runs off the main thread.
    func refresh() {
        config = bottle.loadConfig()
        loading = true
        let bottle = bottle, config = config
        Task.detached(priority: .userInitiated) {
            let apps = AppScanner.apps(in: bottle, config: config)
            let reg = bottle.registry()
            let version = reg.value("Version", in: #"Software\Wine"#).flatMap(WindowsVersion.init(rawValue:)) ?? .wineDefault
            let retina = ["y", "yes", "true", "1"].contains(reg.value("RetinaMode", in: #"Software\Wine\Mac Driver"#)?.lowercased() ?? "")
            let overrides = reg.values(of: #"Software\Wine\DllOverrides"#)
                .compactMap { name, value in DLLOverrideMode(registryValue: value).map { DLLOverrideRow(name: name, mode: $0) } }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            await MainActor.run {
                self.apps = apps
                self.windowsVersion = version
                self.retina = retina
                self.overrides = overrides
                self.loading = false
            }
        }
    }

    // MARK: Manager config (bottle.json)

    func update(_ change: (inout BottleConfig) -> Void) {
        var c = config
        change(&c)
        guard c != config else { return }
        do {
            try bottle.saveConfig(c)
            config = c
        } catch {
            app.runner.lastError = .init(title: "Không lưu được cấu hình", message: error.localizedDescription, logURL: nil)
        }
    }

    func pin(executable: URL, name: String, arguments: String) {
        update { $0.pinnedApps.append(PinnedApp(name: name, path: executable.path, arguments: arguments)) }
        refresh()
    }

    func updatePinned(_ pin: PinnedApp) {
        update { c in
            if let i = c.pinnedApps.firstIndex(where: { $0.id == pin.id }) { c.pinnedApps[i] = pin }
        }
        refresh()
    }

    func remove(_ app: WinApp) {
        update { c in
            switch app.source {
            case .pinned(let id): c.pinnedApps.removeAll { $0.id == id }
            case .shortcut(let lnk): if !c.hiddenShortcuts.contains(lnk.path) { c.hiddenShortcuts.append(lnk.path) }
            }
        }
        refresh()
    }

    func restoreHiddenShortcuts() {
        update { $0.hiddenShortcuts = [] }
        refresh()
    }

    func pinned(for app: WinApp) -> PinnedApp? {
        guard case .pinned(let id) = app.source else { return nil }
        return config.pinnedApps.first { $0.id == id }
    }

    func launch(_ winApp: WinApp) {
        app.runner.launch(launcher.run(winApp), title: winApp.name, bottle: bottle)
    }

    // MARK: Registry-backed settings (applied with `wine reg`, shown optimistically)

    func setWindowsVersion(_ v: WindowsVersion) {
        guard v != windowsVersion else { return }
        windowsVersion = v
        write(launcher.setRegistryValue(key: WineLauncher.wineKey, name: "Version", value: v.rawValue))
    }

    func setRetina(_ on: Bool) {
        guard on != retina else { return }
        retina = on
        write(launcher.setRegistryValue(key: WineLauncher.macDriverKey, name: "RetinaMode", value: on ? "y" : "n"))
    }

    func setOverride(_ name: String, _ mode: DLLOverrideMode) {
        let dll = Self.normalizedDLLName(name)
        guard !dll.isEmpty else { return }
        if let i = overrides.firstIndex(where: { $0.id == dll.lowercased() }) {
            guard overrides[i].mode != mode else { return }
            overrides[i].mode = mode
        } else {
            overrides.append(DLLOverrideRow(name: dll, mode: mode))
            overrides.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        write(launcher.setRegistryValue(key: WineLauncher.dllOverridesKey, name: dll, value: mode.rawValue))
    }

    func removeOverride(_ row: DLLOverrideRow) {
        overrides.removeAll { $0.id == row.id }
        write(launcher.deleteRegistryValue(key: WineLauncher.dllOverridesKey, name: row.name))
    }

    func applyPreset(_ preset: DLLOverridePreset) async {
        for (name, mode) in preset.overrides.sorted(by: { $0.key < $1.key }) {
            setOverride(name, mode)
        }
        while pendingWrites > 0 { try? await Task.sleep(nanoseconds: 200_000_000) }
    }

    /// `libEGL.dll` → `libegl`; Wine matches override names without the extension, case-insensitively.
    static func normalizedDLLName(_ s: String) -> String {
        var n = s.trimmingCharacters(in: .whitespaces)
        if n.lowercased().hasSuffix(".dll") { n.removeLast(4) }
        return n.lowercased()
    }

    /// Registry writes run one after another so their order is kept.
    private var writeChain: Task<Void, Never>?

    private func write(_ cmd: WineCommand) {
        pendingWrites += 1
        let previous = writeChain
        let runner = app.runner, bottle = bottle
        writeChain = Task {
            await previous?.value
            let status = await runner.run(cmd, title: "reg", bottle: bottle, keepLogOnSuccess: false)
            if status != 0 {
                runner.lastError = .init(title: "Ghi registry thất bại", message: "wine reg trả về mã \(status).", logURL: nil)
            }
            pendingWrites -= 1
        }
    }
}

/// Icons of Windows executables, extracted once per path in the background.
@MainActor
final class IconCache: ObservableObject {
    static let shared = IconCache()
    @Published private var icons: [String: NSImage] = [:]
    private var requested = Set<String>()

    func icon(for exe: URL) -> NSImage? {
        let key = exe.path
        if let i = icons[key] { return i }
        if requested.insert(key).inserted {
            Task.detached(priority: .utility) {
                guard let data = PEIcon.icoData(contentsOf: exe), let image = NSImage(data: data) else { return }
                await MainActor.run { IconCache.shared.icons[key] = image }
            }
        }
        return nil
    }
}
