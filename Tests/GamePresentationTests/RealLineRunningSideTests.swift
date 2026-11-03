import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 564: the metro and light-rail lines bought from the map run on
/// the right, as the real trains drawn on them before were
/// (``Map3DRealTrains/rightHand``); the TRA's lines keep left (decision 202).
@MainActor
final class RealLineRunningSideTests: XCTestCase {
    /// How many times a train of the bought line, running in service on
    /// double track, had the line's other track on its left (it ran on the
    /// right) and on its right (it ran on the left), sampled each minute.
    struct Sides {
        var right = 0
        var left = 0
        /// The same of the empty runs.
        var emptyRight = 0
        var emptyLeft = 0
    }

    static func sides(of world: inout GameWorld, hours: Int, line: LineID? = nil) throws -> Sides {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        // Every piece of the world's track between two of its sampled
        // points, by the 50 m squares it crosses.
        struct Piece {
            let edge: TrackEdgeID
            let ax, ay, bx, by: Double
        }
        struct Square: Hashable {
            let x, y: Int
        }
        let cell = 50 * metre
        func square(_ value: Double) -> Int { Int((value / cell).rounded(.down)) }
        var pieces: [Square: [Piece]] = [:]
        for edge in world.network.edges {
            guard let points = world.trackGeometry(of: edge.id)?.points else { continue }
            for (a, b) in zip(points, points.dropFirst()) {
                let piece = Piece(edge: edge.id, ax: Double(a.x), ay: Double(a.y), bx: Double(b.x), by: Double(b.y))
                for x in square(min(piece.ax, piece.bx))...square(max(piece.ax, piece.bx)) {
                    for y in square(min(piece.ay, piece.by))...square(max(piece.ay, piece.by)) { pieces[Square(x: x, y: y), default: []].append(piece) }
                }
            }
        }
        // Not near an end of a line or a depot, where the loops and the
        // depot's tracks lie either side.
        let ends = world.lines.flatMap { [$0.stops.first, $0.stops.last].compactMap(\.self) } + world.stations.filter(\.isDepot).map(\.id)
        let endPoints = ends.compactMap { world.station(id: $0).map { (x: Double($0.location.x), y: Double($0.location.y)) } }
        let clear = 1_200 * metre
        var sides = Sides()
        // From six in the morning, when the first trains are out.
        let morning = 6 * 60 - Int(world.clock.now.seconds % 86_400 / 60)
        if morning > 0 { try world.advance(ticks: morning) }
        var was: [TrainID: TrainPosition] = [:]
        for _ in 0..<(hours * 60) {
            try world.advance(ticks: 1)
            let before = was
            was = Dictionary(uniqueKeysWithValues: world.trains.compactMap { train in train.position.map { (train.id, $0) } })
            let trains = line.flatMap { world.line(id: $0) }.map { Set($0.trains) }
            for train in world.trains where trains?.contains(train.id) ?? true {
                // A train that moved this minute.
                guard let position = train.position, case .onEdge(let traversal, _) = position, before[train.id] != nil, before[train.id] != position,
                      let location = world.location(of: position) else { continue }
                let x = Double(location.position.x), y = Double(location.position.y)
                guard !endPoints.contains(where: { ($0.x - x) * ($0.x - x) + ($0.y - y) * ($0.y - y) < clear * clear }) else { continue }
                let length = Double(location.direction.length)
                guard length > 0 else { continue }
                let wx = Double(location.direction.dx) / length, wy = Double(location.direction.dy) / length
                // The nearest other track across this one, 2 to 8 m to
                // the side: how far, x east and y south, so negative on
                // the left (decision 202).
                var nearest: Double?
                for piece in pieces[Square(x: square(x), y: square(y))] ?? [] where piece.edge != traversal.edge {
                    let dx = piece.bx - piece.ax, dy = piece.by - piece.ay
                    let t = max(0, min(1, ((x - piece.ax) * dx + (y - piece.ay) * dy) / max(dx * dx + dy * dy, 1)))
                    let ox = piece.ax + t * dx - x, oy = piece.ay + t * dy - y
                    let along = ox * wx + oy * wy, across = wx * oy - wy * ox
                    guard abs(along) <= metre, abs(across) >= 2 * metre, abs(across) <= 8 * metre else { continue }
                    if nearest.map({ abs(across) < abs($0) }) ?? true { nearest = across }
                }
                guard let nearest else { continue }
                if ProcessInfo.processInfo.environment["RUNNING_SIDE_DEBUG"] != nil, nearest >= 0 {
                    let near = world.stations.min { a, b in
                        (WorldVector(a.location) - WorldVector(location.position.plan)).length < (WorldVector(b.location) - WorldVector(location.position.plan)).length
                    }
                    print("RUNNING_SIDE on the left: \(world.clock.now.seconds % 86_400 / 60) \(train.name) empty \(train.isDeadheading) \(traversal) near \(near?.name ?? "?") to \(train.timetable.last.flatMap { world.station(id: $0.station)?.name } ?? "-")")
                }
                switch (train.isDeadheading, nearest < 0) {
                case (false, true): sides.right += 1
                case (false, false): sides.left += 1
                case (true, true): sides.emptyRight += 1
                case (true, false): sides.emptyLeft += 1
                }
            }
        }
        return sides
    }

