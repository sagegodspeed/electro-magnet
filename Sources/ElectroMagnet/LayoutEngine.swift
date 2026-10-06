import AppKit
import ElectroMagnetCore

struct RestoreReport {
    var restored = 0
    var adjusted = 0
    var skipped = 0
    var details: [String] = []
    var summary: String { "\(restored) restored, \(adjusted) adjusted, \(skipped) skipped" }
    var text: String { ([summary, ""] + details).joined(separator: "\n") }
}

@MainActor final class LayoutEngine {
    let spaces = SpacesBridge()
    var onlyPID: Int32?

    static var bootSession: String {
        var count = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &count, nil, 0) == 0, count > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &count, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }

    func capture() throws -> (windows: [SavedWindow], omissions: [String]) {
        let inventory = try WindowAccess.inventory(onlyPID: onlyPID)
        let displays = WindowAccess.displays()
        let desktops = try spaces.desktops()
        var saved: [SavedWindow] = []
        var omissions = inventory.omissions
        for window in inventory.windows {
            let label = Self.label(window.identity)
            let assignments = spaces.windowSpaces(window.identity.windowID)
            guard assignments.count == 1, let desktop = desktops.first(where: { $0.id == assignments[0] }),
                  let display = displays.first(where: { $0.uuid.caseInsensitiveCompare(desktop.displayUUID) == .orderedSame }) else {
                omissions.append("\(label): not assigned to one ordinary desktop Space")
                continue
            }
            saved.append(SavedWindow(identity: window.identity, displayUUID: display.uuid, displayName: display.name,
                space: SpaceDestination(uuid: desktop.uuid, sessionID: desktop.id, ordinal: desktop.ordinal,
                                        bootSession: Self.bootSession),
                relativeFrame: WindowFrame(x: window.frame.x - display.usable.x, y: window.frame.y - display.usable.y,
                                          width: window.frame.width, height: window.frame.height)))
        }
        guard !saved.isEmpty else { throw RuntimeError.message("No supported windows could be remembered.\n\n" + omissions.joined(separator: "\n")) }
        return (saved, omissions)
    }

    /// Invoked exclusively by the user's Restore command or the isolated fixture test.
    func restore(_ layout: Layout) async throws -> RestoreReport {
        guard WindowAccess.trusted else { throw RuntimeError.message("Accessibility permission is required. No windows were moved.") }
        let inventory = try WindowAccess.inventory(onlyPID: onlyPID)
        let displays = WindowAccess.displays()
        let desktops = try spaces.desktops()
        guard let fallback = displays.first else { throw RuntimeError.message("No available display was found.") }
        let matches = WindowMatcher.matches(layout.windows.map(\.identity), in: inventory.identities)
        var report = RestoreReport()
        for (saved, match) in zip(layout.windows, matches) {
            let label = Self.label(saved.identity)
            if let reason = skipReason(saved.identity, match: match, inventory: inventory) {
                report.skipped += 1
                report.details.append("\(label): skipped, \(reason)")
                continue
            }
            guard case .found(let index) = match else { continue }
            let window = inventory.windows[index]
            var adjustments: [String] = []
            let display = displays.first(where: { $0.uuid == saved.displayUUID }) ?? fallback
            if display.uuid != saved.displayUUID {
                adjustments.append("\(saved.displayName) disconnected; using \(display.name). Saved destination retained")
            }
            let onDisplay = desktops.filter { $0.displayUUID.caseInsensitiveCompare(display.uuid) == .orderedSame }
            let spaceMatch = SpaceMatcher.match(saved.space, displayUUID: display.uuid, in: desktops,
                bootSession: Self.bootSession,
                allowPosition: display.uuid.caseInsensitiveCompare(saved.displayUUID) == .orderedSame)
            let savedSpace: DesktopSpace?
            switch spaceMatch {
            case .identity(let index), .position(let index): savedSpace = desktops[index]
            case .missing: savedSpace = nil
            }
            guard let targetSpace = savedSpace ?? onDisplay.first(where: \.isCurrent) ?? onDisplay.first else {
                report.skipped += 1; report.details.append("\(label): skipped, no ordinary desktop Space on the available monitor"); continue
            }
            if case .position = spaceMatch {
                adjustments.append("saved Space identity unavailable; using saved desktop position \(targetSpace.ordinal). Saved assignment retained")
            } else if savedSpace == nil {
                adjustments.append("saved Space unavailable; using desktop \(targetSpace.ordinal). Saved assignment retained")
            }
            let originalTarget = WindowFrame(x: display.usable.x + saved.relativeFrame.x, y: display.usable.y + saved.relativeFrame.y,
                                            width: saved.relativeFrame.width, height: saved.relativeFrame.height)
            let target = originalTarget.clamped(to: display.usable)
            if !target.isNear(originalTarget) { adjustments.append("adjusted to usable screen bounds") }
            do {
                guard WindowAccess.trusted else { throw RuntimeError.message("Accessibility permission was revoked.") }
                if !spaces.canMove && spaces.windowSpaces(window.identity.windowID) != [targetSpace.id] {
                    throw RuntimeError.message("Space restoration is unavailable on this macOS version")
                }
                _ = try WindowAccess.setFrame(window.element, to: target, bounds: display.usable)
                try await spaces.move(window.identity.windowID, to: targetSpace.id)
                _ = try WindowAccess.setFrame(window.element, to: target, bounds: display.usable)
                // Geometry changes can make macOS reassign a window to a display's active Space.
                try await spaces.move(window.identity.windowID, to: targetSpace.id)
                try await Task.sleep(nanoseconds: 100_000_000)
                guard let actual = WindowAccess.frame(window.element),
                      spaces.windowSpaces(window.identity.windowID) == [targetSpace.id],
                      WindowAccess.display(for: actual, in: displays)?.uuid == display.uuid else {
                    throw RuntimeError.message("final monitor, Space, or bounds could not be verified")
                }
                if !actual.isNear(target) { adjustments.append("application constrained the requested position or size") }
                let reachable = actual.reachable(in: display.usable)
                guard abs(actual.x - reachable.x) < 3, abs(actual.y - reachable.y) < 3 else {
                    throw RuntimeError.message("application refused a position within usable screen bounds")
                }
                if adjustments.isEmpty { report.restored += 1; report.details.append("\(label): restored") }
                else { report.adjusted += 1; report.details.append("\(label): " + adjustments.joined(separator: "; ")) }
            } catch {
                report.skipped += 1
                report.details.append("\(label): incomplete, \(error.localizedDescription)")
            }
        }
        return report
    }

    private func skipReason(_ saved: WindowIdentity, match: WindowMatch, inventory: WindowInventory) -> String? {
        switch match {
        case .found(let index):
            return index < inventory.windows.count ? nil : inventory.excluded[index - inventory.windows.count].reason
        case .ambiguous:
            return "window identity is not unique; no window was selected"
        case .missing:
            guard let app = inventory.applications[saved.bundleID] else { return "application is not running" }
            if app.hidden { return "application is hidden" }
            let exposed = inventory.identities.filter { $0.bundleID == saved.bundleID }
            if exposed.isEmpty, app.windowListError == nil {
                return "application is running but no ordinary window is accessible; show its window or Space and Restore again"
            }
            if let profile = WindowMatcher.browserProfile(saved),
               !exposed.contains(where: { WindowMatcher.browserProfile($0) == profile }) {
                return "no accessible window for browser profile “\(profile)”; show that profile's window or Space and Restore again"
            }
            if app.uninspectedCount > 0 {
                return "no reliable match; some application windows could not be inspected. Visit the saved window's Space and Restore again"
            }
            if let error = app.windowListError {
                return "window list could not be read (Accessibility error \(error))"
            }
            if app.pid != saved.pid || app.started != saved.processStarted {
                return "application relaunched; no unique document, identifier, account, title or browser profile matches the saved window"
            }
            return "saved window is no longer present among the application's accessible windows"
        }
    }

    /// Read-only inspection uses exactly the same discovery and matching as Restore.
    func diagnostics(_ layout: Layout) throws -> [String: Any] {
        let inventory = try WindowAccess.inventory(onlyPID: onlyPID)
        let displays = WindowAccess.displays()
        let desktops = try spaces.desktops()
        let matches = WindowMatcher.matches(layout.windows.map(\.identity), in: inventory.identities)
        let rows = zip(layout.windows, matches).map { saved, match -> [String: Any] in
            var row: [String: Any] = ["application": saved.identity.appName, "savedWindowID": saved.identity.windowID,
                                     "reason": skipReason(saved.identity, match: match, inventory: inventory) ?? "matchable"]
            if let display = displays.first(where: { $0.uuid == saved.displayUUID }) ?? displays.first {
                let spaceMatch = SpaceMatcher.match(saved.space, displayUUID: display.uuid, in: desktops,
                    bootSession: Self.bootSession,
                    allowPosition: display.uuid.caseInsensitiveCompare(saved.displayUUID) == .orderedSame)
                let target: DesktopSpace?
                switch spaceMatch {
                case .identity(let index): target = desktops[index]; row["spaceMatch"] = "identity"
                case .position(let index): target = desktops[index]; row["spaceMatch"] = "saved desktop position"
                case .missing:
                    let available = desktops.filter { $0.displayUUID.caseInsensitiveCompare(display.uuid) == .orderedSame }
                    target = available.first(where: \.isCurrent) ?? available.first
                    row["spaceMatch"] = "available desktop"
                }
                row["targetDesktopPosition"] = target?.ordinal
                row["targetDisplayName"] = display.name
            }
            row["currentWindows"] = inventory.identities.enumerated().filter { $0.element.bundleID == saved.identity.bundleID }.map { index, window in
                ["windowID": window.windowID, "title": window.title, "document": window.document ?? "",
                 "identifier": window.identifier ?? "", "browserProfile": WindowMatcher.browserProfile(window) ?? "",
                 "contextKeys": Array(WindowMatcher.windowContextKeys(window)).sorted(),
                 "exclusion": index < inventory.windows.count ? "" : inventory.excluded[index - inventory.windows.count].reason] as [String: Any]
            }
            if case .found(let index) = match { row["matchedWindowID"] = inventory.identities[index].windowID }
            return row
        }
        return ["layout": layout.name, "accessibilityGranted": WindowAccess.trusted, "windows": rows, "inventoryNotes": inventory.omissions]
    }
    static func label(_ identity: WindowIdentity) -> String {
        identity.title.isEmpty ? identity.appName : "\(identity.appName): \(identity.title)"
    }
}
