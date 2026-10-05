import XCTest
@testable import ElectroMagnetCore

final class LayoutTests: XCTestCase {
    func window(id: UInt32 = 42, title: String = "Page", pid: Int32 = 10, start: Date? = Date(timeIntervalSince1970: 100), document: String? = nil) -> WindowIdentity {
        WindowIdentity(bundleID: "test.browser", appName: "Browser", pid: pid, processStarted: start, windowID: id, title: title, document: document)
    }
    func saved() -> SavedWindow {
        SavedWindow(identity: window(), displayUUID: "monitor-A", displayName: "Monitor A",
                    space: SpaceDestination(uuid: "space-A", sessionID: 6, ordinal: 2, bootSession: "boot-A"),
                    relativeFrame: WindowFrame(x: 200, y: 100, width: 700, height: 500))
    }
    func store() -> LayoutStore {
        LayoutStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("layouts.json"))
    }
    func testLiveBrowserMatchesAfterTitleChangesAndWindowReorder() {
        XCTAssertEqual(WindowMatcher.match(window(), in: [window(id: 43), window(title: "Different tab, same logged-in window")]), .found(1))
    }
    func testMissingWindowDoesNotMatchReplacementInSameProcess() {
        XCTAssertEqual(WindowMatcher.match(window(), in: [window(id: 99)]), .missing)
    }
    func testDuplicateTitlesAfterAppRestartAreAmbiguous() {
        XCTAssertEqual(WindowMatcher.match(window(), in: [window(id: 3, pid: 11), window(id: 4, pid: 11)]), .ambiguous)
    }
    func testUniqueDocumentAfterRestart() {
        XCTAssertEqual(WindowMatcher.match(window(document: "file:///report.txt"), in: [window(id: 3, pid: 11, document: "file:///other.txt"), window(id: 4, pid: 11, document: "file:///report.txt")]), .found(1))
    }
    func testAppPIDReuseRequiresNewLaunchIdentity() {
        XCTAssertEqual(WindowMatcher.match(window(title: "Original"), in: [window(id: 42, title: "Replacement", start: Date(timeIntervalSince1970: 200))]), .missing)
    }
    func testCannotAssignTwoSavedWindowsToOneCurrentWindow() {
        let old = [window(id: 1, pid: 1), window(id: 2, pid: 1)]
        XCTAssertEqual(WindowMatcher.matches(old, in: [window(id: 4, pid: 11)]), [.ambiguous, .ambiguous])
    }
    func testClosedAppSkipped() { XCTAssertEqual(WindowMatcher.match(window(), in: []), .missing) }
    func testEmptyTitleIsNotEvidenceAfterAppRestart() {
        XCTAssertEqual(WindowMatcher.match(window(title: ""), in: [window(title: "", pid: 11)]), .missing)
    }
    func testNegativeMonitorCoordinatesAndBounds() {
        let bounds = WindowFrame(x: -1920, y: -300, width: 1920, height: 1050)
        XCTAssertEqual(WindowFrame(x: -2100, y: -400, width: 800, height: 600).clamped(to: bounds), WindowFrame(x: -1920, y: -300, width: 800, height: 600))
    }
    func testDisconnectedMonitorFallbackFitsSmallerScreen() {
        let bounds = WindowFrame(x: 0, y: 25, width: 1000, height: 700)
        let requested = WindowFrame(x: 3000, y: 500, width: 1400, height: 900)
        XCTAssertEqual(requested.clamped(to: bounds), bounds)
    }
    func testMinimumSizeLargerThanScreenKeepsTitleBarReachable() {
        let bounds = WindowFrame(x: 0, y: 25, width: 1000, height: 700)
        let actual = WindowFrame(x: 2000, y: 1500, width: 1400, height: 900).reachable(in: bounds)
        XCTAssertEqual(actual, WindowFrame(x: 0, y: 25, width: 1400, height: 900))
    }
    func testTwoLayoutsPersistAcrossStoreRestartAndRetainAssignments() throws {
        let original = store(); defer { try? FileManager.default.removeItem(at: original.url.deletingLastPathComponent()) }
        let first = try original.save(name: "Work", windows: [saved()])
        var moved = saved(); moved.relativeFrame.x = 600
        let second = try original.save(name: "Writing", windows: [moved])
        let restarted = LayoutStore(url: original.url); try restarted.load()
        XCTAssertEqual(restarted.layouts, [first, second])
        XCTAssertEqual(restarted.layouts[0].windows[0].displayUUID, "monitor-A")
        XCTAssertEqual(restarted.layouts[0].windows[0].space.uuid, "space-A")
        // A temporary restore projection must not mutate the persisted destinations.
        _ = restarted.layouts[0].windows[0].relativeFrame.clamped(to: WindowFrame(x: 0, y: 0, width: 300, height: 200))
        let readBack = LayoutStore(url: original.url); try readBack.load()
        XCTAssertEqual(readBack.layouts, [first, second])
    }
    func testRenameOverwriteDeleteAndDuplicateProtection() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let one = try store.save(name: " One ", windows: [saved()])
        let two = try store.save(name: "Two", windows: [saved()])
        XCTAssertThrowsError(try store.rename(id: two.id, to: "one"))
        XCTAssertThrowsError(try store.save(name: "  ", windows: [saved()]))
        try store.rename(id: one.id, to: "Renamed")
        var updated = saved(); updated.relativeFrame.width = 300
        _ = try store.save(name: "Renamed", windows: [updated], replacing: one.id)
        try store.delete(id: two.id)
        let readBack = LayoutStore(url: store.url); try readBack.load()
        XCTAssertEqual(readBack.layouts.count, 1)
        XCTAssertEqual(readBack.layouts[0].id, one.id)
        XCTAssertEqual(readBack.layouts[0].windows[0].relativeFrame.width, 300)
    }
    func testCorruptFileRemainsUntouched() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bad = Data("invalid JSON".utf8); try bad.write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.url), bad)
    }
    func testFailedWriteLeavesPreviousInMemoryLayoutsIntact() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        _ = try store.save(name: "Original", windows: [saved()])
        try FileManager.default.removeItem(at: store.url)
        try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.save(name: "New", windows: [saved()]))
        XCTAssertEqual(store.layouts.map(\.name), ["Original"])
    }
    func testNewerFormatIsNotOverwrittenOnLoad() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data("{\"version\":999,\"layouts\":[]}".utf8); try data.write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.url), data)
    }
}
