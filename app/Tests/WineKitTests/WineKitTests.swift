import Foundation
import Testing
@testable import WineKit

@Suite struct ShellLinkTests {
    @Test func parsesWineCreatedShortcut() throws {
        // Written by Wine's shell32 when the Notepad++ installer created its Start-menu entry.
        let url = try #require(Bundle.module.url(forResource: "Fixtures/notepadpp", withExtension: "lnk"))
        let link = try #require(ShellLink.parse(contentsOf: url))
        #expect(link.targetPath == #"C:\Program Files (x86)\Notepad++\notepad++.exe"#)
        #expect(link.workingDirectory == #"C:\Program Files (x86)\Notepad++"#)
        #expect(link.arguments == "")
    }

    @Test func rejectsOtherFiles() {
        #expect(ShellLink.parse(Data("not a shortcut".utf8)) == nil)
        #expect(ShellLink.parse(Data()) == nil)
        // Valid header, truncated right after it: no crash, no result.
        var header = Data([0x4C, 0, 0, 0, 0x01, 0x14, 0x02, 0, 0, 0, 0, 0, 0xC0, 0, 0, 0, 0, 0, 0, 0x46])
        header.append(contentsOf: [0x03, 0, 0, 0])
        #expect(ShellLink.parse(header) == nil)
    }

    @Test func joinsPaths() {
        #expect(ShellLink.joinWindowsPath(#"C:\"#, "a.exe") == #"C:\a.exe"#)
        #expect(ShellLink.joinWindowsPath(#"C:\Games"#, #".\a.exe"#) == #"C:\Games\a.exe"#)
        #expect(ShellLink.joinWindowsPath(#"C:\Games\a.exe"#, "") == #"C:\Games\a.exe"#)
    }
}

@Suite struct PEIconTests {
    /// Minimal PE32+ with one .rsrc section holding RT_ICON #1 and RT_GROUP_ICON #1.
    static func makePE(iconBytes: [UInt8]) -> Data {
        var f = [UInt8](repeating: 0, count: 0x400)
        func put16(_ at: Int, _ v: Int) { f[at] = UInt8(v & 0xFF); f[at + 1] = UInt8((v >> 8) & 0xFF) }
        func put32(_ at: Int, _ v: Int) { for i in 0..<4 { f[at + i] = UInt8((v >> (8 * i)) & 0xFF) } }
        f[0] = 0x4D; f[1] = 0x5A
        put32(0x3C, 0x40)
        f[0x40] = 0x50; f[0x41] = 0x45
        put16(0x44, 0x8664); put16(0x46, 1); put16(0x54, 240)
        let opt = 0x58
        put16(opt, 0x20B)
        let rsrcVA = 0x1000, raw = 0x200
        put32(opt + 112 + 16, rsrcVA); put32(opt + 112 + 20, 0x100)
        let sec = opt + 240
        for (i, c) in ".rsrc".utf8.enumerated() { f[sec + i] = c }
        put32(sec + 8, 0x100); put32(sec + 12, rsrcVA); put32(sec + 16, 0x200); put32(sec + 20, raw)

        let r = raw
        func dir(_ at: Int, id: Int, to: Int, isDir: Bool) {
            put16(r + at + 14, 1)
            put32(r + at + 16, id)
            put32(r + at + 20, to | (isDir ? 0x8000_0000 : 0))
        }
        // root: two id entries
        put16(r + 14, 2)
        put32(r + 16, 3); put32(r + 20, 32 | 0x8000_0000)
        put32(r + 24, 14); put32(r + 28, 80 | 0x8000_0000)
        dir(32, id: 1, to: 56, isDir: true)
        dir(56, id: 0x409, to: 128, isDir: false)
        dir(80, id: 1, to: 104, isDir: true)
        dir(104, id: 0x409, to: 144, isDir: false)
        let iconAt = 160, groupAt = 160 + iconBytes.count
        put32(r + 128, rsrcVA + iconAt); put32(r + 132, iconBytes.count)
        put32(r + 144, rsrcVA + groupAt); put32(r + 148, 20)
        f.replaceSubrange((r + iconAt)..<(r + iconAt + iconBytes.count), with: iconBytes)
        let g = r + groupAt
        put16(g + 2, 1); put16(g + 4, 1)
        f[g + 6] = 16; f[g + 7] = 16
        put16(g + 10, 1); put16(g + 12, 32); put32(g + 14, 999); put16(g + 18, 1)
        return Data(f)
    }

    @Test func extractsIconGroupAsICO() throws {
        let image = Array("ICONDATA".utf8)
        let ico = try #require(PEIcon.icoData(fromPE: Self.makePE(iconBytes: image)))
        let expectedHeader: [UInt8] = [0, 0, 1, 0, 1, 0,
                                       16, 16, 0, 0, 1, 0, 32, 0, 8, 0, 0, 0, 22, 0, 0, 0]
        #expect(Array(ico.prefix(22)) == expectedHeader)  // size rewritten from the group's 999 to the real 8
        #expect(Array(ico.dropFirst(22)) == image)
    }

