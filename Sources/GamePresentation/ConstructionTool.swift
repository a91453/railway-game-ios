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

    /// Short name for the tool picker.
    public var title: String {
        switch self {
        case .select: "Select"
        case .buildTrack: "Track"
        case .buildStation: "Station"
        case .removeTrack: "Remove"
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

    public var title: String {
        switch self {
        case .straight: "Straight"
        case .curve: "Curve"
        case .junction: "T-junction"
        case .fourWay: "Four-way"
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
