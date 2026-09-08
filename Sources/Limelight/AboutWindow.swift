import AppKit

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Limelight has no Dock icon and no windows, so opening it from Finder did
/// nothing visible except take focus - leaving the user looking at a dimmed
/// screen with no way to tell whether anything had happened. This is what it
/// shows.
final class AboutWindow: NSObject, NSWindowDelegate {
    static let shared = AboutWindow()

    private var window: NSWindow?
    private var statusLabel: NSTextField?
    private var grantButton: NSButton?

    func show() {
        if window == nil { window = build() }
        refreshStatus()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func refreshStatus() {
        let ok = AX.trusted
        statusLabel?.stringValue = ok
            ? "Accessibility granted — grouping is active."
            : "Accessibility not granted — groups are ignored."
        statusLabel?.textColor = ok ? .secondaryLabelColor : .systemOrange
        grantButton?.isHidden = ok
    }

    // MARK: build

    private func build() -> NSWindow {
        let size = NSSize(width: 460, height: 430)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "About Limelight"
        w.isReleasedWhenClosed = false
        w.delegate = self

        let root = FlippedView(frame: NSRect(origin: .zero, size: size))
        var y: CGFloat = 28
        let margin: CGFloat = 28
        let textX: CGFloat = 116
        let textW = size.width - textX - margin

        if let icon = NSApp.applicationIconImage {
            let iv = NSImageView(frame: NSRect(x: margin, y: y, width: 68, height: 68))
            iv.image = icon
            iv.imageScaling = .scaleProportionallyUpOrDown
            root.addSubview(iv)
        }

        let name = label("Limelight", size: 24, weight: .semibold, color: .labelColor)
        name.frame = NSRect(x: textX, y: y - 2, width: textW, height: 30)
        root.addSubview(name)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let sub = label("Version \(version)", size: 12, weight: .regular, color: .secondaryLabelColor)
        sub.frame = NSRect(x: textX, y: y + 30, width: textW, height: 17)
        root.addSubview(sub)

        y += 92
        let blurb = label("Stage Manager's focus model without the strip, the animations "
                        + "or the layout shifts. The app you're working in stays lit along "
                        + "with anything grouped with it; everything else fades.",
                          size: 13, weight: .regular, color: .labelColor)
        blurb.frame = NSRect(x: margin, y: y, width: size.width - margin * 2, height: 56)
        blurb.lineBreakMode = .byWordWrapping
        blurb.maximumNumberOfLines = 4
        root.addSubview(blurb)

        y += 70
        root.addSubview(separator(y: y, width: size.width, margin: margin))

        y += 16
        root.addSubview(header("Gestures", y: y, x: margin))
        y += 24
        for (keys, what) in [
            ("⇧ click", "add a window to the current group, or remove it"),
            ("⌥⌘P", "break up the group, leaving the current app on its own"),
            ("⌥⌘D", "turn dimming off and on"),
        ] {
            let k = label(keys, size: 12, weight: .medium, color: .labelColor)
            k.frame = NSRect(x: margin, y: y, width: 74, height: 18)
            root.addSubview(k)
            let v = label(what, size: 12, weight: .regular, color: .secondaryLabelColor)
            v.frame = NSRect(x: margin + 82, y: y, width: size.width - margin * 2 - 82, height: 18)
            root.addSubview(v)
            y += 23
        }

        y += 10
        root.addSubview(separator(y: y, width: size.width, margin: margin))

        y += 18
        let status = label("", size: 12, weight: .regular, color: .secondaryLabelColor)
        status.frame = NSRect(x: margin, y: y, width: size.width - margin * 2, height: 34)
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 2
        root.addSubview(status)
        statusLabel = status

        let grant = NSButton(title: "Grant Accessibility…", target: self,
                             action: #selector(grant))
        grant.bezelStyle = .rounded
        grant.frame = NSRect(x: margin, y: y + 38, width: 180, height: 24)
        root.addSubview(grant)
        grantButton = grant

        w.contentView = root
        return w
    }

    private func label(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: s)
        f.font = .systemFont(ofSize: size, weight: weight)
        f.textColor = color
        f.isSelectable = false
        f.drawsBackground = false
        f.isBezeled = false
        return f
    }

    private func header(_ s: String, y: CGFloat, x: CGFloat) -> NSTextField {
        let f = label(s.uppercased(), size: 10, weight: .semibold, color: .tertiaryLabelColor)
        f.frame = NSRect(x: x, y: y, width: 200, height: 14)
        return f
    }

    private func separator(y: CGFloat, width: CGFloat, margin: CGFloat) -> NSBox {
        let b = NSBox(frame: NSRect(x: margin, y: y, width: width - margin * 2, height: 1))
        b.boxType = .separator
        return b
    }

    @objc private func grant() {
        AX.requestTrust()
        // The prompt is answered in System Settings, so poll briefly for the flip.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.refreshStatus()
            if AX.trusted { t.invalidate() }
        }
    }
}
