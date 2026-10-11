import Foundation
import GameCore
import GamePresentation
import XCTest

/// The website's "along the line" timeline (ARCHITECTURE decision 166): a
/// blank new game as the app starts one (``GameWorld/newGame(anchor:bounds:balance:eventSeed:land:water:steep:buysMap:)``
/// with `buysMap`), played by a scripted player who opens a line from one
/// town to the middle town on the first morning and extends it to the third
/// town on day ``GrowthTimeline/extensionDay``, recorded each morning as the
/// map draws its city (``CitySkyline``). The website draws the recording;
/// nothing in it is made up outside the game's rules.
///
/// The recording is written only on request, to the website's data file:
///
///     WEBSITE_TIMELINE=../railway-reference-private/Website/site/assets/timeline.json \
///       swift test -c release -Xswiftc -enable-testing --filter WebsiteTimelineTests
///
/// A release build plays the year in under a minute. The other test plays
/// a few days with the line extended on the second, so CI keeps the script
/// building.
final class WebsiteTimelineTests: XCTestCase {
    /// The script still builds: the first stretch opens, the extension
    /// reaches the third town and its train serves it, and the recording
    /// holds each day's city and stops.
    func testTheTimelineStillPlays() throws {
        var timeline = try GrowthTimeline()
        var recording = GrowthTimelineRecording(timeline)
        for day in 1...3 {
            try timeline.playDay()
            if day == 1 { try timeline.extend(on: day) }
            recording.record(timeline, day: day)
        }
        let line = try XCTUnwrap(timeline.world.lines.first)
        XCTAssertEqual(line.stops.count, 3, "the line reaches the third town")
        XCTAssertEqual(timeline.world.stations.count, 3)
        // The train runs on to the third town: its passengers were served
        // the day after (two trains on one track without a passing place
        // would stand for good, as the first try did).
        let third = try XCTUnwrap(timeline.world.stations.last).id
        XCTAssertGreaterThan(try XCTUnwrap(timeline.world.townGrowth(of: third)).lastService, 0)
        let json = try recording.json()
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(object["days"] as? Int, 3)
        XCTAssertFalse(try XCTUnwrap(object["start"] as? [[Int]]).isEmpty, "the first morning's city")
        let stops = try XCTUnwrap(object["stops"] as? [[String: Any]])
        XCTAssertEqual(stops.map { $0["opens"] as? Int }, [0, 0, 1])
        XCTAssertTrue(stops.allSatisfy { ($0["trips"] as? [Int])?.count == 4 }, "a value for each morning, the first included")
    }

    /// Writes the recording to `WEBSITE_TIMELINE` and prints how the towns
    /// grew.
    func testWriteTheTimeline() throws {
        guard let path = ProcessInfo.processInfo.environment["WEBSITE_TIMELINE"] else {
            throw XCTSkip("set WEBSITE_TIMELINE=<file> to write the website's timeline")
        }
        var timeline = try GrowthTimeline()
        var recording = GrowthTimelineRecording(timeline)
        for day in 1...GrowthTimeline.days {
            try timeline.playDay()
            if day == GrowthTimeline.extensionDay { try timeline.extend(on: day) }
            recording.record(timeline, day: day)
        }
        let json = try recording.json()
        try json.write(to: URL(fileURLWithPath: path))
        print("wrote \(json.count) bytes to \(path)")
        print(recording.summary())
    }
}

/// The scripted game (decision 166). The three towns of a new game lie
/// almost in a line on seed ``seed``, so one straight track runs from the
/// first through the middle town to the last: the first stretch opens on
/// the first morning, the second, built on from its end, on day
/// ``extensionDay``. Each stretch is as ``newGameLine(through:in:)`` lays
/// one: a platform a train long round each stop, the track running a
/// platform beyond the end ones, one train of four cars.
struct GrowthTimeline {
    /// A new game's towns: the second and third about 3.3 and 3.6 km from
    /// the middle one, 4° off a straight line through it, so the map from
    /// the first town to the last is wider than tall (7.2 × 5.6 km).
    static let seed: UInt32 = 2_467
    /// The morning the line reaches the third town, counted from the
    /// first (0): the game's 30th day (it calls the first 第 1 日).
    static let extensionDay = 29
    /// The mornings recorded after the first: the game's first year.
    static let days = 364

    /// A stop of the line: where its station stands (on the track, by its
    /// town's middle) and its town's middle.
    struct Stop {
        let name: (zh: String, en: String)
        let point: PlanPoint
        let town: PlanPoint
        var station: StationID?
        var opens: Int?
    }

