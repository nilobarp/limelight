import AppKit

/// Transient feedback for the global hotkeys, which are otherwise completely
/// silent - pinning the frontmost app changes nothing user can see until
/// switching away from it.
///
/// Deliberately a non-activating panel: taking focus would rebuild the bright
/// band and defeat the thing it is reporting on. It sits at `.statusBar` level,
/// which also keeps it out of `WindowGraph.onScreen()` (that filters to layer 0),
/// so it can never be mistaken for a window that ought to be dimmed.
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var dismiss: DispatchWorkItem?

    private let size = NSSize(width: 272, height: 76)
    private let hold = 1.15

    func show(icon: NSImage?, title: String, detail: String? = nil) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = makeContent(icon: icon, title: title, detail: detail)
        position(panel)

        dismiss?.cancel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.28
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }
        dismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.animationBehavior = .none
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.appearance = NSAppearance(named: .darkAqua)
        return p
    }

    private func makeContent(icon: NSImage?, title: String, detail: String?) -> NSView {
        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.appearance = NSAppearance(named: .darkAqua)
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 16
        bg.layer?.masksToBounds = true
        bg.layer?.borderWidth = 1
        bg.layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor

        let scrim = NSView(frame: bg.bounds)
        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor(white: 0.07, alpha: 0.55).cgColor
        bg.addSubview(scrim)

        var textX: CGFloat = 20
        if let icon {
            let iv = NSImageView(frame: NSRect(x: 18, y: (size.height - 38) / 2, width: 38, height: 38))
            iv.image = icon
            iv.imageScaling = .scaleProportionallyUpOrDown
            bg.addSubview(iv)
            textX = 68
        }

        let hasDetail = !(detail ?? "").isEmpty
        let width = size.width - textX - 16
        let titleY = hasDetail ? size.height / 2 : (size.height - 21) / 2

        let t = label(title, size: 15, weight: .semibold, color: .labelColor)
        t.frame = NSRect(x: textX, y: titleY, width: width, height: 21)
        bg.addSubview(t)

        if hasDetail {
            let d = label(detail!, size: 12, weight: .regular,
                          color: .secondaryLabelColor)
            d.frame = NSRect(x: textX, y: titleY - 19, width: width, height: 17)
            bg.addSubview(d)
        }
        return bg
    }

    private func label(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: s)
        f.font = .systemFont(ofSize: size, weight: weight)
        f.textColor = color
        f.lineBreakMode = .byTruncatingTail
        return f
    }

    /// Follows the mouse's screen, so on a multi-display setup it lands where
    /// you are looking rather than always on the primary.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let f = screen?.frame else { return }
        panel.setFrame(NSRect(x: f.midX - size.width / 2,
                              y: f.minY + f.height * 0.16,
                              width: size.width, height: size.height), display: false)
    }
}
