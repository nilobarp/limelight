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

        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        let quarantined = Set(s.quarantined)
        let stage = engine.stageApp
        let stageBID = stage?.bundleIdentifier
        let companions = stageBID.map { s.companions(of: $0) } ?? []

        menu.addItem(.separator())
        if let stage, let stageBID {
            menu.addItem(disabled("Stage: \(stage.localizedName ?? stageBID)"))
            if companions.isEmpty {
                menu.addItem(disabled("   nothing grouped yet"))
            }
            for bid in companions {
                let app = running.first { $0.bundleIdentifier == bid }
                let name = app?.localizedName ?? bid
                let title = quarantined.contains(bid) ? "⚠ \(name) — steals focus" : "✓ \(name)"
                let it = item(title, action: quarantined.contains(bid)
                                        ? #selector(retryApp(_:)) : #selector(toggleMember(_:)))
                it.representedObject = bid
                if quarantined.contains(bid) {
                    it.toolTip = "Limelight stopped raising this app because it grabs focus when raised. Click to retry."
                }
                menu.addItem(it)
            }
        } else {
            menu.addItem(disabled("No stage yet"))
        }

        menu.addItem(.separator())
        menu.addItem(disabled("Add to stage"))
        let grouped = Set(companions)
        for app in running {
            guard let bid = app.bundleIdentifier,
                  bid != stageBID, !grouped.contains(bid) else { continue }
            let it = item(app.localizedName ?? bid, action: #selector(toggleMember(_:)))
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
            let label = s.groups.isEmpty
                ? "Enable grouping (needs Accessibility)…"
                : "⚠ Groups inactive — grant Accessibility…"
            menu.addItem(item(label, action: #selector(grantAccessibility)))
        }
        let sc = item("Shift-click to group", action: #selector(toggleShiftClick))
        sc.state = s.shiftClickToPin ? .on : .off
        sc.toolTip = "Shift-click any window other than the one you're working in to add or remove it from the stage."
        menu.addItem(sc)

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

    @objc private func toggleMember(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String,
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid })
        else { return }
        engine.toggleMembership(of: app)
    }

    @objc private func retryApp(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        engine.unquarantine(bid)
    }

    @objc private func alphaChanged(_ sender: NSSlider) {
        engine.settings.alpha = sender.doubleValue
    }

    @objc private func toggleShiftClick() { engine.settings.shiftClickToPin.toggle() }

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
