import Foundation

public enum WindowMatch: Equatable {
    case found(Int), missing, ambiguous
}

public enum WindowMatcher {
    /// Prefer an exact live window in the same process lifetime. For a restarted process,
    /// use unique document/identifier/title or browser-profile evidence.
    /// Never use geometry or list order.
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
        let profile = browserProfile(saved)
        let candidates = profile.map { profile in app.filter { browserProfile(current[$0]) == profile } } ?? app
        if let document = saved.document, !document.isEmpty {
            let matches = candidates.filter { current[$0].document == document }
            if matches.count == 1 { return .found(matches[0]) }
            if matches.count > 1 { return .ambiguous }
        }
        if let identifier = saved.identifier, !identifier.isEmpty {
            let matches = candidates.filter { current[$0].identifier == identifier }
            if matches.count == 1 { return .found(matches[0]) }
            if matches.count > 1 { return .ambiguous }
        }
        if !saved.title.isEmpty {
            let matches = candidates.filter { current[$0].title == saved.title }
            if matches.count == 1 { return .found(matches[0]) }
            if matches.count > 1 { return .ambiguous }
        }
        let contexts = windowContextKeys(saved)
        if !contexts.isEmpty {
            let matches = candidates.filter { !contexts.isDisjoint(with: windowContextKeys(current[$0])) }
            if matches.count == 1 { return .found(matches[0]) }
            if matches.count > 1 { return .ambiguous }
        }
        if profile != nil {
            if candidates.count == 1 { return .found(candidates[0]) }
            if candidates.count > 1 { return .ambiguous }
        }
        return .missing
    }

    /// Chrome and Edge append their profile label after the browser name.
    /// This survives tab/title/URL changes and also works with existing saved layouts.
    /// A profile is not a unique window: duplicate profile windows remain ambiguous.
    public static func browserProfile(_ window: WindowIdentity) -> String? {
        let browser: String
        switch window.bundleID {
        case "com.google.Chrome": browser = "Google Chrome"
        case "com.microsoft.edgemac": browser = "Microsoft Edge"
        default: return nil
        }
        guard let range = window.title.range(of: browser, options: .backwards),
              [" - ", " – ", " — "].contains(where: { window.title[..<range.lowerBound].hasSuffix($0) }) else { return nil }
        var suffix = window.title[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = suffix.first, ["-", "–", "—"].contains(String(separator)) else { return nil }
        suffix.removeFirst()
        let profile = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.isEmpty,
              !["incognito", "inprivate", "guest"].contains(where: { profile.lowercased().contains($0) }) else { return nil }
        return profile
    }

    public static func windowContextKeys(_ window: WindowIdentity) -> Set<String> {
        let title = window.title.lowercased()
        if ["com.google.Chrome", "com.microsoft.edgemac"].contains(window.bundleID),
           ["incognito", "inprivate", "guest"].contains(where: { title.contains($0) }) { return [] }
        var keys = Set(window.contextKeys ?? [])
        if let key = contextKey(title: window.title, bundleID: window.bundleID) { keys.insert(key) }
        return keys
    }

    /// Use app-owned account labels, not changing folders, chat titles or memory banners.
    /// These keys are local identity hints; every key still requires a unique window.
    public static func contextKey(title: String, bundleID: String) -> String? {
        func email(_ value: String) -> Bool {
            value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
        }
        if bundleID == "com.microsoft.teams2" {
            let parts = title.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.last == "Microsoft Teams", let account = parts.first(where: email) else { return nil }
            return "teams-account:" + account.lowercased()
        }
        if bundleID == "com.google.GeminiMacOS",
           ["Gemini – ", "Gemini - ", "Gemini — "].contains(where: { title.hasPrefix($0) }) {
            return "gemini-main-window"
        }
        guard ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac"].contains(bundleID) else { return nil }
        let parts = title.replacingOccurrences(of: " – ", with: " - ").replacingOccurrences(of: " — ", with: " - ")
            .components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for index in parts.indices where index > 0 {
            let service = parts[index].lowercased(), account = parts[index - 1]
            if (service == "gmail" || service.hasSuffix(" mail")), email(account) {
                return "gmail-account:" + account.lowercased()
            }
            if service == "outlook", index >= 2, !account.isEmpty {
                return "outlook-account:" + account.lowercased()
            }
        }
        return nil
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