    /// Asserts the side of a right-hand line; a left-hand one (a Taiwan
    /// Railway branch, laid as before decision 564) is only printed, and
    /// `seen: false` takes a line too short to see outside its ends.
    private func check(_ world: World, _ id: String, right: Bool, hours: Int, seen: Bool = true) throws {
        var played = world.world
        let sides = try Self.sides(of: &played, hours: hours, line: world.line)
        print("RUNNING_SIDE \(id): on the right \(sides.right), on the left \(sides.left); empty runs \(sides.emptyRight), \(sides.emptyLeft)")
        guard right else { return }
        if seen { XCTAssertGreaterThan(sides.right + sides.left, 20, "\(id): too few trains seen on double track") }
        XCTAssertEqual(sides.left, 0, "\(id): trains ran on the left")
    }

    struct World {
        let world: GameWorld
        let line: LineID?
    }

    /// Before decision 564, its trains ran on the left: from six to seven
    /// in the morning 0 times on the right and some 800 on the left.
    func testTheWenhuLineRunsOnTheRight() throws {
        try check(World(world: DepotReturnReportTests.bought("trtc:BR", rules: .realistic), line: nil), "trtc:BR", right: true, hours: 1)
    }

    /// A game saved with the Wenhu Line bought before decision 564 names
    /// for each way the platforms of the left-hand running: it loads and
    /// runs as before, on the left, every morning run out and no train in a
    /// deadlock. The line's trains are not moved to the other track (one
    /// running between stations has no way across); removing the line and
    /// buying it again (decision 528) lays it to run on the right.
    func testAWenhuLineBoughtBeforeKeepsRunningOnTheLeft() throws {
        var world = try DepotReturnReportTests.bought("trtc:BR", rules: .realistic)
        let line = try XCTUnwrap(world.lines.first)
        // The preferences as before: at each station between the ends,
        // the two ways' platforms the other way round.
        var old = line.routePreferences
        for stop in 1..<(line.stops.count - 1) {
            guard let down = old.firstIndex(where: { $0.from == stop - 1 && $0.to == stop }),
                  let up = old.firstIndex(where: { $0.from == stop + 1 && $0.to == stop }) else { continue }
            let (a, b) = (old[down], old[up])
            old[down] = LineRoutePreference(from: a.from, to: a.to, tracks: a.tracks, platform: b.platform)
            old[up] = LineRoutePreference(from: b.from, to: b.to, tracks: b.tracks, platform: a.platform)
        }
        XCTAssertNotEqual(old, line.routePreferences)
        try world.setLineRoutePreferences(line.id, to: old)
        world = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
        XCTAssertEqual(world.line(id: line.id)?.routePreferences, old)
        var played = world
        let sides = try Self.sides(of: &played, hours: 1)
        print("RUNNING_SIDE trtc:BR bought before: on the right \(sides.right), on the left \(sides.left)")
        XCTAssertGreaterThan(sides.left, 20)
        XCTAssertEqual(sides.right, 0)
        XCTAssertEqual(played.deadlockedTrains().count, 0)
        let ran = try XCTUnwrap(played.line(id: line.id))
        let day = played.clock.now.seconds / GameTime.secondsPerDay
        let due = zip(ran.runs, ran.runDays).filter { run, _ in
            run.runs(onDay: day) && run.start(onDay: day) + LineRun.latestDispatch < played.clock.now.seconds
        }
        XCTAssertGreaterThan(due.count, 20)
        XCTAssertEqual(due.filter { _, sent in (sent ?? -1) < day }.count, 0, "runs not sent out by seven")
    }

