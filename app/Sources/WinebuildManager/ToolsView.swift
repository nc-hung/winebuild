import AppKit
import SwiftUI
import WineKit

struct ToolsView: View {
    @ObservedObject var store: BottleStoreModel
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var runner: ProcessRunner

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                group("Tiện ích Windows") {
                    tool("Cấu hình Wine", "winecfg — ổ đĩa, âm thanh, giao diện", "gearshape.2") { builtin("winecfg") }
                    tool("Trình sửa registry", "regedit", "list.bullet.indent") { builtin("regedit") }
                    tool("Trình quản lý tác vụ", "taskmgr — xem và dừng tiến trình", "chart.bar.doc.horizontal") { builtin("taskmgr") }
                    tool("Control Panel", "control — thiết bị, game controller", "switch.2") { builtin("control") }
                    tool("Gỡ cài đặt chương trình", "uninstaller — danh sách phần mềm đã cài", "trash.square") { builtin("uninstaller") }
                    tool("Dấu nhắc lệnh", "cmd trong cửa sổ console", "terminal") { builtin("start", ["cmd"], title: "cmd") }
                    tool("Trình duyệt tệp", "explorer của Wine", "folder") { builtin("explorer") }
                }
                group("Bottle") {
                    tool("Mở ổ C: trong Finder", "drive_c của bottle", "externaldrive") { NSWorkspace.shared.open(store.bottle.driveC) }
                    tool("Terminal", "Shell có sẵn WINEPREFIX và lệnh wine", "apple.terminal") { model.openShell(for: store.bottle) }
                    tool(store.bottle.hasDXVKInstalled ? "Cài lại DXVK" : "Cài DXVK",
                         model.paths.hasDXVK ? "Chép DLL DXVK vào system32/syswow64" : "Chưa build DXVK (scripts/build-dxvk.sh)",
                         "cube.transparent", enabled: model.paths.hasDXVK) { model.installDXVK(in: store.bottle) }
                    tool("Cập nhật bottle", "wineboot -u sau khi đổi bản Wine", "arrow.triangle.2.circlepath") { model.reinitialize(store.bottle) }
                    tool("Dừng mọi tiến trình", "wineserver -k", "stop.circle", tint: .red) { model.killAll(in: store.bottle) }
                }
            }
            .padding(20)
        }
        .disabled(model.busy[store.bottle.id] != nil)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 14) { content() }
        }
    }

    private func tool(_ title: String, _ subtitle: String, _ symbol: String, tint: Color = .accentColor,
                      enabled: Bool = true, action: @escaping () -> Void) -> some View {
        ToolCard(title: title, subtitle: subtitle, symbol: symbol, tint: tint, action: action)
            .disabled(!enabled)
    }

    private func builtin(_ program: String, _ args: [String] = [], title: String? = nil) {
        runner.launch(store.launcher.builtin(program, args), title: title ?? program, bottle: store.bottle)
    }

}

struct ToolCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hover && isEnabled ? Color.primary.opacity(0.07) : Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
