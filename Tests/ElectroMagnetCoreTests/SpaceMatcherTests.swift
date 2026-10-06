import XCTest
@testable import ElectroMagnetCore

final class SpaceMatcherTests: XCTestCase {
    private func desktop(_ id: UInt64, _ uuid: String?, monitor: String = "monitor-A", position: Int = 1) -> DesktopSpace {
        DesktopSpace(id: id, uuid: uuid, displayUUID: monitor, ordinal: position, isCurrent: position == 1)
    }
    private func saved(uuid: String? = "original-space", id: UInt64 = 10, position: Int = 3, boot: String = "old-boot") -> SpaceDestination {
        SpaceDestination(uuid: uuid, sessionID: id, ordinal: position, bootSession: boot)
    }
    func testSurvivingUUIDTakesPriorityAfterDesktopReordering() {
        let current = [desktop(20, "replacement", position: 3), desktop(21, "original-space", position: 1)]
        XCTAssertEqual(SpaceMatcher.match(saved(), displayUUID: "monitor-A", in: current, bootSession: "new-boot"), .identity(1))
    }
    func testUUIDAndMonitorComparisonsAreCaseInsensitive() {
        let current = [desktop(20, "ORIGINAL-SPACE", monitor: "MONITOR-A")]
        XCTAssertEqual(SpaceMatcher.match(saved(), displayUUID: "monitor-a", in: current, bootSession: "new-boot"), .identity(0))
    }
    func testSessionIdentityWorksWithinSameBootWhenUUIDIsUnavailable() {
        let current = [desktop(10, nil), desktop(20, nil, position: 3)]
        XCTAssertEqual(SpaceMatcher.match(saved(uuid: nil), displayUUID: "monitor-A", in: current, bootSession: "old-boot"), .identity(0))
    }
    func testMissingIdentityUsesSavedPositionOnOriginalMonitorAfterNewBoot() {
        let current = [desktop(20, "other-monitor-space", monitor: "monitor-B", position: 3),
                       desktop(21, "new-first-space"), desktop(22, "new-third-space", position: 3)]
        XCTAssertEqual(SpaceMatcher.match(saved(), displayUUID: "monitor-A", in: current, bootSession: "new-boot"), .position(2))
    }
    func testChangedUUIDDoesNotTrustReusedSessionIDEvenWithinSameBoot() {
        let current = [desktop(10, "different-space"), desktop(20, "new-third-space", position: 3)]
        XCTAssertEqual(SpaceMatcher.match(saved(), displayUUID: "monitor-A", in: current, bootSession: "old-boot"), .position(1))
    }
    func testSessionIDIsNotTrustedAcrossBoots() {
        let current = [desktop(10, nil), desktop(20, nil, position: 3)]
        XCTAssertEqual(SpaceMatcher.match(saved(uuid: nil), displayUUID: "monitor-A", in: current, bootSession: "new-boot"), .position(1))
    }
    func testMissingDesktopPositionDoesNotSelectAnotherPosition() {
        let current = [desktop(20, "new-first-space"), desktop(21, "new-second-space", position: 2)]
        XCTAssertEqual(SpaceMatcher.match(saved(), displayUUID: "monitor-A", in: current, bootSession: "new-boot"), .missing)
    }
    func testDisconnectedMonitorCannotBorrowDesktopPositionFromFallbackMonitor() {
        let current = [desktop(20, "new-third-space", monitor: "monitor-B", position: 3)]
        XCTAssertEqual(SpaceMatcher.match(saved(), displayUUID: "monitor-B", in: current, bootSession: "new-boot", allowPosition: false), .missing)
        XCTAssertEqual(SpaceMatcher.match(saved(), displayUUID: "monitor-A", in: current, bootSession: "new-boot"), .missing)
    }
    func testEmptyBootSessionIsNotEvidenceForSessionIdentity() {
        let current = [desktop(10, nil)]
        XCTAssertEqual(SpaceMatcher.match(saved(uuid: nil, boot: ""), displayUUID: "monitor-A", in: current, bootSession: "", allowPosition: false), .missing)
    }
    func testInvalidOrDuplicateDesktopPositionCannotSelectAWindowDestination() {
        let current = [desktop(20, "new-first"), desktop(21, "duplicate-first")]
        XCTAssertEqual(SpaceMatcher.match(saved(position: 1), displayUUID: "monitor-A", in: current, bootSession: "new-boot"), .missing)
        XCTAssertEqual(SpaceMatcher.match(saved(position: 0), displayUUID: "monitor-A", in: current, bootSession: "new-boot"), .missing)
    }
}