    /// The other lines on sale with double track, three hours each, and the
    /// Wenhu Line bought on the real Taipei opening and on the high-speed
    /// demo; only when asked (`RUNNING_SIDE_REPORT=1`, some minutes each;
    /// `RUNNING_SIDE_ONLY=<id>` or `openings` for one).
    func testTheOtherLinesKeepToTheirSide() throws {
        guard ProcessInfo.processInfo.environment["RUNNING_SIDE_REPORT"] != nil else {
            throw XCTSkip("Set RUNNING_SIDE_REPORT=1 to play every line on sale (decision 564).")
        }
        for (id, right, seen) in [("ntdlrt:V", true, true), ("ntdlrt:VB", true, true), ("ntalrt:K", true, true),
                                  ("sanying:LB", true, true), ("trtc:R_XBT", true, false), ("trtc:G_XBT", true, false),
                                  ("LIUJIA", false, false), ("SHALUN", false, false)]
            where ProcessInfo.processInfo.environment["RUNNING_SIDE_ONLY"].map({ $0 == id }) ?? true {
            let session = try RealLineAcquisitionTests.game(round: id, side: 1 << 21, heights: true)
            guard let line = session.buyableRealLines.first(where: { $0.network == id || $0.id == id }) else {
                print("RUNNING_SIDE \(id): not on sale")
                continue
            }
            XCTAssertEqual(line.keepsRight, right, id)
            let offer = session.realLineOffer(for: line)
            guard session.acquireRealLine(offer) else {
                print("RUNNING_SIDE \(id): not bought, \(offer.problem ?? session.message?.text ?? "")")
                continue
            }
            try check(World(world: session.world, line: nil), id, right: right, hours: 3, seen: seen)
        }
        if let only = ProcessInfo.processInfo.environment["RUNNING_SIDE_ONLY"], only != "openings" { return }
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        // The screenshot scene buys it and follows a train near its middle.
        let scene = GameSession(world: ScreenshotScene.wenhu.make(in: .english), language: .english)
        scene.population = data.population
        scene.places = data.places
        scene.water = data.water
        scene.heights = data.heights
        scene.coverage = data.coverage
        scene.railways = data.railways
        XCTAssertTrue(scene.buyForScreenshot("trtc:BR", until: 7 * 3_600 + 40 * 60), scene.message?.text ?? "")
        XCTAssertEqual(scene.world.clock.now.seconds % GameTime.secondsPerDay, 7 * 3_600 + 40 * 60)
        XCTAssertNotNil(scene.screenshotTrainMidway(on: "trtc:BR"))
        let city = try XCTUnwrap(AcquisitionReportTests.cities.first { $0.name == "Taipei" })
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: city.latitude, longitudeDegrees: city.longitude))
        let openings = [
            ("Taipei opening", GameLauncher.newWorld(at: anchor, options: NewGameOptions(), data: GameLauncher.NewWorldData(
                population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights
            ))),
            ("high-speed demo", try HighSpeedDemo.make(
                in: .english, railways: XCTUnwrap(data.railways), population: data.population, places: data.places, water: data.water,
                coverage: data.coverage, heights: data.heights
            )),
        ]
        for (name, world) in openings {
            let session = GameSession(world: world, language: .english)
            session.population = data.population
            session.places = data.places
            session.water = data.water
            session.heights = data.heights
            session.coverage = data.coverage
            session.railways = data.railways
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "trtc:BR" }, "\(name): on sale")
            let offer = session.realLineOffer(for: line)
            let acquisition = try XCTUnwrap(offer.acquisition, "\(name): \(offer.problem ?? "")")
            // Built on a funded copy, as the opening's cash may not reach.
            var built = session.world.pricingCopy()
            _ = try session.build(acquisition, in: &built, recording: false)
            // Not recorded as bought: the line it made, the last.
            let bought = try XCTUnwrap(built.lines.last?.id)
            try check(World(world: built, line: bought), "trtc:BR on the \(name)", right: true, hours: 3)
        }
    }
}
