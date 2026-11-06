// Composes the Mac App Store screenshots (2880x1800) from `Hushclip --snapshot` renders.
//   usage: swift Scripts/make-appstore-screenshots.swift <Hushclip binary> <out dir>
import AppKit

let args = CommandLine.arguments
let binary = args[1], outDir = URL(fileURLWithPath: args[2])
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let icon = NSImage(contentsOf: root.appendingPathComponent("docs/icon.png"))!
let tmp = FileManager.default.temporaryDirectory

let W: CGFloat = 2880, H: CGFloat = 1800
let PAD: CGFloat = 40   // must match `padding` in Sources/Hushclip/Snapshot.swift

// MARK: - Helpers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func withState(_ body: () -> Void) { NSGraphicsContext.saveGraphicsState(); body(); NSGraphicsContext.restoreGraphicsState() }
func shadow(_ alpha: CGFloat, blur: CGFloat, dy: CGFloat) {
    let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(alpha)
    s.shadowBlurRadius = blur; s.shadowOffset = NSSize(width: 0, height: -dy); s.set()
}
func radial(_ color: UInt32, _ alpha: CGFloat, at p: NSPoint, radius: CGFloat) {
    NSGradient(colors: [rgb(color, alpha), rgb(color, 0)])!.draw(fromCenter: p, radius: 0, toCenter: p, radius: radius, options: [])
}
func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage {
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: size, weight: weight))!
    return NSImage(size: base.size, flipped: false) { r in base.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true }
}
func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, mono: Bool = false, kern: CGFloat = 0) -> NSAttributedString {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern])
}
/// Text filled with a horizontal gradient.
func gradientText(_ s: NSAttributedString, _ colors: [NSColor]) -> NSImage {
    let size = s.size()
    return NSImage(size: size, flipped: false) { r in
        s.draw(at: .zero)
        NSGraphicsContext.current?.compositingOperation = .sourceIn
        NSGradient(colors: colors)!.draw(in: r, angle: 0)
        return true
    }
}

struct Theme {
    let dark: Bool
    var ink: NSColor { dark ? .white : rgb(0x14112E) }
    var muted: NSColor { dark ? NSColor.white.withAlphaComponent(0.68) : rgb(0x14112E, 0.62) }
    var accent: [NSColor] { dark ? [rgb(0xC4B5FD), rgb(0x67E8F9)] : [rgb(0x7C3AED), rgb(0x0891B2)] }
    var glassFill: NSColor { dark ? NSColor.white.withAlphaComponent(0.10) : NSColor.white.withAlphaComponent(0.70) }
    var glassStroke: NSColor { dark ? NSColor.white.withAlphaComponent(0.22) : NSColor.white }
}

func background(_ t: Theme) {
    let full = NSRect(x: 0, y: 0, width: W, height: H)
    if t.dark {
        NSGradient(colors: [rgb(0x2A1A5E), rgb(0x15123D), rgb(0x0A1030)])!.draw(in: full, angle: -50)
        radial(0x8B5CF6, 0.55, at: NSPoint(x: 700, y: 1500), radius: 1300)
        radial(0x22D3EE, 0.30, at: NSPoint(x: 2600, y: 200), radius: 1200)
        radial(0xF472B6, 0.25, at: NSPoint(x: 200, y: 150), radius: 1000)
    } else {
        NSGradient(colors: [rgb(0xF3EEFF), rgb(0xE6ECFF), rgb(0xE3F6FB)])!.draw(in: full, angle: -50)
        radial(0xA78BFA, 0.45, at: NSPoint(x: 600, y: 1500), radius: 1300)
        radial(0x67E8F9, 0.35, at: NSPoint(x: 2650, y: 200), radius: 1200)
        radial(0xF9A8D4, 0.30, at: NSPoint(x: 150, y: 150), radius: 1000)
    }
}

/// Icon + "HUSHCLIP" eyebrow, then a headline with a gradient accent, then a subtitle.
func header(_ t: Theme, title: String, accent: String, subtitle: String) {
    let brand = text("HUSHCLIP", 34, .bold, t.muted, kern: 9)
    let iconSize: CGFloat = 76, gap: CGFloat = 20
    let bw = iconSize + gap + brand.size().width
    let bx = (W - bw) / 2, by = H - 150
    icon.draw(in: NSRect(x: bx, y: by - 6, width: iconSize, height: iconSize))
    brand.draw(at: NSPoint(x: bx + iconSize + gap, y: by + (iconSize - brand.size().height) / 2 - 6))

    let plain = text(title, 104, .heavy, t.ink, kern: -1.5)
    let acc = gradientText(text(accent, 104, .heavy, .white, kern: -1.5), t.accent)
    let tw = plain.size().width + acc.size.width
    let ty = H - 320
    plain.draw(at: NSPoint(x: (W - tw) / 2, y: ty))
    acc.draw(in: NSRect(origin: NSPoint(x: (W - tw) / 2 + plain.size().width, y: ty), size: acc.size))

    let sub = text(subtitle, 50, .medium, t.muted)
    sub.draw(at: NSPoint(x: (W - sub.size().width) / 2, y: ty - 92))
}

