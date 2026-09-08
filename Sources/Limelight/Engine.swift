import AppKit

/// Rebuilds the bright band: bright windows raised until they sit contiguously
/// at the top of each screen's stack, then each screen's scrim slid just below
/// the lowest bright window on it.
final class Engine {
    var settings: Settings { didSet { onSettingsChanged(oldValue) } }
    var onStateChange: (() -> Void)?
    private(set) var suspendReason: String?

    private var overlays: OverlayController
    private var observers: [pid_t: AppObserver] = [:]
    private var lastGoodFrontPID: pid_t?
    private var strikes: [String: Int] = [:]

    private var settleTimer: Timer?
    private var settleDeadline = Date.distantPast
    private var reconcileScheduled = false
    private var inReconcile = false

    /// Ignore AX notifications we caused ourselves.
    private var fenceUntil = Date.distantPast
    private var lastRaiseAt = Date.distantPast
    private var lastRaiseSet: Set<pid_t> = []
    /// Display layout at the last rebuild, to tell a real screen change from the
    /// many other things that post didChangeScreenParameters.
    private var screenConfig: [CGRect] = []
    /// Anchor each scrim was last ordered against; 0 means "ordered to front".
    private var placedAnchor: [Int: CGWindowID] = [:]

    private let settleInterval = 0.025
    private let settleCeiling  = 0.6
    private let fenceDuration  = 0.5
    private let raiseCooldown  = 0.35
    private let strikeLimit    = 3

    init(settings: Settings) {
        self.settings = settings
        overlays = OverlayController(alpha: settings.alpha)
        screenConfig = NSScreen.screens.map(\.frame)
    }

    // MARK: lifecycle

    func start() {
        Log.d("accessibility trusted: \(AX.trusted) — pins \(AX.trusted ? "active" : "IGNORED")")

        let nc = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            nc.addObserver(self, selector: #selector(workspaceEvent), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.schedule("poll")
        }
        schedule("startup")
    }

    @objc private func workspaceEvent(_ n: Notification) { schedule("workspace") }

    @objc private func screensChanged() {
        // The notification fires for far more than display changes - showing the
        // HUD triggers it. Recreating both scrims tears down and re-adds two
        // full-screen windows, which can flash, so only do it for a real change.
        let now = NSScreen.screens.map(\.frame)
        guard now != screenConfig else {
            Log.d("screen parameters unchanged — not rebuilding")
            return
        }
        screenConfig = now
        overlays.rebuild()
        placedAnchor.removeAll()
        schedule("screens")
    }

    private func onSettingsChanged(_ old: Settings) {
        if settings.alpha != old.alpha { overlays.setAlpha(settings.alpha) }
        settings.save()
        schedule("settings")
        onStateChange?()
    }

