import AppKit
import SwiftUI
import WineKit

@main
struct WinebuildManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Winebuild", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.runner)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Bottle mới…") { model.showNewBottle = true }
                    .keyboardShortcut("n")
                Button("Chạy chương trình hoặc bộ cài…") {
                    if let b = model.selectedBottle { model.chooseAndRun(in: b) }
                }
                .keyboardShortcut("o")
                .disabled(model.selectedBottle == nil)
            }
            CommandMenu("Bottle") {
                ForEach(DetailTab.allCases) { tab in
                    Button(tab.title) { model.tab = tab }
                        .keyboardShortcut(KeyEquivalent(Character("\(DetailTab.allCases.firstIndex(of: tab)! + 1)")))
                }
                Divider()
                Button("Làm mới") { model.reload(); if let b = model.selectedBottle { model.store(for: b).refresh() } }
                    .keyboardShortcut("r")
                Button("Dừng mọi tiến trình") { if let b = model.selectedBottle { model.killAll(in: b) } }
                    .keyboardShortcut(".", modifiers: [.command, .shift])
                    .disabled(model.selectedBottle == nil)
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from `swift run` there is no bundle; make it a regular app with a Dock icon and menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
