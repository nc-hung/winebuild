import AppKit
import SwiftUI
import WineKit

enum DetailTab: String, CaseIterable, Identifiable {
    case apps, settings, tools, logs
    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: "Ứng dụng"
        case .settings: "Cấu hình"
        case .tools: "Công cụ"
        case .logs: "Nhật ký"
        }
    }

    var symbol: String {
        switch self {
        case .apps: "square.grid.2x2"
        case .settings: "slider.horizontal.3"
        case .tools: "wrench.and.screwdriver"
        case .logs: "doc.text.magnifyingglass"
        }
    }
}

/// App-wide state: the winebuild root, the bottles in it, the selection and running processes.
@MainActor
final class AppModel: ObservableObject {
    static let rootDefaultsKey = "winebuildRoot"

    @Published var paths: WinePaths
    @Published private(set) var bottles: [Bottle] = []
    @Published var selection: Bottle.ID?
    @Published var tab: DetailTab = .apps
    /// Bottles with a long operation in progress (creation, wineboot), with a short status text.
    @Published var busy: [Bottle.ID: String] = [:]
    @Published var showNewBottle = false
    @Published var pendingTrash: Bottle?

    let runner = ProcessRunner()
    private var stores: [Bottle.ID: BottleStoreModel] = [:]

    init() {
        // Saved choice, else the repo the .app was built from (scripts/build-app.sh records it), else ~/winebuild.
        let saved = UserDefaults.standard.string(forKey: Self.rootDefaultsKey)
            ?? Bundle.main.object(forInfoDictionaryKey: "WinebuildRoot") as? String
        paths = WinePaths(root: saved.map { URL(fileURLWithPath: $0) } ?? WinePaths.defaultRoot)
        reload()
        selection = bottles.first?.id
    }

    var selectedBottle: Bottle? { bottles.first { $0.id == selection } }

    func setRoot(_ url: URL) {
        paths = WinePaths(root: url)
        UserDefaults.standard.set(url.path, forKey: Self.rootDefaultsKey)
        stores.removeAll()
        reload()
        selection = bottles.first?.id
    }

    func reload() {
        bottles = BottleStore.bottles(in: paths)
        if let sel = selection, !bottles.contains(where: { $0.id == sel }) { selection = bottles.first?.id }
    }

    /// Per-bottle view model, kept while the app runs so icons and settings aren't reloaded on every click.
    func store(for bottle: Bottle) -> BottleStoreModel {
        if let s = stores[bottle.id] { return s }
        let s = BottleStoreModel(bottle: bottle, app: self)
        stores[bottle.id] = s
        return s
    }

    // MARK: Bottle lifecycle

    func createBottle(named name: String, installDXVK: Bool, cefFix: Bool) {
        let bottle = Bottle(url: paths.prefixes.appendingPathComponent(name))
        do {
            try FileManager.default.createDirectory(at: bottle.url, withIntermediateDirectories: true)
        } catch {
            runner.lastError = .init(title: "Không tạo được bottle", message: error.localizedDescription, logURL: nil)
            return
        }
        reload()
        selection = bottle.id
        tab = .apps
        busy[bottle.id] = "Đang khởi tạo Windows…"
        let launcher = WineLauncher(paths: paths, bottle: bottle, config: BottleConfig())
        Task {
            let status = await runner.run(launcher.initialize(), title: "wineboot", bottle: bottle)
            if status == 0, installDXVK {
                busy[bottle.id] = "Đang cài DXVK…"
                _ = await runner.run(launcher.builtinWrun("dxvk-install"), title: "dxvk-install", bottle: bottle)
            }
            if status == 0, cefFix {
                busy[bottle.id] = "Đang áp mẹo CEF…"
                let s = store(for: bottle)
                await s.applyPreset(.cefSoftwareCompositing)
            }
            busy[bottle.id] = nil
            if status != 0 {
                runner.lastError = .init(title: "Khởi tạo bottle “\(name)” thất bại",
                                         message: "wineboot trả về mã \(status).", logURL: nil)
            }
            store(for: bottle).refresh()
        }
    }

