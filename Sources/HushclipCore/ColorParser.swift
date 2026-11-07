import Foundation

/// Parses the color strings `Categorizer` labels `.color`, for the preview swatch.
public enum ColorParser {
    public struct RGBA: Equatable, Sendable {
        public var r, g, b, a: Double
    }

    public static func parse(_ raw: String) -> RGBA? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#") { return parseHex(String(s.dropFirst())) }
        if s.hasPrefix("rgb") { return parseRGB(s) }
        if s.hasPrefix("hsl") { return parseHSL(s) }
        return nil
    }

    // MARK: - Formatting

    static func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
    static func trim(_ v: Double, places: Int = 2) -> String {
        var s = String(format: "%.\(places)f", v)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// `#1a2b3c`, or `#1a2b3c80` with transparency.
    public static func hex(_ c: RGBA) -> String {
        var s = String(format: "#%02x%02x%02x", byte(c.r), byte(c.g), byte(c.b))
        if c.a < 1 { s += String(format: "%02x", byte(c.a)) }
        return s
    }

    /// `rgb(26, 43, 60)` or `rgba(26, 43, 60, 0.5)`.
    public static func rgb(_ c: RGBA) -> String {
        let parts = "\(byte(c.r)), \(byte(c.g)), \(byte(c.b))"
        return c.a < 1 ? "rgba(\(parts), \(trim(c.a)))" : "rgb(\(parts))"
    }

    /// `hsl(210, 40%, 17%)` or `hsla(…, 0.5)`.
    public static func hsl(_ c: RGBA) -> String {
        let r = min(max(c.r, 0), 1), g = min(max(c.g, 0), 1), b = min(max(c.b, 0), 1)
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        let d = maxV - minV
        var h = 0.0, s = 0.0
        if d > 0 {
            s = d / (1 - abs(2 * l - 1))
            switch maxV {
            case r: h = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6)
            case g: h = 60 * ((b - r) / d + 2)
            default: h = 60 * ((r - g) / d + 4)
            }
            if h < 0 { h += 360 }
        }
        let parts = "\(Int(h.rounded()) % 360), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%"
        return c.a < 1 ? "hsla(\(parts), \(trim(c.a)))" : "hsl(\(parts))"
    }

    /// `Color(red: 0.1, green: 0.17, blue: 0.24)` for SwiftUI.
    public static func swiftUI(_ c: RGBA) -> String {
        var s = "Color(red: \(trim(c.r, places: 3)), green: \(trim(c.g, places: 3)), blue: \(trim(c.b, places: 3))"
        if c.a < 1 { s += ", opacity: \(trim(c.a, places: 3))" }
        return s + ")"
    }

    static func parseHex(_ hex: String) -> RGBA? {
        var h = hex
        if h.count == 3 || h.count == 4 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        if h.count == 6 {
            return RGBA(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255, a: 1)
        }
        return RGBA(r: Double((v >> 24) & 0xFF) / 255, g: Double((v >> 16) & 0xFF) / 255,
                    b: Double((v >> 8) & 0xFF) / 255, a: Double(v & 0xFF) / 255)
    }

    static func components(_ s: String) -> [String] {
        guard let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") else { return [] }
        return s[s.index(after: open)..<close]
            .split(whereSeparator: { ", /".contains($0) })
            .map(String.init)
    }

    static func value(_ c: String, scale: Double) -> Double? {
        if c.hasSuffix("%") { return Double(c.dropLast()).map { $0 / 100 } }
        return Double(c).map { $0 / scale }
    }

    static func parseRGB(_ s: String) -> RGBA? {
        let c = components(s)
        guard c.count >= 3, let r = value(c[0], scale: 255), let g = value(c[1], scale: 255), let b = value(c[2], scale: 255)
        else { return nil }
        let a = c.count > 3 ? (value(c[3], scale: 1) ?? 1) : 1
        return RGBA(r: r, g: g, b: b, a: a)
    }

    static func parseHSL(_ s: String) -> RGBA? {
        let c = components(s)
        guard c.count >= 3, let h = Double(c[0].replacingOccurrences(of: "deg", with: "")),
              let sat = value(c[1], scale: 100), let l = value(c[2], scale: 100) else { return nil }
        let a = c.count > 3 ? (value(c[3], scale: 1) ?? 1) : 1
        let k = { (n: Double) in (n + h / 30).truncatingRemainder(dividingBy: 12) }
        let amp = sat * min(l, 1 - l)
        let f = { (n: Double) in l - amp * max(-1, min(k(n) - 3, 9 - k(n), 1)) }
        return RGBA(r: f(0), g: f(8), b: f(4), a: a)
    }
}
