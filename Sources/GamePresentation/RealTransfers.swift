import Foundation
import GameCore

// The real network's transfers (ARCHITECTURE decision 298): on a real-world
// map whose game has them on (``GameWorld/realTransfers``), a station of the
// player's within the site's transfer distance (450 m) of a real station
// brings the people who change there from the real railways. GameCore keeps
// only each station's transfer points; this file works them out from the
// real place nearest the station (``GameSession/nearestRealStation(to:within:)``,
// decision 295) and sets them after every edit and when the railways
// arrive (``GameSession/refreshTransfers()``).
//
// The points stand for how many people change there, which no file the app
// ships gives by station: the system's size and, for Taiwan Railway, the
// station's official grade (`tra_station_class.json`), as the platform's
// default length already reads it (``GameSession/realPlatformCars(forStationNamed:at:)``).

/// What the transfer points were last worked out from (decision 298): the
/// stations' places, and whether the railways were there.
struct TransferMemo: Equatable {
    var stations: [StationID: PlanPoint]
    var hasRailways: Bool
    var points: [StationID: Int64]
}

extension GameSession {
    /// The transfer points a system's station gives a place (decision 298):
    /// high-speed rail and Taiwan Railway's special-class stations 6, its
    /// first-class 4, second-class 2 and any other 1; a metro 2; a light
    /// rail, the Sanying Line and the Alishan Forest Railway 1.
    static func transferPoints(of station: RealRailways.Station, data: RealStationData?) -> Int64 {
        switch station.system.id {
        case "thsr_sched":
            return 6
        case "tra_sched":
            switch data?.stationClass(forStation: station.chinese) {
            case .special: return 6
            case .first: return 4
            case .second: return 2
            default: return 1
            }
        case "mrt", "krtc", "tmrt", "tymc":
            return 2
        default:
            return 1
        }
    }

    /// The transfer points the real place `place` gives a station by it:
    /// the points of each of its systems, the highest where a system has
    /// several stations there, added up, at most
    /// ``TransferDemand/maximumPoints``.
    static func transferPoints(of place: RealStationSuggestion, data: RealStationData?) -> Int64 {
        var bySystem: [String: Int64] = [:]
        for station in place.stations {
            bySystem[station.system.id] = max(bySystem[station.system.id] ?? 0, transferPoints(of: station, data: data))
        }
        return min(bySystem.values.reduce(0, +), TransferDemand.maximumPoints)
    }

    /// The real place station `id` changes with: the nearest within the
    /// site's transfer distance, while the game has real transfers on;
    /// `nil` for a depot, on a blank map or without the railways.
    public func transferPlace(of id: StationID) -> RealStationSuggestion? {
        guard world.realTransfers, let station = world.station(id: id), !station.isDepot else { return nil }
        return nearestRealStation(to: station.point)
    }

    /// The transfer points every station should have now (decision 298),
    /// those with none left out.
    func wantedTransfers() -> [StationID: Int64] {
        var points: [StationID: Int64] = [:]
        let data = railways?.stationData
        for station in world.stations {
            guard let place = transferPlace(of: station.id) else { continue }
            let value = Self.transferPoints(of: place, data: data)
            if value > 0 { points[station.id] = value }
        }
        return points
    }

    /// Sets every station's transfer points to those the real railways
    /// give it now (decision 298): after every edit, and when the
    /// railways arrive. Nothing while the game has real transfers off or
    /// the session has no railways (a replay has the values in its log), or
    /// when the stations stand where they stood the last time.
    func refreshTransfers() {
        guard world.realTransfers, railways != nil, RealWorldFrame(world: world) != nil else { return }
        let stations = Dictionary(uniqueKeysWithValues: world.stations.filter { !$0.isDepot }.map { ($0.id, $0.point) })
        let points: [StationID: Int64]
        if let memo = transferMemo, memo.stations == stations, memo.hasRailways {
            points = memo.points
        } else {
            points = wantedTransfers()
            transferMemo = TransferMemo(stations: stations, hasRailways: true, points: points)
        }
        let current = Dictionary(uniqueKeysWithValues: world.stations.filter { $0.transferPoints > 0 }.map { ($0.id, $0.transferPoints) })
        guard points != current else { return }
        applyTransfers(points)
    }

    /// Who changes at station `id` from the real railways (decision 298):
    /// the systems of the real place by it and the trips a day they bring.
    /// `nil` for a station that brings none.
    public func transferText(of id: StationID) -> String? {
        let trips = world.transferTrips(of: id)
        guard trips > 0, let place = transferPlace(of: id) else { return nil }
        let systems = place.systems.map { $0.name(in: language) }.joined(separator: language.text(", ", "、"))
        let count = trips.formatted()
        return language.text("Changing here from \(systems): about \(count) a day", "從\(systems)轉乘：每天約 \(count) 人")
    }
}
