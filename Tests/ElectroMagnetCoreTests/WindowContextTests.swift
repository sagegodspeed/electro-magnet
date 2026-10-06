import XCTest
@testable import ElectroMagnetCore

final class WindowContextTests: XCTestCase {
    private func window(_ bundle: String, _ title: String, pid: Int32 = 10, id: UInt32 = 1, contexts: [String]? = nil) -> WindowIdentity {
        WindowIdentity(bundleID: bundle, appName: "Test", pid: pid, processStarted: Date(timeIntervalSince1970: Double(pid)),
                       windowID: id, title: title, contextKeys: contexts)
    }

    func testOutlookFolderChangeKeepsAccountIdentityAfterRelaunch() {
        let saved = window("com.apple.Safari", "Mail - Test Person - Outlook")
        let current = [window("com.apple.Safari", "Inbox - Other Person - Outlook", pid: 20),
                       window("com.apple.Safari", "Inbox - Test Person - Outlook", pid: 20, id: 2)]
        XCTAssertEqual(WindowMatcher.match(saved, in: current), .found(1))
        XCTAssertEqual(WindowMatcher.match(saved, in: [current[0]]), .missing)
    }

    func testDuplicateOutlookAccountWindowsStayAmbiguous() {
        let saved = window("com.apple.Safari", "Mail - Test Person - Outlook")
        let current = [window("com.apple.Safari", "Inbox - Test Person - Outlook", pid: 20),
                       window("com.apple.Safari", "Calendar - Test Person - Outlook", pid: 20, id: 2)]
        XCTAssertEqual(WindowMatcher.match(saved, in: current), .ambiguous)
    }

    func testTeamsParticipantBannerCanChangeWithoutChangingAccount() {
        let saved = window("com.microsoft.teams2", "Calendar | Person, +4 | Test Company | user@example.com | Microsoft Teams")
        let current = [window("com.microsoft.teams2", "Calendar | Test Company | other@example.com | Microsoft Teams", pid: 20),
                       window("com.microsoft.teams2", "Chat | Test Company | user@example.com | Microsoft Teams", pid: 20, id: 2)]
        XCTAssertEqual(WindowMatcher.match(saved, in: current), .found(1))
        XCTAssertEqual(WindowMatcher.match(saved, in: [current[0]]), .missing)
    }

    func testGeminiMainWindowSurvivesConversationChangesOnlyWhenUnique() {
        let saved = window("com.google.GeminiMacOS", "Gemini – Old conversation")
        let current = window("com.google.GeminiMacOS", "Gemini – New chat", pid: 20)
        XCTAssertEqual(WindowMatcher.match(saved, in: [current]), .found(0))
        XCTAssertEqual(WindowMatcher.match(saved, in: [current, window("com.google.GeminiMacOS", "Gemini – Other chat", pid: 20, id: 2)]), .ambiguous)
        XCTAssertEqual(WindowMatcher.match(saved, in: [window("com.google.GeminiMacOS", "Gemini – New chat", id: 2)]), .missing)
    }

    func testOpenMailTabDisambiguatesTwoChromeWindowsInSameProfile() {
        let saved = window("com.google.Chrome", "Search results - user@example.com - Gmail - High memory usage - 1 GB - Google Chrome – Personal")
        let key = "gmail-account:user@example.com"
        let current = [window("com.google.Chrome", "Music - Google Chrome – Personal", pid: 20),
                       window("com.google.Chrome", "Project - Google Chrome – Personal", pid: 20, id: 2, contexts: [key])]
        XCTAssertEqual(WindowMatcher.match(saved, in: current), .found(1))
        var duplicate = current[0]; duplicate.contextKeys = [key]
        XCTAssertEqual(WindowMatcher.match(saved, in: [duplicate, current[1]]), .ambiguous)
    }

    func testAccountHintCannotCrossBrowserProfiles() {
        let saved = window("com.google.Chrome", "Inbox - user@example.com - Gmail - Google Chrome – Personal")
        let current = window("com.google.Chrome", "Project - Google Chrome – Work", pid: 20, contexts: ["gmail-account:user@example.com"])
        XCTAssertEqual(WindowMatcher.match(saved, in: [current]), .missing)
    }

    func testTwoSavedAccountWindowsCannotClaimOneLiveWindow() {
        let saved = [window("com.apple.Safari", "Mail - Test Person - Outlook"),
                     window("com.apple.Safari", "Calendar - Test Person - Outlook", id: 2)]
        let current = [window("com.apple.Safari", "Inbox - Test Person - Outlook", pid: 20)]
        XCTAssertEqual(WindowMatcher.matches(saved, in: current), [.ambiguous, .ambiguous])
    }

    func testOnlyRecognizedAppTitleFormatsYieldContexts() {
        XCTAssertNil(WindowMatcher.contextKey(title: "Inbox - user@example.com - Gmail", bundleID: "test.editor"))
        XCTAssertNil(WindowMatcher.contextKey(title: "user@example.com", bundleID: "com.microsoft.teams2"))
        XCTAssertNil(WindowMatcher.contextKey(title: "Settings", bundleID: "com.google.GeminiMacOS"))
        for mode in ["Incognito", "Guest", "InPrivate"] {
            let privateWindow = window("com.google.Chrome", "Inbox - user@example.com - Gmail - Google Chrome – \(mode)", contexts: ["gmail-account:user@example.com"])
            XCTAssertTrue(WindowMatcher.windowContextKeys(privateWindow).isEmpty)
        }
    }

    func testLegacyIdentityWithoutContextKeysLoads() throws {
        let data = Data(#"{"bundleID":"com.apple.Safari","appName":"Safari","pid":10,"windowID":1,"title":"Mail - Test Person - Outlook"}"#.utf8)
        let saved = try JSONDecoder().decode(WindowIdentity.self, from: data)
        XCTAssertNil(saved.contextKeys)
        XCTAssertEqual(WindowMatcher.match(saved, in: [window("com.apple.Safari", "Inbox - Test Person - Outlook", pid: 20)]), .found(0))
    }

    func testLocalContextKeysPersistAcrossStoreRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LayoutStore(url: directory.appendingPathComponent("layouts.json"))
        let identity = window("com.google.Chrome", "Project - Google Chrome – Personal", contexts: ["gmail-account:user@example.com"])
        let saved = SavedWindow(identity: identity, displayUUID: "monitor-A", displayName: "Monitor A",
                                space: SpaceDestination(uuid: "space-A", sessionID: 1, ordinal: 1, bootSession: "boot-A"),
                                relativeFrame: WindowFrame(x: 100, y: 100, width: 600, height: 400))
        let layout = try store.save(name: "Test", windows: [saved])
        let restarted = LayoutStore(url: store.url); try restarted.load()
        XCTAssertEqual(restarted.layouts, [layout])
    }
}
