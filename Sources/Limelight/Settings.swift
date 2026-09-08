import AppKit

struct Settings: Codable {
    var enabled = true
    var alpha: Double = 0.55
    /// Bundle IDs that stay lit alongside the frontmost app.
    var pins: [String] = []
    /// Pins we stopped raising because they steal focus.
    var quarantined: [String] = []
    /// Shift-click a non-frontmost window to add or remove it from the lit set.
    var shiftClickToPin = true
    /// Apps whose presence on screen suspends dimming. There is no public API
    /// to ask "am I being recorded", so this is a watchlist, not a detector.
    var captureWatchlist: [String] = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.obsproject.obs-studio",
        "com.apple.ScreenSharing",
    ]

    private enum CodingKeys: String, CodingKey {
        case enabled, alpha, pins, quarantined, shiftClickToPin, captureWatchlist
    }

    init() {}

    /// Decoded field by field with defaults. The synthesised decoder throws on a
    /// missing key, so adding one setting would otherwise fail to decode every
    /// stored blob and silently reset the user's pins.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        enabled          = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        alpha            = try c.decodeIfPresent(Double.self, forKey: .alpha) ?? d.alpha
        pins             = try c.decodeIfPresent([String].self, forKey: .pins) ?? d.pins
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
