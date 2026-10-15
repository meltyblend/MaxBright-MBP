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

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { BrightnessController.shared.shutdown() }
    }
}
