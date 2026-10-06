/// Stable identifier of a station, unique within a ``GameWorld``.
///
/// IDs are allocated sequentially by the world (never reused), so the same
/// sequence of actions always yields the same IDs.
public struct StationID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: StationID, rhs: StationID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A station: a point of the world it stands at (Stage F1).
///
/// Its platforms are on the track network (Stage S4,
/// ``GameWorld/trackPlatforms(of:)``), and stations may stand anywhere,
/// however near each other. Fares and demand measure the distance between
/// their points (Stage F3d). Until Stage F3c a station could also be built
/// on a tile and grow onto the tiles beside it, with the grid track beside
/// them as its platforms; that went with the grid (ARCHITECTURE decision
/// 51), and until Stage F3d a station also kept the tile under its point
/// (decision 54).
public struct Station: Identifiable, Hashable, Sendable {
    public let id: StationID
    public let name: String
    /// Where the station stands.
    public let point: PlanPoint
    /// Whether passengers may enter, change and leave here (Phase 5F, see
    /// ``StationOperationMode``). Set by
    /// ``GameWorld/setStationOperationMode(_:to:)`` only.
    public internal(set) var operationMode: StationOperationMode = .normalFlow

    /// A station standing at `point`.
    ///
    /// - Precondition: both components of `point` are 0 or more.
    public init(id: StationID, name: String, point: PlanPoint) {
        precondition(point.x >= 0 && point.y >= 0, "A station's point lies in the world")
        self.id = id
        self.name = name
        self.point = point
    }

    /// Where the station is seen from above: its point.
    public var location: PlanPoint {
        point
    }
}

extension Station: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, position, annexes, point, operationMode
    }

    /// Decodes a station, `{"id", "name", "point"}` (Stage F1), rejecting a
    /// point with a negative component; that the point lies in the world's
    /// bounds is checked by the ``GameWorld`` decoder.
    ///
    /// A station on tiles (`"position"`, and `"annexes"` once it had grown),
    /// which only a save made by hand could hold (the app has built stations
    /// at points since saves began, Stage C4), is refused with that reason:
    /// the grid went in Stage F3c (ARCHITECTURE decision 51).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(StationID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        guard !container.contains(.position), !container.contains(.annexes) else {
            throw DecodingError.dataCorruptedError(
                forKey: container.contains(.position) ? .position : .annexes, in: container,
                debugDescription: "Station \(id.rawValue) stands on tiles, which is no longer supported: the grid was removed in Stage F3c. Only a save made by hand could hold one."
            )
        }
        let point = try container.decode(PlanPoint.self, forKey: .point)
        guard point.x >= 0, point.y >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .point, in: container, debugDescription: "Station \(id.rawValue) stands outside the world."
            )
        }
        self.init(id: id, name: name, point: point)
        // Saves before version 12 have no operation mode: every station
        // is open.
        operationMode = try container.decodeIfPresent(StationOperationMode.self, forKey: .operationMode) ?? .normalFlow
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(point, forKey: .point)
        if operationMode != .normalFlow {
            try container.encode(operationMode, forKey: .operationMode)
        }
    }
}

/// A station's operation mode (Phase 5F), ported from the owner's `Ci/`
/// reference (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`:
/// `applyStationOperationToStation` accepts exactly these three values, and
/// a station without one is `"normalFlow"`):
///
/// - ``normalFlow``: passengers enter, change and leave as usual.
/// - ``flowControl``: no new passengers enter here
///   (`metroStationAllowsEntryForLine` is true only for `normalFlow`), but
///   trains still serve it and passengers still change here and arrive.
/// - ``closed``: no passenger boards, alights, changes or arrives here
///   (`metroStationAllowsTrainServiceAtStation`, `metroStationAllowsTransfer`
///   and `metroStationAllowsPassengerDestination` are false), and those
///   waiting here leave when it closes (`clearStationWaitingPassengers`).
public enum StationOperationMode: String, Codable, CaseIterable, Sendable {
    case normalFlow
    case flowControl
    case closed

    /// Whether new passengers may set out from the station.
    public var allowsEntry: Bool { self == .normalFlow }

    /// Whether passengers may board, alight, change or arrive here.
    public var allowsService: Bool { self != .closed }
}
