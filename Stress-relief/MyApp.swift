import SwiftUI
import Cocoa

// MARK: - 1. Khai báo Identifier
extension NSTouchBarItem.Identifier {
    static let controlStripItem = NSTouchBarItem.Identifier("com.8bitwave.controlstrip")
    static let waveItem = NSTouchBarItem.Identifier("com.8bitwave.item")
}

// MARK: - 2. Cầu nối gọi thẳng Private API (Ẩn hoàn toàn nút X)
enum TouchBarPrivateAPI {
    private static let handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)

    static func setControlStripPresence(identifier: String, present: Bool) {
        guard let sym = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        typealias Func = @convention(c) (CFString, Bool) -> Void
        let fn = unsafeBitCast(sym, to: Func.self)
        fn(identifier as CFString, present)
    }

    static func setModalShowsCloseBox(_ show: Bool) {
        guard let sym = dlsym(handle, "DFRSystemModalShowsCloseBoxWhenFrontMost") else { return }
        typealias Func = @convention(c) (Bool) -> Void
        let fn = unsafeBitCast(sym, to: Func.self)
        fn(show)
    }

    static func addSystemTrayItem(_ item: NSTouchBarItem) {
        let sel = NSSelectorFromString("addSystemTrayItem:")
        if NSTouchBarItem.responds(to: sel) {
            NSTouchBarItem.perform(sel, with: item)
        }
    }

    static func presentSystemModal(_ touchBar: NSTouchBar, identifier: String) {
        let selPlacement = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        let selOld = NSSelectorFromString("presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:")
        typealias PresentFunc = @convention(c) (AnyObject, Selector, NSTouchBar, Int, NSString) -> Void

        if NSTouchBar.responds(to: selPlacement), let imp = NSTouchBar.method(for: selPlacement) {
            let fn = unsafeBitCast(imp, to: PresentFunc.self)
            fn(NSTouchBar.self, selPlacement, touchBar, 1, identifier as NSString)
        } else if NSTouchBar.responds(to: selOld), let imp = NSTouchBar.method(for: selOld) {
            let fn = unsafeBitCast(imp, to: PresentFunc.self)
            fn(NSTouchBar.self, selOld, touchBar, 1, identifier as NSString)
        }
    }
}

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

// MARK: - 3. Danh mục 16 Background Sounds & Cấu hình Lưới Chuẩn Retina (@2x)
enum SoundTheme: String, CaseIterable {
    case balancedNoise, brightNoise, darkNoise
    case ocean, rain, stream, night, fire
    case babble, steam
    case airplane, boat, bus, train
    case rainOnRoof, quietNight

    var gridConfig: (blockSize: CGFloat, gap: CGFloat, softGrid: Bool) {
        switch self {
        case .balancedNoise, .brightNoise, .darkNoise:
            return (2.5, 0.5, false) // 12 hàng x 402 cột
        case .fire, .night, .rain, .quietNight, .babble:
            return (2.0, 0.5, false) // 15 hàng x 502 cột
        case .steam, .rainOnRoof, .stream, .ocean, .boat, .bus, .airplane, .train:
            return (1.5, 0.5, true)  // 20 hàng x 670 cột
        }
    }

    static func detect(from rawString: String) -> SoundTheme? {
        let s = rawString.lowercased()
        if s.contains("rainonroof") || s.contains("rain_on_roof") || s.contains("roof") { return .rainOnRoof }
        if s.contains("quietnight") || s.contains("quiet_night") || s.contains("quiet") { return .quietNight }
        if s.contains("balanced") || s.contains("whitenoise") || s.contains("white_noise") { return .balancedNoise }
        if s.contains("bright") || s.contains("pinknoise") || s.contains("pink_noise") { return .brightNoise }
        if s.contains("dark") || s.contains("brownnoise") || s.contains("brown_noise") { return .darkNoise }
        if s.contains("train") || s.contains("rail") { return .train }
        if s.contains("airplane") || s.contains("plane") || s.contains("cabin") || s.contains("flight") { return .airplane }
        if s.contains("stream") || s.contains("creek") || s.contains("brook") { return .stream }
        if s.contains("ocean") || s.contains("beach") || s.contains("waves") { return .ocean }
        if s.contains("boat") || s.contains("ferry") || s.contains("ship") || s.contains("sail") { return .boat }
        if s.contains("bus") || s.contains("coach") { return .bus }
        if s.contains("babble") || s.contains("crowd") || s.contains("chatter") || s.contains("cafe") { return .babble }
        if s.contains("steam") || s.contains("kettle") || s.contains("vapor") { return .steam }
        if s.contains("fire") || s.contains("camp") || s.contains("hearth") { return .fire }
        if s.contains("night") { return .night }
        if s.contains("rain") { return .rain }
        return nil
    }
}

// MARK: - 4. Bộ theo dõi Hearing (Background Sounds) của macOS
class ComfortSoundsMonitor {
    private let domain = "com.apple.ComfortSounds" as CFString
    private(set) var currentTheme: SoundTheme = .stream
    private(set) var currentVolume: Double = 0.4
    private(set) var isEnabled: Bool = false

    func pollSystemPreferences() {
        CFPreferencesAppSynchronize(domain)
        if let enabledVal = CFPreferencesCopyAppValue("comfortSoundsEnabled" as CFString, domain) as? Bool {
            self.isEnabled = enabledVal
        } else if let enabledNum = CFPreferencesCopyAppValue("comfortSoundsEnabled" as CFString, domain) as? NSNumber {
            self.isEnabled = enabledNum.boolValue
        } else {
            self.isEnabled = false
        }

        if let volNum = CFPreferencesCopyAppValue("relativeVolume" as CFString, domain) as? NSNumber {
            self.currentVolume = max(0.05, min(1.0, volNum.doubleValue))
        }

        let possibleKeys = ["ComfortSoundsSelectedSound", "selectedSound", "comfortSound"]
        for key in possibleKeys {
            guard let rawVal = CFPreferencesCopyAppValue(key as CFString, domain) else { continue }
            if let str = rawVal as? String, let detected = SoundTheme.detect(from: str) {
                self.currentTheme = detected
                break
            } else if let data = rawVal as? Data, let detected = extractTheme(from: data) {
                self.currentTheme = detected
                break
            }
        }
    }

    private func extractTheme(from data: Data) -> SoundTheme? {
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            if let dict = plist as? [String: Any], let objects = dict["$objects"] as? [Any] {
                for obj in objects.reversed() {
                    if let str = obj as? String, !str.hasPrefix("$"), str != "HUComfortSound", str != "AXAsset",
                       let detected = SoundTheme.detect(from: str) {
                        return detected
                    }
                }
            }
            if let detected = SoundTheme.detect(from: String(describing: plist)) { return detected }
        }
        return SoundTheme.detect(from: String(decoding: data, as: UTF8.self))
    }
}

// MARK: - 5. View vẽ Nghệ thuật Toàn cảnh 8-Bit
class Wave8BitView: NSView {
    private var renderTimer: Timer?
    private var monitorTimer: Timer?
    private var phase: Double = 0.0
    private let monitor = ComfortSoundsMonitor()
    private let visibleWidth: CGFloat = 1004.0

