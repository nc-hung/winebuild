// Move the mouse to a screen point (in points, top-left origin) and wiggle it there, so the window under it
// gets real mouse-moved events.
// usage: swift move-mouse.swift X Y
// Exit status: 0 moved, 3 not allowed (the terminal lacks Accessibility permission to post events).
import CoreGraphics
import Foundation

let a = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard a.count == 2 else {
    print("usage: move-mouse.swift X Y")
    exit(2)
}
guard CGPreflightPostEventAccess() else { exit(3) }

for i in 0..<20 {
    let p = CGPoint(x: a[0] + Double(i % 5), y: a[1] + Double(i % 3))
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(50_000)
}
