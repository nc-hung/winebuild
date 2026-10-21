// Helper for test-modeset.sh.
//   swift check-modeset.swift mode     prints the main Mac display's mode: "W H PIXELW PIXELH MODEID"
//   swift check-modeset.swift window   prints the largest on-screen window owned by Wine: "W H X Y" (points)
import CoreGraphics

let display = CGMainDisplayID()
switch CommandLine.arguments.dropFirst().first {
case "mode":
    let m = CGDisplayCopyDisplayMode(display)!
    print(m.width, m.height, m.pixelWidth, m.pixelHeight, m.ioDisplayModeID)
case "window":
    let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]) ?? []
    let rects: [CGRect] = list.compactMap { info in
        guard (info[kCGWindowOwnerName as String] as? String)?.lowercased().hasPrefix("wine") == true,
              (info[kCGWindowLayer as String] as? Int ?? 0) >= 0,
              let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
        return CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!)
    }
    guard let r = rects.max(by: { $0.width * $0.height < $1.width * $1.height }) else { print("none"); break }
    print(Int(r.width), Int(r.height), Int(r.minX), Int(r.minY))
default:
    print("usage: check-modeset.swift mode|window")
}
