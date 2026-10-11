import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// High-speed rail (decision 168) against the real Taiwan High Speed Rail,
/// printed as Markdown, so the gravity's constant
/// (``HighSpeed/tripsPerMillionSquared``) and the hinterland's radius are
/// chosen from what the twelve real stations would carry instead of worked
/// out by hand. It asserts nothing and runs only on request:
///
///     BALANCE_REPORT=1 swift test -c release -Xswiftc -enable-testing \
///       --filter HighSpeedReportTests
@MainActor
final class HighSpeedReportTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let population: PopulationGrid = {
        do {
            return try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json")))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    private static let places: PlaceGrid = {
        do {
            return try PlaceGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_places.json")))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    /// The twelve stations of `thsr_track.json`: name, latitude, longitude,
    /// and metres along the track from the Nangang end.
    private static let stations: [(name: String, latitude: Double, longitude: Double, chainage: Int64)] = {
        do {
            let data = try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/thsr_track.json"))
            guard let file = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let line = (file["lines"] as? [[String: Any]])?.first,
                  let list = line["stations"] as? [[String: Any]]
            else { preconditionFailure("thsr_track.json has changed shape") }
            let english = ["Nangang", "Taipei", "Banqiao", "Taoyuan", "Hsinchu", "Miaoli", "Taichung", "Changhua", "Yunlin", "Chiayi", "Tainan", "Zuoying"]
            return list.enumerated().map { index, entry in
                (english[index], entry["lat"] as! Double, entry["lon"] as! Double, Int64((entry["d"] as! Double) * 1_000))
            }
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    /// What the real Taiwan High Speed Rail carries a day, to the nearest
    /// ten thousand (public statistics, not in the references, so the
    /// target is the owner's to confirm).
    private static let realBoardings: Int64 = 180_000

    // MARK: - The hinterlands

    /// The twelve real stations on the whole of Taiwan, a high-speed line
    /// calling at all of them, the land round them read in as the game does
    /// it: each station's hinterland, and what the land costs.
    private func hinterlands() throws -> (people: [Int64], cells: Int, seconds: Double) {
        var world = GameWorld.newWholeTaiwanGame()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var ids: [StationID] = []
        for station in Self.stations {
            let at = frame.worldPosition(latitude: station.latitude, longitude: station.longitude)
            ids.append(try world.buildStation(named: station.name, at: PlanPoint(x: Int64(at.x.rounded()), y: Int64(at.y.rounded()))).id)
        }
        let line = try world.createLine(named: "THSR", stops: ids).id
        try world.setLinePerformance(line, to: .highSpeed)
        let start = Date()
        GameSession.readLand(roundStationsOf: &world, population: Self.population, places: Self.places)
        let seconds = Date().timeIntervalSince(start)
        return (ids.map { world.stationDemand(of: $0)?.hinterland ?? 0 }, world.land.cells.count, seconds)
    }

    // MARK: - The line

    /// A straight track with the twelve stations at their chainage, three
    /// high-speed lines on it as the real day has them (all twelve stops, the
    /// nine-stop and the five-stop express), the hinterlands `people`, in
    /// network routing; what the plan gives: the trips a day of every pair.
    private func lineWorld(people: [Int64]) throws -> (world: GameWorld, ids: [StationID], lines: [LineID]) {
        let last = Self.stations.last!.chainage
        var world = try GameWorld(
            bounds: WorldBounds(width: 100_000 + (last + 20_000) * WorldCoordinate.unitsPerMetre, height: 200_000),
            economy: GameEconomy(balance: 1_000_000_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 5_000)),
            clock: GameClock(speed: .normal)
        )
        let x = Self.stations.map { 100_000 + $0.chainage * WorldCoordinate.unitsPerMetre }
        let y: Int64 = 100_000
        let nodes = try x.map { try world.buildTrackNode(at: WorldCoordinate(x: $0, y: y)) }
        var edges: [TrackEdgeID] = []
        for index in 1..<nodes.count {
            edges.append(try world.buildTrackEdge(from: nodes[index - 1], to: nodes[index]))
        }
        var ids: [StationID] = []
        for (index, station) in Self.stations.enumerated() {
            let id = try world.buildStation(named: station.name, at: PlanPoint(x: x[index], y: y)).id
            ids.append(id)
            if index >= 1 {
                let length = x[index] - x[index - 1]
                try world.addTrackPlatform(id, on: edges[index - 1], from: length - 8_192, to: length)
            }
            if index + 1 < nodes.count {
                try world.addTrackPlatform(id, on: edges[index], from: 0, to: 8_192)
            }
        }
        // The real day's stopping patterns (the schedule's 58, 32 and 28
        // trains): by station index.
        let services: [(name: String, stops: [Int], headway: Int64, trains: Int)] = [
            ("All stops", Array(0..<12), 30, 12),
            ("Nine stops", [0, 1, 2, 3, 4, 6, 9, 10, 11], 15, 20),
            ("Five stops", [0, 1, 2, 6, 11], 12, 22),
        ]
        var lines: [LineID] = []
        for service in services {
            let line = try world.createLine(named: service.name, stops: service.stops.map { ids[$0] }).id
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTargetHeadways(line, to: TargetHeadways(peak: service.headway, offPeak: service.headway, low: service.headway))
            try world.setLinePerformance(line, to: .highSpeed)
            for number in 0..<service.trains {
                let train = try world.purchaseTrain(named: "\(service.name) \(number)").id
                try world.setTrainType(train, to: .highSpeed)
                try world.setTrainCars(train, to: 12)
                try world.setTrainPerformance(train, to: .highSpeed)
                try world.assignTrain(train, to: line)
            }
            lines.append(line)
        }
        world.setPassengerRoutingMode(.network)
        for (id, count) in zip(ids, people) {
            try world.setStationDemand(id, to: StationDemand(kind: .residential, dailyTrips: 0, hinterland: count))
        }
        return (world, ids, lines)
    }

    /// What reading the land of a few of the real stations costs: the land,
    /// the save's size and the time to write and read it, the time the land
    /// demand takes to work the hinterlands out again (as every edit and
    /// midnight does), and a game day with the line running without trains.
    func testTheCostOfTheLandRoundHighSpeedStations() throws {
        guard ProcessInfo.processInfo.environment["BALANCE_REPORT"] != nil else {
            throw XCTSkip("set BALANCE_REPORT=1 to print the balance report")
        }
        var report = [
            "### The land round high-speed stations (8 km), read in as the game does it",
            "",
            "| Stations | Land cells | Read in (ms) | Save (MB) | Encode (ms) | Decode (ms) | Hinterlands again (ms) | A game day (ms) |",
            "| --- | --: | --: | --: | --: | --: | --: | --: |",
        ]
        for chosen in [[6], [6, 11], [1, 6, 11], Array(0..<12)] {
            var world = GameWorld.newWholeTaiwanGame()
            let frame = try XCTUnwrap(RealWorldFrame(world: world))
            var ids: [StationID] = []
            for index in chosen {
                let station = Self.stations[index]
                let at = frame.worldPosition(latitude: station.latitude, longitude: station.longitude)
                ids.append(try world.buildStation(named: station.name, at: PlanPoint(x: Int64(at.x.rounded()), y: Int64(at.y.rounded()))).id)
            }
            let line = try ids.count > 1 ? world.createLine(named: "THSR", stops: ids).id : nil
            let start = Date()
            if let line { try world.setLinePerformance(line, to: .highSpeed) }
            GameSession.readLand(roundStationsOf: &world, population: Self.population, places: Self.places)
            let readMs = Date().timeIntervalSince(start) * 1_000
            let encodeStart = Date()
            let data = try JSONEncoder().encode(SavedGame(world: world))
            let encodeMs = Date().timeIntervalSince(encodeStart) * 1_000
            let decodeStart = Date()
            _ = try JSONDecoder().decode(SavedGame.self, from: data)
            let decodeMs = Date().timeIntervalSince(decodeStart) * 1_000
            var again = 0.0
            if let line {
                try world.setLinePerformance(line, to: .standard)
                let t = Date()
                try world.setLinePerformance(line, to: .highSpeed)
                again = Date().timeIntervalSince(t) * 1_000
            }
            world.setSpeed(.normal)
            let dayStart = Date()
            try world.advance(ticks: 1_440)
            let dayMs = Date().timeIntervalSince(dayStart) * 1_000
            report.append(
                "| \(chosen.map { Self.stations[$0].name }.joined(separator: ", ")) | \(world.land.cells.count) | \(Int(readMs)) | "
                    + "\(String(format: "%.1f", Double(data.count) / 1_000_000)) | \(Int(encodeMs)) | \(Int(decodeMs)) | \(Int(again)) | \(Int(dayMs)) |"
            )
        }
        print(report.joined(separator: "\n"))
    }

    func testTheRealHighSpeedRail() throws {
        guard ProcessInfo.processInfo.environment["BALANCE_REPORT"] != nil else {
            throw XCTSkip("set BALANCE_REPORT=1 to print the balance report")
        }
        let read = try hinterlands()
        var report = [
            "### The real Taiwan High Speed Rail on the whole of Taiwan: hinterlands of \(HighSpeed.hinterlandRadius / WorldCoordinate.unitsPerMetre) m",
            "",
            "Land read in: \(read.cells) cells in \(String(format: "%.1f", read.seconds)) s.",
            "",
            "| Station | Chainage (km) | Hinterland (people) | Share |",
            "| --- | --: | --: | --: |",
        ]
        let total = read.people.reduce(0, +)
        for (station, people) in zip(Self.stations, read.people) {
            report.append("| \(station.name) | \(String(format: "%.1f", Double(station.chainage) / 1_000)) | \(people) | \(people * 1_000 / max(1, total) / 10).\(people * 1_000 / max(1, total) % 10) % |")
        }
        report.append("| **Total** | | \(total) | |")

        let (world, ids, lines) = try lineWorld(people: read.people)
        report += ["", "Headways (minutes) at the busiest level: " + lines.map { line in
            "\(world.line(id: line)?.name ?? "?") \(world.lineHeadway(line, at: .peak).map(String.init) ?? "-")"
        }.joined(separator: ", ")]
        // What the world's own demand gives each ordered pair, the trips a day
        // once the minutes of the fastest route have taken their share.
        var matrix = [[Int64]](repeating: [Int64](repeating: 0, count: ids.count), count: ids.count)
        for from in ids {
            for (to, trips) in world.dailyDemands(from: from) {
                matrix[from.rawValue - 1][to.rawValue - 1] = trips
            }
        }
        let boardings = matrix.map { $0.reduce(0, +) }
        let alightings = (0..<ids.count).map { column in matrix.reduce(0) { $0 + $1[column] } }
        let boarded = boardings.reduce(0, +)
        report += [
            "",
            "K = \(HighSpeed.tripsPerMillionSquared): **\(boarded) boardings a day** against about \(Self.realBoardings) for the real line (K for the real number: \(HighSpeed.tripsPerMillionSquared * Self.realBoardings / max(1, boarded))).",
            "",
            "| Station | Boardings | Alightings | Share of boardings |",
            "| --- | --: | --: | --: |",
        ]
        for (index, station) in Self.stations.enumerated() {
            report.append("| \(station.name) | \(boardings[index]) | \(alightings[index]) | \(boardings[index] * 1_000 / max(1, boarded) / 10).\(boardings[index] * 1_000 / max(1, boarded) % 10) % |")
        }
        let distance: (Int, Int) -> Int64 = { abs(Self.stations[$0].chainage - Self.stations[$1].chainage) }
        var pairs: [(Int, Int, Int64)] = []
        var revenue: Int64 = 0
        var passengerKilometres: Int64 = 0
        for from in 0..<ids.count {
            for to in 0..<ids.count where from != to {
                pairs.append((from, to, matrix[from][to]))
                let squared = distance(from, to) * WorldCoordinate.unitsPerMetre * distance(from, to) * WorldCoordinate.unitsPerMetre
                revenue += matrix[from][to] * HighSpeed.fare(squaredDistance: squared).amount / 100
                passengerKilometres += matrix[from][to] * distance(from, to) / 1_000
            }
        }
        // What other distances for the full share would give: each pair's
        // trips scaled by the other ramp over this one (the pairs this one
        // gives none are left out), and the K that would carry the real line's
        // boardings.
        report += ["", "| Full from (km) | Boardings at K = \(HighSpeed.tripsPerMillionSquared) | K for \(Self.realBoardings) | Taipei → Taoyuan | Taipei → Hsinchu | Taipei → Taichung | Taipei → Zuoying |", "| --: | --: | --: | --: | --: | --: | --: |"]
        func ramp(_ metres: Int64, from near: Int64, to full: Int64) -> Int64 {
            metres <= near ? 0 : metres >= full ? 1_000 : 1_000 * (metres - near) / (full - near)
        }
        let nearMetres = HighSpeed.nearDistance / WorldCoordinate.unitsPerMetre, fullMetres = HighSpeed.fullDistance / WorldCoordinate.unitsPerMetre
        for full in [50, 60, 80, 100, 120].map({ Int64($0) * 1_000 }) {
            var total: Int64 = 0
            var chosen: [Int64] = []
            for from in 0..<ids.count {
                for to in 0..<ids.count where from != to {
                    let metres = distance(from, to)
                    let now = ramp(metres, from: nearMetres, to: fullMetres)
                    guard now > 0 else { continue }
                    let scaled = matrix[from][to] * ramp(metres, from: nearMetres, to: full) / now
                    total += scaled
                    if from == 1, [3, 4, 6, 11].contains(to) { chosen.append(scaled) }
                }
            }
            report.append("| \(full / 1_000) | \(total) | \(HighSpeed.tripsPerMillionSquared * Self.realBoardings / max(1, total)) | " + chosen.map(String.init).joined(separator: " | ") + " |")
        }
        report += ["", "Fares: $\(revenue) a day; the average trip \(passengerKilometres / max(1, boarded)) km, the average fare $\(revenue / max(1, boarded)).", "", "The busiest pairs (one way, trips a day):", ""]
        for pair in pairs.sorted(by: { $0.2 > $1.2 }).prefix(12) {
            report.append("- \(Self.stations[pair.0].name) → \(Self.stations[pair.1].name): \(pair.2), \(distance(pair.0, pair.1) / 1_000) km")
        }
        print(report.joined(separator: "\n"))
    }
}
