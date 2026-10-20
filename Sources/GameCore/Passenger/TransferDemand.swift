// The real network's transfers (ARCHITECTURE decision 298): on a real-world
// map, a station of the player's that stands by a real station brings the
// people who change there from the real railways.
//
// GameCore never reads the real railways. GamePresentation works out how
// many transfer points the real stations within the site's transfer
// distance give each station (by system and TRA grade) and sets them with
// ``GameWorld/setTransfers(_:)``; the world keeps only the number
// (``Station/transferPoints``). Each point brings
// ``TransferDemand/tripsPerPoint`` trips a day, added to the station's
// ridership from the land as the outside connections' are (decision 137):
// the travellers set out from it, and the other stations' trips are drawn
// to it. They pay the fare of the player's part of the way, nothing more.
//
// The owner's references have no rule for it (gap): the site's
// `station_transfers.json` lists which routes meet at a place, not how many
// people change there, and no ridership by station ships with the app. The
// numbers are this project's, chosen with `BalanceReportTests`.

/// The rules of the real network's transfers (ARCHITECTURE decision 298).
public enum TransferDemand {
    /// The trips a day each transfer point brings.
    public static let tripsPerPoint: Int64 = 100
    /// The most transfer points a station can have.
    public static let maximumPoints: Int64 = 100
}

extension GameWorld {
    // MARK: - Commands

    /// Turns the real network's transfers on or off (decision 298). Off,
    /// every station's transfer points go. Free; passengers already
    /// waiting stay.
    public mutating func setRealTransfers(_ enabled: Bool) {
        guard enabled != realTransfers else { return }
        realTransfers = enabled
        if !enabled {
            for index in stations.indices { setTransferPoints(0, at: index) }
        }
        passengerPlan = PassengerPlanCache()
        refreshLandDemand()
    }

    /// Sets every station's transfer points (decision 298): those `points`
    /// names to theirs, every other station to none. Free; passengers
    /// already waiting stay. Changes nothing when every station already
    /// has its points.
    ///
    /// - Throws: ``GameError/unknownStation(_:)`` for a station that does
    ///   not exist; ``GameError/invalidStationDemand`` while real transfers
    ///   are off (``realTransfers``), for points outside 0 to
    ///   ``TransferDemand/maximumPoints`` or for a depot's above 0. The
    ///   world is then unchanged.
    public mutating func setTransfers(_ points: [StationID: Int64]) throws(GameError) {
        for (id, value) in points.sorted(by: { $0.key < $1.key }) {
            guard let station = station(id: id) else { throw .unknownStation(id) }
            guard realTransfers, (0...TransferDemand.maximumPoints).contains(value), value == 0 || !station.isDepot else {
                throw .invalidStationDemand
            }
        }
        var changed = false
        for index in stations.indices {
            let value = points[stations[index].id] ?? 0
            guard stations[index].transferPoints != value else { continue }
            setTransferPoints(value, at: index)
            changed = true
        }
        guard changed else { return }
        passengerPlan = PassengerPlanCache()
        refreshLandDemand()
    }

    // MARK: - Queries

    /// The trips a day station `id`'s transfers bring (decision 298): its
    /// transfer points times ``TransferDemand/tripsPerPoint``. 0 for an
    /// unknown station, with real transfers off, and for a closed station.
    public func transferTrips(of id: StationID) -> Int64 {
        guard realTransfers, let station = station(id: id), station.operationMode != .closed else { return 0 }
        return station.transferPoints * TransferDemand.tripsPerPoint
    }

    // MARK: - Deriving

    /// The trips each of `stations` adds to its ridership for its transfers
    /// (``transferTrips(of:)``). Empty with real transfers off.
    func transferTrips(among stations: [Station]) -> [StationID: Int64] {
        guard realTransfers else { return [:] }
        var trips: [StationID: Int64] = [:]
        for station in stations where station.transferPoints > 0 {
            trips[station.id] = station.transferPoints * TransferDemand.tripsPerPoint
        }
        return trips
    }
}