    func reinitialize(_ bottle: Bottle) {
        busy[bottle.id] = "Đang cập nhật bottle…"
        Task {
            _ = await runner.run(WineLauncher(paths: paths, bottle: bottle, config: bottle.loadConfig()).initialize(),
                                 title: "wineboot", bottle: bottle)
            busy[bottle.id] = nil
            store(for: bottle).refresh()
        }
    }

    /// `wrun dxvk-install`: copies the DXVK DLLs into the bottle's system32/syswow64.
    func installDXVK(in bottle: Bottle) {
        busy[bottle.id] = "Đang cài DXVK…"
        let cmd = WineLauncher(paths: paths, bottle: bottle, config: bottle.loadConfig()).builtinWrun("dxvk-install")
        Task {
            let status = await runner.run(cmd, title: "dxvk-install", bottle: bottle)
            busy[bottle.id] = nil
            if status != 0 {
                runner.lastError = .init(title: "Cài DXVK thất bại", message: "wrun dxvk-install trả về mã \(status).", logURL: nil)
            }
            store(for: bottle).refresh()
        }
    }

    func killAll(in bottle: Bottle) {
        let cmd = WineLauncher(paths: paths, bottle: bottle, config: BottleConfig()).killAll()
        Task { _ = await runner.run(cmd, title: "wineserver-k", bottle: bottle, keepLogOnSuccess: false) }
    }

    /// Stops the bottle, then moves its folder to the Trash (recoverable from Finder).
    func trash(_ bottle: Bottle) {
        busy[bottle.id] = "Đang dừng…"
        Task {
            _ = await runner.run(WineLauncher(paths: paths, bottle: bottle, config: BottleConfig()).killAll(),
                                 title: "wineserver-k", bottle: bottle)
            busy[bottle.id] = nil
            do {
                try FileManager.default.trashItem(at: bottle.url, resultingItemURL: nil)
                stores[bottle.id] = nil
                reload()
            } catch {
                runner.lastError = .init(title: "Không chuyển được vào Thùng rác", message: error.localizedDescription, logURL: nil)
            }
        }
    }

    // MARK: Files

    func chooseAndRun(in bottle: Bottle) {
        let panel = NSOpenPanel()
        panel.title = "Chọn chương trình hoặc bộ cài Windows"
        panel.prompt = "Chạy"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url, in: bottle)
    }

    static let runnableExtensions: Set<String> = ["exe", "msi", "msp", "bat", "cmd", "lnk"]

    func open(_ url: URL, in bottle: Bottle) {
        guard Self.runnableExtensions.contains(url.pathExtension.lowercased()) else {
            runner.lastError = .init(title: "Không mở được \(url.lastPathComponent)",
                                     message: "Chỉ hỗ trợ .exe, .msi, .bat, .cmd và .lnk.", logURL: nil)
            return
        }
        let launcher = WineLauncher(paths: paths, bottle: bottle, config: bottle.loadConfig())
        runner.launch(launcher.open(file: url), title: url.deletingPathExtension().lastPathComponent, bottle: bottle)
    }

    /// Opens a Terminal window with the Wine environment of `bottle` (`wrun shell`).
    func openShell(for bottle: Bottle) {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("winebuild-\(bottle.name).command")
        let body = "#!/bin/bash\nexec \(shellQuote(paths.wrun.path)) -p \(shellQuote(bottle.url.path)) shell\n"
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch {
            runner.lastError = .init(title: "Không mở được Terminal", message: error.localizedDescription, logURL: nil)
        }
    }

    private func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

extension WineLauncher {
    /// `wrun -p PREFIX <subcommand>` (init, dxvk-install).
    func builtinWrun(_ sub: String) -> WineCommand {
        WineCommand(executable: paths.wrun, arguments: ["-p", bottle.url.path, sub], environment: ["WB_ROOT": paths.root.path])
    }
}