/// A frosted capsule with an SF Symbol and a label, centred at `center`.
func pill(_ t: Theme, _ symbolName: String, _ label: String, tint: UInt32, center: NSPoint) {
    let l = text(label, 40, .semibold, t.ink)
    let sym = symbol(symbolName, size: 38, weight: .bold, color: rgb(tint))
    let h: CGFloat = 96, padX: CGFloat = 40, gap: CGFloat = 20
    let w = padX * 2 + sym.size.width + gap + l.size().width
    let r = NSRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    let path = NSBezierPath(roundedRect: r, xRadius: h / 2, yRadius: h / 2)
    withState {
        shadow(t.dark ? 0.45 : 0.18, blur: 40, dy: 14)
        (t.dark ? rgb(0x1E1A4A, 0.92) : NSColor.white.withAlphaComponent(0.92)).setFill(); path.fill()
    }
    t.glassFill.setFill(); path.fill()
    t.glassStroke.setStroke(); path.lineWidth = 2; path.stroke()
    sym.draw(in: NSRect(x: r.minX + padX, y: r.midY - sym.size.height / 2, width: sym.size.width, height: sym.size.height))
    l.draw(at: NSPoint(x: r.minX + padX + sym.size.width + gap, y: r.midY - l.size().height / 2))
}

/// A faint app window behind the overlay, so it reads as floating over your desktop.
func ghostWindow(_ t: Theme, _ r: NSRect) {
    let path = NSBezierPath(roundedRect: r, xRadius: 34, yRadius: 34)
    withState {
        shadow(t.dark ? 0.35 : 0.12, blur: 60, dy: 20)
        (t.dark ? rgb(0x221D52, 0.55) : NSColor.white.withAlphaComponent(0.55)).setFill(); path.fill()
    }
    (t.dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.white).setStroke(); path.lineWidth = 2; path.stroke()
    for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        rgb(UInt32(c), 0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: r.minX + 40 + CGFloat(i) * 46, y: r.maxY - 62, width: 26, height: 26)).fill()
    }
    let lineColor = t.dark ? NSColor.white.withAlphaComponent(0.08) : rgb(0x14112E, 0.07)
    for (i, w) in [0.42, 0.30, 0.55, 0.36, 0.48].enumerated() {
        lineColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: r.minX + 60, y: r.maxY - 160 - CGFloat(i) * 70, width: r.width * w, height: 26),
                     xRadius: 13, yRadius: 13).fill()
    }
}

func snapshot(_ flags: [String]) -> (NSImage, NSRect) {
    let url = tmp.appendingPathComponent("hushclip-snap-\(UUID().uuidString).png")
    let p = Process(); p.executableURL = URL(fileURLWithPath: binary)
    p.arguments = ["--snapshot", url.path] + flags
    p.standardOutput = FileHandle.nullDevice
    try! p.run(); p.waitUntilExit()
    let img = NSImage(contentsOf: url)!
    try? FileManager.default.removeItem(at: url)
    // Crop the backdrop padding (in points) around the 800x520 panel.
    return (img, NSRect(x: PAD, y: PAD, width: img.size.width - 2 * PAD, height: img.size.height - 2 * PAD))
}

/// Draws the overlay panel with its own rounded corners and a deep shadow; returns where it went.
@discardableResult
func overlay(_ t: Theme, _ flags: [String], height: CGFloat = 1240, y: CGFloat = 70) -> NSRect {
    let (img, crop) = snapshot(flags)
    let scale = height / crop.height
    let dest = NSRect(x: (W - crop.width * scale) / 2, y: y, width: crop.width * scale, height: height)
    ghostWindow(t, NSRect(x: dest.minX - 230, y: dest.minY + 200, width: dest.width * 0.62, height: dest.height - 250))
    ghostWindow(t, NSRect(x: dest.maxX - dest.width * 0.50 + 250, y: dest.minY + 90, width: dest.width * 0.50, height: dest.height * 0.70))
    let path = NSBezierPath(roundedRect: dest, xRadius: 18 * scale, yRadius: 18 * scale)
    withState { shadow(t.dark ? 0.6 : 0.28, blur: 120, dy: 40); NSColor.black.setFill(); path.fill() }
    withState { path.addClip(); img.draw(in: dest, from: crop, operation: .copy, fraction: 1) }
    (t.dark ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.08)).setStroke()
    path.lineWidth = 2; path.stroke()
    return dest
}

