#!/usr/bin/env swift
// Renders Resources/AppIcon.icns: a violet→blue squircle with a clipboard glyph and a lock badge.
//   usage: swift Scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Clipster-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func tinted(_ symbol: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    return NSImage(size: base.size, flipped: false) { rect in
        base.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: 824/1024 body with shadow room.
    let body = NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.03
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(srgbRed: 0.49, green: 0.36, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.48, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.74, blue: 0.95, alpha: 1),
    ])!.draw(in: path, angle: -60)

    // Soft top highlight.
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Clipboard glyph.
    let glyph = tinted("list.clipboard.fill", pointSize: s * 0.40, weight: .semibold, color: .white)
    let gSize = glyph.size
    let gRect = NSRect(x: body.midX - gSize.width / 2 - s * 0.02, y: body.midY - gSize.height / 2 + s * 0.01,
                       width: gSize.width, height: gSize.height)
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    glyphShadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    glyphShadow.shadowBlurRadius = s * 0.02
    NSGraphicsContext.saveGraphicsState()
    glyphShadow.set()
    glyph.draw(in: gRect)
    NSGraphicsContext.restoreGraphicsState()

    // Lock badge.
    let badgeDiameter = s * 0.27
    let badge = NSRect(x: body.maxX - badgeDiameter - s * 0.07, y: body.minY + s * 0.07,
                       width: badgeDiameter, height: badgeDiameter)
    NSGraphicsContext.saveGraphicsState()
    glyphShadow.set()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: badge).fill()
    NSGraphicsContext.restoreGraphicsState()
    let lock = tinted("lock.fill", pointSize: badgeDiameter * 0.48, weight: .bold,
                      color: NSColor(srgbRed: 0.33, green: 0.38, blue: 1.0, alpha: 1))
    lock.draw(in: NSRect(x: badge.midX - lock.size.width / 2, y: badge.midY - lock.size.height / 2,
                         width: lock.size.width, height: lock.size.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(512).write(to: root.appendingPathComponent("docs/icon.png"))

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "wrote \(out.path)" : "iconutil failed")
