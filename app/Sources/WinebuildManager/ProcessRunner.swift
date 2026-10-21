import Foundation
import WineKit

/// A wrun process the manager started. Output goes to a per-run log file in the bottle.
struct RunningProcess: Identifiable, Equatable {
    let id = UUID()
    let bottle: Bottle
    let title: String
    let logURL: URL
    let started: Date
    let pid: Int32
}

@MainActor
final class ProcessRunner: ObservableObject {
    @Published private(set) var running: [RunningProcess] = []
    /// Last failure to show to the user (non-zero exit within a few seconds, or a launch error).
    @Published var lastError: RunError?

    struct RunError: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let logURL: URL?
    }

    private var processes: [UUID: Process] = [:]

    func running(in bottle: Bottle) -> [RunningProcess] { running.filter { $0.bottle == bottle } }

    /// Starts `command` and returns at once. Quick failures are reported through `lastError`.
    @discardableResult
    func launch(_ command: WineCommand, title: String, bottle: Bottle) -> RunningProcess? {
        let started = Date()
        let process: Process
        let logURL: URL
        do {
            (process, logURL) = try makeProcess(command, title: title, bottle: bottle)
            try process.run()
        } catch {
            lastError = RunError(title: "Không chạy được \(title)", message: error.localizedDescription, logURL: nil)
            return nil
        }
        let entry = RunningProcess(bottle: bottle, title: title, logURL: logURL, started: started, pid: process.processIdentifier)
        processes[entry.id] = process
        running.append(entry)
        process.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            Task { @MainActor in
                guard let self else { return }
                self.processes[entry.id] = nil
                self.running.removeAll { $0.id == entry.id }
                // A program that exits non-zero right away almost always failed to start (missing DLL, bad path).
                if status != 0, Date().timeIntervalSince(started) < 10, p.terminationReason == .exit {
                    self.lastError = RunError(title: "\(title) đã thoát với mã \(status)",
                                              message: "Xem nhật ký để biết chi tiết.", logURL: logURL)
                }
            }
        }
        return entry
    }

    /// Runs `command` to completion (registry edits, wineboot) and returns its exit status.
    /// With `keepLogOnSuccess: false` the log is only kept when the command fails, so routine
    /// housekeeping (one `reg add` per settings toggle) does not flood the Logs tab.
    func run(_ command: WineCommand, title: String, bottle: Bottle, keepLogOnSuccess: Bool = true) async -> Int32 {
        do {
            let (process, logURL) = try makeProcess(command, title: title, bottle: bottle)
            let status: Int32 = try await withCheckedThrowingContinuation { cont in
                process.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
                do { try process.run() } catch {
                    process.terminationHandler = nil
                    cont.resume(throwing: error)
                }
            }
            if status == 0 && !keepLogOnSuccess { try? FileManager.default.removeItem(at: logURL) }
            return status
        } catch {
            lastError = RunError(title: "Không chạy được \(title)", message: error.localizedDescription, logURL: nil)
            return -1
        }
    }

    func terminate(_ entry: RunningProcess) {
        processes[entry.id]?.terminate()
    }

    private func makeProcess(_ command: WineCommand, title: String, bottle: Bottle) throws -> (Process, URL) {
        let fm = FileManager.default
        try fm.createDirectory(at: bottle.logsDir, withIntermediateDirectories: true)
        let stamp = Self.stampFormatter.string(from: Date())
        let safeTitle = title.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        let logURL = bottle.logsDir.appendingPathComponent("\(stamp)-\(safeTitle.prefix(40)).log")
        fm.createFile(atPath: logURL.path, contents: Data("$ \(command.displayString)\n\n".utf8))
        let log = try FileHandle(forWritingTo: logURL)
        log.seekToEndOfFile()

        let p = Process()
        p.executableURL = command.executable
        p.arguments = command.arguments
        p.environment = ProcessInfo.processInfo.environment.merging(command.environment) { $1 }
        if let dir = command.currentDirectory { p.currentDirectoryURL = dir }
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = log
        p.standardError = log
        return (p, logURL)
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
