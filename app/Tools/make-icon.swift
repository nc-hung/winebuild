// Renders the app icon (1024×1024 PNG): a wine-red squircle with a wine glass and a small Windows-style grid.
// Usage: swift Tools/make-icon.swift OUT.png
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "icon.png")
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824 pt body centred in 1024 with ~185 pt corner radius.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGraphicsContext.current?.cgContext.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                                                color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill(); shape.fill()
NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
NSGradient(colors: [NSColor(red: 0.62, green: 0.10, blue: 0.27, alpha: 1),
                    NSColor(red: 0.33, green: 0.05, blue: 0.30, alpha: 1)])!.draw(in: shape, angle: -90)
// Soft top highlight.
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
NSGraphicsContext.restoreGraphicsState()

func symbol(_ name: String, pointSize: CGFloat, in rect: NSRect, color: NSColor) {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(.init(paletteColors: [color]))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
    let s = img.size, scale = min(rect.width / s.width, rect.height / s.height)
    let r = NSRect(x: rect.midX - s.width * scale / 2, y: rect.midY - s.height * scale / 2, width: s.width * scale, height: s.height * scale)
    img.draw(in: r)
}

symbol("wineglass.fill", pointSize: 400, in: NSRect(x: 250, y: 215, width: 420, height: 560), color: .white)

// Four-pane window badge, bottom right.
let badge = NSRect(x: 610, y: 190, width: 230, height: 230)
let badgePath = NSBezierPath(roundedRect: badge, xRadius: 52, yRadius: 52)
NSColor.white.setFill(); badgePath.fill()
let gap: CGFloat = 14, pane = (badge.width - 60 - gap) / 2
let colors = [NSColor.systemRed, .systemGreen, .systemBlue, .systemYellow]
for i in 0..<4 {
    let x = badge.minX + 30 + CGFloat(i % 2) * (pane + gap)
    let y = badge.minY + 30 + CGFloat(1 - i / 2) * (pane + gap)
    colors[i].setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: pane, height: pane), xRadius: 12, yRadius: 12).fill()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
