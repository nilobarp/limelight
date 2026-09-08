import CoreGraphics

/// The band algebra, with every system dependency removed.
///
/// "Bright" means above the scrim, so the lit windows have to form a contiguous
/// band at the top of the stack - per screen, since the stack is global but each
/// scrim only covers one display.
enum Band {

    /// Windows that must be raised: a lit window with any dim window above it on
    /// the same screen. `windows` is front-to-back and excludes the scrims.
    static func outOfPosition(windows: [Win], lit: Set<pid_t>, screens: [CGRect]) -> [Win] {
        var out: [Win] = []
        for i in screens.indices {
            var sawDim = false
            for w in windows where Screens.index(of: w.bounds, in: screens) == i {
                if lit.contains(w.pid) {
                    if sawDim { out.append(w) }
                } else {
                    sawDim = true
                }
            }
        }
        return out
    }

    /// The window each screen's scrim should be ordered just below — the lowest
    /// lit window on that screen. nil means nothing is lit there, and the scrim
    /// should go to the front so the whole display dims.
    ///
    /// Indexed to match `screens`.
    static func anchors(windows: [Win], lit: Set<pid_t>, screens: [CGRect]) -> [Win?] {
        screens.indices.map { i in
            windows.last { lit.contains($0.pid) && Screens.index(of: $0.bounds, in: screens) == i }
        }
    }

    /// nil when the band is correct on every screen, otherwise what is wrong.
    /// `all` is front-to-back and *includes* the scrims; `scrims` holds one
    /// scrim window id per screen, indexed to match `screens`.
    static func verify(all: [Win], lit: Set<pid_t>,
                       screens: [CGRect], scrims: [CGWindowID]) -> String? {
        let scrimSet = Set(scrims)
        for (i, scrim) in scrims.enumerated() {
            guard let idx = all.firstIndex(where: { $0.id == scrim }) else {
                return "scrim \(i) not yet listed"
            }
            let onThisScreen = { (w: Win) in
                !scrimSet.contains(w.id) && Screens.index(of: w.bounds, in: screens) == i
            }
            if let leak = all[..<idx].first(where: { onThisScreen($0) && !lit.contains($0.pid) }) {
                return "\(leak.owner) undimmed on screen \(i)"
            }
            if let stuck = all[(idx + 1)...].first(where: { onThisScreen($0) && lit.contains($0.pid) }) {
                return "\(stuck.owner) stuck below scrim on screen \(i)"
            }
        }
        return nil
    }
}
