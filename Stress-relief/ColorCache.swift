import Cocoa

// MARK: - Hỗ trợ mã màu Hex, Nội suy màu mượt (Smooth Lerp) & Bộ nhớ đệm CGColor
extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255.0
        let g = CGFloat((int >> 8) & 0xFF) / 255.0
        let b = CGFloat(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

final class ColorCache {
    static let shared = ColorCache()
    private var cache: [String: CGColor] = [:]
    private var rgbCache: [String: (Double, Double, Double)] = [:]

    let streamWater: [CGColor] = [
        "#F4FAFD", "#DCEFF7", "#B8DFEE", "#A8DCF0", "#7EC8E3", "#4BA8CA",
        "#1B9AAA", "#0F6E73", "#074346", "#C5CFD9", "#E3E8EF", "#F2F5F8"
    ].map { NSColor(hex: $0).cgColor }

    // Bảng màu 32x32x32 = 32,768 màu (quantized 5-bit mỗi kênh R, G, B từ 0..<32)
    // Tra cứu O(1) thay vì cấp phát CGColor trên heap mỗi khung hình
    let babblePalette: [CGColor] = {
        var palette: [CGColor] = []
        palette.reserveCapacity(32 * 32 * 32)
        for r in 0..<32 {
            let rf = CGFloat(r * 8) / 255.0
            for g in 0..<32 {
                let gf = CGFloat(g * 8) / 255.0
                for b in 0..<32 {
                    let bf = CGFloat(b * 8) / 255.0
                    palette.append(CGColor(srgbRed: rf, green: gf, blue: bf, alpha: 1.0))
                }
            }
        }
        return palette
    }()

    func color(for hex: String, alpha: CGFloat = 1.0) -> CGColor {
        let key = alpha == 1.0 ? hex : "\(hex)_\(Int(alpha * 100))"
        if let existing = cache[key] { return existing }
        let c = NSColor(hex: hex, alpha: alpha).cgColor
        cache[key] = c
        return c
    }

    func rgb(for hex: String) -> (Double, Double, Double) {
        if let existing = rgbCache[hex] { return existing }
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let val = (Double((int >> 16) & 0xFF) / 255.0, Double((int >> 8) & 0xFF) / 255.0, Double(int & 0xFF) / 255.0)
        rgbCache[hex] = val
        return val
    }

    func lerpHex(_ h1: String, _ h2: String, t: Double) -> CGColor {
        let clamped = max(0.0, min(1.0, t))
        let qStep = Int(round(clamped * 32.0))
        if qStep == 0 { return color(for: h1) }
        if qStep == 32 { return color(for: h2) }
        let key = "\(h1)_\(h2)_\(qStep)"
        if let existing = cache[key] { return existing }
        let c1 = rgb(for: h1), c2 = rgb(for: h2)
        let f = Double(qStep) / 32.0
        let r = CGFloat(c1.0 + (c2.0 - c1.0) * f)
        let g = CGFloat(c1.1 + (c2.1 - c1.1) * f)
        let b = CGFloat(c1.2 + (c2.2 - c1.2) * f)
        let col = NSColor(red: r, green: g, blue: b, alpha: 1.0).cgColor
        cache[key] = col
        return col
    }
}
