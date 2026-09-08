import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: Engine!
    private var menuBar: MenuBarController!

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
            self?.engine.toggleEnabled()
        }
        HotkeyManager.shared.register(key: HotkeyManager.keyP, modifiers: HotkeyManager.cmdOpt) { [weak self] in
            self?.engine.togglePinFrontmost()
        }

        engine.start()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
