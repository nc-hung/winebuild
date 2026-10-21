import AppKit
import SwiftUI
import WineKit

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var runner: ProcessRunner

    var body: some View {
        List(selection: $model.selection) {
            Section("Bottle") {
                ForEach(model.bottles) { bottle in
                    BottleRow(bottle: bottle, store: model.store(for: bottle),
                              busy: model.busy[bottle.id], runningCount: runner.running(in: bottle).count)
                        .tag(bottle.id)
                        .contextMenu { menu(for: bottle) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .toolbar {
            ToolbarItem {
                Button { model.showNewBottle = true } label: { Label("Bottle mới", systemImage: "plus") }
                    .help("Tạo bottle mới (⌘N)")
            }
        }
    }

    @ViewBuilder
    private func menu(for bottle: Bottle) -> some View {
        Button("Chạy chương trình…") { model.chooseAndRun(in: bottle) }
        Button("Mở ổ C: trong Finder") { NSWorkspace.shared.open(bottle.driveC) }
        Button("Mở Terminal với môi trường Wine") { model.openShell(for: bottle) }
        Divider()
        Button("Cập nhật bottle (wineboot -u)") { model.reinitialize(bottle) }
        Button("Dừng mọi tiến trình") { model.killAll(in: bottle) }
        Divider()
        Button("Chuyển vào Thùng rác…", role: .destructive) { model.pendingTrash = bottle }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: model.paths.isBuilt ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.paths.isBuilt ? .green : .orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.paths.wineVersion.map { $0.replacingOccurrences(of: "wine-", with: "Wine ") } ?? "Wine")
                        .font(.caption.weight(.semibold))
                    Text(model.paths.hasDXVK ? "MoltenVK · DXVK-macOS" : "MoltenVK · chưa có DXVK")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Quét lại thư mục prefixes")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }
}

struct BottleRow: View {
    let bottle: Bottle
    @ObservedObject var store: BottleStoreModel
    let busy: String?
    let runningCount: Int

    var body: some View {
        HStack(spacing: 10) {
            BottleGlyph(name: bottle.name, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.name).font(.body.weight(.medium)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if busy != nil {
                ProgressView().controlSize(.small)
            } else if runningCount > 0 {
                Circle().fill(.green).frame(width: 8, height: 8)
                    .help("\(runningCount) chương trình đang chạy")
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        if let busy { return busy }
        if !bottle.isInitialized { return "Chưa khởi tạo" }
        let n = store.apps.filter { !$0.isUninstaller }.count
        let gfx = store.config.graphics == .dxvk ? "DXVK" : "wined3d"
        return "\(n) ứng dụng · \(gfx)"
    }
}

/// Rounded tile with the bottle's initial, tinted by a stable colour derived from the name.
struct BottleGlyph: View {
    let name: String
    let size: CGFloat

    static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red, .mint, .cyan]

    var color: Color {
        let h = name.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return Self.palette[Int(h % UInt32(Self.palette.count))]
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            .overlay(
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
            )
            .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(.white.opacity(0.18)))
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.25), radius: size * 0.08, y: size * 0.04)
    }
}
