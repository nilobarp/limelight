import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    private var engine: Engine!
    private var menuBar: MenuBarController!
    private var clickPin: ClickPin!

    public func applicationDidFinishLaunching(_ n: Notification) {
        // Two instances means two sets of scrims fighting over the z-order, and
        // each one reads the other's overlay as an undimmed leak.
        if let bid = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bid).count > 1 {
            Log.d("another instance is already running — exiting")
            NSApp.terminate(nil)
            return
        }

        engine = Engine(settings: .load())
        menuBar = MenuBarController(engine: engine)

        HotkeyManager.shared.register(key: HotkeyManager.keyD, modifiers: HotkeyManager.cmdOpt) { [weak self] in
            guard let self else { return }
            self.engine.toggleEnabled()
            HUD.shared.show(icon: nil,
                            title: self.engine.settings.enabled ? "Dimming on" : "Dimming off")
        }
        // ⌥⌘P used to pin the frontmost app, which is meaningless once the
        // stage is always lit. It now breaks up the stage's group instead.
        HotkeyManager.shared.register(key: HotkeyManager.keyP, modifiers: HotkeyManager.cmdOpt) { [weak self] in
            guard let self, let (name, wasGrouped) = self.engine.soloStage() else { return }
            HUD.shared.show(icon: self.engine.stageApp?.icon,
                            title: wasGrouped ? "\(name) is now solo" : "\(name) is already solo",
                            detail: wasGrouped ? "Group broken up" : nil)
        }

        clickPin = ClickPin(engine: engine) { [weak self] app in
            guard let self else { return }
            switch self.engine.toggleMembership(of: app) {
            case .added(let app, let stage):
                HUD.shared.show(icon: app.icon,
                                title: "Added \(app.localizedName ?? "app")",
                                detail: AX.trusted ? "Lit alongside \(stage)"
                                                   : "Needs Accessibility to take effect")
            case .removed(let app, let stage):
                HUD.shared.show(icon: app.icon,
                                title: "Removed \(app.localizedName ?? "app")",
                                detail: "No longer lit with \(stage)")
            case .notPossible:
                HUD.shared.show(icon: nil, title: "Can't group that app")
            }
        }
        clickPin.start()

        engine.start()

        // Nothing is stored on a genuinely first run, so explain the app.
        if UserDefaults.standard.data(forKey: "settings") == nil {
            AboutWindow.shared.show()
        }
    }

    /// Double-clicking a menu bar app in Finder otherwise does nothing visible
    /// at all — it just takes focus, which reads as "the screen dimmed and
    /// nothing happened".
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        AboutWindow.shared.show()
        return true
    }
}
