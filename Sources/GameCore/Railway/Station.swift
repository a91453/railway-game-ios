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
    /// Its name; ``GameWorld/renameStation(_:to:)`` changes it.
    public internal(set) var name: String
    /// Where the station stands.
    public let point: PlanPoint
    /// Whether passengers may enter, change and leave here (Phase 5F, see
    /// ``StationOperationMode``). Set by
    /// ``GameWorld/setStationOperationMode(_:to:)`` only.
    public internal(set) var operationMode: StationOperationMode = .normalFlow
    /// Whether the station is a depot (decision 209): where lines keep
    /// their trains out of service. No line calls at it, and its platforms
    /// are sidings no line's service runs over. Set by
    /// ``GameWorld/setStationDepot(_:to:)`` only; not one of the
    /// ``StationOperationMode``s, which the player switches on the panel.
    public internal(set) var isDepot: Bool = false
    /// The shops the company runs in it (decision 222), `nil` for none.
    /// Set by ``GameWorld/buildStationCommerce(at:)``,
    /// ``GameWorld/upgradeStationCommerce(at:)`` and
    /// ``GameWorld/demolishStationCommerce(at:)`` only; a depot has none.
    public internal(set) var commerce: StationCommerceLevel?
    /// How many transfer points the real railways nearby give it (decision
    /// 298): 0 for none. Each brings ``TransferDemand/tripsPerPoint`` trips
    /// a day from the real network. Set by ``GameWorld/setTransfers(_:)``
    /// only, while ``GameWorld/realTransfers`` is on; a depot has none.
    public internal(set) var transferPoints: Int64 = 0

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
        case id, name, position, annexes, point, operationMode, depot, commerce, transferPoints
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
        // A station written without an operation mode (every save before
        // Phase 5F's station modes, and every open station since) is open.
        operationMode = try container.decodeIfPresent(StationOperationMode.self, forKey: .operationMode) ?? .normalFlow
        // Only a station not run normally is written with a mode, so a save
        // has one form (the rule #157's stationOperations list kept too).
        if container.contains(.operationMode), operationMode == .normalFlow {
            throw DecodingError.dataCorruptedError(
                forKey: .operationMode, in: container,
                debugDescription: "Station \(id.rawValue) is written with \"normalFlow\", which a save leaves out."
            )
        }
        // Decision 209: only a depot is written with `"depot": true`.
        isDepot = try container.decodeIfPresent(Bool.self, forKey: .depot) ?? false
        if container.contains(.depot), !isDepot {
            throw DecodingError.dataCorruptedError(
                forKey: .depot, in: container, debugDescription: "Station \(id.rawValue) is written with \"depot\": false, which a save leaves out."
            )
        }
        // Decision 222: a station without `"commerce"` has none (every save
        // before version 57), and a depot has none.
        commerce = container.contains(.commerce) ? try container.decode(StationCommerceLevel.self, forKey: .commerce) : nil
        if commerce != nil, isDepot {
            throw DecodingError.dataCorruptedError(
                forKey: .commerce, in: container, debugDescription: "Station \(id.rawValue) is a depot, which has no shops."
            )
        }
        // Decision 298: only a station with transfer points is written with
        // them (every save before version 64 has none).
        if container.contains(.transferPoints) {
            transferPoints = try container.decode(Int64.self, forKey: .transferPoints)
            guard (1...TransferDemand.maximumPoints).contains(transferPoints), !isDepot else {
                throw DecodingError.dataCorruptedError(
                    forKey: .transferPoints, in: container,
                    debugDescription: "Station \(id.rawValue) has \(transferPoints) transfer points: 1 to \(TransferDemand.maximumPoints), and none at a depot."
                )
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(point, forKey: .point)
        // Written only when not open, so a save keeps its earlier form.
        if operationMode != .normalFlow {
            try container.encode(operationMode, forKey: .operationMode)
        }
        if isDepot {
            try container.encode(true, forKey: .depot)
        }
        try container.encodeIfPresent(commerce, forKey: .commerce)
        if transferPoints > 0 {
            try container.encode(transferPoints, forKey: .transferPoints)
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