    /// Coalesce every trigger onto one reconcile per runloop turn. Without this,
    /// AX callbacks reconcile synchronously and nest inside each other.
    private func schedule(_ reason: String) {
        guard !reconcileScheduled else { return }
        reconcileScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reconcileScheduled = false
            self.reconcile(reason)
        }
    }

    // MARK: bright set

    /// The app whose stage is showing - the last real frontmost app. Our own
    /// menu taking focus must not count, or opening it would blank the screen.
    var stageApp: NSRunningApplication? {
        lastGoodFrontPID.flatMap { NSRunningApplication(processIdentifier: $0) }
    }

    /// Bright apps ordered bottom-to-top: companions first, the stage last.
    private func computeBright() -> [pid_t] {
        // Our own scrims are layer-0 windows; without excluding them Limelight
        // looks like a windowed app and can become the stage itself.
        let withWindows = Set(WindowGraph.onScreen().filter { $0.pid != ourPID }.map(\.pid))

        var frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let f = frontPID, f != ourPID, withWindows.contains(f) {
            lastGoodFrontPID = f
        } else {
            // A windowless helper grabbed focus — keep the stage as it was.
            frontPID = lastGoodFrontPID.flatMap { withWindows.contains($0) ? $0 : nil }
        }
        guard let front = frontPID else { return [] }

        // Companions need Accessibility to be raised. Without it, lighting one
        // would drag the scrim down to its buried window and leave everything
        // above it undimmed - worse than ignoring the group.
        guard AX.trusted,
              let stage = NSRunningApplication(processIdentifier: front)?.bundleIdentifier
        else { return [front] }

        let quarantined = Set(settings.quarantined)
        let companions = Set(settings.companions(of: stage)).subtracting(quarantined)
        guard !companions.isEmpty else { return [front] }

        var bright: [pid_t] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier, companions.contains(bid) else { continue }
            let pid = app.processIdentifier
            if pid != front, withWindows.contains(pid) { bright.append(pid) }
        }
        bright.append(front)   // the stage sits on top
        return bright
    }

    // MARK: suspension

    private func currentSuspendReason() -> String? {
        if !settings.enabled { return "off" }
        if AX.frontmostIsFullscreen() { return "fullscreen" }
        let watch = Set(settings.captureWatchlist)
        guard !watch.isEmpty else { return nil }
        let onScreenPIDs = Set(WindowGraph.onScreen().map(\.pid))
        for app in NSWorkspace.shared.runningApplications {
            if let bid = app.bundleIdentifier, watch.contains(bid),
               onScreenPIDs.contains(app.processIdentifier) {
                return "screen capture (\(app.localizedName ?? bid))"
            }
        }
        return nil
    }

    // MARK: reconcile

    func reconcile(_ reason: String) {
        guard !inReconcile else { return }
        inReconcile = true
        defer { inReconcile = false }

        let was = suspendReason
        suspendReason = currentSuspendReason()
        if suspendReason != was { onStateChange?() }

        guard suspendReason == nil else {
            stopSettle()
            overlays.hide()
            placedAnchor.removeAll()
            syncObservers(for: [])
            return
        }

        let bright = computeBright()
        let set = Set(bright)
        syncObservers(for: set)

        // Without Accessibility we can still dim behind the frontmost app.
        if AX.trusted { raiseIfNeeded(bright) }

        place(set)
        if let problem = verify(set) {
            Log.d("[\(reason)] unsettled: \(problem)")
            startSettle(set)
        } else {
            stopSettle()
        }
    }

    // MARK: raising

    /// Windows that must move: a bright window with any dim window above it on
    /// the same screen. Computed per screen — the stack is global but the band
    /// only has to be contiguous within each display.
    private func windowsOutOfPosition(_ bright: Set<pid_t>) -> [Win] {
        let ids = overlays.ids
        let frames = overlays.cgFrames
        let all = WindowGraph.onScreen().filter { $0.pid != ourPID && !ids.contains($0.id) }

        var out: [Win] = []
        for i in overlays.overlays.indices {
            var sawDim = false
            for w in all where Screens.index(of: w.bounds, in: frames) == i {
                if bright.contains(w.pid) {
                    if sawDim { out.append(w) }
                } else {
                    sawDim = true
                }
            }
        }
        return out
    }

    private func raiseIfNeeded(_ bright: [pid_t]) {
        let set = Set(bright)
        let stragglers = windowsOutOfPosition(set)
        guard !stragglers.isEmpty else { return }

        // A raise that lands late can look like it failed; without a cooldown we
        // re-raise on the next tick and the app never stops reordering.
        if Date().timeIntervalSince(lastRaiseAt) < raiseCooldown, lastRaiseSet == set {
            Log.d("raise held off by cooldown")
            return
        }
        lastRaiseAt = Date()
        lastRaiseSet = set
        fenceUntil = Date().addingTimeInterval(fenceDuration)

        let order = WindowGraph.onScreen()
        let needed = Set(stragglers.map(\.id))
        var maps: [pid_t: [CGWindowID: AXUIElement]] = [:]
        var raisedForeign = false

        // Back-to-front, so the windows keep their relative order once raised.
        for w in order.filter({ needed.contains($0.id) }).reversed() {
            let map = maps[w.pid] ?? {
                let m = AX.windowMap(pid: w.pid)
                maps[w.pid] = m
                return m
            }()
            if let el = map[w.id] {
                AX.raise(el)                    // exactly one window
            } else {
                AX.raiseAll(pid: w.pid)         // no window targeting available
            }
            if w.pid != bright.last { raisedForeign = true }
        }

        // Frontmost wins: only needed if we lifted a pin past it.
        if raisedForeign, let front = bright.last { AX.raiseAll(pid: front) }
        Log.d("raised \(needed.count) window(s)")

        watchForFocusTheft(expectedFront: bright.last, pins: Set(bright.dropLast()))
    }

    private func watchForFocusTheft(expectedFront: pid_t?, pins: Set<pid_t>) {
        guard let expectedFront, !pins.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self,
                  let now = NSWorkspace.shared.frontmostApplication,
                  now.processIdentifier != expectedFront,
                  pins.contains(now.processIdentifier),
                  let bid = now.bundleIdentifier
            else { return }
            self.strike(bid, name: now.localizedName ?? bid)
        }
    }

    private func strike(_ bundleID: String, name: String) {
        let n = (strikes[bundleID] ?? 0) + 1
        strikes[bundleID] = n
        Log.d("focus theft strike \(n)/\(strikeLimit) — \(name)")
        guard n >= strikeLimit, !settings.quarantined.contains(bundleID) else { return }
        settings.quarantined.append(bundleID)
    }

    func unquarantine(_ bundleID: String) {
        strikes[bundleID] = 0
        settings.quarantined.removeAll { $0 == bundleID }
    }

    // MARK: placement

    /// `order(.below:)` makes a hidden window visible, so there is never a reason
    /// to orderFront first, doing so flashes the scrim over everything for a frame.
    private func place(_ bright: Set<pid_t>) {
        let frames = overlays.cgFrames
        let wins = WindowGraph.onScreen().filter { $0.pid != ourPID }

        for (i, overlay) in overlays.overlays.enumerated() {
            let anchor = wins.last {
                bright.contains($0.pid) && Screens.index(of: $0.bounds, in: frames) == i
            }
            let key = anchor?.id ?? 0
            if placedAnchor[i] == key, overlay.window.isVisible { continue }
            placedAnchor[i] = key
            if let anchor {
                overlay.window.order(.below, relativeTo: Int(anchor.id))
            } else {
                overlay.show()   // nothing bright on this screen — dim all of it
            }
        }
    }

    /// nil when the band is correct on every screen.
    private func verify(_ bright: Set<pid_t>) -> String? {
        let all = WindowGraph.onScreen()
        let frames = overlays.cgFrames

        for (i, overlay) in overlays.overlays.enumerated() {
            guard let idx = all.firstIndex(where: { $0.id == overlay.number }) else {
                return "scrim \(i) not yet listed"
            }
            let mine = { (w: Win) in w.pid != ourPID && Screens.index(of: w.bounds, in: frames) == i }
            if let leak = all[..<idx].first(where: { mine($0) && !bright.contains($0.pid) }) {
                return "\(leak.owner) undimmed on screen \(i)"
            }
            if let stuck = all[(idx + 1)...].first(where: { mine($0) && bright.contains($0.pid) }) {
                return "\(stuck.owner) stuck below scrim on screen \(i)"
            }
        }
        return nil
    }

    // MARK: settle loop

    private func startSettle(_ bright: Set<pid_t>) {
        settleDeadline = Date().addingTimeInterval(settleCeiling)
        guard settleTimer == nil else { return }
        settleTimer = Timer.scheduledTimer(withTimeInterval: settleInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.placedAnchor.removeAll()   // z-order moved under us; re-issue
            self.place(bright)
            if self.verify(bright) == nil {
                Log.d("settled")
                self.stopSettle()
            } else if Date() > self.settleDeadline {
                Log.d("settle ceiling hit — leaving it to the poll")
                self.stopSettle()
            }
        }
    }

    private func stopSettle() {
        settleTimer?.invalidate()
        settleTimer = nil
    }

    // MARK: observers

    private func syncObservers(for bright: Set<pid_t>) {
        for pid in observers.keys where !bright.contains(pid) { observers[pid] = nil }
        for pid in bright where observers[pid] == nil {
            observers[pid] = AppObserver(pid: pid) { [weak self] in
                guard let self else { return }
                guard Date() >= self.fenceUntil else {
                    Log.d("ax event inside fence — ignored")
                    return
                }
                self.schedule("ax")
            }
        }
    }

    // MARK: actions

    func toggleEnabled() {
        settings.enabled.toggle()
        if !settings.enabled { overlays.hide(); placedAnchor.removeAll() }
    }

    enum GroupChange {
        case added(NSRunningApplication, stage: String)
        case removed(NSRunningApplication, stage: String)
        case notPossible
    }

    /// Adds or removes `app` from the current stage's group.
    @discardableResult
    func toggleMembership(of app: NSRunningApplication) -> GroupChange {
        guard let bid = app.bundleIdentifier,
              let stage = stageApp,
              let stageBID = stage.bundleIdentifier,
              bid != stageBID
        else { return .notPossible }

        let stageName = stage.localizedName ?? stageBID
        let added = settings.toggleMember(bid, with: stageBID)
        // Grouping is what Accessibility is for; ask at the moment it matters.
        if added, !AX.trusted { AX.requestTrust() }
        return added ? .added(app, stage: stageName) : .removed(app, stage: stageName)
    }

    func isGrouped(_ bundleID: String) -> Bool {
        guard let stageBID = stageApp?.bundleIdentifier else { return false }
        return settings.companions(of: stageBID).contains(bundleID)
    }

    /// Breaks up the current stage's group, leaving it on its own.
    /// Returns the stage's name and whether it had a group to break up.
    @discardableResult
    func soloStage() -> (name: String, wasGrouped: Bool)? {
        guard let stage = stageApp, let bid = stage.bundleIdentifier else { return nil }
        let name = stage.localizedName ?? bid
        guard settings.groupIndex(containing: bid) != nil else { return (name, false) }
        settings.dissolveGroup(containing: bid)
        return (name, true)
    }

}
