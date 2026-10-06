import AppKit
import ApplicationServices
import ElectroMagnetCore

struct LiveWindow {
    let identity: WindowIdentity
    let element: AXUIElement
    let frame: WindowFrame
}

struct Display {
    let uuid: String
    let name: String
    let bounds: WindowFrame
    let usable: WindowFrame
}

struct WindowInventory {
    var windows: [LiveWindow] = []
    var omissions: [String] = []
    var excluded: [(identity: WindowIdentity, reason: String)] = []
    var applications: [String: ApplicationWindowStatus] = [:]
    var identities: [WindowIdentity] { windows.map(\.identity) + excluded.map(\.identity) }
}

struct ApplicationWindowStatus {
    let pid: Int32
    let started: Date?
    let hidden: Bool
    var windowListError: Int32?
    var uninspectedCount = 0
}

@MainActor enum WindowAccess {
    private typealias AXWindowID = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
    private typealias AXRemote = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private static var cached: [Int32: (started: Date?, elements: [UInt32: AXUIElement])] = [:]
    private static let getWindowID: AXWindowID? = {
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW),
              let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: AXWindowID.self)
    }()
    private static let remoteElement: AXRemote? = {
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW),
              let symbol = dlsym(handle, "_AXUIElementCreateWithRemoteToken") else { return nil }
        return unsafeBitCast(symbol, to: AXRemote.self)
    }()

    /// Only inspect roots whose window ID appears in the app's current layer-zero CG list.
    /// No Space switching or window movement is performed during discovery.
    private static func otherSpaceWindows(pid: Int32, wanted: Set<UInt32>) -> [AXUIElement] {
        guard !wanted.isEmpty, let remoteElement, let getWindowID else { return [] }
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
        var remaining = wanted
        var found: [AXUIElement] = []
        let deadline = Date().addingTimeInterval(0.75)
        for elementID in UInt64(0)..<4000 {
            if Date() > deadline || remaining.isEmpty { break }
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let element = remoteElement(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(element, 0.08)
            var id: UInt32 = 0
            guard getWindowID(element, &id) == 0, remaining.contains(id),
                  attribute(element, kAXRoleAttribute) as? String == kAXWindowRole else { continue }
            remaining.remove(id); found.append(element)
        }
        return found
    }

    static var trusted: Bool { AXIsProcessTrusted() }
    /// Read-only cache priming as the user naturally visits Spaces. This helps apps
    /// (notably some browsers) that expose a window only while its Space is active.
    static func primeVisibleWindows() {
        guard trusted, let getWindowID else { return }
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        let running = Set(apps.map(\.processIdentifier))
        cached = cached.filter { running.contains($0.key) }
        for app in apps where !app.isHidden {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.1)
            guard let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            var known: [UInt32: AXUIElement] = [:]
            if let previous = cached[app.processIdentifier], previous.started == app.launchDate {
                known = previous.elements
            }
            for window in windows {
                var id: UInt32 = 0
                if getWindowID(window, &id) == 0, id != 0 { known[id] = window }
            }
            cached[app.processIdentifier] = (app.launchDate, known)
        }
    }
    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
    static func writable(_ element: AXUIElement, _ key: String) -> Bool {
        var result: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, key as CFString, &result) == .success && result.boolValue
    }
    static func frame(_ element: AXUIElement) -> WindowFrame? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
        let result = WindowFrame(x: point.x, y: point.y, width: dimensions.width, height: dimensions.height)
        return result.isValid ? result : nil
    }
    static func unsupportedReason(_ element: AXUIElement) -> String? {
        if attribute(element, kAXMinimizedAttribute) as? Bool == true { return "minimized window" }
        guard attribute(element, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole else { return "unsupported window type" }
        if attribute(element, "AXFullScreen") as? Bool == true { return "native fullscreen window" }
        guard writable(element, kAXPositionAttribute), writable(element, kAXSizeAttribute) else { return "window does not support moving and resizing" }
        return nil
    }

    /// Inspect browser chrome only. Never enter page content or change the selected tab.
    private static func tabContextKeys(_ window: AXUIElement, bundleID: String) -> [String] {
        guard ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac"].contains(bundleID) else { return [] }
        var pending: [(AXUIElement, Int, Bool)] = [(window, 0, false)]
        var keys = Set<String>(), inspected = 0
        let deadline = Date().addingTimeInterval(0.2)
        while let (element, depth, inTabs) = pending.popLast(), inspected < 500, Date() < deadline {
            inspected += 1
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            guard role != "AXWebArea" else { continue }
            let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
            if subrole == "AXTabButton" || role == "AXTab" || (inTabs && role == kAXRadioButtonRole) {
                for name in [kAXTitleAttribute, kAXDescriptionAttribute] {
                    if let title = attribute(element, name) as? String,
                       let key = WindowMatcher.contextKey(title: title, bundleID: bundleID) { keys.insert(key) }
                }
                continue
            }
            guard depth < 8, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            pending.append(contentsOf: children.prefix(100).reversed().map { ($0, depth + 1, inTabs || role == kAXTabGroupRole) })
        }
        return keys.sorted()
    }

    static func inventory(onlyPID: Int32? = nil) throws -> WindowInventory {
        guard trusted else { throw RuntimeError.message("Accessibility permission is required. No windows were moved.") }
        guard let getWindowID else { throw RuntimeError.message("Window identification is unavailable on this macOS version.") }
        var result = WindowInventory()
        let appPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != appPID && (onlyPID == nil ? $0.activationPolicy == .regular : $0.processIdentifier == onlyPID)
        }
        let cgWindows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for app in apps {
            let name = app.localizedName ?? "Application"
            guard let bundleID = app.bundleIdentifier else { result.omissions.append("\(name): no application identifier"); continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.4)
            let appCG = cgWindows.filter {
                ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier &&
                ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
            }
            let cgIDs = Set(appCG.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
            var value: CFTypeRef?
            let windowListStatus = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
            var status = ApplicationWindowStatus(pid: app.processIdentifier, started: app.launchDate, hidden: app.isHidden)
            if windowListStatus != .success { status.windowListError = windowListStatus.rawValue }
            var windows = value as? [AXUIElement] ?? []
            if let previous = cached[app.processIdentifier], previous.started == app.launchDate {
                windows.append(contentsOf: previous.elements.filter { cgIDs.contains($0.key) }.map(\.value))
            }
            let exposed = Set(windows.compactMap { window -> UInt32? in
                var id: UInt32 = 0
                return getWindowID(window, &id) == 0 ? id : nil
            })
            windows.append(contentsOf: otherSpaceWindows(pid: app.processIdentifier, wanted: cgIDs.subtracting(exposed)))
            var seen = Set<UInt32>()
            var liveElements: [UInt32: AXUIElement] = [:]
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.4)
                var id: UInt32 = 0
                guard getWindowID(window, &id) == 0, id != 0, seen.insert(id).inserted else { continue }
                liveElements[id] = window
                let title = attribute(window, kAXTitleAttribute) as? String ?? ""
                let label = title.isEmpty ? name : "\(name): \(title)"
                let contexts = attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole
                    ? tabContextKeys(window, bundleID: bundleID) : []
                let identity = WindowIdentity(bundleID: bundleID, appName: name,
                    pid: app.processIdentifier, processStarted: app.launchDate, windowID: id, title: title,
                    document: attribute(window, kAXDocumentAttribute) as? String,
                    identifier: attribute(window, kAXIdentifierAttribute) as? String,
                    contextKeys: contexts.isEmpty ? nil : contexts)
                let reason = unsupportedReason(window) ?? (app.isHidden ? "application is hidden" : nil)
                if let reason {
                    result.excluded.append((identity, reason)); result.omissions.append("\(label): \(reason)"); continue
                }
                guard let rect = frame(window) else {
                    result.excluded.append((identity, "bounds could not be read"))
                    result.omissions.append("\(label): bounds could not be read"); continue
                }
                result.windows.append(LiveWindow(identity: identity, element: window, frame: rect))
            }
            cached[app.processIdentifier] = (app.launchDate, liveElements)
            let unexposed = cgIDs.subtracting(seen)
            status.uninspectedCount = unexposed.count
            result.applications[bundleID] = status
            if !unexposed.isEmpty { result.omissions.append("\(name): \(unexposed.count) window(s) could not be inspected; visit their Spaces and retry") }
            if windowListStatus != .success {
                result.omissions.append("\(name): window list could not be read (Accessibility error \(windowListStatus.rawValue))")
            }
        }
        return result
    }

    static func displays() -> [Display] {
        // AppKit's first screen defines the origin, not a persisted monitor identity.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            func ax(_ frame: CGRect) -> WindowFrame {
                WindowFrame(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
            }
            return Display(uuid: (CFUUIDCreateString(nil, uuid) as String).uppercased(), name: screen.localizedName,
                           bounds: ax(screen.frame), usable: ax(screen.visibleFrame))
        }
    }

    static func display(for frame: WindowFrame, in displays: [Display]) -> Display? {
        displays.max { intersection(frame, $0.bounds) < intersection(frame, $1.bounds) }
    }
    private static func intersection(_ a: WindowFrame, _ b: WindowFrame) -> Double {
        max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x)) *
        max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
    }

    static func setFrame(_ element: AXUIElement, to frame: WindowFrame, bounds: WindowFrame) throws -> WindowFrame {
        guard trusted else { throw RuntimeError.message("Accessibility permission was revoked.") }
        if let reason = unsupportedReason(element) { throw RuntimeError.message(reason) }
        func size(_ width: Double, _ height: Double) throws {
            var value = CGSize(width: width, height: height)
            guard let ax = AXValueCreate(.cgSize, &value) else { throw RuntimeError.message("Could not encode the window size.") }
            let status = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, ax)
            guard status == .success else { throw RuntimeError.message("Resize failed (Accessibility error \(status.rawValue)).") }
        }
        func position(_ x: Double, _ y: Double) throws {
            var value = CGPoint(x: x, y: y)
            guard let ax = AXValueCreate(.cgPoint, &value) else { throw RuntimeError.message("Could not encode the window position.") }
            let status = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, ax)
            guard status == .success else { throw RuntimeError.message("Move failed (Accessibility error \(status.rawValue)).") }
        }
        // Apps commonly constrain resize using their current monitor; repeat after moving.
        try size(frame.width, frame.height)
        try position(frame.x, frame.y)
        try size(frame.width, frame.height)
        guard let actual = self.frame(element) else { throw RuntimeError.message("Could not verify the window's bounds.") }
        let reachable = actual.reachable(in: bounds)
        if actual.x != reachable.x || actual.y != reachable.y { try position(reachable.x, reachable.y) }
        guard let verified = self.frame(element) else { throw RuntimeError.message("Could not verify the final window position.") }
        return verified
    }
}
