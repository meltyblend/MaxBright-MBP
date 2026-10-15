import AppKit
import IOKit

/// Reads the built-in panel's live luminance from the display driver.
enum PanelLuminance {
    /// Nits of unboosted SDR white on the built-in display, or nil if the driver doesn't report it.
    static func standardWhiteNits() -> Double? {
        guard let backlight = backlightNits(), let screen = builtInScreen() else { return nil }
        // In EDR mode the backlight runs `headroom` times brighter than SDR white, so dividing it back out gives
        // SDR white whether or not EDR is engaged.
        return backlight / Double(screen.maximumExtendedDynamicRangeColorComponentValue)
    }

    /// The built-in display's brightness setting from 0 to 1, as set by the brightness keys and Control Center.
    static func userBrightness() -> Float? {
        guard let getBrightness, let id = builtInScreen()?.displayID else { return nil }
        var brightness: Float = 0
        return getBrightness(id, &brightness) == 0 ? brightness : nil
    }

    /// Moves the brightness setting one step the way the brightness keys do: sixteenths, or sixty-fourths for
    /// fine steps, snapped to that grid. Returns whether the setting could be changed.
    static func stepUserBrightness(up: Bool, fine: Bool) -> Bool {
        guard let setBrightness, let id = builtInScreen()?.displayID, let current = userBrightness() else { return false }
        let steps: Float = fine ? 64 : 16
        let position = current * steps
        let target = (up ? (position + 0.01).rounded(.down) + 1 : (position - 0.01).rounded(.up) - 1) / steps
        return setBrightness(id, min(max(target, 0), 1)) == 0
    }

    /// Whether the built-in panel is in EDR mode, which includes the several seconds it takes to leave it after
    /// EDR content goes away.
    static var isInEDRMode: Bool {
        (builtInScreen()?.maximumExtendedDynamicRangeColorComponentValue ?? 1) > 1.001
    }

    private static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { $0.displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false }
    }

    // DisplayServicesGetBrightness and DisplayServicesSetBrightness from the private DisplayServices framework;
    // there is no public equivalent.
    private static let getBrightness = displayServices("DisplayServicesGetBrightness",
                                                       as: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
    private static let setBrightness = displayServices("DisplayServicesSetBrightness",
                                                       as: (@convention(c) (CGDirectDisplayID, Float) -> Int32).self)

    private static func displayServices<Function>(_ name: String, as type: Function.Type) -> Function? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    /// The backlight's current output: IOMFBBrightnessLevel on the built-in framebuffer, in 16.16 fixed-point nits.
    private static func backlightNits() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferShim"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var nits: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if nits == nil, property("external", of: service) as? Bool != true,
               let level = property("IOMFBBrightnessLevel", of: service) as? Int {
                nits = Double(level) / 65536
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return nits
    }

    private static func property(_ key: String, of service: io_service_t) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
