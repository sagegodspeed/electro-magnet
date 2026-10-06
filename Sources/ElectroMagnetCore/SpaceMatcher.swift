import Foundation

public struct DesktopSpace: Equatable {
    public let id: UInt64
    public let uuid: String?
    public let displayUUID: String
    public let ordinal: Int
    public let isCurrent: Bool

    public init(id: UInt64, uuid: String?, displayUUID: String, ordinal: Int, isCurrent: Bool) {
        self.id = id; self.uuid = uuid; self.displayUUID = displayUUID
        self.ordinal = ordinal; self.isCurrent = isCurrent
    }
}

public enum SpaceMatch: Equatable {
    case identity(Int), position(Int), missing
}

public enum SpaceMatcher {
    /// Match a Space within one identified monitor. Surviving identities take priority
    /// over desktop order. Session IDs are valid only within the saved boot session.
    public static func match(_ saved: SpaceDestination, displayUUID: String, in current: [DesktopSpace],
                             bootSession: String, allowPosition: Bool = true) -> SpaceMatch {
        let onDisplay = current.indices.filter {
            current[$0].displayUUID.caseInsensitiveCompare(displayUUID) == .orderedSame
        }
        let identity: [Int]
        if let uuid = saved.uuid, !uuid.isEmpty {
            identity = onDisplay.filter { current[$0].uuid?.caseInsensitiveCompare(uuid) == .orderedSame }
        } else if !saved.bootSession.isEmpty, saved.bootSession == bootSession {
            identity = onDisplay.filter { current[$0].id == saved.sessionID }
        } else { identity = [] }
        if identity.count == 1 { return .identity(identity[0]) }
        if identity.count > 1 { return .missing }
        guard allowPosition, saved.ordinal > 0 else { return .missing }
        let position = onDisplay.filter { current[$0].ordinal == saved.ordinal }
        return position.count == 1 ? .position(position[0]) : .missing
    }
}
