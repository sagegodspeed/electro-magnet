import AppKit
import Darwin
import ElectroMagnetCore

enum RuntimeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// The only Space write path is the dynamically resolved bridged operation.
/// No Dock injection, compatibility-ID mutation, helpers, or SIP changes.
@MainActor final class SpacesBridge {
    private typealias Connection = @convention(c) () -> Int32
    private typealias CopyManaged = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private let handle: UnsafeMutableRawPointer?
    private let connection: Int32
    private let copyManaged: CopyManaged?
    private let copySpaces: CopySpaces?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        self.handle = handle
        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        connection = load("SLSMainConnectionID", as: Connection.self)?() ?? 0
        copyManaged = load("SLSCopyManagedDisplaySpaces", as: CopyManaged.self)
        copySpaces = load("SLSCopySpacesForWindows", as: CopySpaces.self)
    }

    var canMove: Bool {
        guard let cls = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation") else { return false }
        return class_getInstanceMethod(cls, NSSelectorFromString("initWithWindows:spaceID:")) != nil &&
            class_getInstanceMethod(cls, NSSelectorFromString("performWithWMBridgeDelegate")) != nil
    }

    func desktops() throws -> [DesktopSpace] {
        guard connection != 0, let copyManaged,
              let raw = copyManaged(connection)?.takeRetainedValue() as? [[String: Any]] else {
            throw RuntimeError.message("macOS Spaces information is unavailable. No windows were moved.")
        }
        return raw.flatMap { display -> [DesktopSpace] in
            guard let displayUUID = display["Display Identifier"] as? String else { return [] }
            let current = ((display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value
            let userSpaces = (display["Spaces"] as? [[String: Any]] ?? []).filter { ($0["type"] as? NSNumber)?.intValue == 0 }
            return userSpaces.enumerated().compactMap { index, space in
                guard let id = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value else { return nil }
                let uuid = space["uuid"] as? String
                return DesktopSpace(id: id, uuid: uuid?.isEmpty == false ? uuid : nil, displayUUID: displayUUID,
                                    ordinal: index + 1, isCurrent: id == current)
            }
        }
    }

    func windowSpaces(_ windowID: UInt32) -> [UInt64] {
        guard let copySpaces else { return [] }
        let values = copySpaces(connection, 7, [NSNumber(value: windowID)] as CFArray)?.takeRetainedValue()
        return (values as? [NSNumber] ?? []).map(\.uint64Value)
    }

    func move(_ windowID: UInt32, to target: UInt64) async throws {
        if windowSpaces(windowID) == [target] { return }
        guard let cls = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation"),
              let allocation = (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else {
            throw RuntimeError.message("This macOS version does not support the Space move operation.")
        }
        let initSelector = NSSelectorFromString("initWithWindows:spaceID:")
        let performSelector = NSSelectorFromString("performWithWMBridgeDelegate")
        guard allocation.responds(to: initSelector) else {
            throw RuntimeError.message("The Space move initializer is unavailable.")
        }
        typealias Initializer = @convention(c) (AnyObject, Selector, NSArray, UInt64) -> AnyObject
        let initializer = unsafeBitCast(allocation.method(for: initSelector), to: Initializer.self)
        let operation = initializer(allocation, initSelector, [NSNumber(value: windowID)] as NSArray, target)
        guard operation.responds(to: performSelector) else {
            throw RuntimeError.message("The Space move operation is unavailable.")
        }
        typealias Perform = @convention(c) (AnyObject, Selector) -> Void
        unsafeBitCast(operation.method(for: performSelector), to: Perform.self)(operation, performSelector)
        for _ in 0..<75 {
            try await Task.sleep(nanoseconds: 20_000_000)
            if windowSpaces(windowID) == [target] {
                // Space membership updates before macOS finishes translating the
                // window's coordinates between displays. Wait before resizing it.
                try await Task.sleep(nanoseconds: 250_000_000)
                withExtendedLifetime(operation) {}; return
            }
        }
        withExtendedLifetime(operation) {}
        throw RuntimeError.message("macOS did not move the window to its saved Space.")
    }
}
