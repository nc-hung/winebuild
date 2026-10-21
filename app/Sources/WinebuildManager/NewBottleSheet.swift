import AppKit
import SwiftUI
import WineKit

struct NewBottleSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var installDXVK = false
    @State private var cefFix = false

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var exists: Bool { model.bottles.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame } }
    private var valid: Bool { BottleStore.isValidName(trimmed) && !exists }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                BottleGlyph(name: trimmed.isEmpty ? "bottle" : trimmed, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bottle mới").font(.title3.weight(.semibold))
                    Text("Một ổ C: Windows riêng, tách biệt với các bottle khác.").foregroundStyle(.secondary)
                }
            }

            Form {
                TextField("Tên", text: $name, prompt: Text("ví dụ: games"))
                if !trimmed.isEmpty && !valid {
                    Text(exists ? "Đã có bottle tên này." : "Chỉ dùng chữ không dấu, số, dấu - _ . (tối đa 64 ký tự).")
                        .font(.caption).foregroundStyle(.red)
                }
                Toggle(isOn: $installDXVK) {
                    Text("Cài sẵn DXVK")
                    Text(model.paths.hasDXVK ? "Cho game Direct3D 9/10/11. Có thể bật sau trong Cấu hình." : "Chưa build DXVK.")
                }
                .disabled(!model.paths.hasDXVK)
                Toggle(isOn: $cefFix) {
                    Text("Áp mẹo CEF cho launcher game")
                    Text("Tắt libegl và libglesv2 để khung đăng nhập dựng bằng CEF không bị trắng hoặc trong suốt.")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Text("Sẽ tạo tại \(model.paths.prefixes.appendingPathComponent(trimmed.isEmpty ? "<tên>" : trimmed).path.replacingOccurrences(of: NSHomeDirectory(), with: "~")). Khởi tạo lần đầu mất khoảng một phút.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Huỷ") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Tạo") {
                    model.createBottle(named: trimmed, installDXVK: installDXVK, cefFix: cefFix)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(22)
        .frame(width: 500)
    }
}

struct PreferencesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Thư mục winebuild") {
                LabeledContent("Đường dẫn") {
                    Text(model.paths.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Chọn thư mục khác…", action: choose)
                    Button("Dùng mặc định (~/winebuild)") { model.setRoot(WinePaths.defaultRoot) }
                        .disabled(model.paths.root == WinePaths(root: WinePaths.defaultRoot).root)
                    Spacer()
                    Button("Mở trong Finder") { NSWorkspace.shared.open(model.paths.root) }
                }
            }
            Section("Thành phần") {
                status("Wine", ok: model.paths.isBuilt, detail: model.paths.wineVersion ?? "dist/wine/bin/wine")
                status("wrun", ok: FileManager.default.isExecutableFile(atPath: model.paths.wrun.path), detail: "scripts/wrun")
                status("DXVK", ok: model.paths.hasDXVK, detail: "dist/dxvk")
                status("Bottle", ok: !model.bottles.isEmpty, detail: "\(model.bottles.count) trong prefixes/")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 360)
    }

    private func status(_ name: String, ok: Bool, detail: String) -> some View {
        LabeledContent {
            Text(detail).foregroundStyle(.secondary)
        } label: {
            Label(name, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Chọn"
        panel.message = "Chọn thư mục gốc của repo winebuild (có scripts/wrun và dist/wine)."
        panel.directoryURL = model.paths.root
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.setRoot(url)
    }
}