    private let babbleCols = 502
    private let babbleRows = 15
    private var babbleBuffer = [UInt8](repeating: 0, count: 502 * 15 * 4)
    private var babbleBitmapCtx: CGContext?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupBabbleRasterizer()
        monitor.pollSystemPreferences()

        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.monitor.pollSystemPreferences()
        }

        renderTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let effectiveVol = self.monitor.isEnabled ? self.monitor.currentVolume : 0.12
            let curvedVol = pow(effectiveVol, 1.35)
            let speedStep = 0.009 + (curvedVol * 0.045)
            self.phase += speedStep
            self.needsDisplay = true
        }
    }

    private func setupBabbleRasterizer() {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        babbleBitmapCtx = babbleBuffer.withUnsafeMutableBytes { ptr -> CGContext? in
            guard let base = ptr.baseAddress else { return nil }
            return CGContext(
                data: base,
                width: babbleCols,
                height: babbleRows,
                bitsPerComponent: 8,
                bytesPerRow: babbleCols * 4,
                space: cs,
                bitmapInfo: bitmapInfo
            )
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 2170, height: 30)
    }

    private func c(_ hex: String, _ alpha: CGFloat = 1.0) -> CGColor {
        return ColorCache.shared.color(for: hex, alpha: alpha)
    }

    private func lerp(_ h1: String, _ h2: String, _ t: Double) -> CGColor {
        return ColorCache.shared.lerpHex(h1, h2, t: t)
    }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }

    private func hash2D(_ x: Int, _ y: Int) -> Int {
        var h = (x &* 374761393) &+ (y &* 668265263)
        h = (h ^ (h >> 13)) &* 1274126177
        return abs(h ^ (h >> 16))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let theme = monitor.currentTheme

        if theme == .babble, let offCtx = babbleBitmapCtx {
            offCtx.saveGState()
            offCtx.scaleBy(x: CGFloat(babbleCols) / visibleWidth, y: CGFloat(babbleRows) / bounds.height)
            drawKandinskyMasterpiece(in: offCtx, width: visibleWidth, height: bounds.height)
            offCtx.restoreGState()
        }

        context.setAllowsAntialiasing(false)
        let cfg = theme.gridConfig
        let blockSize = cfg.blockSize
        let cols = Int(visibleWidth / blockSize) + 2
        let rows = Int(bounds.height / blockSize)

        if cfg.softGrid {
            for col in 0..<cols {
                let xPos = CGFloat(col) * blockSize
                for row in 0..<rows {
                    context.setFillColor(pixelColor(for: theme, col: col, row: row))
                    context.fill(CGRect(x: xPos, y: CGFloat(row) * blockSize, width: blockSize, height: blockSize))
                }
            }
            context.setFillColor(c("#05070A", 0.26))
            for col in 0..<cols {
                context.fill(CGRect(x: CGFloat(col) * blockSize, y: 0, width: 0.5, height: bounds.height))
            }
            for row in 0..<rows {
                context.fill(CGRect(x: 0, y: CGFloat(row) * blockSize, width: visibleWidth, height: 0.5))
            }
        } else {
            let drawSize = blockSize - cfg.gap
            context.setFillColor(c("#050608"))
            context.fill(bounds)
            for col in 0..<cols {
                let xPos = CGFloat(col) * blockSize
                for row in 0..<rows {
                    context.setFillColor(pixelColor(for: theme, col: col, row: row))
                    context.fill(CGRect(x: xPos, y: CGFloat(row) * blockSize, width: drawSize, height: drawSize))
                }
            }
        }
    }

    private func sample8BitKandinsky(col: Int, row: Int) -> CGColor {
        let cx = max(0, min(babbleCols - 1, col % babbleCols))
        let memY = max(0, min(babbleRows - 1, (babbleRows - 1) - row))
        let offset = (memY * babbleCols + cx) * 4
        let r = CGFloat((Int(babbleBuffer[offset]) / 8) * 8) / 255.0
        let g = CGFloat((Int(babbleBuffer[offset + 1]) / 8) * 8) / 255.0
        let b = CGFloat((Int(babbleBuffer[offset + 2]) / 8) * 8) / 255.0
        return CGColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    // 1. BABBLE — BẢN VẼ WASSILY KANDINSKY (8-BIT RASTERIZED)
    private func drawKandinskyMasterpiece(in ctx: CGContext, width: CGFloat, height: CGFloat) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let p = CGFloat(phase)
        let d1 = sin(p * 0.55) * 3.5
        let d2 = cos(p * 0.45) * 3.0
        let breathe = sin(p * 0.7) * 1.1

        let bgCols = [c("#F5EEDC"), c("#EDE2C8"), c("#D2E0EC"), c("#ECE5D5"), c("#E2D8C0")] as CFArray
        let bgLocs: [CGFloat] = [0.0, 0.18, 0.42, 0.70, 1.0]
        if let grad = CGGradient(colorsSpace: cs, colors: bgCols, locations: bgLocs) {
            ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: width, y: 0), options: [])
        }

        func drawHalo(cx: CGFloat, cy: CGFloat, r: CGFloat, innerHex: String, midHex: String, outerHex: String, alpha: CGFloat = 0.75) {
            let cols = [c(innerHex, alpha), c(midHex, alpha * 0.55), c(outerHex, 0.0)] as CFArray
            let locs: [CGFloat] = [0.0, 0.55, 1.0]
            if let g = CGGradient(colorsSpace: cs, colors: cols, locations: locs) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
            }
        }

        drawHalo(cx: 120, cy: 24, r: 75, innerHex: "#F7E6B5", midHex: "#EFE0B8", outerHex: "#F5EEDC", alpha: 0.55)
        drawHalo(cx: 315, cy: 13, r: 95, innerHex: "#8EB4D9", midHex: "#C2D8EC", outerHex: "#D2E0EC", alpha: 0.50)
        drawHalo(cx: 545, cy: 18, r: 65, innerHex: "#C9D6DF", midHex: "#E2E8EC", outerHex: "#ECE5D5", alpha: 0.45)
        drawHalo(cx: 745, cy: 21, r: 70, innerHex: "#E5B8BF", midHex: "#F0D6DA", outerHex: "#ECE5D5", alpha: 0.48)
        drawHalo(cx: 920, cy: 5,  r: 65, innerHex: "#D4C29E", midHex: "#E4D7BC", outerHex: "#E2D8C0", alpha: 0.50)

        func fillShadedPoly(_ pts: [CGPoint], hexStart: String, hexEnd: String, alpha: CGFloat = 0.85, shadowOffset: CGSize? = nil, strokeHex: String? = nil, lw: CGFloat = 1.0) {
            guard let first = pts.first else { return }
            let path = CGMutablePath()
            path.move(to: first)
            for pt in pts.dropFirst() { path.addLine(to: pt) }
            path.closeSubpath()

            if let sOff = shadowOffset {
                ctx.saveGState()
                ctx.translateBy(x: sOff.width, y: sOff.height)
                ctx.addPath(path)
                ctx.setFillColor(c("#26211E", 0.22))
                ctx.fillPath()
                ctx.restoreGState()
            }

            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let box = path.boundingBox
            let cols = [c(hexStart, alpha), c(hexEnd, alpha * 0.82)] as CFArray
            if let g = CGGradient(colorsSpace: cs, colors: cols, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: box.minX, y: box.maxY), end: CGPoint(x: box.maxX, y: box.minY), options: [])
            }
            ctx.restoreGState()

            if let sHex = strokeHex {
                ctx.saveGState()
                ctx.addPath(path)
                ctx.setStrokeColor(c(sHex))
                ctx.setLineWidth(lw)
                ctx.strokePath()
                ctx.restoreGState()
            }
        }

        func drawShadedDisc(cx: CGFloat, cy: CGFloat, r: CGFloat, lightHex: String, darkHex: String, alpha: CGFloat = 1.0, strokeHex: String? = nil, lw: CGFloat = 1.0, hasShadow: Bool = false) {
            let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            if hasShadow {
                ctx.setFillColor(c("#1C1917", 0.24))
                ctx.fillEllipse(in: rect.offsetBy(dx: 1.5, dy: -1.3))
            }
            ctx.saveGState()
            ctx.addEllipse(in: rect)
            ctx.clip()
            let cols = [c(lightHex, alpha), c(darkHex, alpha)] as CFArray
            if let g = CGGradient(colorsSpace: cs, colors: cols, locations: [0.0, 1.0]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx - r * 0.3, y: cy + r * 0.3), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r * 1.15, options: [])
            }
            ctx.restoreGState()
            if let sHex = strokeHex {
                ctx.setStrokeColor(c(sHex))
                ctx.setLineWidth(lw)
                ctx.strokeEllipse(in: rect)
            }
        }

        func strokeLine(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, lw: CGFloat, hex: String = "#141318", alpha: CGFloat = 1.0, shadow: Bool = false) {
            ctx.saveGState()
            ctx.setLineCap(.round)
            if shadow {
                ctx.setStrokeColor(c("#26211E", 0.18))
                ctx.setLineWidth(lw + 2.4)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x1 + 1.1, y: y1 - 1.2))
                ctx.addLine(to: CGPoint(x: x2 + 1.1, y: y2 - 1.2))
                ctx.strokePath()
            }
            ctx.setStrokeColor(c(hex, alpha))
            ctx.setLineWidth(lw)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x1, y: y1))
            ctx.addLine(to: CGPoint(x: x2, y: y2))
            ctx.strokePath()
            ctx.restoreGState()
        }

        fillShadedPoly([CGPoint(x: 185 + d1, y: -2), CGPoint(x: 418 + d1, y: -2), CGPoint(x: 290 - d2, y: 27.8)],
                       hexStart: "#4F7CAC", hexEnd: "#C5D9EB", alpha: 0.68, shadowOffset: CGSize(width: -2.2, height: -1.5))
        fillShadedPoly([CGPoint(x: 382, y: 29.5), CGPoint(x: 418, y: 12.0), CGPoint(x: 438, y: 29.5)],
                       hexStart: "#D8E0E8", hexEnd: "#FAF6EB", alpha: 0.55, strokeHex: "#141318", lw: 1.4)
        fillShadedPoly([CGPoint(x: 432, y: 1.0), CGPoint(x: 568, y: 1.0), CGPoint(x: 500 + d1 * 0.4, y: 29.5)],
                       hexStart: "#FAF6EB", hexEnd: "#BAC4CE", alpha: 0.86, shadowOffset: CGSize(width: 2.4, height: -1.5), strokeHex: "#141318", lw: 1.6)
        fillShadedPoly([CGPoint(x: 488, y: 12.5), CGPoint(x: 534, y: 21.0), CGPoint(x: 552, y: 18.0), CGPoint(x: 505, y: 11.0)],
                       hexStart: "#5C5852", hexEnd: "#C5CED6", alpha: 0.45)
        strokeLine(x1: 488, y1: 12.5, x2: 534, y2: 21.0, lw: 2.2)
        strokeLine(x1: 534, y1: 21.0, x2: 575, y2: 14.5, lw: 1.8)
        fillShadedPoly([CGPoint(x: 635, y: 16.0), CGPoint(x: 685, y: 24.5), CGPoint(x: 715, y: 19.0)],
                       hexStart: "#E295A2", hexEnd: "#F2C6CE", alpha: 0.65)
        fillShadedPoly([CGPoint(x: 510, y: 8.0), CGPoint(x: 688, y: 8.0), CGPoint(x: 632 + d2, y: 21.8)],
                       hexStart: "#965425", hexEnd: "#E3A857", alpha: 0.86, shadowOffset: CGSize(width: 1.6, height: -1.5))
        fillShadedPoly([CGPoint(x: 588, y: 8.0), CGPoint(x: 678, y: 8.0), CGPoint(x: 636 - d1 * 0.4, y: 22.8)],
                       hexStart: "#13362F", hexEnd: "#3E7C70", alpha: 0.88, shadowOffset: CGSize(width: 1.5, height: -1.2))
        fillShadedPoly([CGPoint(x: 588, y: 8.0), CGPoint(x: 665, y: 8.0), CGPoint(x: 634, y: 19.5)],
                       hexStart: "#1A2926", hexEnd: "#384B45", alpha: 0.60)
        fillShadedPoly([CGPoint(x: 534 + d2, y: 22.8), CGPoint(x: 562 + d2, y: 22.8), CGPoint(x: 548 + d2, y: 28.6)],
                       hexStart: "#FCE258", hexEnd: "#D4931E", alpha: 0.94, shadowOffset: CGSize(width: 1.0, height: -0.8))
        fillShadedPoly([CGPoint(x: 760, y: 3.5), CGPoint(x: 824, y: 1.0), CGPoint(x: 796 + d1 * 0.5, y: 13.2)],
                       hexStart: "#F5CA48", hexEnd: "#C47822", alpha: 0.88, shadowOffset: CGSize(width: 1.5, height: -1.0))

        let tcX: CGFloat = 68.0 + d1 * 0.5, tcY: CGFloat = 18.2 + d2 * 0.25
        drawHalo(cx: tcX, cy: tcY, r: 22.0 + breathe, innerHex: "#C93838", midHex: "#E88D84", outerHex: "#F5EEDC", alpha: 0.82)
        drawHalo(cx: tcX + 24.0, cy: tcY - 8.2, r: 12.5 + breathe * 0.6, innerHex: "#F5C438", midHex: "#F7DC6F", outerHex: "#F5EEDC", alpha: 0.85)
        drawShadedDisc(cx: tcX, cy: tcY, r: 12.8, lightHex: "#F7E8C8", darkHex: "#E5BA98", alpha: 0.65)
        drawShadedDisc(cx: tcX, cy: tcY, r: 12.0, lightHex: "#24222B", darkHex: "#09080C", hasShadow: true)
        drawShadedDisc(cx: tcX, cy: tcY, r: 6.7 + breathe * 0.2, lightHex: "#A366B8", darkHex: "#452054", strokeHex: "#C93B6B", lw: 1.6)
        drawHalo(cx: tcX - 1.5, cy: tcY + 1.2, r: 4.2, innerHex: "#B57EDC", midHex: "#7A4988", outerHex: "#452054", alpha: 0.65)
        drawShadedDisc(cx: tcX + 23.5, cy: tcY - 8.0, r: 5.7, lightHex: "#F5543E", darkHex: "#9E1912", hasShadow: true)

        drawHalo(cx: 34.0 - d2 * 0.4, cy: 5.8, r: 9.8 + breathe * 0.5, innerHex: "#467BB0", midHex: "#8AB4DA", outerHex: "#F5EEDC", alpha: 0.78)
        drawShadedDisc(cx: 34.0 - d2 * 0.4, cy: 5.8, r: 5.0, lightHex: "#FAF6EB", darkHex: "#D8E2EC", alpha: 0.75)
        drawShadedDisc(cx: 34.0 - d2 * 0.4, cy: 5.8, r: 4.0, lightHex: "#FCE45C", darkHex: "#D6A118", strokeHex: "#141318", lw: 1.2)

        drawHalo(cx: 335.0 + d1 * 0.4, cy: 4.8, r: 8.2 + breathe * 0.4, innerHex: "#E8A817", midHex: "#F5D76E", outerHex: "#D2E0EC", alpha: 0.85)
        drawShadedDisc(cx: 335.0 + d1 * 0.4, cy: 4.8, r: 3.6, lightHex: "#2E8ECE", darkHex: "#0D4578")
        strokeLine(x1: 255, y1: 0.8, x2: 368, y2: 9.8, lw: 1.1)
        strokeLine(x1: 295, y1: 9.5, x2: 352, y2: 0.8, lw: 1.1)

        strokeLine(x1: 96, y1: 13.5, x2: 105, y2: 11.2, lw: 2.5)
        for offset: CGFloat in [0.0, 2.3] {
            ctx.saveGState()
            ctx.setStrokeColor(c(offset == 0 ? "#141318" : "#3A3842", offset == 0 ? 1.0 : 0.65))
            ctx.setLineWidth(offset == 0 ? 2.4 : 1.1)
            let wPath = CGMutablePath()
            wPath.move(to: CGPoint(x: 105, y: 11.2 + offset))
            for i in 1...44 {
                let t = CGFloat(i) / 44.0
                let wx = 105.0 + t * 148.0
                let wy = 11.2 + offset + t * 8.2 + sin(t * 14.5 - p * 1.35) * 3.0
                wPath.addLine(to: CGPoint(x: wx, y: wy))
            }
            ctx.addPath(wPath)
            ctx.strokePath()
            ctx.restoreGState()
        }

        strokeLine(x1: 245, y1: 17.5, x2: 245, y2: 29.0, lw: 1.2)
        strokeLine(x1: 236, y1: 25.2, x2: 254, y2: 25.2, lw: 1.1)
        strokeLine(x1: 218, y1: 27.8, x2: 272, y2: 20.2, lw: 1.2, hex: "#8C6D32")
        ctx.saveGState()
        ctx.setStrokeColor(c("#141318"))
        ctx.setLineWidth(2.6)
        ctx.addArc(center: CGPoint(x: 242, y: 23.5), radius: 9.0, startAngle: -.pi * 0.66, endAngle: -.pi * 0.14, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()

        strokeLine(x1: 142, y1: 11.0, x2: 244, y2: 1.8, lw: 3.0, shadow: true)
        drawShadedDisc(cx: 252, cy: 14.2, r: 2.3, lightHex: "#8D99AE", darkHex: "#2B2D42", strokeHex: "#141318", lw: 1.1)

        let cPairs: [(String, String)] = [
            ("#D9824E", "#A85628"), ("#FAF6EB", "#D8D0C0"), ("#7A8C5B", "#4F5E38"), ("#232129", "#0B0A0E"),
            ("#7396B5", "#486885"), ("#EDBE45", "#B8891E"), ("#FAF6EB", "#D8D0C0"), ("#232129", "#0B0A0E")
        ]
        for rIdx in 0..<4 {
            for cIdx in 0..<12 {
                if cIdx >= 7 && rIdx >= 2 { continue }
                let u0 = CGFloat(cIdx) / 12.0, u1 = CGFloat(cIdx + 1) / 12.0
                let v0 = CGFloat(rIdx) * 1.55, v1 = CGFloat(rIdx + 1) * 1.55
                let bx0 = 205.0 + u0 * 188.0 + d1 * 0.25, by0 = 2.8 + u0 * 22.8
                let bx1 = 205.0 + u1 * 188.0 + d1 * 0.25, by1 = 2.8 + u1 * 22.8
                let nx: CGFloat = -1.05, ny: CGFloat = 1.35
                let pts = [
                    CGPoint(x: bx0 + v0 * nx, y: by0 + v0 * ny),
                    CGPoint(x: bx1 + v0 * nx, y: by1 + v0 * ny),
                    CGPoint(x: bx1 + v1 * nx, y: by1 + v1 * ny),
                    CGPoint(x: bx0 + v1 * nx, y: by0 + v1 * ny)
                ]
                let pair = (cIdx >= 7) ? ((cIdx + rIdx) % 2 == 0 ? ("#141318", "#09080C") : ("#FAF6EB", "#DFD8C8"))
                                       : cPairs[(cIdx + rIdx * 3) % cPairs.count]
                fillShadedPoly(pts, hexStart: pair.0, hexEnd: pair.1, alpha: 0.95, strokeHex: "#141318", lw: 0.9)
            }
        }

        drawShadedDisc(cx: 438, cy: 20.5 + d2 * 0.3, r: 4.4, lightHex: "#FFFFFF", darkHex: "#DFD8C8", strokeHex: "#141318", lw: 1.2, hasShadow: true)
        drawShadedDisc(cx: 438, cy: 20.5 + d2 * 0.3, r: 2.7, lightHex: "#FAF6EB", darkHex: "#E5DEC9", strokeHex: "#B8292F", lw: 1.6)
        drawShadedDisc(cx: 444, cy: 25.5, r: 1.6, lightHex: "#E65C55", darkHex: "#9E2A25", strokeHex: "#141318", lw: 0.8)
        drawShadedDisc(cx: 472, cy: 27.2, r: 2.0, lightHex: "#B0A2D6", darkHex: "#6E5E9E")
        drawShadedDisc(cx: 562, cy: 24.5, r: 2.3, lightHex: "#3B73B8", darkHex: "#183B6B", strokeHex: "#9BC1E0", lw: 1.1)

        strokeLine(x1: 582, y1: 20.2, x2: 582, y2: 29.6, lw: 1.2)
        for cyCross: CGFloat in [21.8, 26.5, 28.6] { strokeLine(x1: 577, y1: cyCross, x2: 587, y2: cyCross, lw: 1.1) }

        strokeLine(x1: 308, y1: 8.0, x2: 752, y2: 8.0, lw: 1.5)
        let arcs: [(CGFloat, String)] = [(392, "#2A7B72"), (432, "#D94336"), (472, "#E5A93B"), (512, "#2B5B9E")]
        for (ax, aHex) in arcs {
            let rArc = 7.2 + sin(p * 1.1 + ax * 0.05) * 0.75
            ctx.saveGState()
            ctx.addArc(center: CGPoint(x: ax, y: 8.0), radius: rArc, startAngle: 0, endAngle: .pi, clockwise: false)
            ctx.setFillColor(c("#FAF6EB", 0.50))
            ctx.fillPath()
            ctx.addArc(center: CGPoint(x: ax, y: 8.0), radius: rArc, startAngle: 0, endAngle: .pi, clockwise: false)
            ctx.setStrokeColor(c(aHex))
            ctx.setLineWidth(1.8)
            ctx.strokePath()
            ctx.restoreGState()
        }

        for sIdx in 0..<4 {
            let sx: CGFloat = 556.0 + CGFloat(sIdx) * 11.0
            let sy: CGFloat = 16.5 + CGFloat(sIdx) * 1.4
            ctx.saveGState()
            ctx.setStrokeColor(c("#C8322B", 0.90))
            ctx.setLineWidth(1.5)
            ctx.addArc(center: CGPoint(x: sx, y: sy), radius: 4.2, startAngle: .pi * 0.15, endAngle: .pi * 0.95, clockwise: false)
            ctx.strokePath()
            ctx.restoreGState()
        }

        let clkX: CGFloat = 604.0 + d1 * 0.3, clkY: CGFloat = 14.8
        strokeLine(x1: clkX - 16, y1: clkY + 2.8, x2: clkX - 4, y2: clkY + 0.8, lw: 2.4, hex: "#C8322B")
        drawHalo(cx: 623, cy: 15.0, r: 6.5, innerHex: "#F2C84B", midHex: "#F7DC6F", outerHex: "#FAF6EB", alpha: 0.88)
        drawShadedDisc(cx: 620, cy: 14.8, r: 3.4, lightHex: "#FAF6EB", darkHex: "#E5DEC9", strokeHex: "#E6AF2E", lw: 1.4)
        drawShadedDisc(cx: clkX, cy: clkY, r: 4.3, lightHex: "#1D5AA6", darkHex: "#141318", strokeHex: "#141318", lw: 1.4, hasShadow: true)
        drawShadedDisc(cx: clkX, cy: clkY, r: 2.8, lightHex: "#FFFFFF", darkHex: "#E8E0CE", strokeHex: "#D93829", lw: 1.2)
        let handAng = p * 0.6
        strokeLine(x1: clkX, y1: clkY, x2: clkX + cos(handAng) * 2.3, y2: clkY + sin(handAng) * 2.3, lw: 1.2)

        strokeLine(x1: 672, y1: 18.2, x2: 968, y2: 29.6, lw: 1.8, shadow: true)
        strokeLine(x1: 682, y1: 15.2, x2: 978, y2: 26.6, lw: 1.6)
        strokeLine(x1: 690, y1: 12.8, x2: 885, y2: 20.5, lw: 1.3)
        fillShadedPoly([CGPoint(x: 712, y: 16.5), CGPoint(x: 805, y: 20.2), CGPoint(x: 800, y: 22.8), CGPoint(x: 707, y: 19.1)],
                       hexStart: "#FAF6EB", hexEnd: "#DFD8C8", alpha: 0.90, strokeHex: "#141318", lw: 1.1)
        fillShadedPoly([CGPoint(x: 718, y: 14.2), CGPoint(x: 785, y: 16.8), CGPoint(x: 782, y: 19.0), CGPoint(x: 715, y: 16.4)],
                       hexStart: "#E68444", hexEnd: "#B85620", alpha: 0.88)
        for tie in 0..<8 {
            let tx = 720.0 + CGFloat(tie) * 28.0
            let ty = 16.8 + CGFloat(tie) * 1.08
            strokeLine(x1: tx, y1: ty, x2: tx - 3.5, y2: ty + 3.2, lw: 1.2)
        }
        for rC in 0..<3 {
            for cC in 0..<4 {
                let cx0 = 664.0 + CGFloat(cC) * 6.5 - CGFloat(rC) * 2.5
                let cy0 = 12.5 + CGFloat(cC) * 1.2 + CGFloat(rC) * 2.2
                let pts = [
                    CGPoint(x: cx0, y: cy0), CGPoint(x: cx0 + 6.5, y: cy0 + 1.2),
                    CGPoint(x: cx0 + 4.0, y: cy0 + 3.4), CGPoint(x: cx0 - 2.5, y: cy0 + 2.2)
                ]
                let isBlk = (rC + cC) % 2 == 0
                fillShadedPoly(pts, hexStart: isBlk ? "#1E1C24" : "#FAF6EB", hexEnd: isBlk ? "#09080C" : "#D8D0C0", alpha: 0.95, strokeHex: "#141318", lw: 0.9)
            }
        }

        drawShadedDisc(cx: 718 - d2 * 0.4, cy: 23.2, r: 5.2, lightHex: "#A8B4C4", darkHex: "#5E6B48", alpha: 0.76, strokeHex: "#E6AF2E", lw: 1.6, hasShadow: true)
        drawShadedDisc(cx: 825, cy: 24.2 + d1 * 0.2, r: 3.6, lightHex: "#64B5F6", darkHex: "#1E6091", alpha: 0.82, strokeHex: "#141318", lw: 1.2)
        drawShadedDisc(cx: 822, cy: 18.5 - d1 * 0.2, r: 3.3, lightHex: "#F2A6B0", darkHex: "#A85A68", alpha: 0.80, strokeHex: "#4A3B54", lw: 1.1)
        drawShadedDisc(cx: 882, cy: 21.8, r: 3.1, lightHex: "#FFFFFF", darkHex: "#E2DCD0", strokeHex: "#141318", lw: 1.1)

        drawHalo(cx: 748 + d1 * 0.5, cy: 14.2, r: 8.5, innerHex: "#1E6091", midHex: "#7FAAC9", outerHex: "#ECE5D5", alpha: 0.48)
        drawShadedDisc(cx: 748 + d1 * 0.5, cy: 14.2, r: 5.5, lightHex: "#2E86DE", darkHex: "#0A284E", hasShadow: true)
        strokeLine(x1: 500 - d1, y1: 5.8, x2: 870 + d1, y2: 22.6, lw: 2.4, hex: "#141318", shadow: true)
        strokeLine(x1: 516 - d1, y1: 6.2, x2: 830 + d1, y2: 20.3, lw: 1.6, hex: "#C82829")

        drawShadedDisc(cx: 695, cy: 5.2, r: 4.0, lightHex: "#A37ACC", darkHex: "#5B387D", alpha: 0.88, hasShadow: true)
        strokeLine(x1: 670, y1: 5.2, x2: 724, y2: 5.2, lw: 1.1)
        strokeLine(x1: 695, y1: 0.8, x2: 695, y2: 9.8, lw: 1.1)

        drawShadedDisc(cx: 805 + d2 * 0.3, cy: 3.8, r: 4.9, lightHex: "#9EA4AB", darkHex: "#5A6066", alpha: 0.85, hasShadow: true)
        fillShadedPoly([CGPoint(x: 862, y: 1.4), CGPoint(x: 870, y: 1.4), CGPoint(x: 870, y: 5.8), CGPoint(x: 862, y: 5.8)],
                       hexStart: "#E03C31", hexEnd: "#991B14", alpha: 0.95, shadowOffset: CGSize(width: 1.0, height: -0.8))

        fillShadedPoly([CGPoint(x: 885, y: 14), CGPoint(x: 902, y: 14), CGPoint(x: 902, y: 17), CGPoint(x: 885, y: 17)], hexStart: "#E64833", hexEnd: "#A82417", alpha: 0.88)
        fillShadedPoly([CGPoint(x: 868, y: 11), CGPoint(x: 885, y: 11), CGPoint(x: 885, y: 14), CGPoint(x: 868, y: 14)], hexStart: "#B8D4E8", hexEnd: "#7FAAC9", alpha: 0.82)
        for gx: CGFloat in [868.0, 885.0, 902.0] { strokeLine(x1: gx, y1: 9.5, x2: gx, y2: 20.5, lw: 1.1) }
        for gy: CGFloat in [11.0, 14.0, 17.0] { strokeLine(x1: 855, y1: gy, x2: 922, y2: gy, lw: 1.1) }

        drawHalo(cx: 958, cy: 15.5, r: 9.5 + breathe * 0.5, innerHex: "#E6AF2E", midHex: "#F5D76E", outerHex: "#E2D8C0", alpha: 0.65)
        drawShadedDisc(cx: 958 - d1 * 0.3, cy: 15.5, r: 4.6, lightHex: "#3B6998", darkHex: "#162B47", alpha: 0.90, strokeHex: "#141318", lw: 1.4, hasShadow: true)
        drawShadedDisc(cx: 966, cy: 11.2, r: 2.3, lightHex: "#F2523D", darkHex: "#A81E17")
        strokeLine(x1: 915, y1: 24.5, x2: 992, y2: 4.5, lw: 1.8, shadow: true)
        strokeLine(x1: 935, y1: 3.0, x2: 988, y2: 26.0, lw: 1.2)

        let reach = sin(p * 0.5) * 16.0
        strokeLine(x1: 265, y1: 9.5, x2: 535 + reach, y2: 14.2, lw: 2.2, shadow: true)
        strokeLine(x1: 605, y1: 20.5, x2: 815 - reach * 0.5, y2: 1.5, lw: 2.0, shadow: true)
        strokeLine(x1: 715, y1: 15.0, x2: 885 + reach * 0.4, y2: 8.5, lw: 2.2, shadow: true)
    }

    // =========================================================================
    // ĐIỀU PHỐI 16 TÁC PHẨM 8-BIT / TẢ THỰC TOÀN CẢNH
    // =========================================================================
    private func pixelColor(for theme: SoundTheme, col: Int, row: Int) -> CGColor {
        switch theme {
        case .babble:        return sample8BitKandinsky(col: col, row: row)
        case .balancedNoise: return drawBalancedNoisePriorArt(col: col, row: row)
        case .brightNoise:   return drawBrightNoisePriorArt(col: col, row: row)
        case .darkNoise:     return drawDarkNoisePriorArt(col: col, row: row)
        case .quietNight:    return drawVanGoghWithRareFrog(col: col, row: row)
        case .fire:          return drawFireWithAshBulges(col: col, row: row)
        case .stream:        return drawRealisticStream(col: col, row: row)
        case .airplane:      return drawAirplaneInSkyClouds(col: col, row: row)
        case .boat:          return drawGracefulBoatPanorama(col: col, row: row)
        case .bus:           return drawGreyDeconstructivistLondonBus(col: col, row: row)
        case .train:         return drawRestored3DTrainMoodyColors(col: col, row: row)
        case .rain:          return drawDiverseRain(col: col, row: row)
        case .rainOnRoof:    return drawFarRightCornerGuyRainOnRoof(col: col, row: row)
        case .ocean:         return drawCleanOceanWithOneCrab(col: col, row: row)
        case .steam:         return drawZoomedRedLipsSmoothTurnAndWarmSteam(col: col, row: row)
        case .night:         return drawNightMultiDirectionMeteors(col: col, row: row)
        }
    }

    // 1-3. BỘ BA BALANCED - BRIGHT - DARK NOISE
    private func drawBalancedNoisePriorArt(col: Int, row: Int) -> CGColor {
        let dCol = Double(col), dRow = Double(row)
        let centerAxis = 5.5
        let env = 0.78 + 0.22 * sin(dCol * 0.008)
        let phaseArg = dCol * 0.026 - phase * 0.95
        let waveA = centerAxis + sin(phaseArg) * 4.1 * env + cos(phaseArg * 2.0) * 0.35
        let waveB = centerAxis - sin(phaseArg + 1.15) * 4.1 * env - cos(phaseArg * 2.0 + 1.15) * 0.35
        let distA = abs(dRow - waveA), distB = abs(dRow - waveB)

        if distA < 0.75 && distB < 0.75 { return c("#FFF9D2") }
        if distA < 1.25 && distB < 1.25 { return c("#F1FAEE") }
        if distA < 0.48 { return c("#72EFDD") }
        if distA < 0.92 { return c("#48CAE4") }
        if distA < 1.42 { return c("#0096C7") }
        if distA < 1.95 { return c("#1D4E6B") }

        if distB < 0.48 { return c("#D8F3DC") }
        if distB < 0.92 { return c("#95D5B2") }
        if distB < 1.42 { return c("#52B788") }
        if distB < 1.95 { return c("#2D6A4F") }

        let minW = min(waveA, waveB), maxW = max(waveA, waveB)
        if col % 6 == 0 && dRow > minW && dRow < maxW {
            return (abs(cos(phaseArg)) > 0.65) ? c("#2B455C") : c("#1B2A3B")
        }
        if (row == 5 || row == 6) && col % 4 == 0 { return c("#1F2B3D") }
        return (row <= 1 || row >= 10) ? c("#0B0F19") : c("#111724")
    }

    private func drawBrightNoisePriorArt(col: Int, row: Int) -> CGColor {
        let dCol = Double(col), dRow = Double(row)
        let yTop = 9.2 + sin(dCol * 0.085 - phase * 1.25) * 1.05 + cos(dCol * 0.025 + phase * 0.6) * 0.55
        let yMid = 5.5 + sin(dCol * 0.045 + phase * 0.95) * 1.65 + sin(dCol * 0.13 - phase * 1.5) * 0.35
        let yBot = 1.8 + cos(dCol * 0.105 - phase * 1.35) * 1.05 + sin(dCol * 0.035 + phase * 0.7) * 0.45

        if col % 16 == 0 && (abs(dRow - yTop) < 0.9 || abs(dRow - yMid) < 0.9 || abs(dRow - yBot) < 0.9) {
            return c("#FFFFFF")
        }
        let dTop = abs(dRow - yTop)
        if dTop < 0.48 { return c("#1B9AAA") }
        if dTop < 0.95 { return c("#48CAE4") }
        if dTop < 1.45 { return c("#BCE4EE") }

        let dMid = abs(dRow - yMid)
        if dMid < 0.48 { return c("#1D4E89") }
        if dMid < 0.95 { return c("#457B9D") }
        if dMid < 1.45 { return c("#B5D1E2") }

        let dBot = abs(dRow - yBot)
        if dBot < 0.48 { return c("#D9822B") }
        if dBot < 0.95 { return c("#E9C46A") }
        if dBot < 1.45 { return c("#F2DFB6") }

        if col % 8 == 0 && dRow > yBot && dRow < yTop {
            return (col % 16 == 0) ? c("#B8CEDB") : c("#D0DFE8")
        }
        if row >= 9 { return (col + row) % 2 == 0 ? c("#F2F6F7") : c("#EBF1F3") }
        if row >= 4 { return (col + row) % 2 == 0 ? c("#E8EFF2") : c("#E1EAEF") }
        return (col + row) % 2 == 0 ? c("#DEE7EC") : c("#D6E1E8")
    }

    private func drawDarkNoisePriorArt(col: Int, row: Int) -> CGColor {
        let dCol = Double(col), dRow = Double(row)
        func brownianWave(_ baseFreq: Double, _ spd: Double, _ seed: Double) -> Double {
            let f1 = sin(dCol * baseFreq - phase * spd + seed)
            let f2 = 0.5 * sin(dCol * baseFreq * 2.1 - phase * spd * 1.3 + seed * 1.7)
            let f3 = 0.25 * cos(dCol * baseFreq * 4.3 + phase * spd * 0.8 + seed * 2.3)
            return (f1 + f2 + f3) / 1.75
        }
        let crest1 = 1.8 + brownianWave(0.022, 0.75, 0.0) * 1.35
        let crest2 = 4.2 + brownianWave(0.016, 0.55, 2.1) * 1.55
        let crest3 = 6.8 + brownianWave(0.012, 0.40, 4.3) * 1.55
        let crest4 = 9.2 + brownianWave(0.008, 0.28, 1.2) * 1.35
        let grain = (col / 3 + row) % 3 == 0

        if dRow <= crest1 {
            let depth = crest1 - dRow
            if depth < 0.55 { return c("#E07A3C") }
            if depth < 1.10 { return c("#9C4A22") }
            return grain ? c("#2B140A") : c("#1F0E07")
        }
        if dRow <= crest2 {
            let depth = crest2 - dRow
            if depth < 0.55 { return c("#8C4A27") }
            if depth < 1.15 { return c("#4F2916") }
            return grain ? c("#331B11") : c("#26130C")
        }
        if dRow <= crest3 {
            let depth = crest3 - dRow
            if depth < 0.55 { return c("#5C3D5E") }
            if depth < 1.15 { return c("#38243B") }
            return grain ? c("#261829") : c("#1B111E")
        }
        if dRow <= crest4 {
            let depth = crest4 - dRow
            if depth < 0.55 { return c("#2E4057") }
            if depth < 1.15 { return c("#1D2A3A") }
            return grain ? c("#141E2B") : c("#0F1621")
        }
        return c("#07080C")
    }

    // 4. QUIET NIGHT — STARRY NIGHT + KHUÔN MẶT CHÚ ẾCH 8-BIT DỄ THƯƠNG (HIẾM GẶP)
    private func drawVanGoghWithRareFrog(col: Int, row: Int) -> CGColor {
        let x = col % 502
        let dx = Double(x), dy = Double(row)

        let frogCycle = (phase * 0.45).truncatingRemainder(dividingBy: 52.0)
        if frogCycle < 3.6 {
            let slideProgress = sin((frogCycle / 3.6) * .pi)
            let yOffset = (1.0 - min(1.0, slideProgress * 1.45)) * 14.0
            let fy = dy + yOffset
            let fx = dx - 251.0
            let isBlinking = (frogCycle > 1.65 && frogCycle < 2.05)

            for eyeSign in [-1.0, 1.0] {
                let ex = fx - eyeSign * 52.0, ey = fy - 10.5
                let eyeOuterDist = hypot(ex / 28.0, ey / 4.2)
                let eyeInnerDist = hypot(ex / 21.0, ey / 3.2)
                if eyeOuterDist < 1.0 {
                    if eyeInnerDist < 1.0 {
                        if isBlinking { return c("#52B788") }
                        let pupilDist = hypot((ex + eyeSign * 3.0) / 11.0, ey / 2.2)
                        if pupilDist < 1.0 {
                            if ex > -eyeSign * 3.0 && ex < -eyeSign * 3.0 + 5.0 && ey > 0.4 && ey < 1.5 { return c("#FFFFFF") }
                            return c("#0B0F19")
                        }
                        return c("#FFFFFF")
                    }
                    return (eyeOuterDist > 0.85) ? c("#1B4332") : c("#52B788")
                }
            }

            let faceDist = hypot(fx / 116.0, (fy - 3.5) / 7.2)
            if faceDist < 1.0 && fy <= 10.5 {
                if hypot((abs(fx) - 82.0) / 16.0, (fy - 4.5) / 2.0) < 1.0 {
                    return ((x + row) % 2 == 0) ? c("#FF758F") : c("#FFB3C1")
                }
                if abs(fy - 7.5) < 0.65 && (abs(fx + 7.0) < 1.8 || abs(fx - 7.0) < 1.8) { return c("#1B4332") }
                let smileY = 3.2 + pow(fx / 62.0, 2.0) * 2.2
                if abs(fx) <= 62.0 && abs(fy - smileY) < 0.75 { return c("#141E19") }
                if abs(fx) <= 12.0 && fy >= 1.8 && fy < smileY { return c("#FF758F") }
                if fy < 2.2 && abs(fx) < 75.0 { return c("#D8F3DC") }
                if faceDist > 0.90 { return c("#1B4332") }
                return (fy > 6.5) ? c("#74C69D") : (((x + row) % 7 == 0) ? c("#40916C") : c("#52B788"))
            }
        }

        let sway = sin(phase * 0.35 + dy * 0.3) * 0.9
        let mainCurve = 95.0 - sin(dy * 0.32) * 3.5 + sway
        let mainHalfW = max(0.9, (14.2 - dy) * 0.82)
        let leftShoot = (dy <= 9.0) && abs(dx - (mainCurve - 8.5 + (9.0 - dy) * 0.35)) < (9.5 - dy) * 0.42
        let rightShoot = (dy <= 5.5) && abs(dx - (mainCurve + 9.5 - (5.5 - dy) * 0.3)) < (6.0 - dy) * 0.38
        if (dy <= 13.5 && abs(dx - mainCurve) < mainHalfW) || leftShoot || rightShoot {
            let stroke = sin(dy * 1.1 + dx * 0.6)
            if stroke > 0.50 { return c("#3E3524") }
            if stroke > -0.15 { return c("#283627") }
            return c("#141E19")
        }

        if x >= 355 {
            let hillH = (dx - 355.0) * 0.024 + sin(dx * 0.08) * 0.65
            if dy <= hillH { return (dy > hillH - 0.8) ? c("#111A31") : c("#1F243A") }
        }

        let mDx = (dx - 448.0) * 0.48, mDy = dy - 10.5
        let moonDist = hypot(mDx, mDy)
        let cutDist = hypot(mDx - 1.15, mDy - 0.45)
        let moonPulse = sin(phase * 0.45) * 0.35
        if moonDist < 2.65 { return (cutDist < 1.95) ? c("#E6E8A3") : c("#D6B129") }
        if moonDist < 5.6 + moonPulse {
            let ring = Int(round(moonDist * 1.6 - phase * 0.4)) % 3
            return (ring == 0) ? c("#E2C844") : ((ring == 1) ? c("#E6E8A3") : c("#B3BD9D"))
        }
        if moonDist < 7.2 + moonPulse && (x + row) % 2 == 0 { return c("#7B96A5") }

        let stars: [(sx: Double, sy: Double, sr: Double, isVenus: Bool)] = [
            (22.0,  4.2, 2.1, false), (62.0,  3.6, 2.5, false), (50.0, 13.5, 3.2, false),
            (114.0,13.8, 1.9, false), (118.0,10.5, 3.0, false), (162.0, 7.2, 2.0, false),
            (168.0, 3.2, 4.2, true),  (168.0,13.6, 2.4, false), (206.0,13.0, 2.1, false),
            (305.0,12.6, 3.3, false), (352.0, 9.4, 2.7, false)
        ]
        for st in stars {
            let sd = hypot((dx - st.sx) * 0.52, dy - st.sy)
            let sp = sin(phase * 0.5 + st.sx * 0.1) * 0.35
            if sd < 0.95 { return st.isVenus ? c("#EEF0C8") : c("#E2C844") }
            if sd < st.sr + sp {
                let rRing = Int(round(sd * 1.8 - phase * 0.3)) % 2
                if st.isVenus { return (rRing == 0) ? c("#EEF0C8") : c("#B3BD9D") }
                return (rRing == 0) ? c("#D8D878") : c("#7B96A5")
            }
        }

        let horizonBandY = (dx - 210.0) * 0.024 + sin(dx * 0.05) * 0.6
        if dx >= 200.0 && abs(dy - horizonBandY) < 1.8 {
            return (abs(dy - horizonBandY) < 0.8) ? c("#B3BD9D") : c("#7B96A5")
        }

        let archStreamY = 8.5 + sin((dx - 110.0) * 0.018) * 3.8
        if dx >= 110.0 && dx <= 340.0 && abs(dy - archStreamY) < 2.2 {
            return (sin(dx * 0.12 + dy * 0.8 - phase * 0.4) > 0.2) ? c("#7B96A5") : c("#597AA8")
        }

        let brush = sin(dx * 0.07 + dy * 0.7 - phase * 0.35) + cos(dx * 0.15 - dy * 0.5) * 0.5
        if brush > 0.75 { return c("#597AA8") }
        if brush > 0.25 { return c("#47628D") }
        if brush > -0.25 { return c("#364D80") }
        if brush > -0.70 { return c("#213569") }
        return c("#111A31")
    }

    // 5. FIRE — GIỮ NGUYÊN 100%
    private func drawFireWithAshBulges(col: Int, row: Int) -> CGColor {
        let dCol = Double(col), dRow = Double(row)
        let rawWave = sin(dCol * 0.08) + cos(dCol * 0.05 + 1.3)
        let ashBulge = (rawWave - 0.15) * 1.95 + sin(dCol * 0.25) * 0.35
        if ashBulge > 0.0 && dRow <= ashBulge {
            let h = hash2D(col / 2, row) % 100
            let fineH = hash2D(col, row) % 100
            if dRow > ashBulge - 0.85 {
                if h < 30 { return c("#E9ECEF") }
                if h < 60 { return c("#ADB5BD") }
                if h < 84 { return c("#6C757D") }
                return c("#343A40")
            }
            let emberBreath = sin(phase * 1.3 + Double(h) * 0.1)
            if fineH < 14 && emberBreath > 0.15 {
                return (emberBreath > 0.6) ? c("#FF7900") : c("#9B0000")
            }
            if h < 22 { return c("#CED4DA") }
            if h < 52 { return c("#495057") }
            if h < 82 { return c("#212529") }
            return c("#121417")
        }

        if row >= 11 {
            let sparkX = col + Int(round(sin(dRow + phase * 1.5) * 1.5))
            let sparkY = Int(dRow - phase * 2.2)
            if abs((sparkX * 37 &+ sparkY * 53) % 47) == 0 { return (row >= 13) ? c("#E5383B") : c("#FFBE0B") }
        }

        let env = (rawWave + sin(dCol * 0.022) * 0.5 + 1.8) * 0.42
        let flicker = sin(dRow * 0.55 - phase * 2.2 + dCol * 0.22) * 1.4 + cos(dCol * 0.35 + phase * 1.6) * 0.9
        let distFromTop = (env * 11.5 + flicker) - dRow

        if distFromTop < 0 { return (row <= 4) ? c("#140606") : c("#0D0303") }
        if distFromTop < 1.5 { return c("#9B0000") }
        if distFromTop < 3.0 { return c("#E5383B") }
        if distFromTop < 4.8 { return c("#FF5400") }
        if distFromTop < 6.8 { return c("#FF9E00") }
        if distFromTop < 8.8 { return c("#FFBE0B") }
        return c("#FFF3B0")
    }

    // 6. STREAM — GIỮ NGUYÊN 100%
    private func drawRealisticStream(col: Int, row: Int) -> CGColor {
        let x = col % 670
        let dx = Double(x), dy = Double(row)

        let leftBank = 34.0 - dy * 0.9 + sin(dy * 0.5) * 3.5
        if dx < leftBank {
            let h = hash2D(x, row) % 4
            if dx > leftBank - 2.5 { return c("#74C69D") }
            return (h == 0) ? c("#52B788") : ((h == 1) ? c("#2D6A4F") : c("#1B4332"))
        }
        for reedBase in [296.0, 302.0, 632.0, 640.0, 648.0] {
            let bend = sin(phase * 0.9 + reedBase) * (dy * 0.12)
            if dy <= 14.0 && abs(dx - (reedBase + bend)) < 0.75 {
                return (dy > 11.5) ? c("#D4A373") : c("#40916C")
            }
        }
        let logY = 14.2 - (dx - 22.0) * 0.05
        if x >= 22 && x <= 72 && abs(dy - logY) < 1.7 {
            if dy > logY + 0.4 { return c("#52B788") }
            return (dy > logY - 0.5) ? c("#7F4F24") : c("#4A2C11")
        }

        let boulders: [(cx: Double, cy: Double, rx: Double, ry: Double)] = [
            (115.0, 5.5, 13.5, 4.2), (232.0, 14.0, 11.0, 3.6), (312.0, 4.5, 9.0, 3.2),
            (415.0, 11.5, 15.0, 4.5), (532.0, 5.0, 12.0, 3.8), (608.0, 14.0, 10.0, 3.4)
        ]
        for (bcx, bcy, brx, bry) in boulders {
            let bDist = hypot((dx - bcx) / brx, (dy - bcy) / bry)
            if bDist < 1.0 {
                let mossLine = bcy + bry * 0.18 + sin(dx * 0.45) * 0.7
                if dy > mossLine {
                    return (dy > mossLine + 1.2) ? c("#74C69D") : ((x + row) % 2 == 0 ? c("#40916C") : c("#2D6A4F"))
                }
                if dy < bcy - bry * 0.45 { return c("#343A40") }
                if dx < bcx - brx * 0.25 && dy > bcy { return c("#ADB5BD") }
                if dx > bcx + brx * 0.30 { return c("#495057") }
                return c("#6C757D")
            }
            if dx > bcx - brx * 0.5 && dx < bcx + brx * 1.65 && abs(abs(dy - bcy) - bry * 0.85) < 0.75 {
                if sin(dx * 0.35 - phase * 3.2 + dy) > 0.15 { return c("#F4FAFD") }
            }
        }

        let pads: [(lx: Double, ly: Double, lr: Double, hasLotus: Bool, hasFrog: Bool)] = [
            (164.0, 14.5, 7.2, false, true), (182.0, 10.8, 6.2, true, false),
            (356.0, 15.2, 6.8, true, false), (468.0, 5.5, 6.5, false, false), (485.0, 8.8, 5.8, true, false)
        ]
        for pad in pads {
            let sx = pad.lx + sin(phase * 0.75 + pad.lx) * 1.1
            if pad.hasLotus && abs(pad.lx - 356.0) < 2.0 {
                let dfX = sx + sin(phase * 1.8) * 1.5, dfY = pad.ly + 3.2 + cos(phase * 2.2) * 0.6
                if abs(dy - dfY) < 0.6 && dx >= dfX - 1.5 && dx <= dfX + 2.5 { return c("#00F5D4") }
                if abs(dx - dfX) < 1.2 && abs(dy - (dfY + 0.8)) < 0.6 { return c("#E0FBFC") }
            }
            if pad.hasLotus {
                let fDist = hypot((dx - sx) / 3.8, (dy - (pad.ly + 0.8)) / 2.3)
                if fDist < 0.42 { return c("#FFB703") }
                if fDist < 0.75 { return c("#FFF0F3") }
                if fDist < 1.05 { return c("#FF758F") }
            }
            if pad.hasFrog && abs(dx - sx) <= 1.8 && abs(dy - (pad.ly + 0.7)) <= 1.1 {
                if dy > pad.ly + 0.9 && abs(abs(dx - sx) - 1.0) < 0.7 { return c("#FFF3B0") }
                return c("#52B788")
            }
            let lDist = hypot((dx - sx) / pad.lr, (dy - pad.ly) / (pad.lr * 0.46))
            let isNotch = (dx > sx + 1.0) && abs(dy - pad.ly - (dx - sx) * 0.15) < 0.75
            if lDist < 1.0 && !isNotch {
                if lDist > 0.82 { return c("#1B4332") }
                return (Int(atan2(dy - pad.ly, dx - sx) * 5.0) % 2 == 0) ? c("#40916C") : c("#2D6A4F")
            }
        }

        for leafSeed in [88.0, 265.0, 510.0] {
            let lx = (leafSeed + phase * 3.5).truncatingRemainder(dividingBy: 650.0)
            let ly = 8.0 + sin(lx * 0.05 + leafSeed) * 4.5
            if hypot(dx - lx, dy - ly) < 1.35 { return c("#E63946") }
        }

        let koiList: [(bx: Double, by: Double, spd: Double, style: Int)] = [
            (72.0, 6.5, 1.1, 0), (198.0, 4.8, -0.9, 1), (275.0, 10.5, 1.3, 2),
            (376.0, 7.2, -1.0, 0), (448.0, 14.8, 0.95, 1), (566.0, 11.2, -1.2, 0), (620.0, 5.8, 0.85, 2)
        ]
        for koi in koiList {
            let kx = koi.bx + sin(phase * 0.6 * koi.spd + koi.by) * 18.0
            let ky = koi.by + cos(phase * 0.75 + koi.bx * 0.05) * 1.4
            let dir = (koi.spd >= 0) ? 1.0 : -1.0
            let u = (dx - kx) * dir
            if u >= -6.0 && u <= 7.5 {
                let sCurve = sin(phase * 4.0 - u * 0.42 + koi.bx) * (u > 0 ? (0.35 + u * 0.14) : 0.2)
                let v = dy - (ky + sCurve)
                let halfW: Double = (u < -2.0) ? sqrt(max(0.0, 1.0 - pow((u + 2.0) / 4.0, 2.0))) * 1.75
                                  : ((u < 3.5) ? (1.75 - (u + 2.0) * 0.24) : (0.45 + (u - 3.5) * 0.38))
                if u >= -2.8 && u <= -0.2 && abs(v) >= halfW && abs(v) <= halfW + 1.35 - abs(u + 1.5) * 0.4 {
                    return (koi.style == 1) ? c("#FFF3B0") : c("#E3E8EF")
                }
                if abs(v) <= halfW {
                    if u > 4.2 {
                        if abs(v) < (u - 4.2) * 0.22 { return ColorCache.shared.streamWater[4] }
                        return (koi.style == 1) ? c("#FFE66D") : c("#F4FAFD")
                    }
                    if abs(u + 4.2) < 0.65 && abs(abs(v) - 0.85) < 0.55 { return c("#141824") }
                    let isDorsal = abs(v) < 0.65
                    if koi.style == 0 {
                        if u < -1.8 || (u > 0.6 && u < 2.8) { return isDorsal ? c("#D62828") : c("#FF5400") }
                        return isDorsal ? c("#FFFFFF") : c("#E3E8EF")
                    } else if koi.style == 1 {
                        return isDorsal ? c("#FFB703") : c("#FFE66D")
                    } else {
                        if abs(u - 0.2) < 1.4 { return c("#1B1D22") }
                        return (u < -1.2) ? c("#FF5400") : c("#F4FAFD")
                    }
                }
            }
        }

        if (dx < 95.0 || dx > 585.0 || row <= 2 || row >= 17) && hash2D(x / 2, row / 2) % 11 == 0 {
            return (hash2D(x, row) % 2 == 0) ? c("#5C8D89") : c("#8AB6C1")
        }

        let p = ColorCache.shared.streamWater
        let c1 = sin(dx * 0.045 - phase * 1.4 + dy * 0.35) * 2.3
        let c2 = cos(dx * 0.11 - phase * 2.0 - dy * 0.28) * 1.4
        let rip = sin(dx * 0.24 - phase * 2.6 + dy * 1.1) * 0.7
        let idx = Int(abs(round(dy * 0.55 + c1 + c2 + rip + phase * 0.4))) % p.count
        return p[idx]
    }

    // 7. AIRPLANE — GIỮ NGUYÊN 100%
    private func drawAirplaneInSkyClouds(col: Int, row: Int) -> CGColor {
        let x = col % 670
        let dx = Double(x), dy = Double(row)
        let pScroll = Int(round(phase * 3.8))

        let jx = ((x - pScroll - 90) % 670 + 670) % 670
        let jy = 11.5 + sin(phase * 0.7) * 1.2
        if jx >= 8 && jx <= 95 {
            let u = Double(jx - 50), v = dy - jy
            if v >= 1.8 && v <= 7.2 {
                let h = v - 1.8
                let finLeadingEdge = 11.5 - h * 1.05
                let finTrailingEdge = 3.2 - h * 0.72
                if u >= finTrailingEdge && u <= finLeadingEdge {
                    if v > 5.8 { return c("#E63946") }
                    return (u > finLeadingEdge - 1.8) ? c("#FFFFFF") : c("#1D3557")
                }
            }
            if u >= 1.0 && u <= 6.5 && v >= 0.8 && v <= 1.6 { return c("#94A3B8") }
            if v >= -3.8 && v <= -1.0 && u >= 15.0 && u <= 28.0 {
                if v <= -1.8 && u >= 20.0 && u <= 27.0 {
                    return (u > 25.5) ? c("#1D2D44") : ((v > -2.7) ? c("#FFFFFF") : c("#8D99AE"))
                }
                let wingU = 19.0 - (v + 1.0) * 2.0
                if abs(u - wingU) < 3.2 { return c("#CED4DA") }
            }
            if u >= 0.0 && u <= 39.0 {
                let topProfile: Double = (u < 2.0) ? (1.2 + u * 0.4) : ((u > 31.0) ? sqrt(max(0.0, 1.0 - pow((u - 31.0) / 8.0, 2.0))) * 2.0 : 2.0)
                let botProfile: Double = (u < 9.0) ? (1.0 - u * 0.29) : ((u > 32.0) ? -sqrt(max(0.0, 1.0 - pow((u - 32.0) / 7.0, 2.0))) * 1.6 : -1.6)
                if v >= botProfile && v <= topProfile {
                    if u >= 32.5 && u <= 36.0 && v >= 0.3 && v <= 1.4 { return c("#1D3557") }
                    if u >= 11.0 && u <= 30.0 && v >= 0.3 && v <= 1.0 && Int(u) % 2 == 0 { return c("#90E0EF") }
                    if abs(v + 0.1) < 0.42 && u >= 5.0 { return c("#E63946") }
                    if v > 0.0 { return c("#FFFFFF") }
                    return (v > -0.8) ? c("#E2E8F0") : c("#94A3B8")
                }
            }
            if u < -2.0 && u >= -38.0 {
                let spread = 0.55 + (18.0 - u) * 0.04
                let trailWave = sin(u * 0.2 + phase * 2.0) * 0.35
                let distT = abs((v + 2.0) - trailWave)
                if distT < spread {
                    if u > -14.0 && distT < spread * 0.6 { return c("#FFFFFF") }
                    if u > -26.0 { return c("#E0F7FA") }
                    if (jx + row) % 2 == 0 { return c("#ADE8F4") }
                }
            }
        }

        let bx = ((x - pScroll - 380) % 670 + 670) % 670
        let by = 12.5 + cos(phase * 0.8 + 1.5) * 1.3
        if bx >= 15 && bx <= 72 {
            let u = Double(bx - 42), v = dy - by
            if v >= 2.2 && v <= 3.1 && u >= 9.0 && u <= 21.0 { return (v > 2.6) ? c("#FFFFFF") : c("#DCEFF7") }
            if v >= 0.5 && v <= 2.2 && (abs(u - 11.5) < 0.6 || abs(u - 18.5) < 0.6) { return c("#4A4E69") }
            if v >= 0.5 && v <= 3.8 {
                let tailL = 0.5 - (v - 0.5) * 0.35, tailR = 5.5 - (v - 0.5) * 0.85
                if u >= tailL && u <= tailR { return (u < tailL + 1.5) ? c("#FFFFFF") : c("#D62828") }
            }
            if v >= 1.2 && v <= 2.1 && u >= 12.0 && u <= 14.2 { return c("#1D3557") }
            if v >= 1.1 && v <= 1.8 && u >= 8.5 && u < 12.0 { return c("#FFFFFF") }
            if u >= 1.0 && u <= 24.5 {
                let topH: Double = 1.2, botH: Double = (u < 7.0) ? (0.4 - u * 0.25) : -1.4
                if v >= botH && v <= topH {
                    if u >= 21.5 { return (v > 0) ? c("#E5E5E5") : c("#8D99AE") }
                    if abs(v - 0.2) < 0.45 { return c("#FFFFFF") }
                    return (v > 0) ? c("#E63946") : c("#9B2226")
                }
            }
            if v >= -2.5 && v <= -1.2 && u >= 11.0 && u <= 19.5 { return c("#DCEFF7") }
            if u >= 24.8 && u <= 26.2 && abs(v) <= 2.8 {
                if abs(v) < 0.7 { return c("#FFB703") }
                if (row + Int(phase * 15)) % 2 == 0 { return c("#FFFFFF") }
            }
        }

        let midScroll = dx + phase * 8.0
        let midClouds: [(cx: Double, cy: Double, rx: Double, ry: Double)] = [
            (75.0, 9.5, 28.0, 3.2), (215.0, 13.5, 34.0, 3.5), (355.0, 8.5, 30.0, 3.2),
            (495.0, 14.0, 36.0, 3.6), (615.0, 10.0, 26.0, 3.0)
        ]
        for mc in midClouds {
            let mX = (midScroll - mc.cx).truncatingRemainder(dividingBy: 670.0)
            let wrappedX = (mX < -335.0) ? (mX + 670.0) : ((mX > 335.0) ? (mX - 670.0) : mX)
            let puffBump = sin(wrappedX * 0.22) * 1.1 + cos(wrappedX * 0.11) * 0.8
            let cDist = hypot(wrappedX / mc.rx, (dy - (mc.cy + (dy > mc.cy ? puffBump : 0.0))) / mc.ry)
            if cDist < 1.0 {
                if dy > mc.cy + 0.6 { return c("#FFFFFF") }
                if dy > mc.cy - 0.8 { return c("#F0F9FF") }
                return c("#CAE9F7")
            }
        }

        let lowScroll = dx + phase * 4.5
        let seaTop = 4.2 + sin(lowScroll * 0.038) * 1.6 + cos(lowScroll * 0.085) * 1.1 + sin(lowScroll * 0.18) * 0.5
        if dy <= seaTop {
            if dy > seaTop - 1.3 { return c("#FFFFFF") }
            if dy > seaTop - 2.6 { return c("#EBF8FF") }
            if dy > 1.2 { return c("#D0ECF9") }
            return c("#B6E0F4")
        }

        let cirrus = sin(dx * 0.045 - dy * 0.8 + phase * 0.5) + cos(dx * 0.11 + dy * 0.5) * 0.5
        if row >= 16 && cirrus > 0.85 { return c("#E0F7FA") }

        if row <= 6  { return c("#CAF0F8") }
        if row <= 9  { return c("#90E0EF") }
        if row <= 12 { return c("#48CAE4") }
        if row <= 15 { return c("#00B4D8") }
        if row <= 17 { return c("#0096C7") }
        return c("#0077B6")
    }

    // 8. BOAT — GIỮ NGUYÊN 100%
    private func drawGracefulBoatPanorama(col: Int, row: Int) -> CGColor {
        let x = col % 670
        let dx = Double(x), dy = Double(row)
        let uTrans = smoothstep(45.0, 510.0, dx)

        let cliffH = 7.8 - max(0.0, (dx - 24.0) * 0.16) + sin(dx * 0.35) * 0.6
        if x <= 64 && dy <= cliffH {
            if row == 6 && x >= 48 && (x + Int(phase * 4)) % 3 == 0 { return c("#E0FBFC") }
            if dy > cliffH - 1.2 { return c("#1B3B2B") }
            return (dx < 32.0) ? c("#0D1117") : c("#1B222D")
        }
        let lhCenter = 35.0
        let towerHalfW = 4.6 - (dy - 7.0) * 0.18
        if row >= 7 && row <= 19 && abs(dx - lhCenter) <= towerHalfW + 1.2 {
            let relX = dx - lhCenter
            if row == 19 && abs(relX) <= 1.8 { return c("#9B2226") }
            if row == 18 && abs(relX) <= 3.2 { return (relX > 0) ? c("#E63946") : c("#780000") }
            if (row == 16 || row == 17) && abs(relX) <= 2.8 {
                if abs(relX) > 2.0 { return c("#1B1D24") }
                return (abs(relX) < 1.4) ? c("#FFFFFF") : c("#FFF9D2")
            }
            if row == 15 && abs(relX) <= towerHalfW + 1.0 { return c("#0F1116") }
            if row <= 14 && abs(relX) <= towerHalfW {
                if abs(relX) < 0.7 && (row == 9 || row == 12) { return c("#FFF3B0") }
                let isRedBand = ((row - 7) / 3) % 2 == 1
                if isRedBand {
                    return (relX > 0.5) ? c("#D62828") : ((relX > -1.8) ? c("#9B2226") : c("#590D11"))
                } else {
                    return (relX > 0.5) ? c("#F8F9FA") : ((relX > -1.8) ? c("#ADB5BD") : c("#495057"))
                }
            }
        }

        if x >= 68 {
            let seaX = x - 68
            let scroll = Int(round(phase * 2.5))
            let bob = Int(round(sin(phase * 0.8 + dx * 0.02) * 0.45))
            let r = row - bob

            let b1 = ((seaX - scroll - 30) % 600 + 600) % 600
            if b1 >= 0 && b1 <= 34 {
                if (b1 <= 3 && r >= 7 && r <= 11 - b1) || (b1 >= 31 && r >= 7 && r <= 10 - (34 - b1)) {
                    return (r >= 9) ? c("#2A9D8F") : c("#D4A373")
                }
                if r >= 8 && r <= 15 && b1 == 17 { return c("#5C3A21") }
                if (r == 8 || r == 15) && b1 >= 10 && b1 <= 24 { return c("#6C462B") }
                if r >= 9 && r <= 14 && b1 >= 11 && b1 <= 23 {
                    if b1 == 11 || b1 == 23 || r == 12 { return c("#FFD166") }
                    return (b1 > 17) ? c("#FFF3B0") : c("#E09F3E")
                }
                if (r == 5 || r == 6) && b1 >= 3 && b1 <= 31 { return (r == 6) ? c("#D4A373") : c("#8D5524") }
                if r == 4 && b1 >= 8 && b1 <= 26 && b1 % 3 == 0 { return c("#FAF0CA") }
            }

            let b2 = ((seaX - scroll - 180) % 600 + 600) % 600
            if b2 >= 0 && b2 <= 38 {
                if r == 8 && b2 >= 32 && b2 <= 38 { return c("#5C3A21") }
                if (r == 7 || r == 8) && b2 >= 2 && b2 <= 10 { return (r == 8) ? c("#E9C46A") : c("#7F4F24") }
                if (r == 5 || r == 6) && b2 >= 3 && b2 <= 33 {
                    return (r == 6 && b2 % 4 == 0) ? c("#FFB703") : ((r == 6) ? c("#7F4F24") : c("#4A2C11"))
                }
                for (mX, topR) in [(10, 16), (19, 18), (28, 16)] {
                    if b2 == mX && r >= 7 && r <= topR { return c("#4A2C11") }
                    if r == topR && (b2 == mX - 1 || b2 == mX) { return c("#E63946") }
                    if (r >= 8 && r <= 11) || (r >= 12 && r <= topR - 1) {
                        let curve = Int(round(sin(Double(r) * 0.6) * 1.1))
                        if b2 >= mX - 3 + curve && b2 <= mX + 3 + curve {
                            return (b2 > mX) ? c("#FFF3B0") : c("#F4D5B8")
                        }
                    }
                }
            }

            let b3 = ((seaX - scroll - 330) % 600 + 600) % 600
            if b3 >= 0 && b3 <= 36 {
                if r >= 13 && r <= 16 && b3 >= 6 && b3 <= 22 && (b3 + r + Int(phase * 3)) % 2 == 0 { return c("#E2E8F0") }
                if r >= 10 && r <= 12 && ((b3 >= 14 && b3 <= 16) || (b3 >= 20 && b3 <= 22)) {
                    return (r == 12) ? c("#1B1D24") : c("#E63946")
                }
                if r >= 7 && r <= 9 && b3 >= 6 && b3 <= 29 {
                    if r == 8 && b3 % 3 == 0 { return c("#FFF3B0") }
                    return (r == 9 && b3 >= 23) ? c("#7F4F24") : c("#F8F9FA")
                }
                if (r == 5 || r == 6) && b3 >= 2 && b3 <= 34 {
                    if r == 6 && b3 % 4 == 0 && b3 >= 6 && b3 <= 28 { return c("#FFD166") }
                    return (r == 6) ? c("#1B1D24") : c("#9B2226")
                }
            }

            let b4 = ((seaX - scroll - 480) % 600 + 600) % 600
            if b4 >= 0 && b4 <= 36 {
                if r >= 10 && r <= 12 && b4 >= 12 - (r - 10) && b4 <= 21 - (r - 10) * 2 {
                    return (r == 12) ? c("#FFFFFF") : c("#1D3557")
                }
                if r >= 7 && r <= 9 && b4 >= 5 && b4 <= 29 - (r - 7) * 2 {
                    if r == 8 && b4 >= 8 && b4 <= 24 { return c("#0F172A") }
                    return c("#FFFFFF")
                }
                if (r == 5 || r == 6) && b4 >= 2 && b4 <= 32 + (r - 5) * 2 {
                    return (r == 6) ? c("#FFFFFF") : c("#48CAE4")
                }
            }
        }

        if row <= 6 {
            let sunReflectW = 22.0 + (6.0 - dy) * 5.5 + sin(dy * 1.9 - phase * 3.0) * 5.0
            let distSunX = abs(dx - 565.0)
            if distSunX <= sunReflectW {
                let waveBar = sin(dy * 2.1 - phase * 2.8 + dx * 0.14)
                if waveBar > -0.15 {
                    if distSunX < sunReflectW * 0.35 { return c("#FFFFFF") }
                    if distSunX < sunReflectW * 0.68 { return c("#FFF3B0") }
                    return c("#FFB703")
                }
            }
            if dx >= 68.0 && dx <= 175.0 && row >= 4 && sin(dx * 0.2 - phase * 2.5 + dy) > 0.58 {
                return lerp("#48CAE4", "#FFE66D", 1.0 - (dx - 68.0) / 107.0)
            }
            let waveCrest = sin(dx * 0.08 - phase * 1.4 + sin(dy * 1.3) * 1.8) + cos(dx * 0.19 + phase * 0.9 + dy * 2.1) * 0.6
            if waveCrest > 1.05 { return lerp("#48CAE4", "#FFD166", uTrans) }
            if waveCrest > 0.55 { return lerp("#12354A", "#2A7B88", uTrans) }
            if row >= 5 { return lerp("#0B2233", "#1B566B", uTrans) }
            if row >= 3 { return lerp("#071724", "#123F52", uTrans) }
            return lerp("#040D16", "#0A2836", uTrans)
        }

        let sunDist = hypot((dx - 565.0) * 0.45, dy - 10.5)
        let sunPulse = sin(phase * 0.55) * 0.65
        if sunDist < 9.2 + sunPulse {
            if sunDist < 3.8 { return c("#FFFFFF") }
            if sunDist < 6.2 { return c("#FFF9D2") }
            if sunDist < 7.8 { return c("#FFE66D") }
            return c("#FFB703")
        }

        let islandH = 6.4 + sin(dx * 0.022) * 2.2 + cos(dx * 0.055) * 1.0
        if dx >= 140.0 && dx <= 460.0 && dy <= islandH {
            return lerp("#111827", "#283044", uTrans)
        }

        let nightHex: String, midHex: String, sunsetHex: String
        switch row {
        case 7, 8:   nightHex = "#162238"; midHex = "#8C3B4A"; sunsetHex = "#FFB703"
        case 9, 10:  nightHex = "#121C30"; midHex = "#723656"; sunsetHex = "#F4A261"
        case 11, 12: nightHex = "#0E1627"; midHex = "#56325C"; sunsetHex = "#E76F51"
        case 13, 14: nightHex = "#0B1120"; midHex = "#3D2E57"; sunsetHex = "#B54868"
        case 15, 16: nightHex = "#080D19"; midHex = "#28264B"; sunsetHex = "#5C6B9C"
        default:     nightHex = "#050912"; midHex = "#181C38"; sunsetHex = "#223A66"
        }

        var baseSkyHex = nightHex, targetSkyHex = midHex, localT = uTrans * 2.0
        if uTrans > 0.5 {
            baseSkyHex = midHex; targetSkyHex = sunsetHex; localT = (uTrans - 0.5) * 2.0
        }

        if sunDist < 26.0 + sunPulse {
            let sunGlowFactor = smoothstep(26.0 + sunPulse, 9.2 + sunPulse, sunDist)
            if sunGlowFactor > 0.55 { return lerp(targetSkyHex, "#FF9E00", (sunGlowFactor - 0.55) * 2.2) }
            if sunGlowFactor > 0.15 { return lerp(targetSkyHex, "#F77F00", sunGlowFactor) }
        }

        if dx >= 38.0 && dx <= 265.0 && row >= 9 && row <= 19 {
            let beamDist = dx - 38.0
            let sweepY = 16.5 - beamDist * 0.012 + sin(phase * 0.65) * (beamDist * 0.008)
            let halfSpan = 1.4 + beamDist * 0.032
            let dBeam = abs(dy - sweepY)
            if dBeam <= halfSpan {
                let radialFade = 1.0 - (dBeam / halfSpan)
                let distFade = smoothstep(265.0, 38.0, dx)
                let intensity = pow(radialFade, 1.35) * distFade
                if intensity > 0.72 { return lerp("#FFE66D", "#FFFFFF", (intensity - 0.72) * 3.5) }
                if intensity > 0.05 { return lerp(nightHex, "#FFE66D", intensity * 1.25) }
            }
        }

        if dx < 195.0 && row >= 13 && hash2D(x, row) % 78 == 0 {
            return lerp("#E0FBFC", nightHex, smoothstep(90.0, 195.0, dx))
        }
        return lerp(baseSkyHex, targetSkyHex, localT)
    }

    // 9. BUS — GIỮ NGUYÊN 100%
    private func drawGreyDeconstructivistLondonBus(col: Int, row: Int) -> CGColor {
        let x = col % 670
        let dx = Double(x), dy = Double(row)
        let scroll = Int(round(phase * 3.8))

        let bx = ((x - scroll - 120) % 670 + 670) % 670
        if bx >= 0 && bx <= 48 && row >= 2 && row <= 16 {
            if bx <= 5 && row >= 3 && row <= 8 {
                if bx == 3 { return c("#CED4DA") }
                if row == 3 { return c("#343A40") }
                return c("#1F242D")
            }
            if bx >= 43 && row >= 8 {
                if bx < 46 {
                    if row >= 10 && row <= 13 { return c("#DEE2E6") }
                    return c("#D62828")
                }
            } else {
                if row <= 5 && ((bx >= 9 && bx <= 14) || (bx >= 35 && bx <= 40)) {
                    let wheelCenter = (bx < 20) ? 11.5 : 37.5
                    let wDist = hypot(Double(bx) - wheelCenter, dy - 3.2)
                    if wDist < 1.2 { return c("#E9ECEF") }
                    if wDist < 2.6 { return c("#111318") }
                }
                if row >= 3 {
                    if bx >= 46 && row >= 4 && row <= 6 {
                        return (row == 5 && bx == 48) ? c("#FFFFFF") : c("#CED4DA")
                    }
                    if bx >= 41 && bx <= 45 && row >= 6 && row <= 8 { return c("#2B2D42") }
                    if row == 9 && bx >= 6 && bx <= 42 {
                        return (bx >= 12 && bx <= 36) ? c("#F8F9FA") : c("#E63946")
                    }
                    let isWin1 = (row >= 5 && row <= 8 && bx >= 7 && bx <= 39)
                    let isWin2 = (row >= 11 && row <= 14 && bx >= 3 && bx <= 42)
                    if isWin1 || isWin2 {
                        if bx % 6 == 0 { return c("#C1121F") }
                        if (row == 5 || row == 11) && bx % 6 == 3 { return c("#212529") }
                        if (row == 6 || row == 12) && bx % 6 == 3 { return c("#ADB5BD") }
                        return (row == 8 || row == 14) ? c("#F8F9FA") : c("#CED4DA")
                    }
                    if !(row == 16 && (bx < 3 || bx > 41)) {
                        if bx >= 42 && (row == 14 || row == 15) { return (row == 14) ? c("#F8F9FA") : c("#111318") }
                        return (row >= 14) ? c("#EF233C") : ((row <= 4) ? c("#9B2226") : c("#D90429"))
                    }
                }
            }
        }

        if row == 0 { return c("#212529") }
        if row == 1 { return (x % 22 < 10) ? c("#E9ECEF") : c("#343A40") }
        if row == 2 { return c("#8D99AE") }

        if x >= 25 && x <= 130 && row >= 3 {
            let jaggedRoof = 10 + ((x * 7) % 5) - ((x / 11) % 3)
            if row <= jaggedRoof {
                if row == jaggedRoof { return c("#343A40") }
                if (x + row * 2) % 7 == 0 && row >= 5 { return c("#DEE2E6") }
                return (x % 4 == 0) ? c("#6C757D") : ((row % 2 == 0) ? c("#8D99AE") : c("#ADB5BD"))
            }
        }
        if x >= 132 && x <= 152 && row >= 3 {
            let relB = x - 142
            if row >= 17 && abs(relB) <= (19 - row) * 2 + 1 { return c("#2B2D42") }
            if row >= 12 && row <= 16 && abs(relB) <= 7 {
                let clkDist = hypot(Double(relB), dy - 14.0)
                if clkDist < 1.1 { return c("#212529") }
                if clkDist < 3.2 { return c("#F8F9FA") }
                if clkDist < 4.2 { return c("#6C757D") }
                return c("#ADB5BD")
            }
            if row <= 11 && abs(relB) <= 6 { return (x % 3 == 0) ? c("#6C757D") : c("#CED4DA") }
        }

        if x >= 168 && x <= 196 && row >= 3 {
            let leftEdge = 168.0 + (dy - 3.0) * 0.85
            let rightEdge = 196.0 - (dy - 3.0) * 0.55
            if dx >= leftEdge && dx <= rightEdge {
                if abs(dx - leftEdge) < 1.2 { return c("#F8F9FA") }
                return ((x + row * 3) % 5 == 0) ? c("#DEE2E6") : ((x < 182) ? c("#ADB5BD") : c("#6C757D"))
            }
        }
        if x >= 202 && x <= 262 && row >= 3 {
            let inUpperBlock = (row >= 9 && row <= 15 && x >= 202 && x <= 262)
            let inLowerPillars = (row <= 8 && (x >= 212 && x <= 224 || x >= 242 && x <= 254))
            if inUpperBlock || inLowerPillars {
                if row == 9 || row == 15 { return c("#343A40") }
                if (x - row * 2) % 9 == 0 { return c("#E9ECEF") }
                return ((x / 3 + row) % 2 == 0) ? c("#5C677D") : c("#495057")
            }
        }

        if x >= 272 && x <= 276 && row >= 3 && row <= 8 {
            return (row >= 5 && row <= 7 && x >= 273 && x <= 275 && x % 2 == 1) ? c("#E9ECEF") : c("#D90429")
        }
        if x >= 284 && x <= 402 && row >= 3 {
            let seg = (x - 284) / 24, lx = (x - 284) % 24
            let slope = (seg % 2 == 0) ? (lx / 3) : ((23 - lx) / 3)
            let maxH = 10 + (seg * 3) % 4 + slope
            if row <= maxH && lx < 22 {
                if row >= maxH - 1 { return c("#2B2D42") }
                if row >= 5 && row <= maxH - 2 && (lx + row * 2) % 7 < 3 && lx >= 3 && lx <= 18 { return c("#F8F9FA") }
                let greyTones = ["#CED4DA", "#ADB5BD", "#8D99AE", "#6C757D", "#495057"]
                return c(greyTones[(seg + lx / 8) % greyTones.count])
            }
        }

        if x >= 415 && x <= 535 {
            for tCenter in [449, 501] {
                if abs(x - tCenter) <= 7 && row >= 3 && row <= 17 {
                    if row >= 15 { return (abs(x - tCenter) >= 5 || abs(x - tCenter) <= 2) ? c("#2B2D42") : c("#ADB5BD") }
                    if (row == 8 || row == 12) && abs(x - tCenter) <= 3 { return c("#1F242D") }
                    return (x % 3 == 0) ? c("#6C757D") : c("#CED4DA")
                }
            }
            if x >= 456 && x <= 494 && (row == 13 || row == 14) { return (row == 14) ? c("#E9ECEF") : c("#5C677D") }
            if x < 442 && abs(dy - (4.0 + pow((dx - 415.0) / 27.0, 2.0) * 9.0)) < 1.1 { return c("#8D99AE") }
            if x > 508 && abs(dy - (4.0 + pow((535.0 - dx) / 27.0, 2.0) * 9.0)) < 1.1 { return c("#8D99AE") }
            if row == 4 { return c("#495057") }
        }

        if x >= 552 && x <= 592 && row >= 3 && row <= 17 {
            let expandW = 7.5 + (dy - 3.0) * 0.58
            if abs(dx - 572.0) <= expandW {
                if row >= 15 { return c("#F8F9FA") }
                return ((x + row) % 3 == 0) ? c("#ADB5BD") : c("#495057")
            }
        }
        if x >= 605 && x <= 645 && row >= 3 && row <= 18 {
            let gherkinW = sin((dy - 2.0) / 17.0 * .pi * 0.85) * 12.0
            if abs(dx - 625.0) <= gherkinW {
                return ((x + row) % 4 == 0) ? c("#F8F9FA") : ((x - row) % 4 == 0 ? c("#2B2D42") : c("#8D99AE"))
            }
        }

        let cloudWave = sin(dx * 0.035 - phase * 0.2) + cos(dx * 0.08 + dy * 0.3) * 0.5
        if row >= 14 && cloudWave > 0.72 { return c("#F8F9FA") }
        if row <= 6  { return c("#E9ECEF") }
        if row <= 10 { return c("#DEE2E6") }
        if row <= 14 { return c("#CED4DA") }
        if row <= 17 { return c("#ADB5BD") }
        return c("#8D99AE")
    }

    // 10. TRAIN — GIỮ NGUYÊN 100%
    private func drawRestored3DTrainMoodyColors(col: Int, row: Int) -> CGColor {
        let x = col % 670
        let dx = Double(x), dy = Double(row)

        func trackCurveY(_ atX: Double) -> Double {
            return 8.5 + 4.3 * cos((atX - 45.0) * 0.0145) + 0.8 * sin(atX * 0.03)
        }
        let tY = trackCurveY(dx)
        let zScale = 1.35 - (tY - 4.0) * 0.055

        let fgTrees: [(tx: Double, baseH: Double, topH: Double)] = [
            (102.0, 0.0, 12.5), (345.0, 0.0, 11.5), (358.0, 0.0, 13.5), (562.0, 0.0, 12.0), (575.0, 0.0, 14.0)
        ]
        for ft in fgTrees {
            if dy >= ft.baseH && dy <= ft.topH {
                let coneW = (ft.topH - dy) * 0.52 + (Int(dy) % 2 == 0 ? 0.6 : 0.0)
                if abs(dx - ft.tx) <= coneW {
                    if dy < ft.baseH + 2.0 && abs(dx - ft.tx) <= 1.0 { return c("#4A2C11") }
                    return (dx < ft.tx) ? c("#40916C") : c("#1B4332")
                }
            }
        }

        if (x >= 20 && x <= 54 && dy <= tY + 5.5) || (x >= 628 && x <= 665 && dy <= tY + 5.0) {
            let portalX = (x < 100) ? 54.0 : 628.0
            if abs(dx - portalX) <= 3.5 && dy >= tY - 0.5 && dy <= tY + 4.2 {
                return (abs(dx - portalX) >= 2.0 || dy >= tY + 3.2) ? c("#6C757D") : c("#081C15")
            }
        }

        let tScroll = (phase * 4.2).truncatingRemainder(dividingBy: 670.0)
        let trainHeadX = 55.0 + ((tScroll / 670.0) * 570.0)

        for carIdx in 0..<6 {
            let spacing = 26.0 * zScale
            let carCenterX = trainHeadX - Double(carIdx) * spacing
            if carCenterX > 50.0 && carCenterX < 630.0 {
                let halfLen = 11.5 * zScale
                let relX = dx - carCenterX
                if abs(relX) <= halfLen {
                    let localTrackY = trackCurveY(carCenterX + relX)
                    let carH = 5.8 * zScale
                    let roof3D = 1.6 * zScale
                    let relY = dy - localTrackY

                    if relY >= 0.0 && relY <= carH + roof3D {
                        let is3DFrontFace = relX > halfLen - 2.6 * zScale
                        if relY > carH {
                            if carIdx == 0 && abs(relX - halfLen * 0.4) < 1.8 * zScale { return c("#161920") }
                            return (carIdx == 0) ? c("#2B303A") : c("#7D8597")
                        }
                        if carIdx == 0 {
                            if relY < 1.4 * zScale {
                                return (is3DFrontFace) ? c("#4A4E69") : ((Int(dx) % 3 == 0) ? c("#8D99AE") : c("#161920"))
                            }
                            if is3DFrontFace {
                                return (relY > carH * 0.55) ? c("#D8F3DC") : c("#1F242D")
                            }
                            if relX < -halfLen * 0.35 && relY > carH * 0.45 { return c("#D8F3DC") }
                            return (relY > carH * 0.65) ? c("#2B303A") : c("#354F52")
                        }
                        if is3DFrontFace { return c("#1F242D") }
                        if relY < 1.2 * zScale { return c("#161920") }
                        if relY > carH * 0.42 && relY < carH * 0.85 {
                            let winSlot = Int(abs(relX + halfLen) / (3.2 * zScale))
                            if winSlot % 2 == 1 { return c("#D8F3DC") }
                            return c("#8D99AE")
                        }
                        return (carIdx % 2 == 1) ? c("#3B4D54") : c("#4A4E69")
                    }
                }
                if carIdx == 0 {
                    for pStep in 1...6 {
                        let px = carCenterX + 4.0 - Double(pStep) * 7.5
                        let py = trackCurveY(px) + 6.5 * zScale + Double(pStep) * 1.1 + sin(phase * 2.5 + Double(pStep)) * 0.7
                        if hypot((dx - px) * 0.65, dy - py) < 1.6 + Double(pStep) * 0.25 {
                            return (pStep <= 3) ? c("#FFFFFF") : c("#D8F3DC")
                        }
                    }
                }
            }
        }

        if dy <= tY && dy >= tY - 1.3 * zScale { return (x % 3 == 0) ? c("#7F5539") : c("#ADB5BD") }
        if x >= 130 && x <= 305 && dy < tY - 1.2 * zScale {
            let pierMod = (x - 130) % 22
            let archTop = tY - 2.2 - sqrt(max(0.0, 1.0 - pow(Double(pierMod - 11) / 8.5, 2.0))) * 4.5
            if pierMod < 4 || pierMod > 18 || dy >= archTop {
                return ((x + row) % 3 == 0) ? c("#6C757D") : c("#495057")
            }
        }

        if x >= 168 && x <= 184 && dy <= 13.5 {
            let fallCenter = 176.0 + sin(dy * 0.5 - phase * 3.0) * 1.5
            if abs(dx - fallCenter) < 3.2 + (13.5 - dy) * 0.18 {
                return ((x + row + Int(phase * 5.0)) % 2 == 0) ? c("#FFFFFF") : c("#90E0EF")
            }
        }
        if x >= 155 && x <= 265 && row <= 2 {
            return ((x + Int(phase * 3.0)) % 4 == 0) ? c("#A9D6E5") : c("#2A9D8F")
        }

        let fgHill = 3.2 + sin(dx * 0.025) * 1.8 + cos(dx * 0.06) * 0.9
        if dy <= fgHill {
            if hash2D(x, row) % 23 == 0 { return (x % 2 == 0) ? c("#FFE66D") : c("#FFFFFF") }
            return (dy > fgHill - 1.0) ? c("#95D5B2") : c("#52B788")
        }

        let midSlope = tY + 1.8 + sin(dx * 0.04) * 2.2 + cos(dx * 0.11) * 1.1
        if dy <= midSlope {
            let treeTex = sin(dx * 0.45) * cos(dy * 0.85)
            let sunSide = cos((dx - 45.0) * 0.0145) > 0
            if treeTex > 0.35 { return sunSide ? c("#74C69D") : c("#40916C") }
            if treeTex > -0.25 { return sunSide ? c("#52B788") : c("#2D6A4F") }
            return c("#1B4332")
        }

        let farMountain = 14.2 + sin(dx * 0.015 + 1.0) * 2.8 + cos(dx * 0.038) * 1.5
        if dy <= farMountain {
            if abs(dy - 12.0 - sin(dx * 0.03) * 1.0) < 0.85 && (x + row) % 2 == 0 { return c("#B7E4C7") }
            return (dy > farMountain - 1.2) ? c("#40916C") : ((dx * 0.03).truncatingRemainder(dividingBy: 2.0) < 1.0 ? c("#2D6A4F") : c("#1B4332"))
        }

        let distantPeak = 16.8 + cos(dx * 0.012) * 2.2 + sin(dx * 0.028) * 1.1
        if dy <= distantPeak { return c("#52796F") }
        return (row >= 18) ? c("#A8DADC") : c("#D8F3DC")
    }

    // 11. RAIN ĐA DẠNG
    private func drawDiverseRain(col: Int, row: Int) -> CGColor {
        let dCol = Double(col), dRow = Double(row)
        let windSlant = sin(phase * 0.18) * 1.35 + cos(phase * 0.08) * 0.55

        if row <= 1 {
            let splashSeed = hash2D(col / 8, Int(phase * 2.5)) % 11
            let localMod = col % 8
            let ringRadius = Int(phase * 5.0) % 4
            if splashSeed == 0 && abs(localMod - 4) == ringRadius {
                return (row == 1) ? c("#CAF0F8") : c("#48CAE4")
            }
            return (row == 0) ? c("#0E1A28") : c("#152536")
        }

        let sx = dCol - dRow * windSlant
        let lane = Int(floor(sx))
        let laneHash = hash2D(lane, 13)

        if laneHash % 6 == 0 {
            let spd1 = 3.2 + Double(laneHash % 5) * 0.25
            let offset1 = Double(laneHash % 29)
            let cycle1 = 18.0 + Double(laneHash % 7)
            let pos1 = (16.0 - dRow + phase * spd1 + offset1).truncatingRemainder(dividingBy: cycle1)
            if pos1 >= 0 && pos1 < 1.1 { return c("#E0FBFC") }
            if pos1 >= 1.1 && pos1 < 2.6 { return c("#90E0EF") }
            if pos1 >= 2.6 && pos1 < 3.8 { return c("#48CAE4") }
        }

        let lane2 = Int(floor(dCol - dRow * windSlant * 0.75))
        let hash2 = hash2D(lane2, 37)
        if hash2 % 4 == 0 {
            let spd2 = 2.2 + Double(hash2 % 4) * 0.2
            let pos2 = (16.0 - dRow + phase * spd2 + Double(hash2 % 23)).truncatingRemainder(dividingBy: 15.0)
            if pos2 >= 0 && pos2 < 1.8 { return c("#5C8AA6") }
        }

        let hash3 = hash2D(col, row + Int(phase * 4.0))
        if hash3 % 29 == 0 { return c("#29435C") }
        return (row >= 11) ? c("#0B131E") : ((row >= 6) ? c("#101C2B") : c("#152334"))
    }

    // 12. RAIN ON ROOF — GIỮ NGUYÊN BẢN GÓC XA NHẤT BÊN PHẢI
    private func drawFarRightCornerGuyRainOnRoof(col: Int, row: Int) -> CGColor {
        let x = col % 670
        let dx = Double(x), dy = Double(row)

        var roofTop = -1
        if x >= 85 && x <= 590 {
            let distFromPeak = abs(dx - 355.0)
            roofTop = 13 + Int(round(max(0.0, (275.0 - distFromPeak) / 275.0) * 5.0))
        }
        if x >= 350 && x <= 360 && row >= 14 && row <= 18 {
            return ((x + row) % 2 == 0) ? c("#343A40") : c("#212529")
        }

        if roofTop < 0 || row > roofTop {
            if (x == 84 || x == 591) && row <= 12 {
                let drip = (20.0 - dy + phase * 3.8 + dx).truncatingRemainder(dividingBy: 4.5)
                if drip < 1.6 { return c("#90E0EF") }
            }
            if roofTop > 0 && (row == roofTop + 1 || row == roofTop + 2) {
                let sh = hash2D(x / 2, Int(phase * 6.0)) % 9
                if sh == 0 && row == roofTop + 1 { return c("#FFFFFF") }
                if sh == 1 { return c("#90E0EF") }
            }
            if x < 84 || x > 591 {
                if row == 0 { return (x % 8 == 0) ? c("#1B263B") : c("#0F172A") }
                if row == 1 && hash2D(x / 4, Int(phase * 4.0)) % 7 == 0 { return c("#48CAE4") }
                for bambooX in [35.0, 42.0, 49.0, 625.0, 633.0] {
                    let swayB = sin(phase * 0.8 + bambooX) * (dy * 0.08)
                    if dy <= 14.0 && abs(dx - (bambooX + swayB)) < 0.65 {
                        return (row % 4 == 0) ? c("#1B4332") : c("#386641")
                    }
                }
            }
            let wind = sin(phase * 0.2) * 0.65 + 0.35
            let lane1 = Int(floor(dx - dy * wind))
            let h1 = hash2D(lane1, 19)
            if h1 % 6 == 0 {
                let pos1 = (21.0 - dy + phase * (3.4 + Double(h1 % 4) * 0.3) + Double(h1 % 23)).truncatingRemainder(dividingBy: 17.0)
                if pos1 >= 0 && pos1 < 1.2 { return c("#E0FBFC") }
                if pos1 >= 1.2 && pos1 < 2.8 { return c("#61A5C2") }
            }
            let lane2 = Int(floor(dx - dy * wind * 0.7))
            let h2 = hash2D(lane2, 43)
            if h2 % 4 == 0 {
                let pos2 = (21.0 - dy + phase * 2.3 + Double(h2 % 19)).truncatingRemainder(dividingBy: 14.0)
                if pos2 >= 0 && pos2 < 1.8 { return c("#3A5A78") }
            }
            return (row >= 15) ? c("#08101A") : c("#0E1B2B")
        }

        if row >= roofTop - 1 {
            if row == roofTop && (x == 85 || x == 590) { return c("#94A3B8") }
            return (x % 4 == 0) ? c("#1E293B") : ((row == roofTop) ? c("#475569") : c("#334155"))
        }
        if row == roofTop - 2 { return (x % 12 == 0) ? c("#0F172A") : c("#1E293B") }
        if row == 0 { return c("#1E242B") }
        if row == 1 { return (x % 8 == 0) ? c("#334155") : c("#475569") }

        if x >= 85 && x <= 245 {
            if (x >= 92 && x <= 94) || (x >= 243 && x <= 245) { return c("#1E293B") }

            if row == 3 && x >= 146 && x <= 182 { return c("#94A3B8") }
            if row == 2 && (x == 149 || x == 179) { return c("#475569") }
            if row >= 4 && row <= 7 && (x == 179 || x == 180) { return c("#64748B") }

            if row == 12 && x >= 158 && x <= 167 { return c("#0F141C") }
            if row == 11 && x >= 155 && x <= 168 { return c("#0F141C") }
            if row == 10 && x >= 163 && x <= 168 { return c("#0F141C") }

            if row == 10 && x >= 156 && x <= 162 {
                if x == 157 || x == 158 { return c("#FFFFFF") }
                return c("#FFE5D9")
            }
            if row == 9 && x >= 155 && x <= 163 {
                return (x == 155) ? c("#F4C2AA") : c("#FFE5D9")
            }
            if row == 8 && x >= 159 && x <= 164 { return c("#F4C2AA") }

            if (row == 7 || row == 8) && x >= 157 && x <= 161 { return c("#FFFFFF") }
            if row >= 4 && row <= 8 && x >= 158 && x <= 174 {
                return (x < 166) ? c("#2EC4B6") : c("#1B9AAA")
            }
            if (row == 6 || row == 7) && x >= 147 && x <= 158 { return c("#2EC4B6") }
            if row == 8 && x >= 144 && x <= 148 { return c("#FFE5D9") }

            if (row == 2 || row == 3) && x >= 136 && x <= 143 {
                return (row == 2 && x <= 141) ? c("#E63946") : c("#FFFFFF")
            }
            if row >= 2 && row <= 5 && x >= 144 && x <= 152 { return c("#5C80BC") }
            if (row == 4 || row == 5) && x >= 150 && x <= 164 { return c("#3D5A80") }

            let dragGlow = sin(phase * 1.1)
            if row == 8 && x >= 138 && x <= 143 { return c("#FFFFFF") }
            if (row == 8 || row == 9) && (x >= 135 && x <= 137) {
                if row == 8 { return (dragGlow > 0.1) ? c("#FF4800") : c("#E63946") }
                if dragGlow > 0.25 { return c("#FF9E00") }
            }

            if row >= 9 && row <= roofTop - 3 {
                let hSmoke = dy - 8.0
                let smokeX = 136.0 - hSmoke * 0.8 + sin(hSmoke * 0.9 - phase * 2.2) * (1.3 + hSmoke * 0.25)
                if abs(dx - smokeX) < 1.1 + hSmoke * 0.15 {
                    return (row <= 10) ? c("#F8F9FA") : ((row <= 11) ? c("#CBD5E1") : c("#64748B"))
                }
            }
            return (row >= 7) ? c("#111C2D") : c("#162336")
        }

        if x >= 586 { return c("#1E293B") }

        if x >= 262 && x <= 322 && row >= 2 && row <= 9 {
            if row % 3 == 2 || x == 262 || x == 292 || x == 322 { return c("#1E293B") }
            let minimalistBooks = ["#94A3B8", "#48CAE4", "#E2E8F0", "#2A9D8F", "#64748B", "#F4A261"]
            return c(minimalistBooks[(x / 2 + row) % minimalistBooks.count])
        }
        if x >= 342 && x <= 370 && row >= 2 && row <= 7 {
            if x >= 347 && x <= 365 && row <= 5 {
                let fl = sin(phase * 2.5 + dx * 0.4)
                return (row <= 3) ? c("#FFF3B0") : ((fl > 0) ? c("#FF9E00") : c("#E63946"))
            }
            return c("#1E293B")
        }
        if row == 2 && x >= 388 && x <= 418 { return c("#64748B") }
        let catTop = (sin(phase * 1.5) > 0) ? 4 : 3
        if row >= 2 && row <= catTop && x >= 395 && x <= 409 {
            return (x <= 398 && row == catTop) ? c("#94A3B8") : c("#CBD5E1")
        }

        if row == 4 && x >= 482 && x <= 538 { return c("#94A3B8") }
        if (row == 2 || row == 3) && (x == 486 || x == 534) { return c("#1E293B") }

        if x >= 458 && x <= 461 && row >= 2 && row <= 9 { return c("#1E293B") }
        if row == 3 && x >= 460 && x <= 482 { return c("#1E293B") }

        if row == 12 && x >= 470 && x <= 479 { return c("#0F141C") }
        if row == 11 && x >= 468 && x <= 482 { return c("#0F141C") }
        if row == 10 && x >= 468 && x <= 474 { return c("#0F141C") }

        if row == 10 && x >= 475 && x <= 481 {
            if x == 479 || x == 480 { return c("#FFFFFF") }
            return c("#FFE5D9")
        }
        if row == 9 && x >= 474 && x <= 483 {
            return (x == 483) ? c("#F4C2AA") : c("#FFE5D9")
        }
        if row == 8 && x >= 473 && x <= 478 { return c("#F4C2AA") }

        if (row == 7 || row == 8) && x >= 476 && x <= 480 { return c("#FFFFFF") }
        if row == 5 && x >= 489 && x <= 496 { return c("#FFE5D9") }
        if (row == 5 || row == 6) && x >= 478 && x <= 489 { return c("#2EC4B6") }
        if row >= 4 && row <= 8 && x >= 463 && x <= 480 {
            return (x > 471) ? c("#2EC4B6") : c("#1B9AAA")
        }

        if (row == 2 || row == 3) && x >= 488 && x <= 495 {
            return (row == 2 && x >= 490) ? c("#E63946") : c("#FFFFFF")
        }
        if row >= 2 && row <= 4 && x >= 479 && x <= 487 { return c("#5C80BC") }
        if row == 4 && x >= 465 && x <= 481 { return c("#3D5A80") }

        if row == 5 && x >= 493 && x <= 506 { return c("#E2E8F0") }
        let screenCol = 510 - (row - 5) / 2
        if row >= 5 && row <= 9 && (x == screenCol || x == screenCol + 1 || x == screenCol + 2) {
            return (x == screenCol + 2) ? c("#94A3B8") : c("#72EFDD")
        }

        if (row == 5 || row == 6) && (x >= 520 && x <= 524) { return c("#FFFFFF") }
        if row >= 7 && row <= 10 && x == 522 + Int(round(sin(dy * 1.2 - phase * 2.5) * 0.8)) { return c("#E2E8F0") }

        if x >= 502 && x <= 584 && row >= 4 && row <= 11 {
            if x == 502 || x == 530 || x == 557 || x == 584 || row == 4 || row == 11 { return c("#1E293B") }
            let winDrop = (20.0 - dy + phase * 2.8 + Double(hash2D(x / 2, 7) % 13)).truncatingRemainder(dividingBy: 9.0)
            if winDrop < 1.3 && x % 3 == 0 { return c("#90E0EF") }
            return (row >= 8) ? c("#132235") : c("#1B314B")
        }

        for lampX in [325.0, 490.0] {
            if hypot(dx - lampX, dy - 11.5) < 2.0 { return c("#FFFFFF") }
            if hypot(dx - lampX, dy - 11.5) < 3.4 { return c("#E2E8F0") }
        }
        if x % 24 == 0 { return c("#28313E") }
        let dLight = min(hypot((dx - 325.0) * 0.35, dy - 7.0), hypot((dx - 490.0) * 0.3, dy - 8.0))
        if dLight < 9.5  { return c("#526075") }
        if dLight < 18.0 { return c("#3E4A5C") }
        return c("#2F3947")
    }

    // 13. OCEAN — GIỮ NGUYÊN 100%
    private func drawCleanOceanWithOneCrab(col: Int, row: Int) -> CGColor {
        let x = col % 670
        let dx = Double(x), dy = Double(row)

        let crabX = 335.0 + sin(phase * 0.45) * 145.0 + cos(phase * 0.78) * 65.0
        let crabY = 2.0 + sin(phase * 0.9) * 0.6
        if abs(dy - crabY) <= 1.2 && abs(dx - crabX) <= 3.2 {
            if dy > crabY + 0.3 && abs(abs(dx - crabX) - 2.2) < 1.0 { return c("#FF6B6B") }
            if dy <= crabY + 0.3 && abs(dx - crabX) <= 2.2 { return c("#E63946") }
        }

        let shoreCurve = 4.8 + sin(dx * 0.014) * 1.8 + cos(dx * 0.032) * 0.9
        let tide = sin(phase * 0.72 - dx * 0.012) * 1.9 + cos(phase * 0.42 + dx * 0.022) * 0.8
        let waterEdge = shoreCurve + tide

        if dy < shoreCurve - 1.5 { return ((x + row) % 7 == 0) ? c("#EEB956") : c("#F4D35E") }
        if dy < waterEdge - 0.8 { return c("#C8963E") }
        if dy < waterEdge + 0.75 { return ((x + Int(phase * 3.5)) % 3 == 0) ? c("#E0FBFC") : c("#FFFFFF") }

        let depth = dy - waterEdge
        let horizontalWave = sin(dy * 1.25 - phase * 1.6 + sin(dx * 0.025) * 2.5 + cos(dx * 0.06) * 1.2)
        if horizontalWave > 0.84 && depth > 1.5 && row < 19 { return c("#ADE8F4") }
        if depth < 3.2 { return c("#48CAE4") }
        if depth < 6.5 { return c("#00B4D8") }
        if depth < 10.2 { return c("#0077B6") }
        return c("#023E8A")
    }

    // =========================================================================
    // STEAM (20x670) — CÔ GÁI ANIME TÓC ĐEN MẮT TÍM (BÊ NGUYÊN ẢNH MẪU 8-BIT)
    // MẶC ĐỊNH MỞ 2 MẮT, SẠCH TÓC TRƯỚC MẶT & BỐI CẢNH TÍM ĐEN HUYỀN ẢO
    // =========================================================================
    private func drawZoomedRedLipsSmoothTurnAndWarmSteam(col: Int, row: Int) -> CGColor {
        let x = col % 670
        let dx = Double(x), dy = Double(row) // 0..669, 0..19

        // =====================================================================
        // 1. CÔ GÁI ANIME TÓC ĐEN MẮT TÍM (BÊ NGUYÊN ẢNH MẪU 8-BIT 24x20)
        // Mở mắt trái mặc định, làm sạch các sợi tóc chắn trước mặt & môi
        // =====================================================================
        struct AnimeGirl8Bit {
            static let width = 24
            static let height = 20

            // Bảng 16 màu Anime Cel-Shaded chuẩn từ ảnh mẫu (A -> P)
            static let palette: [String] = [
                "#06040A", // A: Đen tuyền (tóc, viền mi, con ngươi)
                "#140F1D", // B: Tóc bóng tối (Midnight hair shadow)
                "#281D38", // C: Tóc tím than (Mid hair shadow)
                "#48335E", // D: Tóc highlight tím
                "#735296", // E: Tóc viền bắt sáng (Rim light)
                "#FAF6FE", // F: Làn da sứ đào bắt sáng rực rỡ
                "#ECE0F4", // G: Làn da sứ mịn màng
                "#D0BDE3", // H: Làn da tím phấn (Lilac skin midtone)
                "#A38DC0", // I: Bóng cel-shadowing mềm
                "#6D548A", // J: Bóng cel-shadowing sâu khuôn mặt
                "#491875", // K: Bóng mí mắt tím đậm
                "#A855F7", // L: Tròng mắt tím phát sáng rực rỡ (Electric violet)
                "#E879F9", // M: Quầng mắt tím hồng magenta
                "#FFFFFF", // N: Điểm bắt sáng tròng mắt & sống mũi
                "#C85B82", // O: Đôi môi phớt hồng mận quyến rũ
                "#5A162F", // P: Rãnh lòng môi sâu
            ]

            static let baseRows: [String] = [
                "AAAAAAAAAAAACBAAAAAAAAAB",
                "AAAAAAAAAAAADBAAAAAAAAAB",
                "AAAAAAAAAAABJBAAAAAAAAAB",
                "AAAAAAAAAAACJBAAAABABBAC",
                "AAAAAAABBBBBBAAAAAAABAAC",
                "AAAAAAABDAAJCBBBBBABBABC",
                "AAAAAAAAALMCJJJJJDLMLAAC",
                "AAAAAAADDNLDJJJEJDLNCAAC",
                "AAAAAAADJJEEJJJEIIJIBAAB",
                "AAAAAABCJJJJJJEEHHHIAAAB",
                "AAAAAABCCJJJJJJEHFNDAAAB",
                "AAAAAABJCCJJJJJJINHAAAAB",
                "AAAAAAAJJJJJJJJJIGDAAABC",
                "ABBAAAADJJJJJJJHNJABBBCC",
                "AAAAAAABJJJJJJOHJAAAAAAA",
                "AAAAAABAJJJOOOOJAABDCBAA",
                "AAAAAAABBJJJJHDJBBADDDJD",
                "AAAAAAAAADEJHJAAABDJBBDE",
                "AAAAAAAAAACDCAAAAABEDAAC",
                "AAAAAAAAAAAAAAAAAAADDBAA",
            ]

            static let grid: [Int] = {
                var arr = [Int](repeating: 0, count: width * height)
                for (y, line) in baseRows.enumerated() where y < height {
                    for (x, ch) in line.utf8.enumerated() where x < width {
                        let v = Int(ch)
                        if v >= 65 && v <= 80 { arr[y * width + x] = v - 65 }
                    }
                }
                return arr
            }()
        }

        let startCol = 310
        let rawGx = x - startCol
        if rawGx >= 0 && rawGx < AnimeGirl8Bit.width {
            let gy = max(0, min(AnimeGirl8Bit.height - 1, 19 - row))
            var colorIdx = AnimeGirl8Bit.grid[gy * AnimeGirl8Bit.width + rawGx]

            // =================================================================
            // HOẠT ẢNH NHÁY MẮT TRÁI (WINKING ANIMATION)
            // Mặc định: CẢ HAI MẮT ĐỀU MỞ (tròng tím phát sáng, catchlight trắng)
            // Chu kỳ 5 giây: Thi thoảng nháy mắt trái (x=9..10, gy=5..7) trong 0.35s
            // =================================================================
            let cycle = phase.truncatingRemainder(dividingBy: 5.0)
            if cycle >= 4.2 && cycle < 4.55 {
                if gy == 5 && (rawGx == 9 || rawGx == 10) { colorIdx = 3 } // D: nếp mí nhắm
                else if gy == 6 && rawGx == 9 { colorIdx = 1 } // B: mi nhắm
                else if gy == 6 && rawGx == 10 { colorIdx = 2 } // C: mi nhắm
                else if gy == 7 && (rawGx == 9 || rawGx == 10) { colorIdx = 3 } // D: bóng dưới mi
            }

            return c(AnimeGirl8Bit.palette[colorIdx])
        }

        // =====================================================================
        // 2. HỆ THỐNG HƠI NƯỚC ĐA DẠNG BẤT ĐỐI XỨNG (5 VÙNG KHÁC BIỆT HOÀN TOÀN)
        // =====================================================================
        var vaporDensity = 0.0

        // VÙNG 1 (Cực Trái x = 0..160): Sương mặt nước & lọn khói xoắn đôi
        if dx <= 160.0 {
            if dy <= 6.0 {
                let groundWave = (1.0 - dy / 6.0) * (0.62 + 0.38 * sin(dx * 0.045 - phase * 0.7))
                let edgeG = smoothstep(0.0, 20.0, dx) * smoothstep(160.0, 120.0, dx)
                vaporDensity = max(vaporDensity, groundWave * edgeG * 0.85)
            }
            let wisp1Center = 42.0 + dy * 1.8 + sin(dy * 0.55 - phase * 2.2) * (1.8 + dy * 0.15)
            let wisp1W = 1.8 + dy * 0.4
            let dW1 = abs(dx - wisp1Center)
            if dW1 < wisp1W {
                vaporDensity = max(vaporDensity, pow(1.0 - dW1 / wisp1W, 1.3) * (0.95 - dy * 0.015))
            }
            let wisp2Center = 96.0 - dy * 0.8 + cos(dy * 0.42 - phase * 1.4 + 1.2) * (2.4 + dy * 0.22)
            let wisp2W = 2.2 + dy * 0.55
            let dW2 = abs(dx - wisp2Center)
            if dW2 < wisp2W {
                vaporDensity = max(vaporDensity, (1.0 - dW2 / wisp2W) * 0.88)
            }
        }

        // VÙNG 2 (Giữa-Trái x = 148..268): Cột hơi nước cuộn xoáy nở bùng & dải mây lơ lửng
        if dx >= 148.0 && dx <= 268.0 {
            let plumeCenter = 192.0 + sin(dy * 0.35 - phase * 1.5) * (3.5 + dy * 0.35)
            let plumeW = 2.4 + pow(dy / 19.0, 1.25) * 11.0
            let dPlume = abs(dx - plumeCenter)
            if dPlume < plumeW {
                let convectionNoise = 0.72 + 0.28 * sin(dx * 0.16 + dy * 0.65 - phase * 1.9)
                let plumeIntensity = pow(1.0 - dPlume / plumeW, 1.1) * convectionNoise
                vaporDensity = max(vaporDensity, plumeIntensity * 0.96)
            }
            if dy >= 9.5 && dy <= 16.5 {
                let midDist = hypot((dx - 228.0) / 28.0, (dy - 13.0) / 3.8)
                if midDist < 1.0 {
                    let patchNoise = 0.65 + 0.35 * cos(dx * 0.12 - phase * 1.0)
                    vaporDensity = max(vaporDensity, (1.0 - midDist) * patchNoise * 0.85)
                }
            }
        }

        // VÙNG 3 (Quanh cô gái x = 260..395): Sương mờ phông nền tạo chiều sâu
        if dx >= 260.0 && dx <= 395.0 {
            let ambientDist = hypot((dx - 325.0) / 60.0, (dy - 10.0) / 8.0)
            if ambientDist < 1.0 {
                let ambNoise = 0.5 + 0.5 * sin(dx * 0.08 + dy * 0.35 - phase * 0.8)
                vaporDensity = max(vaporDensity, (1.0 - ambientDist) * ambNoise * 0.35)
            }
        }

        // VÙNG 4 (Giữa-Phải x = 388..528): Dải khói chữ S, cụm sương thấp & vòm sương trần
        if dx >= 388.0 && dx <= 528.0 {
            if dy >= 12.0 {
                let ceilingFog = ((dy - 12.0) / 7.0) * (0.65 + 0.35 * sin(dx * 0.06 + phase * 0.85))
                let edgeC = smoothstep(390.0, 425.0, dx) * smoothstep(525.0, 480.0, dx)
                vaporDensity = max(vaporDensity, ceilingFog * edgeC * 0.82)
            }
            if dy <= 8.5 {
                let lowCloudDist = hypot((dx - 425.0) / 22.0, (dy - 4.5) / 3.5)
                if lowCloudDist < 1.0 {
                    vaporDensity = max(vaporDensity, (1.0 - lowCloudDist) * 0.75)
                }
            }
            let sCurve = 482.0 + sin(dy * 0.45 - phase * 1.8) * 4.2 + cos(dy * 0.85 - phase * 2.3) * 2.0
            let sCurveW = 2.0 + dy * 0.38
            let dSCurve = abs(dx - sCurve)
            if dSCurve < sCurveW {
                vaporDensity = max(vaporDensity, (1.0 - dSCurve / sCurveW) * 0.94)
            }
        }

        // VÙNG 5 (Cực Phải x = 518..669): Luồng nhiệt quét chéo & dải sương tan biến
        if dx >= 518.0 {
            let jetCenter = 638.0 - dy * 3.4 + sin(dy * 0.42 - phase * 2.1 + 2.0) * (2.2 + dy * 0.3)
            let jetW = 2.2 + dy * 0.95
            let dJet = abs(dx - jetCenter)
            if dJet < jetW {
                vaporDensity = max(vaporDensity, pow(1.0 - dJet / jetW, 1.25) * 1.05)
            }
            let driftDist = hypot((dx - 580.0) / 42.0, (dy - 7.5) / 3.8)
            if driftDist < 1.0 {
                let driftNoise = 0.7 + 0.3 * cos(dx * 0.09 - phase * 1.1)
                vaporDensity = max(vaporDensity, (1.0 - driftDist) * driftNoise * 0.76)
            }
        }

        // =====================================================================
        // 3. NỀN TÍM ĐEN HUYỀN BÍ (MIDNIGHT INDIGO GRADIENT) & BOKEH VIOLET
        // =====================================================================
        // 3. NỀN TÍM ĐEN HUYỀN BÍ (MIDNIGHT INDIGO GRADIENT) & BOKEH VIOLET
        // =====================================================================
        var bgHex: String
        switch row {
        case 0, 1:    bgHex = "#1E1035" // Đáy: tím đêm suối khoáng huyền ảo
        case 2, 3:    bgHex = "#180D2C"
        case 4, 5:    bgHex = "#130A24"
        case 6, 7:    bgHex = "#0F081C"
        case 8, 9:    bgHex = "#0C0617"
        case 10, 11:  bgHex = "#090512"
        case 12, 13, 14: bgHex = "#07040E"
        default:      bgHex = "#04020A" // Đỉnh: tím đen vũ trụ sâu thẳm
        }

        let bokehLights: [(bx: Double, by: Double, br: Double)] = [
            (105.0, 5.5, 26.0), (225.0, 8.0, 20.0), (445.0, 6.5, 25.0), (590.0, 9.0, 28.0)
        ]
        for bk in bokehLights {
            let bkx = bk.bx + sin(phase * 0.3 + bk.by) * 8.0
            let bDist = hypot((dx - bkx) / bk.br, (dy - bk.by) / (bk.br * 0.25))
            if bDist < 1.0 {
                bgHex = (bDist < 0.45) ? "#482672" : "#311852"
            }
        }

        // Chuyển màu hơi nước chuẩn tông tím khói anime huyền bí
        if vaporDensity > 0.78 { return c("#FFFFFF") } // Lõi khói trắng sáng
        if vaporDensity > 0.58 { return c("#F1E8FB") } // Sương trắng ánh tím nhạt
        if vaporDensity > 0.40 { return c("#D8C3F5") } // Hơi nước tím mờ
        if vaporDensity > 0.22 { return lerp(bgHex, "#8E72B5", 0.65) } // Khói mờ hòa lẫn hoàng hôn tím
        if vaporDensity > 0.08 { return lerp(bgHex, "#4E376E", 0.40) } // Ánh viền tím đêm

        return c(bgHex)
    }
    // 15. NIGHT — SAO BĂNG ĐA HƯỚNG
        private func drawNightMultiDirectionMeteors(col: Int, row: Int) -> CGColor {
            let x = col % 502
            let dCol = Double(x), dRow = Double(row)

            if dRow <= 1.2 + sin(dCol * 0.025) * 1.2 + cos(dCol * 0.07) * 0.6 { return c("#05070F") }

            let meteors: [(x0: Double, y0: Double, vx: Double, vy: Double, period: Double, offset: Double)] = [
                (42.0,  14.2,  78.0, -9.5,  7.8, 0.0),
                (468.0, 13.8, -92.0, -7.2,  8.4, 1.9),
                (325.0, 14.5, -64.0, -10.5, 9.2, 4.1),
                (95.0,   7.5,  86.0,  4.8,  10.5, 6.2),
                (205.0, 12.8,  82.0, -6.5,  8.0, 3.0)
            ]

            for m in meteors {
                let t = (phase * 1.55 + m.offset).truncatingRemainder(dividingBy: m.period)
                if t < 1.25 {
                    let headX = m.x0 + t * m.vx, headY = m.y0 + t * m.vy
                    let speedLen = hypot(m.vx, m.vy)
                    let ux = m.vx / speedLen, uy = m.vy / speedLen
                    let relX = headX - dCol, relY = headY - dRow
                    let distAlongTail = relX * ux + relY * uy
                    let distPerp = abs(-relX * uy + relY * ux)

                    if distAlongTail >= -1.2 && distAlongTail <= 24.0 {
                        if distAlongTail <= 2.2 && distPerp < 0.82 { return c("#FFFFFF") }
                        if distAlongTail <= 8.5 && distPerp < 0.65 { return c("#CAF0F8") }
                        if distAlongTail <= 16.5 && distPerp < 0.52 { return c("#48CAE4") }
                        if distPerp < 0.45 && (x + row) % 2 == 0 { return c("#3A506B") }
                    }
                }
            }

            for (cx, cy) in [(48, 11), (145, 9), (255, 12), (365, 10), (455, 11)] {
                let pulse = sin(phase * 0.8 + Double(cx))
                if x == cx && row == cy { return c("#FFF9D2") }
                if pulse > -0.2 && ((abs(x - cx) == 1 && row == cy) || (abs(row - cy) == 1 && x == cx)) {
                    return (pulse > 0.4) ? c("#80FFDB") : c("#3A506B")
                }
            }

            if hash2D(x, row) % 62 == 0 {
                let twinkle = sin(phase * (0.7 + Double(x % 5) * 0.2) + Double(x * 3 + row * 7))
                if twinkle > 0.42 {
                    let sCols = ["#FFFFFF", "#FFE66D", "#CAF0F8", "#FFCCD5"]
                    return c(sCols[(x + row) % sCols.count])
                } else if twinkle > -0.15 {
                    return c("#5C677D")
                }
            }

            let archY = 4.0 + sin((dCol / 502.0) * .pi) * 8.5
            if abs(dRow - archY) < 2.8 { return c("#231942") }
            if abs(dRow - archY) < 4.8 { return c("#181532") }
            return (row >= 10) ? c("#060814") : c("#0B0F24")
        }
    }
// MARK: - 6. AppDelegate điều khiển Touch Bar
class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    var systemTouchBar: NSTouchBar?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        TouchBarPrivateAPI.setModalShowsCloseBox(false)

        let tb = NSTouchBar()
        tb.delegate = self
        tb.defaultItemIdentifiers = [.waveItem]
        self.systemTouchBar = tb

        let stripItem = NSCustomTouchBarItem(identifier: .controlStripItem)
        stripItem.view = NSView(frame: .zero)
        TouchBarPrivateAPI.addSystemTrayItem(stripItem)
        TouchBarPrivateAPI.setControlStripPresence(
            identifier: NSTouchBarItem.Identifier.controlStripItem.rawValue,
            present: false
        )

        showWave()
    }

    @objc func showWave() {
        guard let tb = systemTouchBar else { return }
        TouchBarPrivateAPI.presentSystemModal(
            tb,
            identifier: NSTouchBarItem.Identifier.controlStripItem.rawValue
        )
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == .waveItem {
            let item = NSCustomTouchBarItem(identifier: .waveItem)
            item.view = Wave8BitView(frame: NSRect(x: 0, y: 0, width: 2170, height: 30))
            return item
        }
        return nil
    }
}

// MARK: - 7. Điểm khởi chạy App
@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
