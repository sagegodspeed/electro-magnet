import Foundation

public struct WindowFrame: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
    }
    public func isNear(_ other: WindowFrame, tolerance: Double = 2) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance &&
        abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
    public func clamped(to bounds: WindowFrame) -> WindowFrame {
        let w = min(width, bounds.width), h = min(height, bounds.height)
        return WindowFrame(x: min(max(x, bounds.x), bounds.x + bounds.width - w),
                           y: min(max(y, bounds.y), bounds.y + bounds.height - h), width: w, height: h)
    }
    /// Keep a minimum-size window's title bar reachable even if the window cannot fit.
    public func reachable(in bounds: WindowFrame) -> WindowFrame {
        WindowFrame(x: min(max(x, bounds.x), max(bounds.x, bounds.x + bounds.width - width)),
                    y: min(max(y, bounds.y), max(bounds.y, bounds.y + bounds.height - min(height, bounds.height))),
                    width: width, height: height)
    }
}

public struct WindowIdentity: Codable, Equatable {
    public var bundleID: String
    public var appName: String
    public var pid: Int32
    public var processStarted: Date?
    public var windowID: UInt32
    public var title: String
    public var document: String?
    public var identifier: String?
    public init(bundleID: String, appName: String, pid: Int32, processStarted: Date?, windowID: UInt32,
                title: String, document: String? = nil, identifier: String? = nil) {
        self.bundleID = bundleID; self.appName = appName; self.pid = pid; self.processStarted = processStarted
        self.windowID = windowID; self.title = title; self.document = document; self.identifier = identifier
    }
}

public struct SpaceDestination: Codable, Equatable {
    public var uuid: String?
    public var sessionID: UInt64
    public var ordinal: Int
    public var bootSession: String
    public init(uuid: String?, sessionID: UInt64, ordinal: Int, bootSession: String = "") {
        self.uuid = uuid?.isEmpty == false ? uuid : nil; self.sessionID = sessionID; self.ordinal = ordinal
        self.bootSession = bootSession
    }
}

public struct SavedWindow: Codable, Equatable {
    public var identity: WindowIdentity
    public var displayUUID: String
    public var displayName: String
    public var space: SpaceDestination
    /// Top-left offset in points from the display's usable frame, in AX coordinates.
    public var relativeFrame: WindowFrame
    public init(identity: WindowIdentity, displayUUID: String, displayName: String,
                space: SpaceDestination, relativeFrame: WindowFrame) {
        self.identity = identity; self.displayUUID = displayUUID; self.displayName = displayName
        self.space = space; self.relativeFrame = relativeFrame
    }
}

public struct Layout: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var savedAt: Date
    public var windows: [SavedWindow]
    public init(id: UUID = UUID(), name: String, savedAt: Date = Date(), windows: [SavedWindow]) {
        self.id = id; self.name = name; self.savedAt = savedAt; self.windows = windows
    }
}

public struct LayoutFile: Codable {
    public var version: Int = 1
    public var layouts: [Layout]
    public init(layouts: [Layout]) { self.layouts = layouts }
}

public enum LayoutError: LocalizedError {
    case invalidName, duplicateName, missingLayout, unsupportedVersion, invalidData
    public var errorDescription: String? {
        switch self {
        case .invalidName: return "Enter a layout name."
        case .duplicateName: return "A layout already has that name. Use Overwrite to replace it."
        case .missingLayout: return "That layout no longer exists."
        case .unsupportedVersion: return "This layout file was created by a newer app version. It has not been modified."
        case .invalidData: return "The layout file contains invalid window data. It has not been modified."
        }
    }
}

public final class LayoutStore {
    public let url: URL
    public private(set) var layouts: [Layout] = []
    public init(url: URL) { self.url = url }
    public func load() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { layouts = []; return }
        let file = try JSONDecoder().decode(LayoutFile.self, from: Data(contentsOf: url))
        guard file.version == 1 else { throw LayoutError.unsupportedVersion }
        guard Set(file.layouts.map(\.id)).count == file.layouts.count,
              Set(file.layouts.map { $0.name.lowercased() }).count == file.layouts.count,
              file.layouts.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  $0.windows.allSatisfy { $0.relativeFrame.isValid && !$0.displayUUID.isEmpty && !$0.identity.bundleID.isEmpty } })
        else { throw LayoutError.invalidData }
        layouts = file.layouts
    }
    @discardableResult public func save(name: String, windows: [SavedWindow], replacing id: UUID? = nil) throws -> Layout {
        let clean = try checkedName(name, excluding: id)
        if let id, !layouts.contains(where: { $0.id == id }) { throw LayoutError.missingLayout }
        let layout = Layout(id: id ?? UUID(), name: clean, windows: windows)
        var updated = layouts
        if let index = updated.firstIndex(where: { $0.id == layout.id }) { updated[index] = layout }
        else { updated.append(layout) }
        try commit(updated)
        return layout
    }
    public func rename(id: UUID, to name: String) throws {
        let clean = try checkedName(name, excluding: id)
        var updated = layouts
        guard let index = updated.firstIndex(where: { $0.id == id }) else { throw LayoutError.missingLayout }
        updated[index].name = clean
        try commit(updated)
    }
    public func delete(id: UUID) throws {
        guard layouts.contains(where: { $0.id == id }) else { throw LayoutError.missingLayout }
        try commit(layouts.filter { $0.id != id })
    }
    private func checkedName(_ name: String, excluding id: UUID?) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw LayoutError.invalidName }
        guard !layouts.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(clean) == .orderedSame })
        else { throw LayoutError.duplicateName }
        return clean
    }
    private func commit(_ updated: [Layout]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LayoutFile(layouts: updated))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        layouts = updated
    }
}
