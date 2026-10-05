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
        let matches = WindowMatcher.matches(layout.windows.map(\.identity), in: inventory.windows.map(\.identity))
        var report = RestoreReport()
        for (saved, match) in zip(layout.windows, matches) {
            let label = Self.label(saved.identity)
            guard case .found(let index) = match else {
                report.skipped += 1
                report.details.append("\(label): skipped, \(match == .ambiguous ? "ambiguous window match" : "app closed, window missing, or window unsupported")")
                continue
            }
            let window = inventory.windows[index]
            var adjustments: [String] = []
            let display = displays.first(where: { $0.uuid == saved.displayUUID }) ?? fallback
            if display.uuid != saved.displayUUID {
                adjustments.append("\(saved.displayName) disconnected; using \(display.name). Saved destination retained")
            }
            let onDisplay = desktops.filter { $0.displayUUID.caseInsensitiveCompare(display.uuid) == .orderedSame }
            let savedSpace: DesktopSpace?
            if let uuid = saved.space.uuid {
                savedSpace = onDisplay.first { $0.uuid == uuid }
            } else if !saved.space.bootSession.isEmpty && saved.space.bootSession == Self.bootSession {
                savedSpace = onDisplay.first { $0.id == saved.space.sessionID }
            } else { savedSpace = nil }
            guard let targetSpace = savedSpace ?? onDisplay.first(where: \.isCurrent) ?? onDisplay.first else {
                report.skipped += 1; report.details.append("\(label): skipped, no ordinary desktop Space on the available monitor"); continue
            }
            if savedSpace == nil {
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
    static func label(_ identity: WindowIdentity) -> String {
        identity.title.isEmpty ? identity.appName : "\(identity.appName): \(identity.title)"
    }
}
