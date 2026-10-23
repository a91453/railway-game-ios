import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 371 (§22.2 10h; PLAYER_FEEDBACK 78.1, 79.1, 82.1: with some
/// thirty or forty stations the flat map ran at about 5 fps and the phone
/// grew hot). What each canvas of the flat map is asked to draw again a
/// second, and why, on the real map round Miaoli with four lines of eleven
/// stations each (44 stations), played `MAP_FRAME_REPORT` days: by day at
/// 1× and at the opening speed, at night after 20:00, and at 6000×, the
/// player not touching the map. Linux cannot time SwiftUI's drawing; it
/// counts how often each canvas's inputs change (each change is a whole
/// canvas drawn again) and times what the map works out for them. Run on
/// request:
///
///     MAP_FRAME_REPORT=3 swift test -c release -Xswiftc -enable-testing \
///       --filter MapFrameCostReportTests
@MainActor
final class MapFrameCostReportTests: XCTestCase {
    func testWhatEachCanvasRedrawsASecond() throws {
        guard let value = ProcessInfo.processInfo.environment["MAP_FRAME_REPORT"] else {
            throw XCTSkip("set MAP_FRAME_REPORT=<days> to count the flat map's redraws on a 44-station map")
        }
        let days = try XCTUnwrap(Int(value).flatMap { (1...365).contains($0) ? $0 : nil }, "MAP_FRAME_REPORT is 1 to 365 days")
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        var world = try Self.miaoli(lines: 4, data: data)
        world.setSpeed(.fast)
        for _ in 0..<days { try world.advance(ticks: 144) }
        let waiting = world.passengers.reduce(Int64(0)) { $0 + $1.waiting.reduce(0) { $0 + $1.count } }
        var rows = [
            "stations \(world.stations.count), lines \(world.lines.count), trains \(world.trains.count), waiting \(waiting), traffic control \(world.isTrafficControlEnabled ? "on" : "off")",
            "",
            "| Scenario | Ticks a second | " + MapRedrawCount.Canvas.allCases.map(\.rawValue).joined(separator: " | ") + " |",
            "| --- | --: |" + String(repeating: " --: |", count: MapRedrawCount.Canvas.allCases.count),
        ]
        let scenarios: [(String, minute: Int64, GameSpeed)] = [
            ("day 08:00, 1×", 8 * 60, .x1),
            ("day 08:00, 600× (opening speed)", 8 * 60, .normal),
            ("night 20:30, 1×", 20 * 60 + 30, .x1),
            ("night 20:30, 600×", 20 * 60 + 30, .normal),
            ("day 08:00, 6000×", 8 * 60, .fast),
        ]
        var costs: [String] = []
        for (label, minute, speed) in scenarios {
            var start = world
            start.setSpeed(.x60)
            // To the minute of the day, a minute a tick at most.
            while Self.minuteOfDay(start.clock.now) != minute {
                let left = (minute - Self.minuteOfDay(start.clock.now) + 1_440) % 1_440
                start.setSpeed(left >= 10 ? .fast : .x60)
                try start.advance(ticks: left >= 10 ? 1 : 10)
            }
            start.setSpeed(speed)
            let session = GameSession(world: start)
            let seconds = 10
            let count = try MapRedrawCount.run(session, ticks: seconds * 10)
            rows.append("| \(label) | 10 | " + MapRedrawCount.Canvas.allCases.map { count.perSecond($0, over: seconds) }.joined(separator: " | ") + " |")
            if costs.isEmpty {
                costs = Self.costs(of: session)
            }
        }
        rows += ["", "Why the track canvas redraws (of its redraws, by day at 600×): see the scenario rows; inputs that changed:"]
        var start = world
        start.setSpeed(.normal)
        let reasons = try MapRedrawCount.run(GameSession(world: start), ticks: 100).reasons
        rows += reasons.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value) of 100 ticks" }
        rows += ["", "| What the map works out | ms |", "| --- | --: |"] + costs
        print(rows.joined(separator: "\n"))
    }

    static func minuteOfDay(_ time: GameTime) -> Int64 {
        (time.seconds % GameTime.secondsPerDay) / 60
    }

    /// What the map works out for its canvases on a render after a tick.
    static func costs(of session: GameSession) -> [String] {
        let clock = ContinuousClock()
        let now = session.world
        var next = now
        try? next.advance(ticks: 1)
        let traffic = session.trafficOverlay
        let renders = 20
        let reads: [(String, () -> Void)] = [
            ("TrafficReading (each tick, off the main actor)", { _ = TrafficReading(world: next, train: nil, in: .english, previous: nil) }),
            ("traffic == after a tick", { _ = traffic == TrafficReading(world: next, train: nil, in: .english, previous: nil).overlay }),
            ("MapLayers.waitingPassengerCounts", { _ = MapLayers.waitingPassengerCounts(in: now) }),
            ("TrainMotion(world:)", { _ = TrainMotion(world: now, time: 0) }),
            ("LineBadge.codes", { _ = LineBadge.codes(for: now.lines) }),
            ("depotRuns()", { _ = now.depotRuns() }),
            ("stations == after a tick", { _ = now.stations == next.stations }),
            ("network == after a tick", { _ = now.network == next.network }),
            ("lines == after a tick", { _ = now.lines == next.lines }),
            ("trains == after a tick", { _ = now.trains == next.trains }),
        ]
        return reads.map { label, read in
            let spent = clock.measure { for _ in 0..<renders { read() } }
            return "| \(label) | \(LongGameCostReportTests.ms(spent, per: renders)) |"
        }
    }

    /// ``LongGameCostReportTests/miaoli(data:)`` with `lines` lines 1.5 km
    /// apart, and a second train on each.
    static func miaoli(lines: Int, data: RealWorldData) throws -> GameWorld {
        var options = NewGameOptions()
        options.funds = .unlimited
        let anchor = try XCTUnwrap(GeoAnchor(latitude: 245_692_340, longitude: 1_208_222_820))
        var world = GameLauncher.newWorld(
            at: anchor, options: options,
            data: .init(population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: nil)
        )
        let tile = try XCTUnwrap(world.mapExpansion?.owned.first)
        let metre = WorldCoordinate.unitsPerMetre, length = MapExpansion.tileLength
        let minX = Int64(tile.column) * length, minY = Int64(tile.row) * length
        for line in 0..<lines {
            let y = minY + length / 2 + Int64(line - lines / 2) * 1_500 * metre
            let points = (0..<11).map { PlanPoint(x: minX + 1_200 * metre + Int64($0) * 700 * metre, y: y) }
            world = try LineBuilder.line(through: points, in: world)
        }
        GameSession.readLand(roundStationsOf: &world, population: data.population, places: data.places, water: data.water)
        return world
    }
}

