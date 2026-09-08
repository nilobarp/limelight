import XCTest
@testable import LimelightCore

/// Settings decodes field by field with defaults rather than using the
/// synthesised decoder, which throws on any missing key. Adding one setting
/// would otherwise fail to decode every stored blob, and `Settings.load()`
/// falls back to defaults on a throw — silently wiping the user's groups, dim
/// level and quarantine list. That nearly happened once; these pin it down.
final class SettingsCodingTests: XCTestCase {

    private func decode(_ json: String) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }

    func testMissingKeysFallBackToDefaultsWithoutThrowing() throws {
        let s = try decode(#"{"alpha":0.9}"#)
        XCTAssertEqual(s.alpha, 0.9)
        XCTAssertTrue(s.enabled)
        XCTAssertTrue(s.shiftClickToPin)
        XCTAssertEqual(s.groups, [])
        XCTAssertFalse(s.captureWatchlist.isEmpty)
    }

    /// The exact shape that would have been on disk before groups existed.
    func testALegacyBlobStillDecodesAndKeepsEverythingElse() throws {
        let legacy = #"{"enabled":true,"alpha":0.9,"pins":["dev.zed.Zed"],"quarantined":[]}"#
        let s = try decode(legacy)
        XCTAssertEqual(s.alpha, 0.9, "an unknown key must not cost the user their dim level")
        XCTAssertEqual(s.groups, [], "pins are gone, but their absence is not an error")
    }

    func testAnEmptyObjectGivesCleanDefaults() throws {
        let s = try decode("{}")
        XCTAssertEqual(s.alpha, Settings().alpha)
        XCTAssertEqual(s.groups, [])
        XCTAssertEqual(s.quarantined, [])
    }

    func testRoundTripPreservesEverything() throws {
        var original = Settings()
        original.alpha = 0.42
        original.enabled = false
        original.shiftClickToPin = false
        original.toggleMember("com.mitchellh.ghostty", with: "dev.zed.Zed")
        original.quarantined = ["com.example.thief"]

        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(Settings.self, from: data)

        XCTAssertEqual(back.alpha, 0.42)
        XCTAssertFalse(back.enabled)
        XCTAssertFalse(back.shiftClickToPin)
        XCTAssertEqual(back.groups, original.groups)
        XCTAssertEqual(back.quarantined, ["com.example.thief"])
    }

    func testGroupsSurviveEncodingAsNestedArrays() throws {
        var s = Settings()
        s.toggleMember("b", with: "a")
        s.toggleMember("d", with: "c")
        let back = try JSONDecoder().decode(Settings.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(back.groups.count, 2)
        XCTAssertEqual(Set(back.companions(of: "a")), ["b"])
        XCTAssertEqual(Set(back.companions(of: "c")), ["d"])
    }
}
