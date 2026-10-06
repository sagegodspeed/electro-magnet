import AppKit
import ElectroMagnetCore

/// Requires an explicitly launched disposable fixture. Never targets working apps.
@MainActor enum IntegrationTest {
    static func run(pid: Int32, directory: URL) async {
        var evidence: [String: Any] = ["macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                                       "accessibilityGranted": WindowAccess.trusted]
        var steps: [[String: Any]] = []
        do {
            guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.jeremyscott.ElectroMagnet.Fixture" else {
                throw RuntimeError.message("Refusing to test: PID is not the disposable fixture app.")
            }
            let engine = LayoutEngine(); engine.onlyPID = pid
            let store = LayoutStore(url: directory.appendingPathComponent("test-layouts.json"))
            let displays = WindowAccess.displays()
            let desktops = try engine.spaces.desktops()
            let initial = try WindowAccess.inventory(onlyPID: pid).windows.sorted { $0.identity.windowID < $1.identity.windowID }
            // Give the fixture a known arrangement before testing Remember.
            for (index, window) in initial.enumerated() {
                let display = displays[index % displays.count]
                guard let desktop = desktops.first(where: { $0.displayUUID == display.uuid && $0.isCurrent }) else { continue }
                let frame = WindowFrame(x: display.usable.x + 120, y: display.usable.y + 150, width: 500, height: 360)
                _ = try WindowAccess.setFrame(window.element, to: frame, bounds: display.usable)
                try await engine.spaces.move(window.identity.windowID, to: desktop.id)
                _ = try WindowAccess.setFrame(window.element, to: frame, bounds: display.usable)
            }
            evidence["displays"] = displays.map { ["uuid": $0.uuid, "name": $0.name, "usable": ["x": $0.usable.x, "y": $0.usable.y, "width": $0.usable.width, "height": $0.usable.height]] as [String: Any] }
            let firstCapture = try engine.capture()
            guard firstCapture.windows.count == 2 else { throw RuntimeError.message("Expected two test windows; captured \(firstCapture.windows.count).") }
            let first = try store.save(name: "Two monitors", windows: firstCapture.windows.sorted { $0.identity.windowID < $1.identity.windowID })
            steps.append(["test": "capture-two-monitors", "passed": Set(first.windows.map(\.displayUUID)).count == min(2, WindowAccess.displays().count), "omissions": firstCapture.omissions])
            let current = try WindowAccess.inventory(onlyPID: pid).windows
            for (index, window) in current.enumerated() {
                let destination = displays[(index + 1) % displays.count]
                let target = WindowFrame(x: destination.usable.x + 40, y: destination.usable.y + 50, width: 380, height: 260)
                _ = try WindowAccess.setFrame(window.element, to: target, bounds: destination.usable)
                let currentSpaces = engine.spaces.windowSpaces(window.identity.windowID)
                guard let targetSpace = desktops.first(where: { $0.displayUUID == destination.uuid && !currentSpaces.contains($0.id) }) else {
                    throw RuntimeError.message("Need at least two ordinary Spaces on each monitor for the test.")
                }
                try await engine.spaces.move(window.identity.windowID, to: targetSpace.id)
            }
            let secondCapture = try engine.capture()
            guard secondCapture.windows.count == 2 else { throw RuntimeError.message("Inactive Space capture failed: found \(secondCapture.windows.count) of two windows.") }
            let second = try store.save(name: "Other Spaces", windows: secondCapture.windows)
            steps.append(["test": "capture-inactive-spaces", "passed": true])
            try Data("change-titles".utf8).write(to: directory.appendingPathComponent("fixture-command"), options: .atomic)
            try await Task.sleep(nanoseconds: 350_000_000)
            let restarted = LayoutStore(url: store.url); try restarted.load()
            guard restarted.layouts == [first, second] else { throw RuntimeError.message("Restart persistence mismatch.") }
            let freshEngine = LayoutEngine(); freshEngine.onlyPID = pid
            let reportA = try await freshEngine.restore(restarted.layouts[0])
            evidence["firstRestoreGeometry"] = try WindowAccess.inventory(onlyPID: pid).windows.map { window in
                ["windowID": window.identity.windowID, "frame": [window.frame.x, window.frame.y, window.frame.width, window.frame.height]] as [String: Any]
            }
            steps.append(["test": "restore-first-after-utility-restart-and-title-change", "passed": reportA.restored == 2 && reportA.skipped == 0, "report": reportA.text])
            let reportB = try await freshEngine.restore(restarted.layouts[1])
            steps.append(["test": "switch-to-second-layout", "passed": reportB.restored == 2 && reportB.skipped == 0, "report": reportB.text])
            var recreatedSpaces = first
            var expectedSpaces: [UInt32: UInt64] = [:]
            for index in recreatedSpaces.windows.indices {
                let saved = recreatedSpaces.windows[index]
                guard let destination = desktops.last(where: { $0.displayUUID == saved.displayUUID }) else {
                    throw RuntimeError.message("No fixture desktop destination found.")
                }
                recreatedSpaces.windows[index].space = SpaceDestination(uuid: "missing-test-space", sessionID: UInt64.max,
                    ordinal: destination.ordinal, bootSession: "previous-test-boot")
                expectedSpaces[saved.identity.windowID] = destination.id
            }
            let persistedBefore = try Data(contentsOf: store.url)
            let recreatedReport = try await freshEngine.restore(recreatedSpaces)
            let persistedUnchanged = try Data(contentsOf: store.url) == persistedBefore
            steps.append(["test": "missing-space-identity-restores-saved-position", "passed": recreatedReport.adjusted == 2 && recreatedReport.skipped == 0 &&
                expectedSpaces.allSatisfy { freshEngine.spaces.windowSpaces($0.key) == [$0.value] } &&
                persistedUnchanged, "report": recreatedReport.text])
            var missingPosition = recreatedSpaces
            missingPosition.windows = [recreatedSpaces.windows[0]]
            missingPosition.windows[0].space.ordinal = Int.max
            let missingPositionReport = try await freshEngine.restore(missingPosition)
            steps.append(["test": "missing-desktop-position-uses-available-space", "passed": missingPositionReport.adjusted == 1 && missingPositionReport.skipped == 0 &&
                missingPositionReport.text.contains("saved Space unavailable"), "report": missingPositionReport.text])
            var ambiguous = first
            for index in ambiguous.windows.indices {
                ambiguous.windows[index].identity.pid = -1
                ambiguous.windows[index].identity.title = "Changed browser tab title"
                ambiguous.windows[index].identity.identifier = nil
                ambiguous.windows[index].identity.document = nil
            }
            let ambiguousReport = try await freshEngine.restore(ambiguous)
            steps.append(["test": "ambiguous-windows-stay-put", "passed": ambiguousReport.skipped == 2 && ambiguousReport.restored == 0 && ambiguousReport.details.allSatisfy { $0.contains("identity is not unique") }, "report": ambiguousReport.text])
            var closedApp = first
            closedApp.windows = [first.windows[0]]
            closedApp.windows[0].identity.bundleID = "test.closed-application"
            let closedReport = try await freshEngine.restore(closedApp)
            steps.append(["test": "closed-app-specific-reason", "passed": closedReport.skipped == 1 && closedReport.text.contains("application is not running"), "report": closedReport.text])
            try Data("close-second".utf8).write(to: directory.appendingPathComponent("fixture-command"), options: .atomic)
            try await Task.sleep(nanoseconds: 350_000_000)
            let missingReport = try await freshEngine.restore(first)
            steps.append(["test": "missing-window", "passed": missingReport.restored == 1 && missingReport.skipped == 1, "report": missingReport.text])
            var oversized = first
            oversized.windows = [first.windows[0]]
            oversized.windows[0].relativeFrame.width = 10
            oversized.windows[0].relativeFrame.height = 10
            let minimumReport = try await freshEngine.restore(oversized)
            steps.append(["test": "minimum-window-size", "passed": minimumReport.adjusted == 1 && minimumReport.skipped == 0, "report": minimumReport.text])
            var disconnected = first
            disconnected.windows = [first.windows[0]]
            disconnected.windows[0].displayUUID = "disconnected-test-monitor"
            let disconnectedReport = try await freshEngine.restore(disconnected)
            steps.append(["test": "simulated-disconnected-display", "passed": disconnectedReport.adjusted == 1 && disconnectedReport.skipped == 0, "report": disconnectedReport.text])
            let final = try await freshEngine.restore(first)
            steps.append(["test": "restore-original-after-fallback", "passed": final.restored == 1 && final.skipped == 1, "report": final.text])
            try Data("minimize-first".utf8).write(to: directory.appendingPathComponent("fixture-command"), options: .atomic)
            try await Task.sleep(nanoseconds: 350_000_000)
            let minimized = try await freshEngine.restore(first)
            steps.append(["test": "minimized-window-specific-reason", "passed": minimized.restored == 0 && minimized.skipped == 2 && minimized.text.contains("minimized window"), "report": minimized.text])
            evidence["passed"] = steps.allSatisfy { $0["passed"] as? Bool == true }
        } catch {
            evidence["passed"] = false; evidence["error"] = error.localizedDescription
        }
        evidence["steps"] = steps
        let data = try! JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
        try? data.write(to: directory.appendingPathComponent("integration-result.json"), options: .atomic)
        NSApp.terminate(nil)
    }
}
