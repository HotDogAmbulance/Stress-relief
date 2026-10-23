import SwiftUI
import Cocoa

// MARK: - 1. Khai báo Identifier
extension NSTouchBarItem.Identifier {
    static let controlStripItem = NSTouchBarItem.Identifier("com.8bitwave.controlstrip")
    static let waveItem = NSTouchBarItem.Identifier("com.8bitwave.item")
}

// MARK: - 2. Cầu nối gọi thẳng Private API (Bản nâng cấp ẩn hoàn toàn nút X)
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
        // Sử dụng selector 3 tham số với placement = 1 (Ẩn hoàn toàn nút X ở góc trái)
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

// MARK: - Hỗ trợ mã màu Hex
extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255.0
        let g = CGFloat((int >> 8) & 0xFF) / 255.0
        let b = CGFloat(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - 3. View vẽ hiệu ứng sóng 8-bit (12 sắc độ Ice/Teal & Grid mịn)
class Wave8BitView: NSView {
    private var timer: Timer?
    private var phase: Double = 0.0

    // 12 màu dựa trên 4 màu gốc (#DCEFF7, #7EC8E3, #0F6E73, #E3E8EF) + 8 sắc độ đậm/nhạt
    // Được sắp xếp theo dải chuyển mượt từ Sáng -> Đậm -> Sáng để tạo hiệu ứng sóng cuộn
    let palette: [NSColor] = [
        NSColor(hex: "#F4FAFD"), // 1. Nhạt hơn của #DCEFF7 (Trắng băng)
        NSColor(hex: "#DCEFF7"), // 2. [GỐC 1] Xanh băng nhạt
        NSColor(hex: "#B8DFEE"), // 3. Đậm hơn của #DCEFF7
        NSColor(hex: "#A8DCF0"), // 4. Nhạt hơn của #7EC8E3
        NSColor(hex: "#7EC8E3"), // 5. [GỐC 2] Xanh da trời dịu
        NSColor(hex: "#4BA8CA"), // 6. Đậm hơn của #7EC8E3
        NSColor(hex: "#1B9AAA"), // 7. Nhạt hơn của #0F6E73
        NSColor(hex: "#0F6E73"), // 8. [GỐC 3] Xanh cổ vịt trầm (Teal)
        NSColor(hex: "#074346"), // 9. Đậm hơn của #0F6E73 (Xanh biển sâu)
        NSColor(hex: "#C5CFD9"), // 10. Đậm hơn của #E3E8EF (Xám xanh sương mù)
        NSColor(hex: "#E3E8EF"), // 11. [GỐC 4] Xám bạc dịu
        NSColor(hex: "#F2F5F8")  // 12. Nhạt hơn của #E3E8EF (Trắng sương)
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // ~15 FPS
        timer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.phase += 0.3
            self.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 2170, height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setAllowsAntialiasing(false)

        // Giảm kích thước mỗi ô lưới từ 10.0 xuống 5.0 (mịn gấp đôi)
        let blockSize: CGFloat = 5.0
        let gap: CGFloat = 0 // Khe hở viền đen giữa các ô (đổi thành 0.0 nếu muốn liền khối)

        let cols = Int(bounds.width / blockSize) + 1
        let rows = Int(bounds.height / blockSize) + 1

        for col in 0..<cols {
            // Tạo độ uốn lượn mượt hơn theo lưới nhỏ
            let waveOffset = Int(round(sin(Double(col) * 0.12 + phase) * 3.0))
            for row in 0..<rows {
                let colorIndex = abs(col / 2 + row + waveOffset) % palette.count
                context.setFillColor(palette[colorIndex].cgColor)

                let rect = CGRect(
                    x: CGFloat(col) * blockSize,
                    y: CGFloat(row) * blockSize,
                    width: blockSize - gap,
                    height: blockSize - gap
                )
                context.fill(rect)
            }
        }
    }
}

// MARK: - 4. AppDelegate điều khiển Touch Bar
class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    var systemTouchBar: NSTouchBar?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Tắt hoàn toàn nút X đóng modal
        TouchBarPrivateAPI.setModalShowsCloseBox(false)

        let tb = NSTouchBar()
        tb.delegate = self
        tb.defaultItemIdentifiers = [.waveItem]
        self.systemTouchBar = tb

        // Không đẩy nút 👾 lên Control Strip nữa để tránh chiếm chỗ, chỉ đăng ký ngầm
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

// MARK: - 5. Điểm khởi chạy App
@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
