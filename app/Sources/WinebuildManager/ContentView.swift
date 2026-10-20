import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WineKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var runner: ProcessRunner
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            Group {
                if !model.paths.isBuilt {
                    MissingBuildView()
                } else if let bottle = model.selectedBottle {
                    BottleDetailView(store: model.store(for: bottle))
                        .id(bottle.id)
                } else {
                    EmptyStateView(symbol: "shippingbox", title: "Chưa có bottle nào",
                                   message: "Mỗi bottle là một ổ C: Windows riêng. Tạo một bottle để cài phần mềm vào đó.") {
                        Button("Tạo bottle…") { model.showNewBottle = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(Label("Thả vào để chạy trong “\(model.selectedBottle?.name ?? "")”", systemImage: "arrow.down.app")
                            .font(.title3.weight(.semibold)).padding(14)
                            .background(.regularMaterial, in: Capsule()))
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
        }
        .sheet(isPresented: $model.showNewBottle) { NewBottleSheet() }
        .alert(item: $runner.lastError) { err in
            if let log = err.logURL {
                return Alert(title: Text(err.title), message: Text(err.message),
                             primaryButton: .default(Text("Xem nhật ký")) { NSWorkspace.shared.open(log) },
                             secondaryButton: .cancel(Text("Đóng")))
            }
            return Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog("Chuyển bottle “\(model.pendingTrash?.name ?? "")” vào Thùng rác?",
                            isPresented: Binding(get: { model.pendingTrash != nil }, set: { if !$0 { model.pendingTrash = nil } }),
                            presenting: model.pendingTrash) { bottle in
            Button("Chuyển vào Thùng rác", role: .destructive) { model.trash(bottle) }
        } message: { _ in
            Text("Mọi chương trình đang chạy trong bottle sẽ bị dừng. Toàn bộ ổ C: của bottle (ứng dụng, dữ liệu, save game) được chuyển vào Thùng rác và vẫn khôi phục được từ Finder.")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let bottle = model.selectedBottle, let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in model.open(url, in: bottle) }
        }
        return true
    }
}

struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            HStack { actions }.padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MissingBuildView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        EmptyStateView(symbol: "hammer", title: "Chưa tìm thấy bản build Wine",
                       message: "Không có \(model.paths.wine.path). Chạy các script build trong \(model.paths.root.path), hoặc chọn thư mục winebuild khác trong Cài đặt.") {
            Button("Mở thư mục") { NSWorkspace.shared.open(model.paths.root) }
            SettingsLink { Text("Cài đặt…") }
        }
    }
}
