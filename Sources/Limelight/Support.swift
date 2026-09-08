import AppKit
import ApplicationServices

let ourPID = ProcessInfo.processInfo.processIdentifier

enum Log {
    static var verbose = UserDefaults.standard.bool(forKey: "verbose")
    static func d(_ s: @autoclosure () -> String) {
        guard verbose else { return }
        FileHandle.standardError.write(("[limelight] " + s() + "\n").data(using: .utf8)!)
    }
}

// MARK: - window graph

struct Win {
    let id: CGWindowID
    let pid: pid_t
    let owner: String
    let bounds: CGRect
}

enum WindowGraph {
    /// Front-to-back, current Space only, normal window layering
    static func onScreen() -> [Win] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return raw.compactMap { d in
            guard let id    = d[kCGWindowNumber as String] as? CGWindowID,
                  let pid   = d[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = d[kCGWindowLayer as String] as? Int, layer == 0,
                  let bd    = d[kCGWindowBounds as String] as? [String: Any],
                  let rect  = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  rect.width > 40, rect.height > 40
            else { return nil }
            return Win(id: id, pid: pid,
                       owner: d[kCGWindowOwnerName as String] as? String ?? "?",
                       bounds: rect)
        }
    }
}

// MARK: - screens

enum Screens {
    /// NSScreen frames are bottom-left origin; CGWindow bounds are top-left. Flip.
    static func cgFrame(of screen: NSScreen) -> CGRect {
        let flipRef = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let f = screen.frame
        return CGRect(x: f.minX, y: flipRef - f.maxY, width: f.width, height: f.height)
    }

    /// Index of the screen a window mostly lives on.
    static func index(of rect: CGRect, in frames: [CGRect]) -> Int? {
        var best: (idx: Int, area: CGFloat)?
        for (i, f) in frames.enumerated() {
            let s = f.intersection(rect).size
            let area = s.width * s.height
            if area > 0, best == nil || area > best!.area { best = (i, area) }
        }
        return best?.idx
    }
}

// MARK: - accessibility

enum AX {
    static var trusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrust() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func element(_ ref: CFTypeRef?) -> AXUIElement? {
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v
    }

    /// Private but ancient HIServices symbol; resolved at runtime so a missing
    /// symbol degrades to raising whole apps rather than failing to launch.
    private static let getWindowID: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
        // RTLD_DEFAULT — dlopen(nil) only searches the main executable's handle,
        // and this symbol lives in HIServices.
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let sym = dlsym(rtldDefault, "_AXUIElementGetWindow") else {
            Log.d("_AXUIElementGetWindow unavailable — falling back to whole-app raises")
            return nil
        }
        return unsafeBitCast(sym, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
    }()

    static var canTargetWindows: Bool { getWindowID != nil }

    /// CGWindowID -> AX element, for the windows of one app.
    static func windowMap(pid: pid_t) -> [CGWindowID: AXUIElement] {
        guard let fn = getWindowID else { return [:] }
        var out: [CGWindowID: AXUIElement] = [:]
        for w in windows(of: pid) where !isMinimized(w) {
            var id: CGWindowID = 0
            if fn(w, &id) == .success, id != 0 { out[id] = w }
        }
        return out
    }

    @discardableResult
    static func raise(_ w: AXUIElement) -> Bool {
        AXUIElementPerformAction(w, kAXRaiseAction as CFString) == .success
    }

    static func windows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        return attr(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? []
    }

    static func isMinimized(_ w: AXUIElement) -> Bool {
        (attr(w, kAXMinimizedAttribute as String) as? Bool) ?? false
    }

    /// Raises every non-minimised window of `pid`, back-to-front so the app's
    /// own frontmost window ends on top. Returns how many raises succeeded.
    @discardableResult
    static func raiseAll(pid: pid_t) -> Int {
        var ok = 0
        for w in windows(of: pid).reversed() where !isMinimized(w) {
            if AXUIElementPerformAction(w, kAXRaiseAction as CFString) == .success { ok += 1 }
        }
        return ok
    }

    static func frontmostIsFullscreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        guard let w = element(attr(app, kAXFocusedWindowAttribute as String)) else { return false }
        return (attr(w, "AXFullScreen") as? Bool) ?? false
    }
}

// MARK: - AX observers

private final class ObserverBox {
    let fire: () -> Void
    init(_ f: @escaping () -> Void) { fire = f }
}

private func axCallback(_ _o: AXObserver, _ _e: AXUIElement, _ _n: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    Unmanaged<ObserverBox>.fromOpaque(refcon).takeUnretainedValue().fire()
}

/// Watches one app for the events that can disturb the bright band.
/// Deliberately not subscribed to focused-window changes: our own raises cause
/// those, and they never change which app is bright.
final class AppObserver {
    private let observer: AXObserver
    private let element: AXUIElement
    private let box: ObserverBox
    private static let notifications = [
        kAXWindowCreatedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    init?(pid: pid_t, onChange: @escaping () -> Void) {
        var obs: AXObserver?
        guard AXObserverCreate(pid, axCallback, &obs) == .success, let obs else { return nil }
        observer = obs
        element = AXUIElementCreateApplication(pid)
        box = ObserverBox(onChange)
        let ref = Unmanaged.passUnretained(box).toOpaque()
        for n in Self.notifications {
            AXObserverAddNotification(observer, element, n as CFString, ref)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    deinit {
        for n in Self.notifications {
            AXObserverRemoveNotification(observer, element, n as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}
