import AppKit
import SwiftUI
import WineKit

struct AppsView: View {
    @ObservedObject var store: BottleStoreModel
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var selection: WinApp.ID?
    @State private var showAdd = false
    @State private var editing: PinnedApp?
    @State private var showUninstallers = false

    private var visible: [WinApp] { filtered(store.apps.filter { !$0.isUninstaller }) }
    private var uninstallers: [WinApp] { filtered(store.apps.filter(\.isUninstaller)) }

    private func filtered(_ apps: [WinApp]) -> [WinApp] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.executable.lastPathComponent.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.apps.isEmpty && !store.loading {
                EmptyStateView(symbol: "app.dashed", title: "Chưa có ứng dụng",
                               message: "Chạy bộ cài để cài phần mềm vào bottle. Nếu chương trình không tạo lối tắt (ví dụ launcher game), dùng “Thêm ứng dụng…” để ghim file .exe.") {
                    Button("Cài đặt phần mềm…") { model.chooseAndRun(in: store.bottle) }
                        .buttonStyle(.borderedProminent)
                    Button("Thêm ứng dụng…") { showAdd = true }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116, maximum: 140), spacing: 14)], spacing: 16) {
                            ForEach(visible) { app in tile(app) }
                        }
                        if !uninstallers.isEmpty {
                            DisclosureGroup(isExpanded: $showUninstallers) {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116, maximum: 140), spacing: 14)], spacing: 16) {
                                    ForEach(uninstallers) { app in tile(app) }
                                }
                                .padding(.top, 8)
                            } label: {
                                Text("Trình gỡ cài đặt (\(uninstallers.count))").font(.headline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(20)
                }
                .contentShape(Rectangle())
                .onTapGesture { selection = nil }
            }
            Divider()
            bottomBar
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Tìm ứng dụng")
        .sheet(isPresented: $showAdd) { AddAppSheet(store: store, editing: nil) }
        .sheet(item: $editing) { pin in AddAppSheet(store: store, editing: pin) }
    }

    private func tile(_ app: WinApp) -> some View {
        AppTile(app: app, selected: selection == app.id)
            .onTapGesture(count: 2) { store.launch(app) }
            .onTapGesture { selection = app.id }
            .contextMenu {
                Button("Mở") { store.launch(app) }
                Button("Hiện trong Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.executable]) }
                Button("Sao chép lệnh chạy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.launcher.run(app).displayString, forType: .string)
                }
                Divider()
                if let pin = store.pinned(for: app) {
                    Button("Sửa…") { editing = pin }
                    Button("Bỏ ghim", role: .destructive) { store.remove(app) }
                } else {
                    Button("Ẩn khỏi danh sách") { store.remove(app) }
                }
            }
            .help(app.executable.path)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { showAdd = true } label: { Label("Thêm ứng dụng…", systemImage: "plus.app") }
            if !store.config.hiddenShortcuts.isEmpty {
                Button("Hiện lại \(store.config.hiddenShortcuts.count) lối tắt đã ẩn") { store.restoreHiddenShortcuts() }
                    .buttonStyle(.link)
            }
            Spacer()
            if store.loading { ProgressView().controlSize(.small) }
            Text(selectionHint).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let app = store.apps.first(where: { $0.id == selection }) {
                Button { store.launch(app) } label: { Label("Mở", systemImage: "play.fill") }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var selectionHint: String {
        if let app = store.apps.first(where: { $0.id == selection }) {
            return store.bottle.windowsPath(forUnixPath: app.executable)
        }
        return "\(visible.count) ứng dụng · nhấp đúp để mở"
    }
}

struct AppTile: View {
    let app: WinApp
    let selected: Bool
    @State private var hover = false

    var body: some View {
        VStack(spacing: 8) {
            AppIconView(exe: app.executable, size: 56)
                .overlay(alignment: .bottomTrailing) {
                    if case .pinned = app.source {
                        Image(systemName: "pin.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .font(.system(size: 16))
                            .offset(x: 4, y: 4)
                    }
                }
            Text(app.name)
                .font(.callout)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 4)
                .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.14) : hover ? Color.primary.opacity(0.05) : .clear))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hover = $0 }
    }
}

