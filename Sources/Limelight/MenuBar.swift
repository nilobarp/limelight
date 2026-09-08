import AppKit
import ServiceManagement

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine: Engine

    init(engine: Engine) {
        self.engine = engine
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
        engine.onStateChange = { [weak self] in self?.refreshIcon() }
    }

    private func refreshIcon() {
        let on = engine.settings.enabled && engine.suspendReason == nil
        let name = on ? "circle.lefthalf.filled" : "circle"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Limelight")
        statusItem.button?.image?.isTemplate = true
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = engine.settings

        if let reason = engine.suspendReason, reason != "off" {
            menu.addItem(disabled("⏸ Paused — \(reason)"))
        } else {
            menu.addItem(item(s.enabled ? "● Dimming on" : "○ Dimming off",
                              action: #selector(toggleEnabled), key: "d"))
        }

        menu.addItem(.separator())
        menu.addItem(disabled("Dim level"))
        menu.addItem(sliderItem())

        let pinned = Set(s.pins)
        let quarantined = Set(s.quarantined)
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        if !pinned.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled("Pinned"))
            for bid in s.pins {
                let name = running.first { $0.bundleIdentifier == bid }?.localizedName ?? bid
                if quarantined.contains(bid) {
                    let it = item("⚠ \(name) — steals focus", action: #selector(retryPin(_:)))
                    it.representedObject = bid
                    it.toolTip = "Limelight stopped raising this app because it grabs focus when raised. Click to retry."
                    menu.addItem(it)
                } else {
                    let it = item("✓ \(name)", action: #selector(togglePin(_:)))
                    it.representedObject = bid
                    menu.addItem(it)
                }
            }
        }

        menu.addItem(.separator())
        menu.addItem(disabled("Running"))
        for app in running {
            guard let bid = app.bundleIdentifier, !pinned.contains(bid) else { continue }
            let it = item(app.localizedName ?? bid, action: #selector(togglePin(_:)))
            it.representedObject = bid
            it.image = app.icon.map { icon in
                let c = icon.copy() as! NSImage
                c.size = NSSize(width: 16, height: 16)
                return c
            }
            menu.addItem(it)
        }

        menu.addItem(.separator())
        if !AX.trusted {
            let label = s.pins.isEmpty
                ? "Enable pinning (needs Accessibility)…"
                : "⚠ Pins inactive — grant Accessibility…"
            menu.addItem(item(label, action: #selector(grantAccessibility)))
        }
        let login = item("Launch at login", action: #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Quit Limelight", action: #selector(quit), key: "q"))
    }

    private func sliderItem() -> NSMenuItem {
        let slider = NSSlider(value: engine.settings.alpha, minValue: 0.1, maxValue: 0.9,
                              target: self, action: #selector(alphaChanged(_:)))
        slider.frame = NSRect(x: 20, y: 0, width: 160, height: 20)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        container.addSubview(slider)
        let it = NSMenuItem()
        it.view = container
        return it
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        return it
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    // MARK: actions

    @objc private func toggleEnabled() { engine.toggleEnabled() }

    @objc private func togglePin(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        engine.togglePin(bid)
    }

    @objc private func retryPin(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        engine.unquarantine(bid)
    }

    @objc private func alphaChanged(_ sender: NSSlider) {
        engine.settings.alpha = sender.doubleValue
    }

    @objc private func grantAccessibility() { AX.requestTrust() }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.d("login item toggle failed: \(error)")
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
