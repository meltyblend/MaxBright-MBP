import AppKit
import MetalKit

/// A 1×1 point, fully transparent window whose Metal layer requests extended dynamic range.
///
/// While EDR content is on screen, macOS switches the XDR panel into EDR mode: the backlight is driven past
/// the SDR limit and headroom above SDR white becomes available. The window draws nothing visible.
final class EDRTriggerWindow: NSWindow {
    private let renderer: ClearRenderer

    init?(screen: NSScreen) {
        guard let device = MTLCreateSystemDefaultDevice(), let renderer = ClearRenderer(device: device) else { return nil }
        self.renderer = renderer
        let rect = Self.frame(on: screen)
        super.init(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        sharingType = .none

        let view = MTKView(frame: NSRect(origin: .zero, size: rect.size), device: device)
        view.delegate = renderer
        view.colorPixelFormat = .rgba16Float
        view.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.preferredFramesPerSecond = 1
        view.layer?.isOpaque = false
        (view.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
        contentView = view
    }

    /// Keeps the window parked in the bottom-left corner of `screen` and on screen.
    func pin(to screen: NSScreen) {
        let target = Self.frame(on: screen)
        if frame != target { setFrame(target, display: true) }
        if !isVisible { orderFrontRegardless() }
    }

    private static func frame(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 1, height: 1)
    }
}

private final class ClearRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue

    init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