/// Icon read from the .exe's resources; a generic window glyph until it loads or if there is none.
struct AppIconView: View {
    let exe: URL
    let size: CGFloat
    @ObservedObject private var cache = IconCache.shared

    var body: some View {
        if let image = cache.icon(for: exe) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [Color.gray.opacity(0.35), Color.gray.opacity(0.18)], startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: "macwindow").font(.system(size: size * 0.42)).foregroundStyle(.secondary))
                .frame(width: size, height: size)
        }
    }
}

/// Pins an executable, or edits an existing pin. Lists .exe files found under drive_c so the user rarely needs the file dialog.
struct AddAppSheet: View {
    @ObservedObject var store: BottleStoreModel
    let editing: PinnedApp?
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [URL] = []
    @State private var scanning = true
    @State private var filter = ""
    @State private var exe: URL?
    @State private var name = ""
    @State private var arguments = ""
    @State private var nameEdited = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editing == nil ? "Thêm ứng dụng vào “\(store.bottle.name)”" : "Sửa ứng dụng")
                .font(.title3.weight(.semibold))

            if editing == nil {
                HStack {
                    TextField("Lọc file .exe", text: $filter).textFieldStyle(.roundedBorder)
                    Button("Chọn tệp khác…", action: browse)
                }
                List(filteredCandidates, id: \.self, selection: $exe) { url in
                    HStack(spacing: 10) {
                        AppIconView(exe: url, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.lastPathComponent)
                            Text(store.bottle.windowsPath(forUnixPath: url.deletingLastPathComponent()))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .tag(url)
                }
                .frame(minHeight: 220)
                .overlay {
                    if scanning { ProgressView("Đang tìm chương trình…") }
                    else if candidates.isEmpty { Text("Không tìm thấy file .exe nào ngoài thư mục Windows.").foregroundStyle(.secondary) }
                }
            }

            Form {
                LabeledContent("Chương trình") {
                    Text(exe.map { store.bottle.windowsPath(forUnixPath: $0) } ?? "Chưa chọn")
                        .foregroundStyle(exe == nil ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                }
                TextField("Tên hiển thị", text: $name)
                    .onChange(of: name) { _, _ in nameEdited = true }
                TextField("Tham số dòng lệnh", text: $arguments, prompt: Text("ví dụ: -windowed"))
            }
            .formStyle(.columns)

            HStack {
                Spacer()
                Button("Huỷ") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Thêm" : "Lưu", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(exe == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onChange(of: exe) { _, url in
            guard let url, !nameEdited || name.isEmpty else { return }
            name = url.deletingPathExtension().lastPathComponent
            nameEdited = false
        }
        .task {
            if let editing {
                exe = URL(fileURLWithPath: editing.path)
                name = editing.name
                arguments = editing.arguments
                nameEdited = true
                scanning = false
                return
            }
            let bottle = store.bottle
            candidates = await Task.detached(priority: .userInitiated) { AppScanner.candidateExecutables(in: bottle) }.value
            scanning = false
        }
    }

    private var filteredCandidates: [URL] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return candidates }
        return candidates.filter { $0.path.localizedCaseInsensitiveContains(q) }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.title = "Chọn chương trình Windows"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.directoryURL = store.bottle.driveC
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !candidates.contains(url) { candidates.insert(url, at: 0) }
        exe = url
    }

    private func save() {
        guard let exe else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if var pin = editing {
            pin.name = trimmed
            pin.path = exe.path
            pin.arguments = arguments
            store.updatePinned(pin)
        } else {
            store.pin(executable: exe, name: trimmed, arguments: arguments)
        }
        dismiss()
    }
}
