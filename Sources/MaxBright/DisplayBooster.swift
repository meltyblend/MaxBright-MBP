import AppKit

/// Boosts one display: keeps it in EDR mode and scales its gamma table so SDR content is drawn above SDR white.
final class DisplayBooster {
    let displayID: CGDirectDisplayID
    private let trigger: EDRTriggerWindow?
    /// The display's table before boosting.
    private var baseline: GammaTable?
    /// The table as read back after our last write, so later comparisons match what the system actually stores.
    private var applied: GammaTable?
    private var appliedFactor: Float = 1

    init(displayID: CGDirectDisplayID, screen: NSScreen) {
        self.displayID = displayID
        trigger = EDRTriggerWindow(screen: screen)
        trigger?.orderFrontRegardless()
    }

    func follow(_ screen: NSScreen) {
        trigger?.pin(to: screen)
    }

    func apply(factor: Float) {
        guard let current = GammaTable.read(from: displayID) else { return }
        if let applied, current.isClose(to: applied) {
            guard abs(factor - appliedFactor) > 0.001 else { return }
        } else {
            // First pass, or the system replaced our table (wake, display reconfiguration, Night Shift, ColorSync):
            // what is there now is the new baseline. Normalizing it means a boosted table is never adopted as
            // the baseline, so the boost can't compound.
            baseline = current.normalized()
        }
        guard let baseline else { return }
        let target = baseline.scaled(by: factor)
        guard target.write(to: displayID) else { return }
        if let readback = GammaTable.read(from: displayID), readback.isClose(to: target) {
            applied = readback
            appliedFactor = factor
        } else {
            // The system clamps the table to SDR white until the panel is in EDR mode, which would flatten
            // highlights. Put the baseline back and try again on the next refresh.
            baseline.write(to: displayID)
            applied = GammaTable.read(from: displayID)
            appliedFactor = 1
        }
    }

    func stop() {
        // Only put the baseline back if our table is still in place; otherwise someone else owns it now.
        if let applied, let baseline, let current = GammaTable.read(from: displayID), current.isClose(to: applied) {
            baseline.write(to: displayID)
        }
        applied = nil
        trigger?.close()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
