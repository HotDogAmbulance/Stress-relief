import SwiftUI
import Cocoa

// MARK: - 6. AppDelegate điều khiển Touch Bar
final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
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
            item.view = Wave8BitView(frame: NSRect(x: 0, y: 0, width: 1004, height: 30))
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
