import XCTest
import CoreGraphics
@testable import LimelightCore

/// Which display a window belongs to. Everything per-screen in Band depends on
/// this, so a wrong answer here silently misplaces a scrim.
final class ScreensTests: XCTestCase {
    private let a = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    private let b = CGRect(x: 1000, y: 0, width: 1000, height: 1000)
    private var screens: [CGRect] { [a, b] }

    func testWindowFullyOnOneScreen() {
        let w = CGRect(x: 100, y: 100, width: 200, height: 200)
        XCTAssertEqual(Screens.index(of: w, in: screens), 0)
    }

    func testWindowOnTheSecondScreen() {
        let w = CGRect(x: 1200, y: 100, width: 200, height: 200)
        XCTAssertEqual(Screens.index(of: w, in: screens), 1)
    }

    /// A window dragged across the boundary belongs to whichever screen shows
    /// more of it — matching what the user perceives.
    func testStraddlingWindowGoesToTheScreenShowingMoreOfIt() {
        let mostlyB = CGRect(x: 900, y: 0, width: 400, height: 100)   // 100 on A, 300 on B
        XCTAssertEqual(Screens.index(of: mostlyB, in: screens), 1)
        let mostlyA = CGRect(x: 700, y: 0, width: 400, height: 100)   // 300 on A, 100 on B
        XCTAssertEqual(Screens.index(of: mostlyA, in: screens), 0)
    }

    func testWindowOffAllScreensHasNoIndex() {
        let w = CGRect(x: 5000, y: 5000, width: 100, height: 100)
        XCTAssertNil(Screens.index(of: w, in: screens))
    }

    func testNoScreensMeansNoIndex() {
        XCTAssertNil(Screens.index(of: a, in: []))
    }

    func testZeroAreaOverlapDoesNotCount() {
        let touching = CGRect(x: 1000, y: 0, width: 0, height: 100)
        XCTAssertNil(Screens.index(of: touching, in: screens))
    }
}
