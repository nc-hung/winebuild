import AppKit
import SwiftUI
import WineKit

extension DLLOverrideMode {
    var label: String {
        switch self {
        case .nativeBuiltin: "Native, rồi builtin"
        case .builtinNative: "Builtin, rồi native"
        case .native: "Chỉ native"
        case .builtin: "Chỉ builtin (Wine)"
        case .disabled: "Tắt"
        }
    }
}

struct BottleSettingsView: View {
    @ObservedObject var store: BottleStoreModel
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var runner: ProcessRunner

    @State private var newDLL = ""
    @State private var newDLLMode: DLLOverrideMode = .nativeBuiltin
    @State private var newEnvName = ""
    @State private var newEnvValue = ""
    @State private var hud = ""
    @State private var applyingPreset = false

    static let hudPresets: [(String, String)] = [
        ("Tắt", ""), ("FPS", "fps"), ("FPS + thời gian khung hình", "fps,frametimes"),
        ("GPU + bộ nhớ", "fps,gpuload,memory"), ("Đầy đủ", "full"),
    ]

    var body: some View {
        Form {
            graphicsSection
            windowsSection
            dllSection
            environmentSection
            debugSection
        }
        .formStyle(.grouped)
        .onAppear { hud = store.config.dxvkHUD }
    }

    // MARK: Sections

