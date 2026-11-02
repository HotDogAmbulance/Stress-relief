import Cocoa

// MARK: - 5. View vẽ Nghệ thuật Toàn cảnh 8-Bit
final class Wave8BitView: NSView {
    private var renderTimer: Timer?
    private var monitorTimer: Timer?
    private var isSleeping: Bool = false

    var phase: Double = 0.0
    var realTime: Double = Date().timeIntervalSinceReferenceDate
    var clownfishSpawn: Double = -10.0
    var clownfishUntil: Double = -10.0

    let monitor = ComfortSoundsMonitor()
    let visibleWidth: CGFloat = 1004.0

    let babbleCols = 502
    let babbleRows = 15
    var babbleBuffer = [UInt8](repeating: 0, count: 502 * 15 * 4)
    var babbleBitmapCtx: CGContext?

    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    var bgGradient: CGGradient?
    var haloGradients: [CGGradient] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupBabbleRasterizer()
        monitor.pollSystemPreferences()
        setupSleepWakeObservers()
        startTimers()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        renderTimer?.invalidate()
        monitorTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopTimers()
        } else if !isSleeping {
            startTimers()
        }
    }

    private func setupSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleSleepNotification(_:)), name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleSleepNotification(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleWakeNotification(_:)), name: NSWorkspace.screensDidWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleWakeNotification(_:)), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func handleSleepNotification(_ notification: Notification) {
        isSleeping = true
        stopTimers()
    }

    @objc private func handleWakeNotification(_ notification: Notification) {
        isSleeping = false
        monitor.pollSystemPreferences()
        startTimers()
        needsDisplay = true
    }

    private func startTimers() {
        if monitorTimer == nil {
            monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.monitor.pollSystemPreferences()
            }
        }
        if renderTimer == nil {
            renderTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let effectiveVol = self.monitor.isEnabled ? self.monitor.currentVolume : 0.12
                let curvedVol = pow(effectiveVol, 1.35)
                let speedStep = 0.009 + (curvedVol * 0.045)
                self.phase += speedStep
                self.realTime = Date().timeIntervalSinceReferenceDate
                self.needsDisplay = true
            }
        }
    }

    private func stopTimers() {
        renderTimer?.invalidate()
        renderTimer = nil
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    // BẮT BUỘC: NSView mặc định bỏ qua direct touch trên TouchBar —
    // phải khai báo .direct thì touchesBegan mới được gọi
    override var allowedTouchTypes: NSTouch.TouchTypeMask {
        get { [.direct] }
        set { super.allowedTouchTypes = newValue }
    }

    // Chạm TouchBar: cá hề xuất hiện (DUY NHẤT khi đang là âm thanh Ocean)
    override func touchesBegan(with event: NSEvent) {
        if monitor.currentTheme == .ocean {
            let now = Date().timeIntervalSinceReferenceDate
            clownfishSpawn = now
            clownfishUntil = now + 6.5
            needsDisplay = true
        }
        super.touchesBegan(with: event)
    }

    private func setupBabbleRasterizer() {
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        babbleBitmapCtx = babbleBuffer.withUnsafeMutableBytes { ptr -> CGContext? in
            guard let base = ptr.baseAddress else { return nil }
            return CGContext(
                data: base,
                width: babbleCols,
                height: babbleRows,
                bitsPerComponent: 8,
                bytesPerRow: babbleCols * 4,
                space: rgbColorSpace,
                bitmapInfo: bitmapInfo
            )
        }

        let bgCols = [c("#F5EEDC"), c("#EDE2C8"), c("#D2E0EC"), c("#ECE5D5"), c("#E2D8C0")] as CFArray
        let bgLocs: [CGFloat] = [0.0, 0.18, 0.42, 0.70, 1.0]
        bgGradient = CGGradient(colorsSpace: rgbColorSpace, colors: bgCols, locations: bgLocs)

        let staticHalos: [(inner: String, mid: String, outer: String, alpha: CGFloat)] = [
            ("#F7E6B5", "#EFE0B8", "#F5EEDC", 0.55),
            ("#8EB4D9", "#C2D8EC", "#D2E0EC", 0.50),
            ("#C9D6DF", "#E2E8EC", "#ECE5D5", 0.45),
            ("#E5B8BF", "#F0D6DA", "#ECE5D5", 0.48),
            ("#D4C29E", "#E4D7BC", "#E2D8C0", 0.50)
        ]
        let haloLocs: [CGFloat] = [0.0, 0.55, 1.0]
        haloGradients = staticHalos.compactMap { h in
            let cols = [c(h.inner, h.alpha), c(h.mid, h.alpha * 0.55), c(h.outer, 0.0)] as CFArray
            return CGGradient(colorsSpace: rgbColorSpace, colors: cols, locations: haloLocs)
        }
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 1004, height: 30)
    }

    func c(_ hex: String, _ alpha: CGFloat = 1.0) -> CGColor {
        return ColorCache.shared.color(for: hex, alpha: alpha)
    }

    func lerp(_ h1: String, _ h2: String, _ t: Double) -> CGColor {
        return ColorCache.shared.lerpHex(h1, h2, t: t)
    }

    func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }

    func hash2D(_ x: Int, _ y: Int) -> Int {
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
            var gridRects: [CGRect] = []
            gridRects.reserveCapacity(cols + rows)
            for col in 0..<cols {
                gridRects.append(CGRect(x: CGFloat(col) * blockSize, y: 0, width: 0.5, height: bounds.height))
            }
            for row in 0..<rows {
                gridRects.append(CGRect(x: 0, y: CGFloat(row) * blockSize, width: visibleWidth, height: 0.5))
            }
            context.setFillColor(c("#05070A", 0.26))
            context.addRects(gridRects)
            context.fillPath()
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

    func sample8BitKandinsky(col: Int, row: Int) -> CGColor {
        let cx = max(0, min(babbleCols - 1, col % babbleCols))
        let memY = max(0, min(babbleRows - 1, (babbleRows - 1) - row))
        let offset = (memY * babbleCols + cx) * 4
        let rIdx = Int(babbleBuffer[offset]) >> 3
        let gIdx = Int(babbleBuffer[offset + 1]) >> 3
        let bIdx = Int(babbleBuffer[offset + 2]) >> 3
        return ColorCache.shared.babblePalette[(rIdx << 10) | (gIdx << 5) | bIdx]
    }
}
