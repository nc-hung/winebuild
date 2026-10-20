import AppKit
import SwiftUI
import WineKit

struct BottleDetailView: View {
    @ObservedObject var store: BottleStoreModel
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var runner: ProcessRunner

    var body: some View {
        VStack(spacing: 0) {
            BottleHeader(store: store)
            Divider()
            Group {
                switch model.tab {
                case .apps: AppsView(store: store)
                case .settings: BottleSettingsView(store: store)
                case .tools: ToolsView(store: store)
                case .logs: LogsView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(store.bottle.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mục", selection: $model.tab) {
                    ForEach(DetailTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.symbol).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleAndIcon)
                .fixedSize()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.chooseAndRun(in: store.bottle) } label: {
                    Label("Cài đặt phần mềm…", systemImage: "square.and.arrow.down.on.square")
                }
                .help("Chạy bộ cài .exe/.msi trong bottle này (⌘O)")
                Button { model.killAll(in: store.bottle) } label: {
                    Label("Dừng", systemImage: "stop.circle")
                }
                .help("Dừng mọi chương trình Windows trong bottle (⇧⌘.)")
            }
        }
    }
}

/// Large header like CrossOver's bottle summary: glyph, name, location and status badges.
struct BottleHeader: View {
    @ObservedObject var store: BottleStoreModel
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var runner: ProcessRunner

    var body: some View {
        let bottle = store.bottle
        let running = runner.running(in: bottle)
        HStack(alignment: .center, spacing: 16) {
            BottleGlyph(name: bottle.name, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(bottle.name).font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    Badge(text: store.windowsVersion.label, symbol: "pc")
                    Badge(text: store.config.graphics == .dxvk ? "DXVK · Vulkan" : "WineD3D · OpenGL",
                          symbol: "cpu", tint: store.config.graphics == .dxvk ? .purple : .blue)
                    if store.retina { Badge(text: "Retina", symbol: "sparkles.rectangle.stack") }
                    if !bottle.isInitialized { Badge(text: "Chưa khởi tạo", symbol: "exclamationmark.triangle", tint: .orange) }
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([bottle.driveC])
                } label: {
                    Text(bottle.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Hiện ổ C: trong Finder")
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                if let busy = model.busy[bottle.id] {
                    Label { Text(busy) } icon: { ProgressView().controlSize(.small) }
                        .font(.callout).foregroundStyle(.secondary)
                } else if store.pendingWrites > 0 {
                    Label { Text("Đang ghi registry…") } icon: { ProgressView().controlSize(.small) }
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if running.isEmpty {
                    Label("Không có gì đang chạy", systemImage: "moon.zzz")
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Button { model.tab = .logs } label: {
                        Label("\(running.count) đang chạy: \(running.map(\.title).joined(separator: ", "))",
                              systemImage: "circle.fill")
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.green)
                    .frame(maxWidth: 320, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.background.secondary)
    }
}

struct Badge: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .lineLimit(1)
        .fixedSize()
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(tint == .secondary ? Color.secondary : tint)
        .background((tint == .secondary ? Color.secondary : tint).opacity(0.12), in: Capsule())
    }
}
