// make-icon.swift — sinh AppIcon.icns cho Stress-relief.app
// Thiết kế: ô vuông bo tròn nền gradient teal → đêm xanh đậm,
// các thanh equalizer mờ phía sau + đường sóng âm trắng ở giữa.
// Chạy:  swift make-icon.swift <output.png>
import AppKit
import CoreGraphics

let outPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "AppIcon-1024.png"
let S: CGFloat = 1024

// Canvas bitmap trực tiếp (ổn định khi chạy headless CLI)
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
let nctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = nctx
let ctx = nctx.cgContext
defer { NSGraphicsContext.restoreGraphicsState() }

// 1. Ô nền bo tròn (margin 10%, radius ~22.5% giống icon macOS)
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let clip = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
clip.addClip()

// 2. Gradient nền: teal sáng (trên-trái) → xanh đêm đậm (dưới-phải)
let grad = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.18, green: 0.77, blue: 0.71, alpha: 1).cgColor,   // #2EC4B6
        NSColor(calibratedRed: 0.04, green: 0.35, blue: 0.52, alpha: 1).cgColor,   // #0A5985
        NSColor(calibratedRed: 0.02, green: 0.11, blue: 0.22, alpha: 1).cgColor,   // #051C38
    ] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
ctx.drawLinearGradient(
    grad,
    start: CGPoint(x: rect.minX, y: rect.maxY),
    end: CGPoint(x: rect.maxX, y: rect.minY),
    options: []
)

// 3. Quầng sáng ấm phía sau sóng (ánh trăng trên nước)
let glow = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 1.0, green: 0.90, blue: 0.55, alpha: 0.30).cgColor,
        NSColor(calibratedRed: 1.0, green: 0.90, blue: 0.55, alpha: 0.0).cgColor,
    ] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: 512, y: 640), startRadius: 0,
    endCenter: CGPoint(x: 512, y: 640), endRadius: 380,
    options: []
)

// 4. Thanh equalizer mờ phía sau (7 cột, alpha thấp)
let barW: CGFloat = 34
let gap: CGFloat = 28
let heights: [CGFloat] = [180, 300, 220, 420, 260, 340, 150]
let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
var bx = 512 - totalW / 2
ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.22).cgColor)
for h in heights {
    let barRect = CGRect(x: bx, y: 512 - h / 2, width: barW, height: h)
    NSBezierPath(roundedRect: barRect, xRadius: barW / 2, yRadius: barW / 2).fill()
    bx += barW + gap
}

// 5. Đường sóng âm trắng chính: y = 512 + A·sin(2π·(x−x0)/λ)
ctx.setStrokeColor(NSColor.white.cgColor)
ctx.setLineWidth(58)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let wave = CGMutablePath()
let x0: CGFloat = 200, x1: CGFloat = 824
let amp: CGFloat = 88, lambda: CGFloat = 310
var first = true
var x = x0
while x <= x1 {
    let y = 512 + amp * sin(2 * .pi * (x - x0) / lambda)
    if first { wave.move(to: CGPoint(x: x, y: y)); first = false }
    else { wave.addLine(to: CGPoint(x: x, y: y)) }
    x += 4
}
ctx.addPath(wave)
ctx.strokePath()

// 6. Điểm bắt sáng nhỏ trên sóng (đầu sóng lấp lánh)
ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.85, alpha: 1).cgColor)
let sparkleY = 512 + amp * sin(2 * .pi * (x1 - x0) / lambda)
ctx.fillEllipse(in: CGRect(x: x1 - 22, y: sparkleY - 22, width: 44, height: 44))

// 7. Xuất PNG
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
