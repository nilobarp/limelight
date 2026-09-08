import AppKit

struct Settings: Codable {
    var enabled = true
    var alpha: Double = 0.55
    /// Apps that stay lit together, Stage Manager style. An app belongs to at
    /// most one group, and the lit set is the current app plus its group.
    var groups: [[String]] = []
    /// Apps we stopped raising because they steal focus.
    var quarantined: [String] = []
    /// Shift-click a non-frontmost window to add or remove it from the group.
    var shiftClickToPin = true
    /// Apps whose presence on screen suspends dimming. There is no public API
    /// to ask "am I being recorded", so this is a watchlist, not a detector.
    var captureWatchlist: [String] = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.cisco.webexmeetingsapp",
        "com.obsproject.obs-studio",
        "com.apple.ScreenSharing",
    ]

    // MARK: groups

    func groupIndex(containing bid: String) -> Int? {
        groups.firstIndex { $0.contains(bid) }
    }

    /// Apps lit alongside `stage`, not including `stage` itself.
    func companions(of stage: String) -> [String] {
        guard let i = groupIndex(containing: stage) else { return [] }
        return groups[i].filter { $0 != stage }
    }

    /// Adds `bid` to `stage`'s group, or removes it if already there.
    /// Returns true when the app ended up grouped.
    @discardableResult
    mutating func toggleMember(_ bid: String, with stage: String) -> Bool {
        guard bid != stage else { return false }

        if let i = groupIndex(containing: stage), groups[i].contains(bid) {
            remove(bid, fromGroupAt: i)
            return false
        }
        // An app belongs to one group at a time, so detach it first.
        detach(bid)
        if let i = groupIndex(containing: stage) {
            groups[i].append(bid)
        } else {
            groups.append([stage, bid])
        }
        return true
    }

    mutating func detach(_ bid: String) {
        guard let i = groupIndex(containing: bid) else { return }
        remove(bid, fromGroupAt: i)
    }

    /// Breaks up `bid`'s group entirely. Returns true if there was one.
    @discardableResult
    mutating func dissolveGroup(containing bid: String) -> Bool {
        guard let i = groupIndex(containing: bid) else { return false }
        groups.remove(at: i)
        return true
    }

    private mutating func remove(_ bid: String, fromGroupAt i: Int) {
        groups[i].removeAll { $0 == bid }
        // A group of one is just an app.
        if groups[i].count < 2 { groups.remove(at: i) }
    }

    // MARK: persistence

    private enum CodingKeys: String, CodingKey {
        case enabled, alpha, groups, quarantined, shiftClickToPin, captureWatchlist
    }

    init() {}

    /// Decoded field by field with defaults. The synthesised decoder throws on a
    /// missing key, so adding one setting would otherwise fail to decode every
    /// stored blob and silently reset everything else.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        enabled          = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        alpha            = try c.decodeIfPresent(Double.self, forKey: .alpha) ?? d.alpha
        groups           = try c.decodeIfPresent([[String]].self, forKey: .groups) ?? d.groups
        quarantined      = try c.decodeIfPresent([String].self, forKey: .quarantined) ?? d.quarantined
        shiftClickToPin  = try c.decodeIfPresent(Bool.self, forKey: .shiftClickToPin) ?? d.shiftClickToPin
        captureWatchlist = try c.decodeIfPresent([String].self, forKey: .captureWatchlist) ?? d.captureWatchlist
    }

    private static let key = "settings"

    static func load() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return s
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