func save(_ name: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    // App Store screenshots must not have an alpha channel: flatten onto opaque RGB.
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: W, height: H))
    let out = outDir.appendingPathComponent("\(name).png")
    let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote", out.path)
}

// MARK: - Category wall data (mirrors ClipCategory titles, symbols and tints)

let categories: [(String, String, (Double, Double, Double), String)] = [
    ("Screenshot", "camera.viewfinder", (0.69, 0.42, 0.98), "2880 × 1800 · PNG"),
    ("Password", "key.fill", (1.00, 0.33, 0.36), "••••••••••••••"),
    ("Secret", "lock.shield.fill", (1.00, 0.55, 0.18), "ghp_••••••••••••"),
    ("Card", "creditcard.fill", (0.92, 0.66, 0.10), "•••• •••• 4242"),
    ("Link", "link", (0.22, 0.62, 1.00), "apple.com/mac"),
    ("Email", "envelope.fill", (0.20, 0.74, 0.86), "hello@arlint.dev"),
    ("Phone", "phone.fill", (0.25, 0.78, 0.42), "+1 (555) 010-4242"),
    ("IP Address", "network", (0.45, 0.52, 0.96), "10.20.30.40/24"),
    ("Color", "paintpalette.fill", (0.88, 0.42, 0.94), "#7C5CFF"),
    ("Code", "chevron.left.forwardslash.chevron.right", (0.24, 0.80, 0.66), "func paste() { … }"),
    ("Command", "terminal.fill", (0.48, 0.84, 0.32), "brew install gh"),
    ("JSON", "curlybraces", (0.95, 0.62, 0.28), "{\"ok\": true}"),
    ("Path", "folder.fill", (0.38, 0.68, 0.95), "~/Developer"),
    ("UUID", "number.square.fill", (0.55, 0.58, 0.70), "3F2504E0-4F89-…"),
    ("Hash", "number", (0.50, 0.60, 0.70), "e3b0c44298fc1c14…"),
    ("Number", "textformat.123", (0.68, 0.55, 1.00), "1,048,576"),
    ("Image", "photo", (0.96, 0.38, 0.62), "1600 × 1200 · JPEG"),
    ("File", "doc.fill", (0.35, 0.60, 1.00), "Q4 Roadmap.pdf"),
    ("Text", "text.alignleft", (0.58, 0.62, 0.70), "Ship it on Friday."),
]

