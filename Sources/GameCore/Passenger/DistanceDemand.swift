// Demand by distance and the outside connections (ARCHITECTURE decision
// 137): one rule for how far a trip goes.
//
// - Short trips walk. A pair's daily trips, once its origin's trips are
//   shared among the stations it reaches, keep a share that grows with the
//   straight-line distance between the two stations (the fare's distance):
//   ``DistanceDemand/nearShare`` up to ``DistanceDemand/nearDistance``, all
//   of them from ``DistanceDemand/fullDistance``, in a straight line
//   between. A line a few hundred metres long no longer carries the whole
//   of its catchment's trips (the balance report's item 3), and a station
//   that reaches far stations sends more of its trips than one that
//   reaches only its neighbours.
// - The map is not the whole world. A station within
//   ``DistanceDemand/outsideMargin`` of the map's edge is an outside
//   connection: it stands for the towns beyond the edge. The outside's
//   ``DistanceDemand/outsideTrips`` a day are shared among the open
//   outside connections and added to their ridership from the land, so
//   visitors set out from them and the other stations' trips are drawn to
//   them; a trip between one and a station that is not one goes beyond
//   the map, so it keeps all its trips whatever the distance on it (two
//   outside connections keep the share of their distance, decision 148),
//   and every trip to or from one pays the fare and
//   ``DistanceDemand/outsideFareMultiple`` times the city's fare baseline
//   for the way beyond (the long-distance fare).
//
// The owner's references have no rule for either (gap): `Ci/` reads its
// flows from a server it does not ship, and the reference pack names
// OpenTTD's `demand_distance` only by its setting. The numbers are this
// project's, chosen by `BalanceReportTests`. Both are off in a new world and
// in saves from before them; the app's new games turn them on, but for the
// whole of Taiwan, whose edge is the sea.

/// The rules of demand by distance and the outside connections (ARCHITECTURE
/// decision 137).
public enum DistanceDemand {
    /// Up to this straight-line distance (500 m) a pair keeps only
    /// ``nearShare`` of its trips: the rest walk.
    public static let nearDistance: Int64 = 32_000
    /// From this distance (2 km) a pair keeps all its trips.
    public static let fullDistance: Int64 = 128_000
    /// The share of its trips a pair at most ``nearDistance`` apart keeps,
    /// in thousandths: 10 %.
    public static let nearShare: Int64 = 100

    /// A station whose point lies within this distance (1 km) of the map's
    /// edge is an outside connection.
    public static let outsideMargin: Int64 = 64_000
    /// The trips the outside starts each day, shared among the outside
    /// connections.
    public static let outsideTrips: Int64 = 6_000
    /// How many times the city's fare baseline a trip to or from an outside
    /// connection pays on top of its fare.
    public static let outsideFareMultiple: Int64 = 1

    /// The share of its trips a pair `squaredDistance` (world units
    /// squared) apart keeps, in thousandths: ``nearShare`` up to
    /// ``nearDistance``, 1000 from ``fullDistance``, and in a straight line
    /// between them by the distance rounded down to a unit.
    public static func share(squaredDistance: Int64) -> Int64 {
        let distance = FixedPoint.squareRoot(max(0, squaredDistance))
        guard distance > nearDistance else { return nearShare }
        guard distance < fullDistance else { return 1_000 }
        return nearShare + (1_000 - nearShare) * (distance - nearDistance) / (fullDistance - nearDistance)
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Turns demand by distance on or off (decision 137): on, each pair's
    /// trips keep the share ``DistanceDemand/share(squaredDistance:)`` gives
    /// its distance. Passengers already waiting stay.
    public mutating func setDistanceDemand(_ enabled: Bool) {
        guard enabled != distanceDemand else { return }
        distanceDemand = enabled
        passengerPlan = PassengerPlanCache()
    }

    /// Turns the outside connections on or off (decision 137): on, the
    /// stations by the map's edge bring the outside's trips and charge the
    /// long-distance fare. Passengers already waiting stay.
    public mutating func setOutsideConnections(_ enabled: Bool) {
        guard enabled != outsideConnections else { return }
        outsideConnections = enabled
        passengerPlan = PassengerPlanCache()
        refreshLandDemand()
    }

    // MARK: - Queries

    /// Whether station `id` is an outside connection: the outside
    /// connections are on and its point lies within
    /// ``DistanceDemand/outsideMargin`` of the map's edge. `false` for an
    /// unknown station.
    public func isOutsideConnection(_ id: StationID) -> Bool {
        guard outsideConnections, let station = station(id: id) else { return false }
        return isOutsideConnectionSite(station.point)
    }

    /// Whether a station at `point` would be an outside connection: the
    /// outside connections are on and `point` lies within
    /// ``DistanceDemand/outsideMargin`` of the map's edge.
    public func isOutsideConnectionSite(_ point: PlanPoint) -> Bool {
        outsideConnections && Self.liesByTheEdge(point, of: bounds)
    }

    /// What a trip to or from an outside connection pays on top of its fare:
    /// ``DistanceDemand/outsideFareMultiple`` times the city's fare
    /// baseline.
    public var outsideFare: Money {
        Money(DistanceDemand.outsideFareMultiple * accounts.fareBaseline.amount)
    }

    static func liesByTheEdge(_ point: PlanPoint, of bounds: WorldBounds) -> Bool {
        let margin = DistanceDemand.outsideMargin
        return point.x < margin || point.y < margin || bounds.width - point.x <= margin || bounds.height - point.y <= margin
    }

    // MARK: - Deriving

    /// `trips` from `origin` to `destination` as their distance keeps them
    /// (see ``DistanceDemand/share(squaredDistance:)``), rounded half up,
    /// while demand by distance is on; all of them between an outside
    /// connection and a station that is not one (the trip goes beyond the
    /// map), and unchanged with it off. A pair of outside connections keeps
    /// the share of its distance like any other (decision 148): two of them
    /// side by side are a short trip along the edge, not a trip beyond it.
    func distancedTrips(_ trips: Int64, from origin: StationID, to destination: StationID) -> Int64 {
        guard distanceDemand, trips > 0, isOutsideConnection(origin) == isOutsideConnection(destination),
              let squared = squaredDistance(from: origin, to: destination)
        else { return trips }
        return (trips * DistanceDemand.share(squaredDistance: squared) + 500) / 1_000
    }

    /// `trips` from `origin` to `destination` as their distance and then
    /// their fare keep them: the pair's trips of its origin's share.
    func keptTrips(_ trips: Int64, from origin: StationID, to destination: StationID) -> Int64 {
        faredTrips(distancedTrips(trips, from: origin, to: destination), from: origin, to: destination)
    }

    /// The outside's trips each of `stations` adds to its ridership:
    /// ``DistanceDemand/outsideTrips`` shared equally among the outside
    /// connections, the lower stations first for what is left over. Empty
    /// with the outside connections off.
    func outsideTrips(among stations: [Station]) -> [StationID: Int64] {
        guard outsideConnections else { return [:] }
        let connections = stations.filter { Self.liesByTheEdge($0.point, of: bounds) }.map(\.id).sorted()
        guard !connections.isEmpty else { return [:] }
        let shares = Self.apportion(DistanceDemand.outsideTrips, by: connections.map { _ in 1 })
        return Dictionary(uniqueKeysWithValues: zip(connections, shares))
    }
}
