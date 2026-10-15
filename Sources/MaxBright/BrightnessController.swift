import AppKit

/// Owns the boost settings and keeps every XDR display boosted while enabled.
@MainActor
final class BrightnessController: ObservableObject {
    static let shared = BrightnessController()

    static let boostRange: ClosedRange<Double> = 1.0...2.0
    static let lowBatteryThreshold = 20

    enum Status: Equatable {
        case off
        /// Waiting for the panel to ramp into EDR mode.
        case engaging
        /// Boosting at `effective`, which is below the requested boost when the display lacks headroom.
        case active(effective: Double)
        case paused(reason: String)
        case unsupported
    }

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.enabled); refresh() }
    }
    @Published var boost: Double {
        didSet {
            // Assigning a @Published property inside its own didSet runs didSet again, so only reassign when
            // the value actually changes; the normalized value then passes straight through.
            let normalized = (min(max(boost, Self.boostRange.lowerBound), Self.boostRange.upperBound) * 1000).rounded() / 1000
            guard boost == normalized else { boost = normalized; return }
            defaults.set(boost, forKey: Key.boost)
            refresh()
        }
    }
    @Published var pauseOnBattery: Bool {
        didSet { defaults.set(pauseOnBattery, forKey: Key.pauseOnBattery); refresh() }
    }
    @Published var pauseOnLowBattery: Bool {
        didSet { defaults.set(pauseOnLowBattery, forKey: Key.pauseOnLowBattery); refresh() }
    }
    @Published var useBrightnessKeys: Bool {
        didSet {
            defaults.set(useBrightnessKeys, forKey: Key.useBrightnessKeys)
            updateKeyTap()
            if brightnessKeysNeedAccess { requestBrightnessKeyAccess() }
        }
    }
    @Published private(set) var brightnessKeysNeedAccess = false
    @Published private(set) var status: Status = .off

    /// Called after a brightness key changed the boost, e.g. to show the HUD.
    var onBrightnessKey: (() -> Void)?

    var isBoosting: Bool {
        switch status {
        case .active, .engaging: return true
        case .off, .paused, .unsupported: return false
        }
    }

    /// The boost actually on screen right now, which is 1 while off or still engaging.
    var appliedBoost: Double {
        if case .active(let effective) = status { return effective }
        return 1
    }

    private enum Key {
        static let enabled = "enabled"
        static let boost = "boost"
        static let pauseOnBattery = "pauseOnBattery"
        static let pauseOnLowBattery = "pauseOnLowBattery"
        static let useBrightnessKeys = "useBrightnessKeys"
    }

    private let defaults = UserDefaults.standard
    private var boosters: [CGDirectDisplayID: DisplayBooster] = [:]
    private var timer: Timer?
    private var powerMonitor: PowerMonitor?
    private lazy var keyTap = BrightnessKeyTap { [weak self] key, fine in
        self?.handleBrightnessKey(key, fine: fine) ?? false
    }
    private var accessTimer: Timer?

    private init() {
        defaults.register(defaults: [
            Key.enabled: true,
            Key.boost: 1.6,
            Key.pauseOnBattery: false,
            Key.pauseOnLowBattery: true,
            Key.useBrightnessKeys: true,
        ])
        isEnabled = defaults.bool(forKey: Key.enabled)
        boost = defaults.double(forKey: Key.boost)
        pauseOnBattery = defaults.bool(forKey: Key.pauseOnBattery)
        pauseOnLowBattery = defaults.bool(forKey: Key.pauseOnLowBattery)
        useBrightnessKeys = defaults.bool(forKey: Key.useBrightnessKeys)
    }

    func start() {
        let refreshOnMain: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main, using: refreshOnMain)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refreshOnMain)
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: refreshOnMain)
        powerMonitor = PowerMonitor { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
        updateKeyTap()
        if brightnessKeysNeedAccess { requestBrightnessKeyAccess() }
    }

    /// Restores every display without changing the saved settings.
    func shutdown() {
        keyTap.stop()
        stopBoosting()
        timer?.invalidate()
        timer = nil
    }

    /// Moves the boost one step along a fixed grid, so presses always land on round values. Stepping up while off
    /// resumes the last boost; stepping down past the bottom turns the boost off but keeps the last step for next
    /// time. Returns false when the boost is already off and there is nothing to lower.
    @discardableResult
    func stepBoost(up: Bool, fine: Bool = false) -> Bool {
        let step = fine ? 0.025 : 0.1
        let lower = Self.boostRange.lowerBound
        let position = (boost - lower) / step
        if up {
            if isEnabled || boost <= lower + 0.001 {
                boost = lower + ((position + 0.001).rounded(.down) + 1) * step
            }
            isEnabled = true
            return true
        }
        guard isEnabled else { return false }
        let lowered = lower + ((position - 0.001).rounded(.up) - 1) * step
        if lowered > lower + 0.001 {
            boost = lowered
        } else {
            isEnabled = false
        }
        return true
    }

    /// The brightness keys carry on past the top of the system range. At full system brightness, brightness-up
    /// raises the boost and brightness-down lowers it a step at a time; once the boost is off, brightness-down
    /// dims the display as usual. Returns whether the key press was used.
    func handleBrightnessKey(_ key: BrightnessKeyTap.Key, fine: Bool) -> Bool {
        guard let brightness = PanelLuminance.userBrightness() else { return false }
        if brightness >= 0.995, stepBoost(up: key == .up, fine: fine) {
            onBrightnessKey?()
            return true
        }
        // While the panel is in EDR mode, including the several seconds it takes to leave it after the boost
        // turns off, macOS ignores brightness keys or changes the setting without dimming the screen. Setting the
        // brightness directly works in that state, so do the step here instead.
        guard PanelLuminance.isInEDRMode, PanelLuminance.stepUserBrightness(up: key == .up, fine: fine) else { return false }
        onBrightnessKey?()
        return true
    }

    /// Asks macOS for the Accessibility permission the brightness keys need.
    func requestBrightnessKeyAccess() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    private func updateKeyTap() {
        accessTimer?.invalidate()
        accessTimer = nil
        guard useBrightnessKeys else {
            keyTap.stop()
            brightnessKeysNeedAccess = false
            return
        }
        brightnessKeysNeedAccess = !keyTap.start()
        guard brightnessKeysNeedAccess else { return }
        // Start the moment access is granted in System Settings.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if AXIsProcessTrusted() { self?.updateKeyTap() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        accessTimer = timer
    }

    func refresh() {
        guard isEnabled else { return idle(.off) }
        if let reason = pauseReason() { return idle(.paused(reason: reason)) }

        let screens = NSScreen.screens.filter { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1 }
        guard !screens.isEmpty else { return idle(.unsupported) }

        var present = Set<CGDirectDisplayID>()
        var effective = boost
        var engaged = false
        for screen in screens {
            guard let id = screen.displayID else { continue }
            present.insert(id)
            let booster = boosters[id] ?? DisplayBooster(displayID: id, screen: screen)
            boosters[id] = booster
            booster.follow(screen)

            // Headroom is how far above SDR white the panel can go right now. It ramps up once EDR engages and
            // shrinks as system brightness rises or the panel heats up. Boosting past it would clip highlights.
            let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
            let factor = min(boost, headroom)
            booster.apply(factor: Float(factor))
            effective = min(effective, factor)
            engaged = engaged || headroom > 1
        }
        for (id, booster) in boosters where !present.contains(id) {
            booster.stop()
            boosters[id] = nil
        }

        startTimer()
        setStatus(engaged ? .active(effective: (effective * 100).rounded() / 100) : .engaging)
    }

    private func pauseReason() -> String? {
        guard let power = powerMonitor?.state, power.onBattery else { return nil }
        if pauseOnBattery { return "on battery power" }
        if pauseOnLowBattery, let level = power.batteryLevel, level < Self.lowBatteryThreshold {
            return "battery below \(Self.lowBatteryThreshold)%"
        }
        return nil
    }

    private func idle(_ status: Status) {
        stopBoosting()
        timer?.invalidate()
        timer = nil
        setStatus(status)
    }

    private func stopBoosting() {
        boosters.values.forEach { $0.stop() }
        boosters.removeAll()
    }

    /// Re-checks headroom and our gamma tables twice a second while boosting.
    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func setStatus(_ newStatus: Status) {
        if status != newStatus { status = newStatus }
    }
}
