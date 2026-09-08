import AppKit

/// Shift-click any window that is not the app you are working in to pin or
/// unpin it, without focusing it.
///
/// The frontmost app is never intercepted. Shift-click means extend-selection
/// in most editors and terminals, and swallowing it inside the app you are
/// typing in would be intolerable. Every other window is fair game, because the
/// click would otherwise just raise something you have chosen to keep dim.
final class ClickPin {
    private let engine: Engine
    private let onHit: (NSRunningApplication) -> Void

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retry: Timer?

    init(engine: Engine, onHit: @escaping (NSRunningApplication) -> Void) {
        self.engine = engine
        self.onHit = onHit
    }

    func start() {
        ensureRunning()
        // The tap cannot exist before Accessibility is granted, and the setting
        // can be switched at any time, so re-evaluate periodically.
        retry = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.ensureRunning()
        }
    }

    private func ensureRunning() {
        let wanted = engine.settings.shiftClickToPin && AX.trusted
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: wanted)
            return
        }
        guard wanted else { return }

        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                             place: .headInsertEventTap,
                                             options: .defaultTap,
                                             eventsOfInterest: mask,
                                             callback: clickPinCallback,
                                             userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let src = CFMachPortCreateRunLoopSource(nil, newTap, 0)
        else {
            Log.d("shift-click tap could not be created")
            return
        }
        tap = newTap
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        Log.d("shift-click tap installed")
    }

    /// macOS disables a tap that takes too long in its callback, or on certain
    /// user input. It has to be switched back on explicitly.
    fileprivate func reenable() {
        guard let tap else { return }
        Log.d("shift-click tap was disabled by the system — re-enabling")
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Returns true when the click has been consumed.
    fileprivate func handle(_ event: CGEvent) -> Bool {
        guard engine.settings.shiftClickToPin else { return false }

        // Shift and nothing else: ⇧⌘click and friends belong to other apps.
        let f = event.flags
        guard f.contains(.maskShift),
              !f.contains(.maskCommand), !f.contains(.maskAlternate), !f.contains(.maskControl)
        else { return false }

        // CGEvent.location and kCGWindowBounds share a top-left origin space.
        let point = event.location
        guard let hit = WindowGraph.onScreen().first(where: {
            $0.pid != ourPID && $0.bounds.contains(point)
        }) else { return false }

        // Never the app being worked in: that is the stage, and shift-click
        // there means extend-selection.
        guard hit.pid != NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let app = NSRunningApplication(processIdentifier: hit.pid),
              app.bundleIdentifier != nil
        else { return false }

        // Event taps have a watchdog, so do the actual work off the callback.
        DispatchQueue.main.async { [weak self] in self?.onHit(app) }
        return true
    }
}

private func clickPinCallback(proxy: CGEventTapProxy, type: CGEventType,
                              event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let me = Unmanaged<ClickPin>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        me.reenable()
        return nil
    }
    guard type == .leftMouseDown else { return Unmanaged.passUnretained(event) }
    return me.handle(event) ? nil : Unmanaged.passUnretained(event)
}
