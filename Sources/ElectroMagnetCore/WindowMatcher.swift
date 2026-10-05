import Foundation

public enum WindowMatch: Equatable {
    case found(Int), missing, ambiguous
}

public enum WindowMatcher {
    /// Prefer an exact live window in the same process lifetime. For a restarted process,
    /// use unique document/identifier/title evidence. Never use geometry or list order.
    public static func match(_ saved: WindowIdentity, in current: [WindowIdentity]) -> WindowMatch {
        let app = current.indices.filter { current[$0].bundleID == saved.bundleID }
        guard !app.isEmpty else { return .missing }
        let sameProcess = app.filter {
            current[$0].pid == saved.pid && saved.processStarted != nil &&
            current[$0].processStarted == saved.processStarted
        }
        if !sameProcess.isEmpty {
            let exact = sameProcess.filter { current[$0].windowID == saved.windowID }
            if exact.count == 1 { return .found(exact[0]) }
            // A still-running app has lost the saved window: a replacement with the
            // same title must not inherit the old window's position.
            return .missing
        }
        if let document = saved.document, !document.isEmpty {
            let matches = app.filter { current[$0].document == document }
            if matches.count == 1 { return .found(matches[0]) }
            if matches.count > 1 { return .ambiguous }
        }
        if let identifier = saved.identifier, !identifier.isEmpty {
            let matches = app.filter { current[$0].identifier == identifier }
            if matches.count == 1 { return .found(matches[0]) }
            if matches.count > 1 { return .ambiguous }
        }
        if !saved.title.isEmpty {
            let matches = app.filter { current[$0].title == saved.title }
            if matches.count == 1 { return .found(matches[0]) }
            if matches.count > 1 { return .ambiguous }
        }
        return .missing
    }
    public static func matches(_ saved: [WindowIdentity], in current: [WindowIdentity]) -> [WindowMatch] {
        let initial = saved.map { match($0, in: current) }
        let counts = initial.reduce(into: [Int: Int]()) { result, match in
            if case .found(let index) = match { result[index, default: 0] += 1 }
        }
        return initial.map { match in
            if case .found(let index) = match, counts[index, default: 0] > 1 { return .ambiguous }
            return match
        }
    }
}
