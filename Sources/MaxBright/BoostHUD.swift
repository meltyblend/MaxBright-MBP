import AppKit
import SwiftUI

/// A small on-screen indicator, like the system brightness HUD, shown when the boost changes from the keyboard.
@MainActor
final class BoostHUD {
    private static let cornerRadius: CGFloat = 16

    private let panel: NSPanel
    private let readings = HUDReadings()
    private var refreshTimer: Timer?
    private var hideTask: Task<Void, Never>?

    init(controller: BrightnessController) {
        let host = NSHostingView(rootView: HUDView(controller: controller, readings: readings))
        let size = host.fittingSize

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        host.frame = background.bounds
        host.autoresizingMask = [.width, .height]
        background.addSubview(host)

        panel = NSPanel(contentRect: background.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = background
    }

    func show() {
        guard let screen = NSScreen.screens.first(where: { $0.displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false })
                ?? NSScreen.main else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                                     y: screen.frame.minY + screen.frame.height * 0.12))
        // A new animation on alphaValue replaces a fade-out that is still running.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()

        // The brightness and nits change outside the app (the setting applies a moment after it is set, and the
        // panel ramps in and out of EDR mode), so keep reading them while the HUD is up.
        readings.update()
        if refreshTimer == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.readings.update() }
            }
            RunLoop.main.add(timer, forMode: .common)
            refreshTimer = timer
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                self.panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            self.panel.orderOut(nil)
            self.refreshTimer?.invalidate()
            self.refreshTimer = nil
        }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// The display values the HUD shows that the app doesn't own, refreshed explicitly so the view redraws when they
/// change. (A TimelineView in this never-key panel doesn't reliably tick.)
@MainActor
private final class HUDReadings: ObservableObject {
    @Published private(set) var brightness: Double = 0
    @Published private(set) var standardNits: Double?

    func update() {
        let brightness = Double(PanelLuminance.userBrightness() ?? 0)
        let standardNits = PanelLuminance.standardWhiteNits()
        if brightness != self.brightness { self.brightness = brightness }
        if standardNits != self.standardNits { self.standardNits = standardNits }
    }
}

private struct HUDView: View {
    @ObservedObject var controller: BrightnessController
    @ObservedObject var readings: HUDReadings

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: controller.isBoosting ? "sun.max.fill" : "sun.max")
                .font(.system(size: 26))
                .foregroundStyle(controller.isBoosting ? Color.orange : Color.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(controller.isEnabled ? "XDR boost" : "Brightness").font(.headline)
                    Spacer()
                    Text(detail)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                // Drawn by hand: a ProgressView in a window that never becomes key renders grey.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(controller.isEnabled ? Color.orange : Color.primary)
                            .frame(width: proxy.size.width * level)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 280)
    }

    /// The boost while it is on, otherwise the system brightness setting.
    private var level: Double {
        let range = BrightnessController.boostRange
        return controller.isEnabled
            ? (controller.boost - range.lowerBound) / (range.upperBound - range.lowerBound)
            : readings.brightness
    }

    private var detail: String {
        switch controller.status {
        case .paused(let reason):
            return "Paused · \(reason)"
        case .unsupported:
            return "No XDR display"
        case .off, .engaging, .active:
            let amount = controller.isEnabled
                ? "+\(Int(((controller.boost - 1) * 100).rounded()))%"
                : "\(Int((level * 100).rounded()))%"
            guard let nits = readings.standardNits else { return amount }
            return "\(amount) · \(Int((nits * controller.appliedBoost).rounded())) nits"
        }
    }
}
