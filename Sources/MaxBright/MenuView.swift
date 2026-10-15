import ServiceManagement
import SwiftUI

struct MenuView: View {
    @ObservedObject var controller: BrightnessController
    @State private var loginStatus = LoginItem.status

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            boostSlider
            Divider()
            settings
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { loginStatus = LoginItem.status }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: controller.isBoosting ? "sun.max.fill" : "sun.max")
                .font(.system(size: 22))
                .foregroundStyle(controller.isBoosting ? Color.orange : Color.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("MaxBright").font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("Boost", isOn: $controller.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var boostSlider: some View {
        // The panel's luminance changes on its own (ambient light, brightness keys, EDR ramping), so poll it.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let standardNits = PanelLuminance.standardWhiteNits()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Maximum brightness")
                    Spacer()
                    if let standardNits {
                        Text("\(Int((standardNits * controller.appliedBoost).rounded())) nits")
                            .monospacedDigit()
                            .fontWeight(.medium)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "sun.min").foregroundStyle(.secondary)
                    Slider(value: $controller.boost, in: BrightnessController.boostRange)
                    Image(systemName: "sun.max").foregroundStyle(.secondary)
                }
                .disabled(!controller.isEnabled)
                Group {
                    if let standardNits {
                        Text("+\(boostPercent)% over the standard \(Int(standardNits.rounded())) nits")
                    } else {
                        Text("+\(boostPercent)% over the standard maximum")
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
    }

    private var boostPercent: Int {
        Int(((controller.boost - 1) * 100).rounded())
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at login", isOn: Binding(
                get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                set: { LoginItem.setEnabled($0); loginStatus = LoginItem.status }
            ))
            if loginStatus == .requiresApproval {
                Button("Approve in System Settings…") { LoginItem.openSystemSettings() }
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.leading, 20)
            }
            Toggle("Brightness keys go past maximum", isOn: $controller.useBrightnessKeys)
            if controller.useBrightnessKeys && controller.brightnessKeysNeedAccess {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Needs Accessibility access to read the keys.")
                        .foregroundStyle(.secondary)
                    Button("Grant access…") { controller.requestBrightnessKeyAccess() }
                        .buttonStyle(.link)
                }
                .font(.caption)
                .padding(.leading, 20)
            }
            Toggle("Pause on battery power", isOn: $controller.pauseOnBattery)
            Toggle("Pause when battery is below \(BrightnessController.lowBatteryThreshold)%",
                   isOn: $controller.pauseOnLowBattery)
                .disabled(controller.pauseOnBattery)
        }
        .toggleStyle(.checkbox)
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("⌃⌥⌘B  toggle")
                Text("⌃⌥⌘=  /  ⌃⌥⌘−  adjust")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private var statusText: String {
        switch controller.status {
        case .off:
            return "Off · standard brightness"
        case .engaging:
            return "Engaging XDR…"
        case .active(let effective):
            if effective < controller.boost - 0.01 {
                return "Active · held at +\(Int(((effective - 1) * 100).rounded()))% by display headroom"
            }
            return "Active · XDR brightness unlocked"
        case .paused(let reason):
            return "Paused · \(reason)"
        case .unsupported:
            return "No XDR display found"
        }
    }
}
