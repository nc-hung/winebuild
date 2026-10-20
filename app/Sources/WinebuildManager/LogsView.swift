import AppKit
import SwiftUI
import WineKit

struct LogsView: View {
    @ObservedObject var store: BottleStoreModel
    @EnvironmentObject private var runner: ProcessRunner

    @State private var files: [LogFile] = []
    @State private var selected: URL?
    @State private var text = ""

    struct LogFile: Identifiable, Hashable {
        let url: URL
        let date: Date
        let size: Int
        var id: URL { url }
        /// `20261021-101500-Notepad.log` → `Notepad`
        var title: String {
            let base = url.deletingPathExtension().lastPathComponent
            let parts = base.split(separator: "-", maxSplits: 2)
            return parts.count == 3 ? String(parts[2]) : base
        }
    }

    private var running: [RunningProcess] { runner.running(in: store.bottle) }

    var body: some View {
        HSplitView {
            List(selection: $selected) {
                if !running.isEmpty {
                    Section("Đang chạy") {
                        ForEach(running) { p in
                            HStack {
                                Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.title)
                                    Text("PID \(p.pid) · từ \(p.started.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { runner.terminate(p) } label: { Image(systemName: "stop.fill") }
                                    .buttonStyle(.borderless)
                                    .help("Dừng tiến trình wrun này")
                            }
                            .tag(p.logURL)
                        }
                    }
                }
                Section("Nhật ký") {
                    if files.isEmpty {
                        Text("Chưa có nhật ký").foregroundStyle(.secondary)
                    }
                    ForEach(files) { f in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.title).lineLimit(1)
                            Text("\(f.date.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(f.url)
                        .contextMenu {
                            Button("Hiện trong Finder") { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
                            Button("Chuyển vào Thùng rác") { trash([f.url]) }
                        }
                    }
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)

            VStack(spacing: 0) {
                if selected == nil {
                    EmptyStateView(symbol: "doc.text", title: "Chọn một nhật ký",
                                   message: "Mỗi lần mở chương trình, đầu ra của Wine được ghi vào .winebuild/logs trong bottle.") {}
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(text.isEmpty ? "(trống)" : text)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                            Color.clear.frame(height: 1).id("end")
                        }
                        .onChange(of: text) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                    }
                    Divider()
                    HStack {
                        if let selected {
                            Text(selected.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Mở bằng Console") {
                            if let selected {
                                NSWorkspace.shared.open([selected], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"),
                                                        configuration: NSWorkspace.OpenConfiguration())
                            }
                        }
                        Button("Sao chép") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Làm mới") { reloadFiles() }
                    Button("Mở thư mục nhật ký") { NSWorkspace.shared.open(store.bottle.logsDir) }
                    Divider()
                    Button("Xoá nhật ký cũ hơn 7 ngày") {
                        let cutoff = Date().addingTimeInterval(-7 * 86400)
                        trash(files.filter { $0.date < cutoff }.map(\.url))
                    }
                } label: { Label("Nhật ký", systemImage: "ellipsis.circle") }
            }
        }
        .onAppear(perform: reloadFiles)
        .onChange(of: running.count) { _, _ in reloadFiles() }
        // Follow the selected log while it grows (a running program keeps writing to it).
        .task(id: selected) {
            while !Task.isCancelled {
                if let selected { text = Self.tail(of: selected) }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func reloadFiles() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: store.bottle.logsDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        files = urls.filter { $0.pathExtension == "log" }.compactMap { url in
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return LogFile(url: url, date: v?.contentModificationDate ?? .distantPast, size: v?.fileSize ?? 0)
        }
        .sorted { $0.date > $1.date }
        if selected == nil { selected = running.first?.logURL ?? files.first?.url }
    }

    private func trash(_ urls: [URL]) {
        for url in urls { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        if let s = selected, urls.contains(s) { selected = nil }
        reloadFiles()
    }

    /// Last 256 KB of the file, decoded leniently (Wine logs mix UTF-8 and code-page text).
    static func tail(of url: URL, maxBytes: Int = 256 * 1024) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? h.seek(toOffset: start)
        let data = (try? h.readToEnd()) ?? Data()
        let s = String(decoding: data, as: UTF8.self)
        return start > 0 ? "… (đã lược phần đầu)\n" + s : s
    }
}
