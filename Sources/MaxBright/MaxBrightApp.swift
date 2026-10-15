import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct MaxBrightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var controller = BrightnessController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller)
        } label: {
            Image(systemName: controller.isBoosting ? "sun.max.fill" : "sun.max")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeys: HotKeyCenter?
    private var hud: BoostHUD?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let controller = BrightnessController.shared
            let hud = BoostHUD(controller: controller)
            controller.onBrightnessKey = { hud.show() }
            controller.start()

            let modifiers = controlKey | optionKey | cmdKey
            let hotKeys = HotKeyCenter()
            hotKeys.register(keyCode: kVK_ANSI_B, modifiers: modifiers) {
                MainActor.assumeIsolated {
                    controller.isEnabled.toggle()
                    hud.show()
                }
            }
            hotKeys.register(keyCode: kVK_ANSI_Equal, modifiers: modifiers) {
                MainActor.assumeIsolated {
                    controller.stepBoost(up: true)
                    hud.show()
                }
            }
            hotKeys.register(keyCode: kVK_ANSI_Minus, modifiers: modifiers) {
                MainActor.assumeIsolated {
                    controller.stepBoost(up: false)
                    hud.show()
                }
            }
            self.hotKeys = hotKeys
            self.hud = hud
        }
    }

    /// Handles the links the `maxbright` command sends: maxbright://on, maxbright://off, maxbright://toggle,
    /// maxbright://boost/60 (percent above the standard maximum) and maxbright://quit. Shortcuts and launchers can
    /// use them too.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            let controller = BrightnessController.shared
            for url in urls where url.scheme == "maxbright" {
                switch url.host {
                case "quit":
                    NSApp.terminate(nil)
                    return
                case "on":
                    controller.isEnabled = true
                case "off":
                    controller.isEnabled = false
                case "toggle":
                    controller.isEnabled.toggle()
                case "boost":
                    guard let percent = Double(url.lastPathComponent) else { continue }
                    controller.boost = 1 + percent / 100
                    controller.isEnabled = true
                default:
                    continue
                }
                hud?.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { BrightnessController.shared.shutdown() }
    }
}
