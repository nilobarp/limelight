import AppKit

/// One click-through scrim per screen, living at the normal window level.
/// Bright means "above this plane".
final class Overlay {
    let window: NSWindow

    init(screen: NSScreen, alpha: Double) {
        window = NSWindow(contentRect: screen.frame,
                          styleMask: .borderless,
                          backing: .buffered,
                          defer: false,
                          screen: screen)
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(alpha)
        window.level = .normal
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.setFrame(screen.frame, display: true)
    }

    var number: CGWindowID { CGWindowID(window.windowNumber) }
    func show() { window.orderFront(nil) }
    func hide() { window.orderOut(nil) }
    func setAlpha(_ a: Double) { window.backgroundColor = NSColor.black.withAlphaComponent(a) }
}

final class OverlayController {
    private(set) var overlays: [Overlay] = []
    private(set) var screens: [NSScreen] = []
    private var alpha: Double

    init(alpha: Double) {
        self.alpha = alpha
        rebuild()
    }

    var ids: Set<CGWindowID> { Set(overlays.map(\.number)) }
    var cgFrames: [CGRect] { screens.map(Screens.cgFrame(of:)) }

    func rebuild() {
        overlays.forEach { $0.hide() }
        screens = NSScreen.screens
        overlays = screens.map { Overlay(screen: $0, alpha: alpha) }
        Log.d("rebuilt \(overlays.count) overlay(s)")
    }

    func setAlpha(_ a: Double) {
        alpha = a
        overlays.forEach { $0.setAlpha(a) }
    }

    func show() { overlays.forEach { $0.show() } }
    func hide() { overlays.forEach { $0.hide() } }
}
