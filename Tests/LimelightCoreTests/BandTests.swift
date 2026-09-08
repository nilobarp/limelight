import XCTest
import CoreGraphics
@testable import LimelightCore

/// Two side-by-side displays, in the top-left origin space CGWindowList uses.
private let screenA = CGRect(x: 0, y: 0, width: 1000, height: 1000)
private let screenB = CGRect(x: 1000, y: 0, width: 1000, height: 1000)
private let screens = [screenA, screenB]

private func win(_ id: CGWindowID, _ pid: pid_t, _ owner: String, on screen: CGRect,
                 size: CGSize = CGSize(width: 400, height: 400)) -> Win {
    Win(id: id, pid: pid, owner: owner,
        bounds: CGRect(origin: CGPoint(x: screen.minX + 100, y: screen.minY + 100), size: size))
}

final class BandOutOfPositionTests: XCTestCase {

    func testContiguousBandNeedsNoRaises() {
        let windows = [win(1, 10, "Zed", on: screenA),
                       win(2, 11, "Ghostty", on: screenA),
                       win(3, 12, "Slack", on: screenA)]
        XCTAssertTrue(Band.outOfPosition(windows: windows, lit: [10, 11], screens: screens).isEmpty)
    }

    func testLitWindowBeneathADimOneMustMove() {
        let windows = [win(1, 12, "Slack", on: screenA),     // dim, on top
                       win(2, 10, "Zed", on: screenA)]       // lit, buried
        let moving = Band.outOfPosition(windows: windows, lit: [10], screens: screens)
        XCTAssertEqual(moving.map(\.id), [2])
    }

    /// Only the windows actually stranded are raised. Reordering every window of
    /// a multi-window app is what made Zed flicker.
    func testOnlyStrandedWindowsOfAMultiWindowAppMove() {
        let windows = [win(1, 10, "Zed", on: screenA),       // lit, already on top
                       win(2, 12, "Slack", on: screenA),     // dim
                       win(3, 10, "Zed", on: screenA)]       // lit, stranded
        let moving = Band.outOfPosition(windows: windows, lit: [10], screens: screens)
        XCTAssertEqual(moving.map(\.id), [3])
    }

    /// The stack is global but each scrim covers one display, so a dim window on
    /// the other screen must not count as blocking.
    func testDimWindowOnAnotherScreenDoesNotStrand() {
        let windows = [win(1, 12, "Slack", on: screenB),     // dim, other display
                       win(2, 10, "Zed", on: screenA)]       // lit
        XCTAssertTrue(Band.outOfPosition(windows: windows, lit: [10], screens: screens).isEmpty)
    }
}

final class BandAnchorTests: XCTestCase {

    func testAnchorIsTheLowestLitWindowOnTheScreen() {
        let windows = [win(1, 10, "Zed", on: screenA),
                       win(2, 11, "Ghostty", on: screenA),
                       win(3, 12, "Slack", on: screenA)]
        let anchors = Band.anchors(windows: windows, lit: [10, 11], screens: screens)
        XCTAssertEqual(anchors[0]?.id, 2, "scrim must sit below the lowest lit window")
    }

    /// The regression: one anchor chosen across the whole stack put the second
    /// display's scrim in the wrong place entirely.
    func testEachScreenGetsItsOwnAnchor() {
        let windows = [win(1, 10, "Zed", on: screenA),
                       win(2, 11, "Ghostty", on: screenB),
                       win(3, 12, "Slack", on: screenA)]
        let anchors = Band.anchors(windows: windows, lit: [10, 11], screens: screens)
        XCTAssertEqual(anchors[0]?.id, 1)
        XCTAssertEqual(anchors[1]?.id, 2)
    }

    func testNoAnchorWhenNothingIsLitOnThatScreen() {
        let windows = [win(1, 10, "Zed", on: screenA),
                       win(2, 12, "Slack", on: screenB)]
        let anchors = Band.anchors(windows: windows, lit: [10], screens: screens)
        XCTAssertEqual(anchors[0]?.id, 1)
        XCTAssertNil(anchors[1], "nothing lit there, so the whole display dims")
    }

    func testAnchorsAreIndexedPerScreenEvenWhenEmpty() {
        let anchors = Band.anchors(windows: [], lit: [], screens: screens)
        XCTAssertEqual(anchors.count, screens.count)
    }
}

final class BandVerifyTests: XCTestCase {
    // Scrim ids, one per screen, matching the `screens` order.
    private let scrims: [CGWindowID] = [100, 200]

    private func scrim(_ id: CGWindowID, covering screen: CGRect) -> Win {
        Win(id: id, pid: 99, owner: "Limelight", bounds: screen)
    }

    func testCorrectBandVerifies() {
        let all = [win(1, 10, "Zed", on: screenA),
                   scrim(100, covering: screenA),
                   win(2, 12, "Slack", on: screenA),
                   scrim(200, covering: screenB)]
        XCTAssertNil(Band.verify(all: all, lit: [10], screens: screens, scrims: scrims))
    }

    func testUndimmedWindowAboveTheScrimIsReported() {
        let all = [win(1, 12, "Slack", on: screenA),   // dim, but above the scrim
                   win(2, 10, "Zed", on: screenA),
                   scrim(100, covering: screenA),
                   scrim(200, covering: screenB)]
        let problem = Band.verify(all: all, lit: [10], screens: screens, scrims: scrims)
        XCTAssertEqual(problem, "Slack undimmed on screen 0")
    }

    func testLitWindowBelowTheScrimIsReported() {
        let all = [scrim(100, covering: screenA),
                   win(1, 10, "Zed", on: screenA),     // lit, but buried
                   scrim(200, covering: screenB)]
        let problem = Band.verify(all: all, lit: [10], screens: screens, scrims: scrims)
        XCTAssertEqual(problem, "Zed stuck below scrim on screen 0")
    }

    /// A window on screen B above screen A's scrim is not a leak: A's scrim does
    /// not cover it.
    func testWindowsOnOtherScreensAreIgnoredPerScrim() {
        let all = [win(1, 12, "Slack", on: screenB),   // dim, above A's scrim
                   scrim(100, covering: screenA),
                   scrim(200, covering: screenB),      // but below B's scrim
                   win(2, 10, "Zed", on: screenA)]
        // Zed is lit and below A's scrim, so that is the complaint — not Slack.
        let problem = Band.verify(all: all, lit: [10], screens: screens, scrims: scrims)
        XCTAssertEqual(problem, "Zed stuck below scrim on screen 0")
    }

    /// A freshly created scrim is not in the window list yet. That is the
    /// pre-commit read the settle loop exists to ride out, not a real failure.
    func testMissingScrimIsReportedRatherThanCrashing() {
        let all = [win(1, 10, "Zed", on: screenA)]
        XCTAssertEqual(Band.verify(all: all, lit: [10], screens: screens, scrims: scrims),
                       "scrim 0 not yet listed")
    }
}
