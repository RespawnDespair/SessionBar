import AppKit
import Darwin
import ObjectiveC.runtime

/// Private AppKit/DFRFoundation calls that let a background app own the Touch Bar and put an
/// item in the Control Strip. Same technique as QuotaBar, Pock and MTMR.
enum SystemModalTouchBar {
    static func present(_ touchBar: NSTouchBar, trayIdentifier: NSTouchBarItem.Identifier) {
        let selector = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        guard let method = class_getClassMethod(NSTouchBar.self, selector) else { return }
        typealias Function = @convention(c) (AnyClass, Selector, NSTouchBar, Int64, NSString?) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        function(NSTouchBar.self, selector, touchBar, 1, trayIdentifier.rawValue as NSString)
    }

    static func dismiss(_ touchBar: NSTouchBar) {
        call("dismissSystemModalTouchBar:", touchBar)
    }

    static func minimize(_ touchBar: NSTouchBar) {
        call("minimizeSystemModalTouchBar:", touchBar)
    }

    private static func call(_ name: String, _ touchBar: NSTouchBar) {
        let selector = NSSelectorFromString(name)
        guard let method = class_getClassMethod(NSTouchBar.self, selector) else { return }
        typealias Function = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        function(NSTouchBar.self, selector, touchBar)
    }
}

@MainActor
enum ControlStripItem {
    private typealias PresenceFunction = @convention(c) (CFString, UInt8) -> Void
    private static let presenceFunction: PresenceFunction? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY),
              let symbol = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") else { return nil }
        return unsafeBitCast(symbol, to: PresenceFunction.self)
    }()

    static func add(_ item: NSTouchBarItem) {
        invoke("addSystemTrayItem:", item)
        setPresence(item.identifier, visible: true)
    }

    static func remove(_ item: NSTouchBarItem) {
        setPresence(item.identifier, visible: false)
        invoke("removeSystemTrayItem:", item)
    }

    static func setPresence(_ identifier: NSTouchBarItem.Identifier, visible: Bool) {
        presenceFunction?(identifier.rawValue as CFString, visible ? 1 : 0)
    }

    private static func invoke(_ name: String, _ item: NSTouchBarItem) {
        let selector = NSSelectorFromString(name)
        guard let method = class_getClassMethod(NSTouchBarItem.self, selector) else { return }
        typealias Function = @convention(c) (AnyClass, Selector, NSTouchBarItem) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        function(NSTouchBarItem.self, selector, item)
    }
}
