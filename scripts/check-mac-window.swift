// Check with CGWindowList that an on-screen Mac window of a given size sits at a given position, belongs to
// a different process than the parent-sized window, and is ordered above it.
// usage: swift check-mac-window.swift W H X Y PARENT_W PARENT_H [R G B]
// Bounds are in points; with Wine's retina mode off, one Wine pixel is one point.
// With R G B, also check that the child window's centre shows that colour (needs Screen Recording permission).
// The child's process must not be a regular app: its only window belongs inside the parent's, so it shouldn't
// add a Dock icon.
// Exit status: 0 pass, 1 fail, 3 partial. Partial means the window manager is showing windows scaled (Stage
// Manager, Mission Control), so only "the child has its own Mac window, above the parent's" could be checked,
// or that the colour couldn't be checked.
import AppKit
import CoreGraphics
import Foundation
import ImageIO

let a = CommandLine.arguments.dropFirst().compactMap { Int($0) }
guard a.count == 6 || a.count == 9 else {
    print("usage: check-mac-window.swift W H X Y PARENT_W PARENT_H [R G B]")
    exit(2)
}
let (w, h, x, y, pw, ph) = (a[0], a[1], a[2], a[3], a[4], a[5])
let wantColor = a.count == 9 ? Array(a[6...8]) : nil

let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let list = (CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]) ?? []  // front to back

struct Win { let index: Int; let pid: Int; let number: Int; let owner: String; let rect: CGRect }
let wins: [Win] = list.enumerated().compactMap { i, info in
    guard let b = info[kCGWindowBounds as String] as? [String: CGFloat],
          let pid = info[kCGWindowOwnerPID as String] as? Int else { return nil }
    let owner = info[kCGWindowOwnerName as String] as? String ?? ""
    return Win(index: i, pid: pid, number: info[kCGWindowNumber as String] as? Int ?? 0, owner: owner,
               rect: CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0))
}

// Check the colour at the centre of the child's Mac window: 0 match, 1 mismatch, 3 can't capture.
func colorCheck(_ win: Win) -> Int32 {
    guard let want = wantColor else { return 0 }
    guard CGPreflightScreenCaptureAccess() else {
        print("PARTIAL: colour not checked (no Screen Recording permission for this terminal)")
        return 3
    }
    let file = NSTemporaryDirectory() + "xprocchild-\(win.number).png"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l", String(win.number), file]
    try? p.run()
    p.waitUntilExit()
    defer { try? FileManager.default.removeItem(atPath: file) }
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: file) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        print("PARTIAL: could not capture window \(win.number)")
        return 3
    }
    var px = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: -img.width / 2, y: -img.height / 2, width: img.width, height: img.height))
    let got = px[0..<3].map(Int.init)
    if zip(got, want).allSatisfy({ abs($0 - $1) <= 40 }) { return 0 }
    print("FAIL: child window centre is rgb\(got), expected rgb\(want)")
    return 1
}
// The child's process shows only a child of another process's window, so it must not get a Dock icon.
func dockCheck(_ win: Win) -> Bool {
    let app = NSRunningApplication(processIdentifier: pid_t(win.pid))
    if app?.activationPolicy == .regular {
        print("FAIL: child process \(win.pid) is a regular app (Dock icon)")
        return false
    }
    return true
}
func near(_ a: CGFloat, _ b: Int) -> Bool { abs(Int(a.rounded()) - b) <= 1 }

let parents = wins.filter { near($0.rect.width, pw) && near($0.rect.height, ph) }
let children = wins.filter { near($0.rect.width, w) && near($0.rect.height, h) }

// Fallback when windows are shown scaled: match Wine windows by aspect ratio instead of size.
func scaledCheck() -> Never {
    func ratio(_ r: CGRect) -> CGFloat { r.height > 0 ? r.width / r.height : 0 }
    let wine = wins.filter { $0.owner.lowercased().hasPrefix("wine") && $0.rect.width > 20 }
    let wantChild = CGFloat(w) / CGFloat(h), wantParent = CGFloat(pw) / CGFloat(ph)
    func closest(_ want: CGFloat, _ cands: [Win]) -> Win? {
        cands.filter { abs(ratio($0.rect) - want) < 0.03 }.min { abs(ratio($0.rect) - want) < abs(ratio($1.rect) - want) }
    }
    guard let parent = closest(wantParent, wine) else {
        print("FAIL: no Wine window shaped like the \(pw)x\(ph) parent (\(wine.count) Wine windows on screen)")
        exit(1)
    }
    guard let child = closest(wantChild, wine.filter { $0.pid != parent.pid }) else {
        print("FAIL: no Mac window for the child process (only the parent's, pid \(parent.pid), windows scaled)")
        exit(1)
    }
    if child.index > parent.index {
        print("FAIL: child window (pid \(child.pid)) is ordered below the parent window (windows scaled)")
        exit(1)
    }
    if colorCheck(child) == 1 || !dockCheck(child) { exit(1) }
    print("PARTIAL: child process \(child.pid) has its own Mac window above the parent's (pid \(parent.pid)); " +
          "windows are shown scaled (\(Int(parent.rect.width))x\(Int(parent.rect.height))), so positions were not checked")
    exit(3)
}

guard let parent = parents.first else { scaledCheck() }
guard let child = children.first else {
    print("FAIL: no on-screen \(w)x\(h) window (parent pid \(parent.pid) at \(parent.rect.origin))")
    exit(1)
}
var ok = true
if !near(child.rect.minX, x) || !near(child.rect.minY, y) {
    print("FAIL: child window at \(Int(child.rect.minX)),\(Int(child.rect.minY)), expected \(x),\(y)")
    ok = false
}
if child.pid == parent.pid {
    print("FAIL: child window belongs to the parent's process \(parent.pid)")
    ok = false
}
if child.index > parent.index {
    print("FAIL: child window is ordered below the parent window")
    ok = false
}
let color = colorCheck(child)
if color == 1 || !dockCheck(child) { ok = false }
if ok { print("\(color == 0 ? "PASS" : "position ok"): \(w)x\(h) window at \(x),\(y) above parent (pids \(child.pid)/\(parent.pid))") }
exit(ok ? color : 1)
