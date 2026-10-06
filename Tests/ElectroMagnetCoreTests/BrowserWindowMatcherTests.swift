import XCTest
@testable import ElectroMagnetCore

final class BrowserWindowMatcherTests: XCTestCase {
    private func chrome(_ title: String, pid: Int32 = 10, id: UInt32 = 1, document: String? = nil) -> WindowIdentity {
        WindowIdentity(bundleID: "com.google.Chrome", appName: "Google Chrome", pid: pid,
                       processStarted: Date(timeIntervalSince1970: Double(pid)), windowID: id,
                       title: title, document: document)
    }

    func testExistingChromeLayoutsMatchUniqueProfilesAfterRelaunchAndTabChanges() {
        let saved = [chrome("Search results - Gmail - High memory usage - 1.8 GB - Google Chrome – Personal"),
                     chrome("Inbox - Gmail - Google Chrome – Work", id: 2)]
        let current = [chrome("Calendar - Google Chrome – Work", pid: 20, id: 30, document: "https://example.com/calendar"),
                       chrome("A different tab - Google Chrome – Personal", pid: 20, id: 31)]
        XCTAssertEqual(WindowMatcher.matches(saved, in: current), [.found(1), .found(0)])
    }

    func testIdenticalURLsInDifferentProfilesDoNotSelectTheWrongAccount() {
        let saved = chrome("Inbox - Google Chrome – Work", document: "https://example.com/inbox")
        let current = [chrome("Inbox - Google Chrome – Personal", pid: 20, id: 2, document: "https://example.com/inbox"),
                       chrome("Chat - Google Chrome – Work", pid: 20, id: 3, document: "https://example.com/chat")]
        XCTAssertEqual(WindowMatcher.match(saved, in: current), .found(1))
    }

    func testMissingProfileDoesNotFallBackToAnotherProfileWithTheSameURL() {
        let saved = chrome("Inbox - Google Chrome – Work", document: "https://example.com/inbox")
        let current = chrome("Inbox - Google Chrome – Personal", pid: 20, id: 2, document: "https://example.com/inbox")
        XCTAssertEqual(WindowMatcher.match(saved, in: [current]), .missing)
    }

    func testMultipleWindowsInAProfileRemainAmbiguousWithoutWindowEvidence() {
        let saved = chrome("Old tab - Google Chrome – Work")
        let current = [chrome("First new tab - Google Chrome – Work", pid: 20, id: 2),
                       chrome("Second new tab - Google Chrome – Work", pid: 20, id: 3)]
        XCTAssertEqual(WindowMatcher.match(saved, in: current), .ambiguous)
    }

    func testMultipleProfileWindowsStillUseAUniqueDocumentMatch() {
        let saved = chrome("Old tab - Google Chrome – Work", document: "https://example.com/report")
        let current = [chrome("Other tab - Google Chrome – Work", pid: 20, id: 2, document: "https://example.com/other"),
                       chrome("Changed report title - Google Chrome – Work", pid: 20, id: 3, document: "https://example.com/report")]
        XCTAssertEqual(WindowMatcher.match(saved, in: current), .found(1))
    }

    func testTwoSavedProfileWindowsCannotClaimOneCurrentWindow() {
        let saved = [chrome("Old first tab - Google Chrome – Work"), chrome("Old second tab - Google Chrome – Work", id: 2)]
        let current = [chrome("New tab - Google Chrome – Work", pid: 20, id: 3)]
        XCTAssertEqual(WindowMatcher.matches(saved, in: current), [.ambiguous, .ambiguous])
    }

    func testProfileDoesNotResurrectAClosedWindowInTheSameProcess() {
        let saved = chrome("Old tab - Google Chrome – Work")
        let replacement = chrome("New tab - Google Chrome – Work", id: 2)
        XCTAssertEqual(WindowMatcher.match(saved, in: [replacement]), .missing)
    }

    func testPrivateAndGuestWindowsDoNotAcquireProfileIdentity() {
        for profile in ["Incognito", "InPrivate", "Guest"] {
            let saved = chrome("Old tab - Google Chrome – \(profile)")
            XCTAssertNil(WindowMatcher.browserProfile(saved))
            XCTAssertEqual(WindowMatcher.match(saved, in: [chrome("New tab - Google Chrome – \(profile)", pid: 20, id: 2)]), .missing)
        }
    }

    func testEdgeProfileSupportsHyphenSuffixAndChangedTabs() {
        var saved = chrome("Inbox - Microsoft Edge - Work")
        saved.bundleID = "com.microsoft.edgemac"
        var current = saved; current.pid = 20; current.processStarted = Date(timeIntervalSince1970: 20)
        current.windowID = 2; current.title = "Calendar - Microsoft Edge - Work"
        XCTAssertEqual(WindowMatcher.match(saved, in: [current]), .found(0))
    }

    func testUnrelatedAppsCannotAcquireBrowserProfileIdentity() {
        var window = chrome("A title containing Google Chrome – Work")
        window.bundleID = "test.editor"
        XCTAssertNil(WindowMatcher.browserProfile(window))
    }
}
