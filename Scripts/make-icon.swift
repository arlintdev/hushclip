#!/usr/bin/env swift
// Renders Resources/AppIcon.icns, the asset-catalog PNGs and docs/icon.png.
// Design: a deep indigo glass squircle holding a fanned stack of clip cards in category colors.
// The front card shows a lock and a masked secret.
//   usage: swift Scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Hushclip-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    return NSImage(size: base.size, flipped: false) { rect in
        base.draw(in: rect); color.set(); rect.fill(using: .sourceAtop); return true
    }
}

func withState(_ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState(); body(); NSGraphicsContext.restoreGraphicsState()
}

func shadow(_ alpha: CGFloat, blur: CGFloat, dy: CGFloat) {
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(alpha)
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: -dy)
    s.set()
}

func radial(_ color: UInt32, _ alpha: CGFloat, at p: NSPoint, radius: CGFloat) {
    NSGradient(colors: [rgb(color, alpha), rgb(color, 0)])!
        .draw(fromCenter: p, radius: 0, toCenter: p, radius: radius, options: [])
}

/// A card centred at `center`, rotated by `degrees`, in the 1024-unit icon space.
func card(center: NSPoint, size: NSSize, degrees: CGFloat, radius: CGFloat, draw: (NSBezierPath, NSRect) -> Void) {
    withState {
        let t = NSAffineTransform()
        t.translateX(by: center.x, yBy: center.y)
        t.rotate(byDegrees: degrees)
        t.concat()
        let rect = NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        draw(NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius), rect)
    }
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)   // draw in 1024-unit space at any pixel size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let small = px <= 64

    // macOS icon grid: an 824-unit body centred in 1024, with room for the drop shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    withState { shadow(0.45, blur: 28, dy: 12); NSColor.black.setFill(); squircle.fill() }

    withState {
        squircle.addClip()
        // Deep indigo base with colored glows behind the stack.
        NSGradient(colors: [rgb(0x34216F), rgb(0x1A1446), rgb(0x0B1233)])!.draw(in: body, angle: -60)
        radial(0x8B5CF6, 0.85, at: NSPoint(x: 430, y: 660), radius: 480)
        radial(0x22D3EE, 0.50, at: NSPoint(x: 820, y: 190), radius: 420)
        radial(0xF472B6, 0.38, at: NSPoint(x: 190, y: 250), radius: 360)

        // Back cards: the history behind the current clip, in category colors.
        card(center: NSPoint(x: 486, y: 636), size: NSSize(width: 470, height: 300), degrees: 10, radius: 58) { path, _ in
            withState { shadow(0.35, blur: 30, dy: 10); rgb(0xF472B6).setFill(); path.fill() }
            NSGradient(colors: [rgb(0xFB7185), rgb(0xC026D3)])!.draw(in: path, angle: -30)
        }
        card(center: NSPoint(x: 534, y: 566), size: NSSize(width: 500, height: 316), degrees: -6, radius: 60) { path, _ in
            withState { shadow(0.35, blur: 30, dy: 10); rgb(0x3B82F6).setFill(); path.fill() }
            NSGradient(colors: [rgb(0x22D3EE), rgb(0x6366F1)])!.draw(in: path, angle: -30)
        }

        // Front card: frosted white, with a lock chip and a masked secret.
        card(center: NSPoint(x: 512, y: 410), size: NSSize(width: 560, height: 350), degrees: 0, radius: 66) { path, rect in
            withState { shadow(0.45, blur: 44, dy: 18); NSColor.white.setFill(); path.fill() }
            NSGradient(colors: [rgb(0xFFFFFF), rgb(0xE6E3FA)])!.draw(in: path, angle: -90)

            let chip = NSRect(x: rect.minX + 54, y: rect.midY - 68, width: 136, height: 136)
            let chipPath = NSBezierPath(roundedRect: chip, xRadius: 40, yRadius: 40)
            NSGradient(colors: [rgb(0x8B5CF6), rgb(0x4F46E5)])!.draw(in: chipPath, angle: -60)
            let lock = symbol("lock.fill", size: small ? 96 : 80, weight: .bold, color: .white)
            lock.draw(in: NSRect(x: chip.midX - lock.size.width / 2, y: chip.midY - lock.size.height / 2,
                                 width: lock.size.width, height: lock.size.height))

            // Masked secret: a row of dots over a faint metadata line.
            let dots = small ? 4 : 6
            let dotD: CGFloat = small ? 46 : 36, gap: CGFloat = small ? 20 : 14
            let startX = chip.maxX + 44
            for i in 0..<dots {
                let d = NSRect(x: startX + CGFloat(i) * (dotD + gap), y: small ? chip.midY - dotD / 2 : chip.midY + 6,
                               width: dotD, height: dotD)
                rgb(0x1E1B4B).setFill(); NSBezierPath(ovalIn: d).fill()
            }
            if !small {
                rgb(0x8B5CF6, 0.40).setFill()
                NSBezierPath(roundedRect: NSRect(x: startX, y: chip.midY - 50, width: 176, height: 24), xRadius: 12, yRadius: 12).fill()
                rgb(0x1E1B4B, 0.14).setFill()
                NSBezierPath(roundedRect: NSRect(x: startX + 192, y: chip.midY - 50, width: 84, height: 24), xRadius: 12, yRadius: 12).fill()
            }
        }

        // Glass: top sheen and a thin bright rim.
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.20), NSColor.white.withAlphaComponent(0)])!
            .draw(in: NSRect(x: body.minX, y: body.midY + 140, width: body.width, height: body.height / 2 - 140), angle: -90)
        if !small {
            NSColor.white.withAlphaComponent(0.22).setStroke()
            squircle.lineWidth = 6   // half of it is clipped away, leaving a 3-unit inner rim
            squircle.stroke()
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let appiconset = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        let data = render(size * scale)
        try data.write(to: iconset.appendingPathComponent(name))
        try data.write(to: appiconset.appendingPathComponent(name))
    }
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