func categoryWall() {
    let cols = 4, rows = 5
    let gx: CGFloat = 36, gy: CGFloat = 34, left: CGFloat = 220, bottom: CGFloat = 90
    let tw = (W - 2 * left - CGFloat(cols - 1) * gx) / CGFloat(cols)
    let th: CGFloat = 214
    for i in 0..<(cols * rows) {
        let c = i % cols, r = i / cols
        let rect = NSRect(x: left + CGFloat(c) * (tw + gx), y: bottom + CGFloat(rows - 1 - r) * (th + gy), width: tw, height: th)
        let path = NSBezierPath(roundedRect: rect, xRadius: 40, yRadius: 40)
        withState { shadow(0.35, blur: 40, dy: 12); rgb(0x1C1846, 0.9).setFill(); path.fill() }
        NSColor.white.withAlphaComponent(0.06).setFill(); path.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke(); path.lineWidth = 2; path.stroke()

        let chip = NSRect(x: rect.minX + 34, y: rect.midY - 56, width: 112, height: 112)
        let chipPath = NSBezierPath(roundedRect: chip, xRadius: 30, yRadius: 30)
        let tx = chip.maxX + 30
        let sampleColor = NSColor.white.withAlphaComponent(0.72)
        if i < categories.count {
            let (title, sym, tint, sample) = categories[i]
            let color = NSColor(srgbRed: tint.0, green: tint.1, blue: tint.2, alpha: 1)
            NSGradient(colors: [color.blended(withFraction: 0.15, of: .white)!, color.blended(withFraction: 0.25, of: .black)!])!
                .draw(in: chipPath, angle: -60)
            let s = symbol(sym, size: 50, weight: .bold, color: .white)
            s.draw(in: NSRect(x: chip.midX - s.size.width / 2, y: chip.midY - s.size.height / 2, width: s.size.width, height: s.size.height))
            text(title, 48, .bold, color.blended(withFraction: 0.35, of: .white)!).draw(at: NSPoint(x: tx, y: rect.midY + 6))
            if title == "Color" {
                rgb(0x7C5CFF).setFill()
                NSBezierPath(roundedRect: NSRect(x: tx, y: rect.midY - 48, width: 40, height: 40), xRadius: 10, yRadius: 10).fill()
                text(sample, 36, .medium, sampleColor, mono: true).draw(at: NSPoint(x: tx + 56, y: rect.midY - 54))
            } else {
                text(sample, 36, .medium, sampleColor, mono: true).draw(at: NSPoint(x: tx, y: rect.midY - 54))
            }
        } else {
            // Last tile: the shortcut.
            NSGradient(colors: [rgb(0x8B5CF6), rgb(0x4F46E5)])!.draw(in: chipPath, angle: -60)
            let s = symbol("command", size: 50, weight: .bold, color: .white)
            s.draw(in: NSRect(x: chip.midX - s.size.width / 2, y: chip.midY - s.size.height / 2, width: s.size.width, height: s.size.height))
            var kx = tx
            for key in ["⌘", "⇧", "V"] {
                let k = NSRect(x: kx, y: rect.midY + 4, width: 64, height: 64)
                let kp = NSBezierPath(roundedRect: k, xRadius: 16, yRadius: 16)
                NSColor.white.withAlphaComponent(0.14).setFill(); kp.fill()
                NSColor.white.withAlphaComponent(0.3).setStroke(); kp.lineWidth = 2; kp.stroke()
                let l = text(key, 36, .semibold, .white)
                l.draw(at: NSPoint(x: k.midX - l.size().width / 2, y: k.midY - l.size().height / 2))
                kx += 78
            }
            text("from any app", 36, .medium, sampleColor).draw(at: NSPoint(x: tx, y: rect.midY - 54))
        }
    }
}

// MARK: - Screenshots

let dark = Theme(dark: true), light = Theme(dark: false)

save("1-overview") {
    background(dark)
    header(dark, title: "Everything you copied, ", accent: "one shortcut away",
           subtitle: "Press ⌘⇧V anywhere. Search, preview and paste straight into the app you're using.")
    let r = overlay(dark, ["--select", "0"])
    pill(dark, "command", "Opens from any app", tint: 0xA78BFA, center: NSPoint(x: r.maxX - 60, y: r.minY + 470))
    pill(dark, "return", "Return pastes it", tint: 0x67E8F9, center: NSPoint(x: r.maxX - 10, y: r.minY + 330))
}

save("2-categories") {
    background(dark)
    header(dark, title: "Every clip, ", accent: "sorted automatically",
           subtitle: "19 kinds of clips are recognized the moment you copy them, entirely on your Mac.")
    categoryWall()
}

save("3-preview") {
    background(dark)
    header(dark, title: "See it ", accent: "before you paste",
           subtitle: "Screenshots, images, colors, code and links get a rich preview right in the overlay.")
    let r = overlay(dark, ["--select", "1"])
    pill(dark, "camera.viewfinder", "Screenshots detected", tint: 0xC084FC, center: NSPoint(x: r.maxX - 40, y: r.minY + 330))
}

save("4-secrets") {
    background(light)
    header(light, title: "Secrets ", accent: "stay secret",
           subtitle: "Passwords, API keys and card numbers are masked, and delete themselves after an hour.")
    let r = overlay(light, ["--light", "--select", "2"])
    pill(light, "timer", "Auto-deletes in 1 hour", tint: 0x7C3AED, center: NSPoint(x: r.maxX - 60, y: r.minY + 330))
    pill(light, "eye.slash.fill", "Hold ⌥ to reveal", tint: 0xEF4444, center: NSPoint(x: r.maxX - 140, y: r.minY + 200))
}

save("5-private") {
    background(dark)
    header(dark, title: "Encrypted. ", accent: "Never uploaded.",
           subtitle: "AES-256 with a key in your Keychain. No network, no accounts, no tracking.")
    let r = overlay(dark, ["--select", "8"])
    pill(dark, "lock.fill", "AES-256-GCM at rest", tint: 0x4ADE80, center: NSPoint(x: r.maxX - 60, y: r.minY + 600))
    pill(dark, "key.fill", "Key stays in your Keychain", tint: 0xFBBF24, center: NSPoint(x: r.maxX - 140, y: r.minY + 465))
    pill(dark, "wifi.slash", "Works fully offline", tint: 0x67E8F9, center: NSPoint(x: r.maxX - 20, y: r.minY + 330))
}
