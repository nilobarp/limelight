import XCTest
@testable import LimelightCore

/// The group model: an app belongs to at most one group, and the lit set is the
/// stage plus its group.
final class SettingsGroupTests: XCTestCase {
    private let zed = "dev.zed.Zed"
    private let ghostty = "com.mitchellh.ghostty"
    private let slack = "com.tinyspeck.slackmacgap"
    private let linear = "com.linear"

    func testGroupingTwoAppsCreatesAPair() {
        var s = Settings()
        XCTAssertTrue(s.toggleMember(ghostty, with: zed))
        XCTAssertEqual(s.groups.count, 1)
        XCTAssertEqual(Set(s.groups[0]), [zed, ghostty])
    }

    func testGroupsAreSymmetric() {
        var s = Settings()
        s.toggleMember(ghostty, with: zed)
        XCTAssertEqual(s.companions(of: zed), [ghostty])
        XCTAssertEqual(s.companions(of: ghostty), [zed])
    }

    func testCompanionsExcludeTheStageItself() {
        var s = Settings()
        s.toggleMember(ghostty, with: zed)
        s.toggleMember(slack, with: zed)
        XCTAssertFalse(s.companions(of: zed).contains(zed))
        XCTAssertEqual(Set(s.companions(of: zed)), [ghostty, slack])
    }

    func testTogglingAMemberOffRemovesIt() {
        var s = Settings()
        s.toggleMember(ghostty, with: zed)
        s.toggleMember(slack, with: zed)
        XCTAssertFalse(s.toggleMember(slack, with: zed))
        XCTAssertEqual(s.companions(of: zed), [ghostty])
    }

    /// A group of one is just an app, so it should not linger as a group.
    func testGroupDissolvesWhenItWouldDropToOneMember() {
        var s = Settings()
        s.toggleMember(ghostty, with: zed)
        s.toggleMember(ghostty, with: zed)
        XCTAssertTrue(s.groups.isEmpty)
        XCTAssertEqual(s.companions(of: zed), [])
    }

    /// An app belongs to one group at a time; joining a new one must detach it
    /// from the old, or it would be lit on two unrelated stages.
    func testJoiningAnotherGroupDetachesFromTheFirst() {
        var s = Settings()
        s.toggleMember(ghostty, with: zed)
        s.toggleMember(slack, with: zed)          // zed + ghostty + slack
        s.toggleMember(slack, with: linear)       // slack moves to linear
        XCTAssertEqual(Set(s.companions(of: zed)), [ghostty])
        XCTAssertEqual(s.companions(of: linear), [slack])
        XCTAssertEqual(s.groups.count, 2)
    }

    func testMovingTheLastCompanionDissolvesTheOldGroup() {
        var s = Settings()
        s.toggleMember(ghostty, with: zed)        // zed + ghostty
        s.toggleMember(ghostty, with: linear)     // ghostty moves away
        XCTAssertEqual(s.companions(of: zed), [])
        XCTAssertEqual(s.companions(of: linear), [ghostty])
        XCTAssertEqual(s.groups.count, 1, "zed's group should be gone, not left as a singleton")
    }

    func testAnAppCannotBeGroupedWithItself() {
        var s = Settings()
        XCTAssertFalse(s.toggleMember(zed, with: zed))
        XCTAssertTrue(s.groups.isEmpty)
    }

    func testDissolveBreaksUpTheWholeGroup() {
        var s = Settings()
        s.toggleMember(ghostty, with: zed)
        s.toggleMember(slack, with: zed)
        XCTAssertTrue(s.dissolveGroup(containing: ghostty))
        XCTAssertTrue(s.groups.isEmpty)
        XCTAssertEqual(s.companions(of: zed), [])
    }

    func testDissolveReportsWhenThereWasNoGroup() {
        var s = Settings()
        XCTAssertFalse(s.dissolveGroup(containing: zed))
    }

    func testUngroupedAppHasNoCompanions() {
        var s = Settings()
        s.toggleMember(ghostty, with: zed)
        XCTAssertEqual(s.companions(of: slack), [])
    }
}