    @Test func noIconOrNotPE() {
        #expect(PEIcon.icoData(fromPE: Data("MZ".utf8)) == nil)
        #expect(PEIcon.icoData(fromPE: Data(count: 4096)) == nil)
        var pe = [UInt8](Self.makePE(iconBytes: [1, 2, 3, 4]))
        pe[0x58 + 112 + 16] = 0; pe[0x58 + 112 + 17] = 0  // resource directory RVA -> 0
        #expect(PEIcon.icoData(fromPE: Data(pe)) == nil)
    }
}

@Suite struct RegistryFileTests {
    static let sample = #"""
    WINE REGISTRY Version 2
    ;; All keys relative to \\User\\S-1-5-21

    [Software\\Wine] 1792527663
    #time=1dd60d087b92c28
    "Version"="win7"

    [Software\\Wine\\DllOverrides] 1792527663
    #time=1dd60d087b92c28
    "libegl"=""
    "*d3d9"="native,builtin"
    "quote\"name"="a\\b\"c"
    "dw"=dword:00000001

    [Software\\Wine\\Mac Driver] 1792527663
    "RetinaMode"="y"
    "Unicode"="Vi\x1ec7t"
    """#

    @Test func readsStringValues() {
        let reg = RegistryFile(text: Self.sample)
        #expect(reg.value("Version", in: #"Software\Wine"#) == "win7")
        #expect(reg.value("version", in: #"SOFTWARE\WINE"#) == "win7")
        let ov = reg.values(of: #"Software\Wine\DllOverrides"#)
        #expect(ov == ["libegl": "", "*d3d9": "native,builtin", #"quote"name"#: #"a\b"c"#])
        #expect(reg.value("RetinaMode", in: #"Software\Wine\Mac Driver"#) == "y")
        #expect(reg.value("Unicode", in: #"Software\Wine\Mac Driver"#) == "Việt")
        #expect(reg.values(of: #"Software\Missing"#).isEmpty)
    }

    @Test func overrideModes() {
        #expect(DLLOverrideMode(registryValue: "n,b") == .nativeBuiltin)
        #expect(DLLOverrideMode(registryValue: "Builtin, Native") == .builtinNative)
        #expect(DLLOverrideMode(registryValue: "") == .disabled)
        #expect(DLLOverrideMode(registryValue: "bogus") == nil)
    }
}

@Suite struct LauncherTests {
    let paths = WinePaths(root: URL(fileURLWithPath: "/wb"))
    let bottle = Bottle(url: URL(fileURLWithPath: "/wb/prefixes/game"))

    @Test func splitsCommandLines() {
        let split = WineLauncher.splitWindowsCommandLine
        #expect(split("") == [])
        #expect(split(#"  -a  "b c" d"#) == ["-a", "b c", "d"])
        #expect(split(#"say \"hi\""#) == ["say", #""hi""#])
        #expect(split(#"C:\path\ "x\\" ""#) == [#"C:\path\"#, #"x\"#, ""])
    }

    @Test func runUsesBottleSettings() {
        var config = BottleConfig()
        config.graphics = .dxvk
        config.dxvkHUD = "fps"
        config.debugLog = true
        config.environment = [EnvironmentVariable(name: "DXVK_ASYNC", value: "1"),
                              EnvironmentVariable(name: "bad name", value: "x")]
        let launcher = WineLauncher(paths: paths, bottle: bottle, config: config)
        let exe = URL(fileURLWithPath: "/wb/prefixes/game/drive_c/Game/game.exe")
        let cmd = launcher.run(executable: exe, arguments: #"-window "a b""#)
        #expect(cmd.executable.path == "/wb/scripts/wrun")
        #expect(cmd.arguments == ["-p", "/wb/prefixes/game", "--hud", "fps", "-v", "--", exe.path, "-window", "a b"])
        #expect(cmd.currentDirectory?.path == "/wb/prefixes/game/drive_c/Game")
        #expect(cmd.environment == ["WB_ROOT": "/wb", "DXVK_ASYNC": "1"])
    }

    @Test func defaultsAndSpecialFiles() {
        let launcher = WineLauncher(paths: paths, bottle: bottle, config: BottleConfig())
        let msi = URL(fileURLWithPath: "/tmp/dl/setup.msi")
        #expect(launcher.open(file: msi).arguments == ["-p", "/wb/prefixes/game", "--", "msiexec", "/i", msi.path])
        #expect(launcher.builtin("winecfg").arguments == ["-p", "/wb/prefixes/game", "--", "winecfg"])
        #expect(launcher.setRegistryValue(key: WineLauncher.dllOverridesKey, name: "libegl", value: "").arguments
                == ["-p", "/wb/prefixes/game", "--", "reg", "add", #"HKCU\Software\Wine\DllOverrides"#,
                    "/v", "libegl", "/t", "REG_SZ", "/d", "", "/f"])
        let kill = launcher.killAll()
        #expect(kill.executable.path == "/wb/dist/wine/bin/wineserver")
        #expect(kill.environment["WINEPREFIX"] == "/wb/prefixes/game")
    }

    @Test func displayStringQuotes() {
        let cmd = WineCommand(executable: URL(fileURLWithPath: "/wb/scripts/wrun"), arguments: ["--", "/a b/it's.exe"],
                              environment: ["X": "1 2"])
        #expect(cmd.displayString == #"X='1 2' /wb/scripts/wrun -- '/a b/it'\''s.exe'"#)
    }
}

@Suite struct BottleTests {
    @Test func pathMapping() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bottle = Bottle(url: tmp)
        try FileManager.default.createDirectory(at: bottle.driveC, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("dosdevices"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: tmp.appendingPathComponent("dosdevices/c:").path,
                                                   withDestinationPath: "../drive_c")
        try FileManager.default.createSymbolicLink(atPath: tmp.appendingPathComponent("dosdevices/z:").path,
                                                   withDestinationPath: "/")

        let exe = try #require(bottle.unixPath(forWindowsPath: #"C:\Program Files\A\a.exe"#))
        #expect(exe.path == bottle.driveC.appendingPathComponent("Program Files/A/a.exe").standardizedFileURL.path)
        #expect(bottle.unixPath(forWindowsPath: #"Z:\tmp\x.exe"#)?.path == "/tmp/x.exe")
        #expect(bottle.unixPath(forWindowsPath: #"Q:\nothing"#) == nil)
        #expect(bottle.unixPath(forWindowsPath: "relative") == nil)
        #expect(bottle.windowsPath(forUnixPath: exe) == #"C:\Program Files\A\a.exe"#)
        #expect(bottle.windowsPath(forUnixPath: URL(fileURLWithPath: "/tmp/x.exe")) == #"Z:\tmp\x.exe"#)
    }

    @Test func configRoundTripAndDefaults() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bottle = Bottle(url: tmp)
        #expect(bottle.loadConfig() == BottleConfig())
        var c = BottleConfig()
        c.graphics = .dxvk
        c.pinnedApps = [PinnedApp(name: "Game", path: "/x/game.exe")]
        try bottle.saveConfig(c)
        let loaded = bottle.loadConfig()
        #expect(loaded.graphics == .dxvk)
        #expect(loaded.pinnedApps.map(\.path) == ["/x/game.exe"])

        // Hand-written, partial, unknown values: defaults instead of failure.
        try Data(#"{"graphics":"metal","pinnedApps":[{"name":"A","path":"/a.exe"}]}"#.utf8).write(to: bottle.configURL)
        let partial = bottle.loadConfig()
        #expect(partial.graphics == .wined3d)
        #expect(partial.pinnedApps.first?.name == "A")
    }

    @Test func bottleNames() {
        #expect(BottleStore.isValidName("truykich"))
        #expect(BottleStore.isValidName("game-2_x.y"))
        #expect(!BottleStore.isValidName(""))
        #expect(!BottleStore.isValidName(".hidden"))
        #expect(!BottleStore.isValidName("a/b"))
        #expect(!BottleStore.isValidName("có dấu"))
    }

    @Test func scansShortcutsAndPins() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bottle = Bottle(url: tmp)
        let fm = FileManager.default
        let npp = bottle.driveC.appendingPathComponent("Program Files (x86)/Notepad++")
        try fm.createDirectory(at: npp, withIntermediateDirectories: true)
        try Data().write(to: npp.appendingPathComponent("notepad++.exe"))
        try Data().write(to: npp.appendingPathComponent("uninstall.exe"))
        let menu = bottle.driveC.appendingPathComponent("ProgramData/Microsoft/Windows/Start Menu/Programs")
        try fm.createDirectory(at: menu, withIntermediateDirectories: true)
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures/notepadpp", withExtension: "lnk"))
        try fm.copyItem(at: fixture, to: menu.appendingPathComponent("Notepad++.lnk"))
        let ie = bottle.driveC.appendingPathComponent("Program Files/Internet Explorer")
        try fm.createDirectory(at: ie, withIntermediateDirectories: true)
        try Data().write(to: ie.appendingPathComponent("iexplore.exe"))

        var config = BottleConfig()
        config.pinnedApps = [PinnedApp(name: "Zeta", path: "/elsewhere/z.exe")]
        let apps = AppScanner.apps(in: bottle, config: config)
        #expect(apps.map(\.name) == ["Notepad++", "Zeta"])
        #expect(apps[0].workingDirectory?.path == npp.standardizedFileURL.path)

        guard case .shortcut(let lnk) = apps[0].source else { Issue.record("not a shortcut"); return }
        config.hiddenShortcuts = [lnk.path]
        #expect(AppScanner.apps(in: bottle, config: config).map(\.name) == ["Zeta"])

        let candidates = AppScanner.candidateExecutables(in: bottle).map(\.lastPathComponent)
        #expect(candidates == ["notepad++.exe", "uninstall.exe"])  // Wine's IE skipped, uninstaller last
    }
}
