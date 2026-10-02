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
    /// Places the selected train at the selected station, or sends it
    /// there once it is on the track (see ``GameSession/applyTool()``).
    case train

    /// The tools the app offers (Stage F1): it builds only on the track
    /// network. The grid's track, station and remove tools stay in the
    /// session for the compatibility layer until the grid goes (Stage F3).
    public static let networkTools: [ConstructionTool] = [.select, .network, .train]

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

/// What kind of grid piece the track tool lays (Stage C2): a plain piece,
/// whose exits all join, or one of Phase 4.5 Stage S1's turnouts and level
/// crossings, which GameCore had and the app could not build.
public enum TrackPieceKind: CaseIterable, Hashable, Sendable {
    case plain
    /// The stem joins every other exit; those join only the stem.
    case turnout
    /// Two straight tracks crossing without joining.
    case crossing

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .plain: language.text("Plain", "一般")
        case .turnout: language.text("Turnout", "道岔")
        case .crossing: language.text("Crossing", "平面交叉")
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