    private(set) var world: GameWorld
    private(set) var stops: [Stop]
    /// The track's stretches: their ends and the morning each opened.
    private(set) var stretches: [(from: PlanPoint, to: PlanPoint, opens: Int)] = []
    private let line: LineID
    private let end: TrackNodeID
    private let direction: (x: Double, y: Double)
    private static let platform = 4 * Train.carLength

    /// The game on its first morning: the first stretch built and its
    /// train running, at a minute past midnight.
    init() throws {
        var world = GameWorld.newGame(eventSeed: Self.seed, buysMap: true)
        let towns = Land.townCentres(seed: Self.seed, in: GameWorld.buyingMapBounds)
        let first = towns[1], middle = towns[0], last = towns[2]
        // The track runs straight from the first town's middle to the
        // last's, so the middle station stands where it passes nearest the
        // middle town's.
        let dx = Double(last.x - first.x), dy = Double(last.y - first.y)
        let span = (dx * dx + dy * dy).squareRoot()
        let direction = (x: dx / span, y: dy / span)
        func along(_ distance: Double) -> PlanPoint {
            PlanPoint(x: first.x + Int64((direction.x * distance).rounded()), y: first.y + Int64((direction.y * distance).rounded()))
        }
        let toMiddle = Double(middle.x - first.x) * direction.x + Double(middle.y - first.y) * direction.y
        let platform = Double(Self.platform)
        stops = [
            Stop(name: Self.name(of: first, from: middle), point: first, town: first),
            Stop(name: ("中央", "Central"), point: along(toMiddle), town: middle),
            Stop(name: Self.name(of: last, from: middle), point: along(span), town: last),
        ]
        let start = try world.buildTrackNode(at: WorldCoordinate(at: along(-platform)))
        end = try world.buildTrackNode(at: WorldCoordinate(at: along(toMiddle + platform)))
        let edge = try world.buildTrackEdge(from: start, to: end)
        let length = world.trackEdge(edge)?.length ?? 0
        let p = Self.platform
        for (index, span) in [(0, (p / 2, p + p / 2)), (1, (length - p - p / 2, length - p / 2))] {
            let station = try world.buildStation(named: stops[index].name.zh, at: stops[index].point).id
            try world.addTrackPlatform(station, on: edge, from: span.0, to: span.1)
            stops[index].station = station
            stops[index].opens = 0
        }
        line = try world.createLine(named: "1", stops: [stops[0].station!, stops[1].station!]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try Self.addTrain(to: line, on: edge, headAt: p + p / 2, in: &world)
        stretches = [(along(-platform), along(toMiddle + platform), 0)]
        try world.advance(ticks: 1)
        self.world = world
        self.direction = direction
    }

    /// Plays to a minute past the next midnight, when the city has grown.
    mutating func playDay() throws {
        try world.advance(ticks: 1_440)
    }

    /// Builds the second stretch from the first's end to a platform beyond
    /// the last town and its station, and calls the line there; its one
    /// train runs on to it (a second on the one track, with no place to
    /// pass, would stand facing the first for good). A train standing at
    /// the middle town's platform holds the end the stretch is built from:
    /// the player waits a minute at a time for it to leave, as the app
    /// would refuse the track till then.
    mutating func extend(on day: Int) throws {
        let p = Self.platform
        let last = stops[2].point
        let beyond = PlanPoint(x: last.x + Int64((direction.x * Double(p)).rounded()), y: last.y + Int64((direction.y * Double(p)).rounded()))
        var waited = 0
        while true {
            do throws(GameError) {
                let node = try world.buildTrackNode(at: WorldCoordinate(at: beyond))
                let edge: TrackEdgeID
                do throws(GameError) {
                    edge = try world.buildTrackEdge(from: end, to: node)
                } catch {
                    try world.removeTrackNode(node)
                    throw error
                }
                let length = world.trackEdge(edge)?.length ?? 0
                let station = try world.buildStation(named: stops[2].name.zh, at: last).id
                try world.addTrackPlatform(station, on: edge, from: length - p - p / 2, to: length - p / 2)
                try world.setLineStops(line, to: stops.compactMap(\.station) + [station])
                stops[2].station = station
                stops[2].opens = day
                stretches.append((stretches[0].to, beyond, day))
                return
            } catch .trackReserved {
                waited += 1
                guard waited < 120 else { throw TimelineError.trainNeverLeft }
                try world.advance(ticks: 1)
            }
        }
    }

    private static func addTrain(to line: LineID, on edge: TrackEdgeID, headAt offset: Int64, in world: inout GameWorld) throws(GameError) {
        let train = try world.purchaseTrain(named: "\(world.trains.count + 1)").id
        try world.setTrainCars(train, to: 4)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: offset))
        try world.setTrainContinuation(train, along: [], stoppingAt: offset)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
    }

    /// A town's name, the way it lies from the middle town, as the demo's
    /// stations are named (West, North, ...): the eight points of the
    /// compass.
    private static func name(of town: PlanPoint, from middle: PlanPoint) -> (zh: String, en: String) {
        // y grows southwards.
        let angle = atan2(Double(middle.y - town.y), Double(town.x - middle.x)) * 180 / .pi
        let points: [(String, String)] = [
            ("東", "East"), ("東北", "Northeast"), ("北", "North"), ("西北", "Northwest"),
            ("西", "West"), ("西南", "Southwest"), ("南", "South"), ("東南", "Southeast"),
        ]
        let index = Int(((angle + 360 + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        return points[index]
    }
}

/// Each morning of a ``GrowthTimeline`` as the website draws it: the city's
/// lots (``CitySkyline/Lot``) on the first morning and what changed on each
/// after, the track and the stops with the morning each opened, and each
/// stop's people within its 800 m and trips, and the city's totals.
///
/// Positions are in cells (64 m) from the north-west corner of the view,
/// the towns' cells and a margin; heights and sizes in metres.
struct GrowthTimelineRecording {
    private struct Lot: Equatable {
        let use: Int
        let density: Int
        let side: Int
    }

    private let origin: (row: Int, column: Int)
    private let size: (rows: Int, columns: Int)
    private var lots: [CellPosition: Lot]
    private let start: [CellPosition: Lot]
    private var changes: [[Int]] = []
    private var days = 0
    private var stops: [[String: Any]] = []
    private var people: [[Int64]]
    private var trips: [[Int64]]
    private var residents: [Int64] = []
    private var jobs: [Int64] = []
    private var balance: [Int64] = []
    private var tracks: [[String: Any]] = []

    /// The view: every cell within 1.6 km of a town's middle, so the towns'
    /// growth stays in it.
    private static let reach: Int64 = 2 * Land.catchmentRadius

    init(_ timeline: GrowthTimeline) {
        let towns = timeline.stops.map(\.town)
        let cell = Land.cellLength
        let minX = towns.map(\.x).min()! - Self.reach, maxX = towns.map(\.x).max()! + Self.reach
        let minY = towns.map(\.y).min()! - Self.reach, maxY = towns.map(\.y).max()! + Self.reach
        origin = (Int(minY / cell), Int(minX / cell))
        size = (Int(maxY / cell) - origin.row + 1, Int(maxX / cell) - origin.column + 1)
        people = timeline.stops.map { _ in [] }
        trips = timeline.stops.map { _ in [] }
        lots = Self.lots(of: timeline.world, origin: origin, size: size)
        start = lots
        record(timeline, day: 0)
    }

    private static func lots(of world: GameWorld, origin: (row: Int, column: Int), size: (rows: Int, columns: Int)) -> [CellPosition: Lot] {
        var lots: [CellPosition: Lot] = [:]
        for lot in CitySkyline(world: world).lots {
            let row = lot.row - origin.row, column = lot.column - origin.column
            guard (0..<size.rows).contains(row), (0..<size.columns).contains(column) else { continue }
            let use = LandUse.allCases.firstIndex(of: lot.use)!
            let side = lot.isOpenGround ? 0 : Int(lot.side / WorldCoordinate.unitsPerMetre)
            lots[CellPosition(row: row, column: column)] = Lot(use: use, density: lot.density, side: side)
        }
        return lots
    }

    /// Records the morning of `day`: the city's changes since the morning
    /// before, and each stop's and the city's numbers.
    mutating func record(_ timeline: GrowthTimeline, day: Int) {
        let world = timeline.world
        if day > 0 {
            let now = Self.lots(of: world, origin: origin, size: size)
            for cell in Set(now.keys).union(lots.keys).sorted() where now[cell] != lots[cell] {
                let lot = now[cell]
                changes.append([day, cell.row, cell.column, lot?.use ?? -1, lot?.density ?? 0, lot?.side ?? 0])
            }
            lots = now
            days = day
        }
        let radius = Land.catchmentRadius
        for (index, stop) in timeline.stops.enumerated() {
            let near = world.land.cells.filter { cell in
                let dx = cell.middle.x - stop.point.x, dy = cell.middle.y - stop.point.y
                return dx * dx + dy * dy < radius * radius
            }
            people[index].append(near.reduce(0) { $0 + $1.residents + $1.jobs })
            trips[index].append(stop.station.flatMap { world.stationDemand(of: $0)?.dailyTrips } ?? 0)
        }
        residents.append(world.land.cells.reduce(0) { $0 + $1.residents })
        jobs.append(world.land.cells.reduce(0) { $0 + $1.jobs })
        balance.append(world.economy.balance.amount / 100)
        stops = timeline.stops.map { stop in
            ["zh": stop.name.zh, "en": stop.name.en, "x": cells(stop.point.x, from: origin.column), "y": cells(stop.point.y, from: origin.row),
             "townX": cells(stop.town.x, from: origin.column), "townY": cells(stop.town.y, from: origin.row), "opens": stop.opens ?? -1]
        }
        tracks = timeline.stretches.map { stretch in
            ["from": [cells(stretch.from.x, from: origin.column), cells(stretch.from.y, from: origin.row)],
             "to": [cells(stretch.to.x, from: origin.column), cells(stretch.to.y, from: origin.row)], "opens": stretch.opens]
        }
    }

    /// A world coordinate in cells from the view's edge, to a hundredth.
    private func cells(_ value: Int64, from edge: Int) -> Double {
        (Double(value) / Double(Land.cellLength) - Double(edge) * 1).rounded(toPlaces: 2)
    }

    /// The recording as the website's JSON, cropped to the cells the
    /// towns ever stood on and a margin of ``margin`` cells.
    func json() throws -> Data {
        let cells = start.keys.map { ($0.row, $0.column) } + changes.map { ($0[1], $0[2]) }
        let top = (cells.map(\.0).min() ?? 0) - Self.margin, left = (cells.map(\.1).min() ?? 0) - Self.margin
        let bottom = (cells.map(\.0).max() ?? 0) + Self.margin, right = (cells.map(\.1).max() ?? 0) + Self.margin
        func point(_ value: Any?) -> [Double] {
            let pair = value as? [Double] ?? [0, 0]
            return [(pair[0] - Double(left)).rounded(toPlaces: 2), (pair[1] - Double(top)).rounded(toPlaces: 2)]
        }
        var stops = self.stops
        for index in stops.indices {
            for (x, y) in [("x", "y"), ("townX", "townY")] {
                let moved = point([stops[index][x] as? Double ?? 0, stops[index][y] as? Double ?? 0])
                stops[index][x] = moved[0]
                stops[index][y] = moved[1]
            }
            stops[index]["people"] = people[index]
            stops[index]["trips"] = trips[index]
        }
        let object: [String: Any] = [
            "format": 1,
            "seed": Int(GrowthTimeline.seed),
            "days": days,
            "extensionDay": GrowthTimeline.extensionDay,
            "cellMetres": Int(Land.cellLength / WorldCoordinate.unitsPerMetre),
            "rows": bottom - top + 1,
            "columns": right - left + 1,
            "uses": LandUse.allCases.map(\.rawValue),
            "start": start.keys.sorted().map { cell in
                let lot = start[cell]!
                return [cell.row - top, cell.column - left, lot.use, lot.density, lot.side]
            },
            "changes": changes.map { [$0[0], $0[1] - top, $0[2] - left] + $0[3...] },
            "stops": stops,
            "track": tracks.map { ["from": point($0["from"]), "to": point($0["to"]), "opens": $0["opens"] ?? 0] },
            "residents": residents,
            "jobs": jobs,
            "balance": balance,
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// The cells round the towns' lots the website's view keeps.
    private static let margin = 3

    /// How each town grew: its stop's people and trips on the first
    /// morning, the morning before the extension and the last, and the
    /// city's buildings by density.
    func summary() -> String {
        var lines = ["\(start.count) lots on the first morning, \(changes.count) changes in \(days) days"]
        for (index, stop) in stops.enumerated() {
            let marks = [0, GrowthTimeline.extensionDay, days].filter { $0 < people[index].count }
            lines.append("\(stop["en"]!): people " + marks.map { "day \($0) \(people[index][$0])" }.joined(separator: ", ")
                + "; trips " + marks.map { "\(trips[index][$0])" }.joined(separator: " → "))
        }
        var densities = [0, 0, 0, 0, 0]
        for lot in lots.values { densities[lot.density] += 1 }
        lines.append("last morning: open \(densities[0]), D1–D4 \(densities[1...].map(String.init).joined(separator: " / "))")
        return lines.joined(separator: "\n")
    }
}

private enum TimelineError: Error {
    /// A train held the end of the first stretch for two hours.
    case trainNeverLeft
}

private extension WorldCoordinate {
    init(at point: PlanPoint) {
        self.init(x: point.x, y: point.y)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}