    private var graphicsSection: some View {
        Section {
            Picker("Bộ dựng hình Direct3D", selection: Binding(
                get: { store.config.graphics },
                set: { g in store.update { $0.graphics = g } })) {
                Text("WineD3D (OpenGL)").tag(BottleConfig.Graphics.wined3d)
                Text("DXVK (Vulkan qua MoltenVK)").tag(BottleConfig.Graphics.dxvk)
            }
            .pickerStyle(.radioGroup)

            if store.config.graphics == .dxvk {
                if !store.bottle.hasDXVKInstalled {
                    HStack {
                        Label("Bottle chưa có DLL của DXVK (wrun sẽ tự cài ở lần chạy đầu).", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Cài DXVK vào bottle") { model.installDXVK(in: store.bottle) }
                            .disabled(!model.paths.hasDXVK || model.busy[store.bottle.id] != nil)
                    }
                }
                LabeledContent("DXVK HUD") {
                    HStack {
                        TextField("", text: $hud, prompt: Text("tắt"))
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                            .onSubmit { commitHUD() }
                        Menu("Mẫu") {
                            ForEach(Self.hudPresets, id: \.1) { title, value in
                                Button(title) { hud = value; commitHUD() }
                            }
                        }
                        .fixedSize()
                    }
                }
            }
        } header: {
            Text("Đồ hoạ")
        } footer: {
            Text(store.config.graphics == .dxvk
                 ? "DXVK dịch Direct3D 9/10/11 sang Vulkan; thường nhanh hơn cho game. Áp dụng từ lần mở chương trình kế tiếp."
                 : "WineD3D tương thích rộng nhất. Chọn DXVK nếu game D3D11 chạy chậm hoặc lỗi hình.")
            .font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var windowsSection: some View {
        Section("Windows") {
            Picker("Phiên bản Windows giả lập", selection: Binding(
                get: { store.windowsVersion }, set: { store.setWindowsVersion($0) })) {
                ForEach(WindowsVersion.allCases) { Text($0.label).tag($0) }
            }
            Toggle(isOn: Binding(get: { store.retina }, set: { store.setRetina($0) })) {
                Text("Chế độ Retina")
                Text("Vẽ ở độ phân giải gốc của màn hình. Chữ nét hơn nhưng giao diện cũ có thể bị nhỏ.")
            }
        }
    }

    private var dllSection: some View {
        Section {
            if store.overrides.isEmpty {
                Text("Chưa có thiết lập riêng; Wine tự chọn DLL.").foregroundStyle(.secondary)
            }
            ForEach(store.overrides) { row in
                HStack {
                    Text(row.name).font(.body.monospaced())
                    Spacer()
                    Picker("", selection: Binding(get: { row.mode }, set: { store.setOverride(row.name, $0) })) {
                        ForEach(DLLOverrideMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button { store.removeOverride(row) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Xoá thiết lập cho \(row.name)")
                }
            }
            HStack {
                TextField("", text: $newDLL, prompt: Text("tên DLL, ví dụ d3dcompiler_47"))
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addOverride)
                Picker("", selection: $newDLLMode) {
                    ForEach(DLLOverrideMode.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button("Thêm", action: addOverride)
                    .disabled(BottleStoreModel.normalizedDLLName(newDLL).isEmpty)
            }
            HStack {
                Button {
                    applyingPreset = true
                    Task {
                        await store.applyPreset(.cefSoftwareCompositing)
                        applyingPreset = false
                    }
                } label: {
                    Label("Sửa popup CEF trong suốt (tắt libegl, libglesv2)", systemImage: "wand.and.stars")
                }
                .disabled(applyingPreset)
                if applyingPreset { ProgressView().controlSize(.small) }
            }
        } header: {
            Text("Thư viện DLL")
        } footer: {
            Text("Lưu trong registry của bottle (HKCU\\Software\\Wine\\DllOverrides), nên cũng áp dụng khi chạy bằng wrun. Mẹo CEF dùng cho launcher game có khung đăng nhập trắng hoặc trong suốt.")
                .font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var environmentSection: some View {
        Section {
            ForEach(store.config.environment) { v in
                HStack {
                    Text(v.name).font(.body.monospaced())
                    Text("=").foregroundStyle(.secondary)
                    Text(v.value).font(.body.monospaced()).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button {
                        store.update { $0.environment.removeAll { $0.id == v.id } }
                    } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                TextField("", text: $newEnvName, prompt: Text("TÊN_BIẾN"))
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(maxWidth: 200)
                TextField("", text: $newEnvValue, prompt: Text("giá trị"))
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addEnv)
                Button("Thêm", action: addEnv)
                    .disabled(!EnvironmentVariable(name: newEnvName, value: newEnvValue).isValid)
            }
        } header: {
            Text("Biến môi trường")
        } footer: {
            Text("Thêm vào mọi chương trình mở từ ứng dụng này, ví dụ MVK_CONFIG_RESUME_LOST_DEVICE=1 hoặc DXVK_ASYNC=1.")
                .font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var debugSection: some View {
        Section("Gỡ lỗi") {
            Toggle(isOn: Binding(get: { store.config.debugLog }, set: { on in store.update { $0.debugLog = on } })) {
                Text("Ghi log chi tiết của Wine")
                Text("Bỏ WINEDEBUG=-all. Log lớn hơn và chạy chậm hơn một chút; chỉ bật khi cần tìm lỗi.")
            }
            LabeledContent("Thư mục bottle") {
                Button(store.bottle.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                    NSWorkspace.shared.activateFileViewerSelecting([store.bottle.url])
                }
                .buttonStyle(.link)
            }
            LabeledContent("Cấu hình trình quản lý") {
                Text(".winebuild/bottle.json").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    private func commitHUD() {
        let value = hud.trimmingCharacters(in: .whitespaces)
        store.update { $0.dxvkHUD = value }
    }

    private func addOverride() {
        let dll = BottleStoreModel.normalizedDLLName(newDLL)
        guard !dll.isEmpty else { return }
        store.setOverride(dll, newDLLMode)
        newDLL = ""
    }

    private func addEnv() {
        let v = EnvironmentVariable(name: newEnvName.trimmingCharacters(in: .whitespaces), value: newEnvValue)
        guard v.isValid else { return }
        store.update { c in
            c.environment.removeAll { $0.name == v.name }
            c.environment.append(v)
        }
        newEnvName = ""
        newEnvValue = ""
    }

}
