import AppKit

struct Settings: Codable {
    var enabled = true
    var alpha: Double = 0.55
    /// Bundle IDs that stay lit alongside the frontmost app.
    var pins: [String] = []
    /// Pins we stopped raising because they steal focus.
    var quarantined: [String] = []
    /// Apps whose presence on screen suspends dimming. There is no public API
    /// to ask "am I being recorded", so this is a watchlist, not a detector.
    var captureWatchlist: [String] = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.obsproject.obs-studio",
        "com.apple.ScreenSharing",
    ]

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
