import GameCore

/// What the action button does to the selected tile.
///
/// Presentation state only: the tool is never stored in GameCore, and
/// choosing one changes nothing in the world until the player acts.
public enum ConstructionTool: CaseIterable, Hashable, Sendable {
    /// Inspect tiles without changing anything.
    case select
    case buildTrack
    case buildStation
    case removeTrack
    /// Builds the track network at any angle, its platforms, and removes
    /// it (Stage C1; see ``GameSession/networkMode``).
    case network
    /// Places the selected train on the selected tile, or sends it there
    /// once it is on the track (see ``GameSession/applyTool()``).
    case train

    /// Short name for the tool picker.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .select: language.text("Select", "選取")
        case .buildTrack: language.text("Track", "軌道")
        case .buildStation: language.text("Station", "車站")
        case .removeTrack: language.text("Remove", "拆除")
        case .network: language.text("Network", "路網")
        case .train: language.text("Train", "列車")
        }
    }
}

/// Common track pieces the player can start from before adjusting
/// individual directions.
public enum TrackPiece: CaseIterable, Hashable, Sendable {
    case straight
    case curve
    case junction
    /// Four exits that all join each other (GameCore has no crossing
    /// without a junction).
    case fourWay

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .straight: language.text("Straight", "直線")
        case .curve: language.text("Curve", "彎道")
        case .junction: language.text("T-junction", "T 字岔")
        case .fourWay: language.text("Four-way", "十字")
        }
    }

    /// The piece in its default orientation; rotate it for the others.
    public var connections: TrackConnections {
        switch self {
        case .straight: [.east, .west]
        case .curve: [.south, .east]
        case .junction: [.east, .south, .west]
        case .fourWay: [.north, .east, .south, .west]
        }
    }
}

extension TrackDirection {
    /// The direction a quarter turn clockwise from this one.
    public var clockwise: TrackDirection {
        switch self {
        case .north: .east
        case .east: .south
        case .south: .west
        case .west: .north
        }
    }
}

extension TrackConnections {
    /// The same piece turned a quarter turn clockwise.
    public var rotatedClockwise: TrackConnections {
        TrackConnections(directions.map { TrackConnections($0.clockwise) })
    }
}
