import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// How long the game's trains take against the real ones
/// (`docs/research/NEXT_PRIORITIES_2026-10-12.md` §2 item 7 (1) and §9.2):
/// the same ruler for every change to how trains run (margins on the
/// timetable, dwell seconds, speed limits from the track's geometry, the
/// high-speed demo on the real timetable). A report, printed, and only on
/// request; it asserts only that its data is sound, never a ratio:
///
///     swift build -c release -Xswiftc -enable-testing --build-tests
///     REALISM_REPORT=1 swift test -c release --skip-build --filter RunTimeRealismReportTests
///
/// Each table row is game / real / game ÷ real. What is measured:
///
/// - The high-speed demo as it is built: its three services' journeys
///   (``GameWorld/lineJourney(_:pattern:)``: the legs, and its dwell at
///   each call between), off and with realistic operation (decision 207),
///   against the median
///   Nangang → Zuoying train of the same stopping pattern in the bundled
///   `thsr-schedule.json`; leg by leg; and the lateness over the first two
///   hours of the opened demo.
/// - Metro lines laid straight with their real station distances (`d` in
///   the bundled `trtc.json` and `krtc.json`), at `.metro` and `.standard`,
///   against the median end-to-end weekday trip of `trtc_times.json` and
///   `krtc_times.json`, and the data's own run and dwell seconds
///   (`segs[].run`, `dwellSec` or `stations[].dwell`).
/// - The Pingxi Line of the flat demo (the challenge, at a headway) and of
///   the demo on the ground (the real runs of `tra_pingxi_runs.json`), leg
///   by leg against the median real run, and the cruising speed a train
///   would need to take the real time.
/// - The least seconds of each preset performance from 0.5 to 100 km.
///
/// TRA's Taipei → Hsinchu (the reference's `tra_schedule_dense.json`) is
/// not bundled in the app and is not measured yet: to be added later.
final class RunTimeRealismReportTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func resource(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/\(path)"))
    }

    private static func json(_ path: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: resource(path)) as? [String: Any], path)
    }

    private func requireReport() throws {
        guard ProcessInfo.processInfo.environment["REALISM_REPORT"] != nil else { throw XCTSkip("Set REALISM_REPORT=1.") }
    }

    private func say(_ text: String) {
        FileHandle.standardError.write(Data(("REALISM " + text + "\n").utf8))
    }

    private static func median(_ values: [Int64]) -> Int64? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    private static func minutes(_ seconds: Int64?) -> String {
        seconds.map { String(format: "%.1f", Double($0) / 60) } ?? "–"
    }

    private static func ratio(_ game: Int64, _ real: Int64?) -> String {
        guard let real, real > 0 else { return "–" }
        return String(format: "%.2f", Double(game) / Double(real))
    }

    /// The speed of a ``RunningCurve``'s cruise in km/h (world units per
    /// ms × 2^32, 64 units a metre).
    private static func kilometresPerHour(_ curve: RunningCurve) -> Double {
        Double(curve.cruiseSpeed) / 4_294_967_296 / Double(WorldCoordinate.unitsPerMetre) * 3_600
    }

    private static let presets: [(String, TrainPerformance)] = [
        ("standard", .standard), ("metro", .metro), ("local", .local), ("ordinary", .ordinary),
        ("semiExpress", .semiExpress), ("express", .express), ("emu3000", .emu3000), ("pushPull", .pushPull),
        ("puyuma", .tiltingPuyuma), ("dieselRailcar", .dieselRailcar), ("highSpeed", .highSpeed), ("steam", .steam),
    ]

    // MARK: - High-speed demo

    /// One real THSR train: its calls in order, with times in seconds.
    private struct RealTrain {
        let names: [String]
        let arrivals: [Int64]
        let departures: [Int64]
    }

    private static func thsrTrains() throws -> [RealTrain] {
        let data = try json("RealRailways/thsr-schedule.json")
        let trains = try XCTUnwrap(data["trains"] as? [[String: Any]])
        return trains.compactMap { train in
            guard let stops = train["stops"] as? [[String: Any]] else { return nil }
            let calls = stops
                .filter { ($0["stop"] as? Bool) ?? true }
                .sorted { (($0["order"] as? Int) ?? 0) < (($1["order"] as? Int) ?? 0) }
            let names = calls.compactMap { $0["name"] as? String }
            let arrivals = calls.compactMap { ($0["arrSec"] as? NSNumber)?.int64Value }
            let departures = calls.compactMap { ($0["depSec"] as? NSNumber)?.int64Value }
            guard names.count == calls.count, arrivals.count == calls.count, departures.count == calls.count else { return nil }
            return RealTrain(names: names, arrivals: arrivals, departures: departures)
        }
    }

    func testHighSpeedDemo() throws {
        try requireReport()
        let real = try Self.thsrTrains()
        XCTAssertGreaterThan(real.count, 100, "the real day has some 169 trains")
        let railways = try HighSpeedDemoTests.railways()
        let layout = try HighSpeedDemo.Layout(railways: railways)
        var world = HighSpeedDemo.newWorld(paying: layout.cost(at: ConstructionCosts.newGame), eventSeed: 1)
        try layout.build(in: &world, language: .traditionalChinese)
        let names = HighSpeedDemo.stationNames
        let ids = world.stations.map(\.id)
        let built = world
        // Decision 207: the same lines planned with realistic operation;
        // decision 217: and with the curve limits too.
        for (realistic, limits) in [(false, false), (true, false), (true, true)] {
            world = built
            world.setRealisticOperation(realistic)
            world.setCurveSpeedLimits(limits)
            say("== High-speed demo: Nangang → Zuoying, as built\(realistic ? ", realistic operation (decision 207)" : "")\(limits ? ", curve limits (decision 217)" : "") (journey legs + its dwell at each call between) ==")
            say("service | calls | game run | game dwell | game | real median (trains) | game/real")
            var legRows: [String] = []
            for line in world.lines {
                let calls = line.stops.compactMap { ids.firstIndex(of: $0) }
                let journey = try XCTUnwrap(world.lineJourney(line.id, pattern: nil))
                let out = Array(journey.legs.prefix(calls.count - 1))
                for leg in out where !limits {
                    XCTAssertEqual(leg.seconds, world.plannedSeconds(length: leg.path.distance, line: line) ?? -1,
                                   "a leg takes the seconds its line plans")
                }
                let run = out.map(\.seconds).reduce(0, +)
                let dwell = journey.dwellSeconds * Int64(calls.count - 2)
                let stopNames = calls.map { names[$0] }
                let same = real.filter { $0.names == stopNames }
                let median = Self.median(same.map { $0.arrivals.last! - $0.departures.first! })
                XCTAssertFalse(same.isEmpty, "the real day has trains calling at \(stopNames)")
                say("\(line.name) | \(calls.count) | \(Self.minutes(run)) | \(Self.minutes(dwell)) | \(Self.minutes(run + dwell)) | \(Self.minutes(median)) (\(same.count)) | \(Self.ratio(run + dwell, median))")
                // Leg by leg: the real median run between the same two calls
                // of the same pattern, and the real dwell at each call between.
                for (index, leg) in out.enumerated() {
                    let from = stopNames[index], to = stopNames[index + 1]
                    let legs = same.map { $0.arrivals[index + 1] - $0.departures[index] }
                    let dwells = index + 1 < stopNames.count - 1 ? same.map { $0.departures[index + 1] - $0.arrivals[index + 1] } : []
                    let km = Double(leg.path.distance) / Double(WorldCoordinate.unitsPerMetre) / 1_000
                    legRows.append("\(line.name) \(from)→\(to) | \(String(format: "%.1f", km)) | \(leg.seconds) | \(Self.median(legs).map(String.init) ?? "–") | \(Self.ratio(leg.seconds, Self.median(legs))) | \(Self.median(dwells).map { "\($0)" } ?? "–")")
                }
            }
            say("-- leg by leg: service from→to | km | game s | real median s | game/real | real dwell at the arrival s (game \(world.dwellSeconds(of: world.lines[0]))) --")
            legRows.forEach { say($0) }
        }

        // Opened: the sets' own timetables, and lateness sampled every game
        // minute for two hours.
        var opened = try HighSpeedDemo.make(in: .traditionalChinese, railways: railways)
        say("opened: realistic operation \(opened.realisticOperation ? "on" : "off") (the demo runs the real timetable)")
        let (nangang, zuoying) = (opened.stations[0].id, opened.stations[11].id)
        for (name, trains) in opened.lines.map({ ($0.name, $0.trains) }) {
            let journeys: [Int64] = trains.compactMap { id in
                guard let timetable = opened.train(id: id)?.timetable,
                      let start = timetable.firstIndex(where: { $0.station == nangang }),
                      let end = timetable[start...].firstIndex(where: { $0.station == zuoying }) else { return nil }
                return timetable[end].arrival.seconds - timetable[start].departure.seconds
            }
            say("opened \(name): \(trains.count) sets, timetabled Nangang → Zuoying \(Set(journeys).sorted().map { Self.minutes($0) }) min")
        }
        opened.setSpeed(.normal)
        var latest: Int64 = 0, earliest: Int64 = 0
        for _ in 0..<120 {
            try opened.advance(ticks: 1)
            for train in opened.trains {
                guard let lateness = opened.lateness(of: train.id) else { continue }
                latest = max(latest, lateness)
                earliest = min(earliest, lateness)
            }
        }
        say("opened, 120 one-minute samples: most late \(latest) s, most early \(-earliest) s")
    }

    // MARK: - Metro

    /// A metro line of the bundled data: its stations' distances, the
    /// data's run and dwell seconds, and the median end-to-end weekday trip.
    private struct MetroLine {
        let name: String
        let kilometres: [Double]
        let dataRun: Int64
        let dataDwell: Int64
        let timetabled: Int64?
        let trips: Int
    }

    private static func metroLines(system: String, times: String, ids: [String]) throws -> [MetroLine] {
        let lines = try XCTUnwrap(json("RealRailways/\(system)")["lines"] as? [[String: Any]])
        let timeLines = try XCTUnwrap(json("RealRailways/\(times)")["lines"] as? [String: Any])
        return try ids.map { id in
            let line = try XCTUnwrap(lines.first { $0["id"] as? String == id }, id)
            let stations = try XCTUnwrap(line["stations"] as? [[String: Any]])
            let kilometres = stations.compactMap { ($0["d"] as? NSNumber)?.doubleValue }
            XCTAssertEqual(kilometres.count, stations.count)
            let segs = try XCTUnwrap(line["segs"] as? [[String: Any]])
            let run = segs.compactMap { ($0["run"] as? NSNumber)?.int64Value }.reduce(0, +)
            let dwells: [Int64] = (line["dwellSec"] as? [NSNumber])?.map(\.int64Value)
                ?? stations.map { ($0["dwell"] as? NSNumber)?.int64Value ?? 0 }
            let dwell = dwells.dropFirst().dropLast().reduce(0, +)
            // A trip is [stop, second, stop, second, …]; a whole one calls at
            // every station, end to end, either way.
            var whole: [Int64] = []
            if let sets = (timeLines[id] as? [String: Any])?["sets"] as? [String: Any],
               let weekday = sets["平日"] as? [[NSNumber]] {
                for trip in weekday {
                    let values = trip.map(\.int64Value)
                    let stops = stride(from: 0, to: values.count, by: 2).map { values[$0] }
                    let seconds = stride(from: 1, to: values.count, by: 2).map { values[$0] }
                    guard stops.count == stations.count, Set([stops.first!, stops.last!]) == [0, Int64(stations.count - 1)] else { continue }
                    whole.append(seconds.last! - seconds.first!)
                }
            }
            return MetroLine(name: "\(id) \(line["name"] as? String ?? "")", kilometres: kilometres, dataRun: run, dataDwell: dwell,
                             timetabled: median(whole), trips: whole.count)
        }
    }

    func testMetro() throws {
        try requireReport()
        let lines = try Self.metroLines(system: "trtc.json", times: "trtc_times.json", ids: ["R", "BL", "G", "O_XINZHUANG"])
            + Self.metroLines(system: "krtc.json", times: "krtc_times.json", ids: ["KR", "KO"])
        say("== Metro lines laid straight at their real station distances ==")
        say("line [performance] | stations | km | game run | game dwell | game | real timetable median (trips) | game/real | data run + dwell | game/data")
        for (index, line) in lines.enumerated() {
            XCTAssertGreaterThan(line.kilometres.count, 10, line.name)
            XCTAssertGreaterThan(line.trips, 50, "\(line.name) has whole weekday trips")
            for (name, performance) in [("metro", TrainPerformance.metro), ("standard", .standard)] {
                let result = try straightRun(kilometres: line.kilometres, performance: performance, drive: index == 0 && name == "metro")
                let data = line.dataRun + line.dataDwell
                say("\(line.name) [\(name)] | \(line.kilometres.count) | \(String(format: "%.1f", line.kilometres.last!)) | \(Self.minutes(result.run)) | \(Self.minutes(result.dwell)) | \(Self.minutes(result.oneWay)) | \(Self.minutes(line.timetabled)) (\(line.trips)) | \(Self.ratio(result.oneWay, line.timetabled)) | \(Self.minutes(line.dataRun)) + \(Self.minutes(line.dataDwell)) | \(Self.ratio(result.oneWay, data))")
                if let driven = result.driven {
                    say("  driven: first departure to last arrival \(Self.minutes(driven)) min, timetabled \(Self.minutes(result.oneWay)) min")
                }
            }
        }
    }

    /// A straight line of stations `kilometres` apart, one train of
    /// `performance` on it: the outbound legs, the dwells between and, when
    /// `drive`, the time the train takes driving it.
    private func straightRun(kilometres: [Double], performance: TrainPerformance, drive: Bool) throws -> (run: Int64, dwell: Int64, oneWay: Int64, driven: Int64?) {
        let unitsPerKilometre = Double(WorldCoordinate.unitsPerMetre) * 1_000
        let margin: Int64 = 8_192
        let xs = [margin - 2_048] + kilometres.map { margin + Int64(($0 * unitsPerKilometre).rounded()) }
            + [margin + Int64((kilometres.last! * unitsPerKilometre).rounded()) + 2_048]
        var world = GameWorld(
            bounds: try WorldBounds(width: xs.last! + margin, height: 16_384),
            economy: GameEconomy(balance: 1_000_000_000_000, costs: testCosts), clock: GameClock(speed: .x10)
        )
        let y: Int64 = 8_192
        var nodes: [TrackNodeID] = []
        for x in xs { nodes.append(try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))) }
        var edges: [TrackEdgeID] = []
        for index in 1..<nodes.count { edges.append(try world.buildTrackEdge(from: nodes[index - 1], to: nodes[index])) }
        var stations: [StationID] = []
        for index in kilometres.indices {
            let id = try world.buildStation(named: "S\(index)", at: PlanPoint(x: xs[index + 1], y: y - 1_024)).id
            let incoming = xs[index + 1] - xs[index]
            try world.addTrackPlatform(id, on: edges[index], from: incoming - 512, to: incoming)
            try world.addTrackPlatform(id, on: edges[index + 1], from: 0, to: 512)
            stations.append(id)
        }
        let line = try world.createLine(named: "L", stops: stations).id
        try world.setLinePerformance(line, to: performance)
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edges[0], direction: .forward), offset: xs[1] - xs[0]))
        try world.setTrainMovementRate(train, to: 2_048)
        try world.setTrainPerformance(train, to: performance)
        try world.assignTrain(train, to: line)
        let journey = try XCTUnwrap(world.lineJourney(line))
        let legs = Array(journey.legs.prefix(kilometres.count - 1))
        for leg in legs {
            XCTAssertEqual(leg.seconds, RunningCurve.leastSeconds(length: leg.path.distance, performance: performance) ?? -1)
        }
        let run = legs.map(\.seconds).reduce(0, +)
        let dwell = ServiceLine.dwellMinutes * GameTime.secondsPerMinute * Int64(kilometres.count - 2)
        guard drive else { return (run, dwell, run + dwell, nil) }
        var left: Int64?, arrived: Int64?, previous: TimetableExecution?
        let last = kilometres.count - 1
        for _ in 0..<40_000 where arrived == nil {
            try world.advance(ticks: 1)
            let now = try XCTUnwrap(world.train(id: train))
            if let execution = now.execution, execution != previous {
                if case .travellingToStop(1, _) = execution, left == nil, let departure = now.times?.departure { left = departure.seconds }
                if case .waitingAtStop(let stop, _) = execution, stop == last, let arrival = now.times?.arrival { arrived = arrival.seconds }
                previous = execution
            }
        }
        let driven = try XCTUnwrap(arrived, "the train reaches the last station") - XCTUnwrap(left, "the train leaves the first")
        return (run, dwell, run + dwell, driven)
    }

    // MARK: - Pingxi Line

    func testPingxi() throws {
        try requireReport()
        let runsData = try Self.resource("RealRailways/tra_pingxi_runs.json")
        let runs = try XCTUnwrap(JSONSerialization.jsonObject(with: runsData) as? [String: Any])["runs"] as? [[String: Any]] ?? []
        // Each passenger run's calls: name, arrival, departure.
        let calls: [[(name: String, arrival: Int64, departure: Int64)]] = runs.compactMap { run in
            guard (run["positioning"] as? Bool) != true, let calls = run["calls"] as? [[Any]] else { return nil }
            return calls.compactMap { call in
                guard call.count == 3, let name = call[0] as? String, let arrival = (call[1] as? NSNumber)?.int64Value,
                      let departure = (call[2] as? NSNumber)?.int64Value else { return nil }
                return (name, arrival, departure)
            }
        }
        XCTAssertGreaterThan(calls.count, 20, "the real Pingxi Line runs some 35 trains a day")
        func realMedian(from: String, to: String) -> (seconds: Int64?, runs: Int) {
            var values: [Int64] = []
            for run in calls {
                for (a, b) in zip(run, run.dropFirst()) where a.name == from && b.name == to {
                    values.append(b.arrival - a.departure)
                }
            }
            return (Self.median(values), values.count)
        }

        let railways = try RealRailways(
            lines: Self.resource("RealRailways/track_lines.geojson"), stations: Self.resource("RealRailways/track_stations.geojson"),
            names: Self.resource("RealRailways/station_names.json"), pingxiRuns: RealLineRuns(data: runsData)
        )
        let heights = try HeightGrid(data: Self.resource("RealWorld/taiwan_heights.dat"))
        let water = try WaterGrid(data: Self.resource("RealWorld/taiwan_water.json"))
        let frame = RealWorldFrame(anchor: RealWorldDemo.anchor, bounds: GameWorld.newGameBounds)
        let flat = PingxiChallenge.make(in: .traditionalChinese, railways: railways)
        let ground = RealWorldDemo.make(
            in: .traditionalChinese, railways: railways, water: water.cells(frame: frame, bounds: GameWorld.newGameBounds),
            steep: water.steepCells(frame: frame, bounds: GameWorld.newGameBounds), heights: heights
        )
        var limited = ground
        limited.setCurveSpeedLimits(true)
        for (title, world) in [("flat (the challenge, at a headway)", flat), ("on the ground (the real runs)", ground),
                               ("on the ground, curve limits (decision 217)", limited)] {
            let line = try XCTUnwrap(world.lines.first { $0.name == "平溪線" }, "the Pingxi Line")
            let names = line.stops.map { world.station(id: $0)?.name ?? "?" }
            let journey = try XCTUnwrap(world.lineJourney(line.id))
            say("== Pingxi Line, \(title): \(names.joined(separator: "–")), \(line.runs.count) runs on the line ==")
            say("leg | km | game s | real median s (runs) | game/real | cruise km/h at the real time")
            var totals: (game: Int64, real: Int64) = (0, 0)
            var fromSandiaoling: (game: Int64, real: Int64) = (0, 0)
            let sandiaoling = names.firstIndex(of: "三貂嶺")
            for leg in journey.legs {
                if !world.curveSpeedLimits {
                    XCTAssertEqual(leg.seconds, RunningCurve.leastSeconds(length: leg.path.distance, performance: line.performance) ?? -1)
                }
                let from = names[leg.from], to = names[leg.to]
                let real = realMedian(from: from, to: to)
                let km = Double(leg.path.distance) / Double(WorldCoordinate.unitsPerMetre) / 1_000
                let cruise = real.seconds.flatMap { RunningCurve(length: leg.path.distance, duration: $0 * 1_000, performance: line.performance) }
                    .map { String(format: "%.0f", Self.kilometresPerHour($0)) } ?? "–"
                say("\(from)→\(to) | \(String(format: "%.2f", km)) | \(leg.seconds) | \(real.seconds.map(String.init) ?? "–") (\(real.runs)) | \(Self.ratio(leg.seconds, real.seconds)) | \(cruise)")
                if leg.from < leg.to, let seconds = real.seconds {
                    totals.game += leg.seconds
                    totals.real += seconds
                    if let sandiaoling, leg.from >= sandiaoling {
                        fromSandiaoling.game += leg.seconds
                        fromSandiaoling.real += seconds
                    }
                }
            }
            say("outbound, running only: game \(Self.minutes(totals.game)) min, real \(Self.minutes(totals.real)) min, \(Self.ratio(totals.game, totals.real)); 三貂嶺→\(names.last ?? "") game \(Self.minutes(fromSandiaoling.game)) min, real \(Self.minutes(fromSandiaoling.real)) min, \(Self.ratio(fromSandiaoling.game, fromSandiaoling.real))")
        }
    }

    // MARK: - Least seconds

    func testLeastSecondsTable() throws {
        try requireReport()
        say("== Least seconds (average km/h) of each preset performance ==")
        say("km | " + Self.presets.map(\.0).joined(separator: " | "))
        for km in [0.5, 1, 2, 5, 10, 30, 50, 100] {
            let length = Int64((km * Double(WorldCoordinate.unitsPerMetre) * 1_000).rounded())
            let cells = try Self.presets.map { _, performance -> String in
                let seconds = try XCTUnwrap(RunningCurve.leastSeconds(length: length, performance: performance))
                return "\(seconds) s (\(String(format: "%.0f", km / (Double(seconds) / 3_600))))"
            }
            say("\(km) | " + cells.joined(separator: " | "))
        }
    }
}
