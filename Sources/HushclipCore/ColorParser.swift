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
