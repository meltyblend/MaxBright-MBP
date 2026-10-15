import AppKit

/// Intercepts the brightness keys (F1/F2 on MacBooks) with an event tap, which needs Accessibility permission.
@MainActor
final class BrightnessKeyTap {
    enum Key { case up, down }

    /// Returns whether the key press was used, in which case macOS never sees it.
    private let handler: @MainActor (_ key: Key, _ fine: Bool) -> Bool
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Keys whose key-down was swallowed, so the matching key-up is swallowed too.
    private var swallowed: Set<Key> = []

    init(handler: @escaping @MainActor (_ key: Key, _ fine: Bool) -> Bool) {
        self.handler = handler
    }

    /// Starts listening; returns false when Accessibility permission hasn't been granted.
    func start() -> Bool {
        guard tap == nil else { return true }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << Self.systemDefinedEvent,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<BrightnessKeyTap>.fromOpaque(context).takeUnretainedValue()
                let swallow = MainActor.assumeIsolated { tap.shouldSwallow(type, event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        swallowed.removeAll()
    }

    // Media keys arrive as NX_SYSDEFINED events of subtype NX_SUBTYPE_AUX_CONTROL_BUTTONS, with the key type in
    // the high 16 bits of data1 and the key state (0xA down, 0xB up) in the next byte.
    private static let systemDefinedEvent: UInt32 = 14
    private static let auxControlButtons: Int16 = 8
    private static let brightnessUpKey = 2
    private static let brightnessDownKey = 3
    private static let keyDownState = 0xA

    private func shouldSwallow(_ type: CGEventType, _ event: CGEvent) -> Bool {
        // macOS switches off taps that are slow or interrupted; turn it straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type.rawValue == Self.systemDefinedEvent,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.auxControlButtons else { return false }

        let key: Key
        switch (nsEvent.data1 & 0xFFFF_0000) >> 16 {
        case Self.brightnessUpKey: key = .up
        case Self.brightnessDownKey: key = .down
        default: return false
        }

        guard (nsEvent.data1 & 0xFF00) >> 8 == Self.keyDownState else {
            return swallowed.remove(key) != nil
        }
        // ⌥⇧ is the macOS modifier for quarter-step brightness changes.
        let fine = nsEvent.modifierFlags.contains([.option, .shift])
        if handler(key, fine) {
            swallowed.insert(key)
            return true
        }
        swallowed.remove(key)
        return false
    }
}