/// How many times each canvas of the flat map would be drawn again over a
/// run of ticks, the player not touching the map: a canvas is drawn again
/// when an input its `==` compares changed (the camera, the layers and the
/// selection stay as they are).
@MainActor
struct MapRedrawCount {
    enum Canvas: String, CaseIterable {
        /// `main`'s one canvas of the track, the stations and traffic
        /// control (``MapCanvas`` before decision 371).
        case trackBefore = "track (main)"
        /// Decision 371: the track and the lines alone.
        case railway = "railway"
        /// Decision 371: traffic control, the buildings and the stations.
        case trafficAndStations = "traffic + stations"
        /// `main`'s names with the waiting counts.
        case namesBefore = "names (main)"
        /// Decision 371: the names alone.
        case names = "names"
        /// Decision 371: the waiting counts alone.
        case waitingCounts = "waiting counts"
        /// The trains' canvas, a new glide.
        case trains = "trains (new glide)"
    }

    var redraws: [Canvas: Int] = [:]
    /// Of the track's redraws on `main`, which input changed.
    var reasons: [String: Int] = [:]

    func perSecond(_ canvas: Canvas, over seconds: Int) -> String {
        String(format: "%.1f", Double(redraws[canvas] ?? 0) / Double(seconds))
    }

    static func run(_ session: GameSession, ticks: Int) throws -> MapRedrawCount {
        var count = MapRedrawCount()
        var last = Inputs(session)
        for _ in 0..<ticks {
            session.advance(realElapsed: GameSession.tickInterval)
            let now = Inputs(session)
            let railway = !MapRedraw.sameRailway(last.world, now.world)
            let stations = !MapRedraw.sameStations(last.world, now.world, comparesLand: false)
            let traffic = last.traffic != now.traffic, lights = last.lights != now.lights
            let names = !MapRedraw.sameNames(last.world, now.world)
            let counts = last.waiting != now.waiting
            func note(_ canvas: Canvas, _ changed: Bool) { if changed { count.redraws[canvas, default: 0] += 1 } }
            note(.trackBefore, railway || stations || traffic || lights)
            note(.railway, railway)
            note(.trafficAndStations, stations || traffic || lights)
            note(.namesBefore, names || counts)
            note(.names, names)
            note(.waitingCounts, counts)
            note(.trains, last.world.trains != now.world.trains)
            for (reason, changed) in [("railway", railway), ("stations", stations), ("traffic", traffic), ("lights", lights)] where changed {
                count.reasons[reason, default: 0] += 1
            }
            last = now
        }
        return count
    }

    /// What the map's canvases read after a tick.
    struct Inputs {
        let world: GameWorld
        let traffic: TrafficOverlay
        let lights: Double
        let waiting: [StationID: Int64]

        @MainActor init(_ session: GameSession) {
            world = session.world
            traffic = session.trafficOverlay
            lights = DayNight.step(DayNight.tint(at: session.world.clock.now).lights)
            waiting = MapLayers.waitingPassengerCounts(in: session.world)
        }
    }
}
