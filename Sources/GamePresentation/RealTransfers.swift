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
// The points stand for how many people change there: the real station's
// riders a day where the app ships them (``RealRidership``: Taiwan Railway,
// the High Speed Rail, the Taipei, New Taipei, Taichung and Kaohsiung
// metros and the Taoyuan Airport MRT, official averages), in
// proportion, so a station ten times as busy brings ten times the
// transfers; elsewhere what a station of its system or TRA grade has.

/// What the transfer points were last worked out from (decision 298): the
/// stations' places, and whether the railways were there.
struct TransferMemo: Equatable {
    var stations: [StationID: PlanPoint]
    var hasRailways: Bool
    var points: [StationID: Int64]
}

extension GameSession {
    /// The real riders a day one transfer point stands for (decision 298):
    /// Taipei's TRA station (63,307) is 63 points, Changhua's High Speed
    /// Rail station (2,621) 3, a halt of a hundred 1.
    static let transferRidersPerPoint = 1_000

    /// The transfer points a system's station gives a place (decision 298):
    /// its real riders a day over ``transferRidersPerPoint``, rounded and
    /// at least 1, where `ridership` has them. Otherwise what a station
    /// like it has: a Taiwan Railway station of its grade, the grade's
    /// median riders of 2025 (special 14, first 9, second 2, any other 1);
    /// a metro 3; the High Speed Rail 20; a light rail (the Kaohsiung
    /// Circular Light Rail's stops among them), the Sanying Line and the
    /// Alishan Forest Railway 1.
    static func transferPoints(of station: RealRailways.Station, data: RealStationData?, ridership: RealRidership? = nil) -> Int64 {
        if let riders = ridership?.riders(of: station, data: data) {
            return max(1, Int64((Double(riders) / Double(transferRidersPerPoint)).rounded()))
        }
        switch station.system.id {
        case "thsr_sched":
            return 20
        case "tra_sched":
            switch data?.stationClass(forStation: station.chinese) {
            case .special: return 14
            case .first: return 9
            case .second: return 2
            default: return 1
            }
        case "krtc":
            // The system holds the Circular Light Rail's stops too. The
            // Kaohsiung Metro's file has every station of its two lines,
            // so one of the system it lacks is a light rail stop: a light
            // rail's 1 (the whole line carried some 40,000 a day over 38
            // stops in 2026-09).
            return ridership?.krtc == nil ? 3 : 1
        case "mrt", "tmrt", "tymc":
            return 3
        default:
            return 1
        }
    }

    /// The transfer points the real place `place` gives a station by it:
    /// the points of each of its systems, the highest where a system has
    /// several stations there, added up, at most
    /// ``TransferDemand/maximumPoints``.
    static func transferPoints(of place: RealStationSuggestion, data: RealStationData?, ridership: RealRidership? = nil) -> Int64 {
        var bySystem: [String: Int64] = [:]
        for station in place.stations {
            bySystem[station.system.id] = max(bySystem[station.system.id] ?? 0, transferPoints(of: station, data: data, ridership: ridership))
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
            let value = Self.transferPoints(of: place, data: data, ridership: railways?.ridership)
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
        // Decision 315: past the junction of a line the company bought,
        // Taiwan Railway's riders there are the line's own.
        if place.systems.map(\.id) == ["tra_sched"], isOnBoughtLinePastItsJunction(id) {
            return language.text("Regulars along the line: about \(count) a day", "沿線的常客：每天約 \(count) 人")
        }
        return language.text("Changing here from \(systems): about \(count) a day", "從\(systems)轉乘：每天約 \(count) 人")
    }

    /// Whether station `id` is a stop of a real line bought, other than
    /// its last, the junction with the main line (decision 315; the line
    /// runs from its terminal, see ``GameSession/routePreferences(_:stops:)``).
    func isOnBoughtLinePastItsJunction(_ id: StationID) -> Bool {
        world.acquisitions.contains { bought in
            world.line(id: bought.line)?.stops.dropLast().contains(id) ?? false
        }
    }
}
