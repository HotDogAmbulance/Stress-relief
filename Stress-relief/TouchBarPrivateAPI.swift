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
