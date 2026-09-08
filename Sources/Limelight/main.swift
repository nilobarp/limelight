import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: Engine!
    private var menuBar: MenuBarController!
    private var clickPin: ClickPin!

    func applicationDidFinishLaunching(_ n: Notification) {
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
        HotkeyManager.shared.register(key: HotkeyManager.keyP, modifiers: HotkeyManager.cmdOpt) { [weak self] in
            guard let self else { return }
            switch self.engine.togglePinFrontmost() {
            case .pinned(let app):
                HUD.shared.show(icon: app.icon,
                                title: "Pinned \(app.localizedName ?? "app")",
                                detail: AX.trusted ? "Stays lit" : "Needs Accessibility to take effect")
            case .unpinned(let app):
                HUD.shared.show(icon: app.icon,
                                title: "Unpinned \(app.localizedName ?? "app")",
                                detail: "Dims when not frontmost")
            case .notPinnable:
                HUD.shared.show(icon: nil, title: "Can't pin this app",
                                detail: "It has no bundle identifier")
            }
        }

        clickPin = ClickPin(engine: engine) { app, pinned in
            HUD.shared.show(icon: app.icon,
                            title: "\(pinned ? "Pinned" : "Unpinned") \(app.localizedName ?? "app")",
                            detail: pinned ? "Stays lit" : "Dims when not frontmost")
        }
        clickPin.start()

        engine.start()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
