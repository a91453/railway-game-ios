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

    /// Decision 377 (TestFlight 84.1, the High Speed Rail demo at 6000×,
    /// the names, the waiting counts and the fares and stamps on: 3 fps,
    /// the track drawn twice a second at up to 375 ms each). Which canvas
    /// a tick asks to draw again there, and which input changed. Run on
    /// request:
    ///
    ///     MAP_FRAME_REPORT_HSR=100 swift test -c release -Xswiftc -enable-testing \
    ///       --filter MapFrameCostReportTests/testWhatEachCanvasRedrawsOnTheHighSpeedRail
    func testWhatEachCanvasRedrawsOnTheHighSpeedRail() throws {
        guard let value = ProcessInfo.processInfo.environment["MAP_FRAME_REPORT_HSR"] else {
            throw XCTSkip("set MAP_FRAME_REPORT_HSR=<ticks> to count the flat map's redraws on the High Speed Rail at 6000×")
        }
        let ticks = try XCTUnwrap(Int(value).flatMap { (1...10_000).contains($0) ? $0 : nil }, "MAP_FRAME_REPORT_HSR is 1 to 10,000 ticks")
        let session = try Self.highSpeedSession()
        session.setSpeed(.fast)
        let count = try MapRedrawCount.run(session, ticks: ticks)
        var rows = [
            "stations \(session.world.stations.count), lines \(session.world.lines.count), trains \(session.world.trains.count), traffic control \(session.world.isTrafficControlEnabled ? "on" : "off"), \(ticks) ticks at 6000×",
            "",
            "| Canvas | redrawn, of \(ticks) ticks |", "| --- | --: |",
        ]
        rows += MapRedrawCount.Canvas.allCases.map { "| \($0.rawValue) | \(count.redraws[$0] ?? 0) |" }
        rows += ["", "Inputs that changed (of \(ticks) ticks):"]
        rows += count.reasons.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value)" }
        rows += ["", "The points the railway canvas draws, the whole line on an iPhone 17 Pro held sideways (874×402):", ""]
        rows += Self.railwayPoints(of: session.world)
        print(rows.joined(separator: "\n"))
    }

    /// The points the railway canvas works out, the whole High Speed Rail
    /// in view: of the track (one polyline an edge) and of the lines (one
    /// a stretch, ``LineMap``), every sampled point as before decision 377
    /// and those ``PolylineDetail`` keeps, and the time to project them.
    static func railwayPoints(of world: GameWorld) -> [String] {
        let focus = WorldRegion(enclosing: world.stations.map { WorldCoordinate(x: $0.point.x, y: $0.point.y) })
        let camera = PlanCamera(bounds: world.bounds, viewport: ScreenSize(width: 874, height: 402), showing: focus)
        let tolerance = PolylineDetail.tolerance(pointsPerUnit: camera.pointsPerUnit)
        let clock = ContinuousClock()
        var details: [TrackEdgeID: PolylineDetail] = [:]
        let detailTime = clock.measure {
            for edge in world.network.edges {
                if let geometry = world.trackGeometry(of: edge.id) { details[edge.id] = PolylineDetail(geometry.points) }
            }
        }
        let lines = LineMap(world: world)
        func pieces(simplified: Bool) -> [[WorldCoordinate]] {
            var pieces: [[WorldCoordinate]] = []
            for edge in world.network.edges {
                guard let geometry = world.trackGeometry(of: edge.id), let detail = details[edge.id] else { continue }
                pieces.append(simplified ? geometry.points(from: 0, to: geometry.length, detail: detail, tolerance: tolerance) : geometry.points)
            }
            for stretch in lines.stretches {
                guard let geometry = world.trackGeometry(of: stretch.edge), let detail = details[stretch.edge] else { continue }
                let end = min(stretch.end, geometry.length)
                guard stretch.start < end else { continue }
                pieces.append(simplified
                    ? geometry.points(from: stretch.start, to: end, detail: detail, tolerance: tolerance)
                    : geometry.points(from: stretch.start, to: end))
            }
            return pieces
        }
        var rows = ["| | polylines | points | ms to pick and project them |", "| --- | --: | --: | --: |"]
        for simplified in [false, true] {
            var drawn: [[WorldCoordinate]] = []
            var projected = 0
            let spent = clock.measure {
                drawn = pieces(simplified: simplified)
                for piece in drawn { projected += piece.map { camera.screenPoint(of: $0) }.count }
            }
            rows.append("| \(simplified ? "kept (decision 377)" : "every sampled point (before)") | \(drawn.count) | \(projected) | \(LongGameCostReportTests.ms(spent)) |")
        }
        rows += [
            "",
            "edges \(world.network.edges.count), line stretches \(lines.stretches.count), tolerance \(String(format: "%.0f", tolerance)) world units (\(PolylineDetail.screenTolerance) pt), significance of every edge worked out once: \(LongGameCostReportTests.ms(detailTime)) ms",
        ]
        return rows
    }

    /// The High Speed Rail demo as the app opens it, with the real-world
    /// data the map reads.
    static func highSpeedSession() throws -> GameSession {
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let railways = try XCTUnwrap(data.railways)
        let world = try HighSpeedDemo.make(
            in: .traditionalChinese, railways: railways, population: data.population, places: data.places, water: data.water, coverage: data.coverage
        )
        let session = GameSession(world: world, language: .traditionalChinese)
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.coverage = data.coverage
        session.railways = railways
        return session
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
            let lines = !last.world.lines.elementsEqual(now.world.lines) {
                $0.id == $1.id && $0.stops == $1.stops && $0.routePreferences == $1.routePreferences && $0.color == $1.color
                    && $0.patterns.map(\.calls) == $1.patterns.map(\.calls) && $0.isRing == $1.isRing && $0.isHighSpeed == $1.isHighSpeed
            }
            let detail: [(String, Bool)] = [
                ("railway", railway), ("stations", stations), ("traffic", traffic), ("lights", lights),
                ("· world.bounds", last.world.bounds != now.world.bounds), ("· world.stations", last.world.stations != now.world.stations),
                ("· world.network", last.world.network != now.world.network),
                ("· world.placedBuildings", last.world.placedBuildings != now.world.placedBuildings),
                ("· line map key (lines)", lines), ("· waiting counts", counts),
            ]
            for (reason, changed) in detail where changed {
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
