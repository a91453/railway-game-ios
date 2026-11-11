import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// PLATSTOP: a player's report on TestFlight 110.1, "a train pulling in
/// overruns the platform by about a car": on the 3D map, at an elevated
/// station of two island platforms, the near train stood with its front
/// car hanging past the platform's end over bare track.
///
/// Measures, for every train standing at a platform, how far its cars as
/// the 3D and 2D maps draw them, and its body as GameCore holds it, reach
/// past that platform.
@MainActor
final class PlatformStopTests: XCTestCase {
    typealias Point = TrainMotion.Point
    static let metre = Double(WorldCoordinate.unitsPerMetre)

    /// How far `point` is from the polyline `line`, in metres.
    static func distance(_ point: Point, to line: [Point]) -> Double {
        var best = Double.infinity
        for (a, b) in zip(line, line.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y, q = dx * dx + dy * dy
            let t = q > 0 ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / q, 0), 1) : 0
            let px = a.x + t * dx - point.x, py = a.y + t * dy - point.y
            best = min(best, (px * px + py * py).squareRoot())
        }
        return best / metre
    }

    struct Overrun: CustomStringConvertible {
        let train: TrainID
        let cars: Int
        let platform: Double
        let body: Double
        let drawn3D: Double
        let drawn2D: Double
        var description: String {
            "train \(train.rawValue) \(cars) cars, platform \(String(format: "%.0f", platform)) m: past it GameCore body "
                + "\(String(format: "%.1f", body)) m, 3D \(String(format: "%.1f", drawn3D)) m, 2D \(String(format: "%.1f", drawn2D)) m"
        }
    }

    /// Every train of `world` whose head stands at a berth of a platform
    /// (its far end the way it travels) with its run at rest: how far its
    /// body, and its cars as the maps lay them, reach past that platform.
    static func overruns(in world: GameWorld, motion: TrainMotion, models: Map3DModelPack?) -> [Overrun] {
        let snapshot = world.railwaySnapshot()
        let heights = Map3DTrains.Heights(world: world)
        var found: [Overrun] = []
        for run in motion.runs {
            guard let train = world.trains.first(where: { $0.id == run.train }),
                  case .onEdge(let traversal, let offset)? = train.position,
                  let edge = world.network.edge(traversal.edge) else { continue }
            let at = traversal.direction == .forward ? offset : edge.length - offset
            guard let platform = snapshot.platforms.first(where: {
                $0.platform.edge == traversal.edge
                    && (traversal.direction == .forward ? $0.platform.end == at : $0.platform.start == at)
            }) else { continue }
            let line = platform.points.map(Point.init)
            let body = run.body(at: 1)
            let laid = Map3DTrains.cars(of: run, progress: 1, heights: heights, models: models).cars
            let flat = TrainCars.mapCars(of: run, progress: 1)
            func worst(_ cars: [[Point]]) -> Double {
                cars.flatMap { [$0.first, $0.last].compactMap { $0 } }.map { distance($0, to: line) }.max() ?? 0
            }
            found.append(Overrun(
                train: run.train, cars: train.cars, platform: Double(platform.platform.length) / metre,
                body: body.map { distance($0, to: line) }.max() ?? 0, drawn3D: worst(laid), drawn2D: worst(flat)
            ))
        }
        return found
    }

    /// Runs `world` `minutes` game minutes and gathers every standing
    /// train's overrun, the worst per train.
    static func measure(_ world: inout GameWorld, minutes: Int, models: Map3DModelPack? = .standard) throws -> [Overrun] {
        var motion = TrainMotion(world: world, time: Double(world.clock.now.seconds))
        var worst: [TrainID: Overrun] = [:]
        for _ in 0..<minutes {
            try world.advance(ticks: 1)
            motion = TrainMotion(world: world, previous: motion, time: Double(world.clock.now.seconds))
            for overrun in overruns(in: world, motion: motion, models: models) {
                if let known = worst[overrun.train], known.drawn3D >= overrun.drawn3D { continue }
                worst[overrun.train] = overrun
            }
        }
        return worst.values.sorted { $0.train.rawValue < $1.train.rawValue }
    }

    /// A line of two stations on straight track in a world with real car
    /// lengths, as every new game on the real map (decision 227), each
    /// platform `platformCars` standard cars long (the platform tool's
    /// length, ``GameWorld/platformCarLength``), and a train of `cars`
    /// running it, placed at the first stop.
    static func line(cars: Int, platformCars: Int, type: TrainType? = nil) throws -> (GameSession, TrainID, assigned: String) {
        var world = try makeWorld(width: 204_800, height: 20_480, balance: 100_000_000, speed: .normal)
        world.setRealCarLengths(true)
        let builder = GameSession(world: world)
        builder.selectTool(.network)
        builder.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
        builder.tapNetwork(at: PlanPoint(x: 194_560, y: 10_240), reach: 16)
        builder.buildNetworkTrack()
        var w = builder.world
        let west = try w.buildStation(named: "West", at: PlanPoint(x: 6_000, y: 10_000)).id
        let east = try w.buildStation(named: "East", at: PlanPoint(x: 190_000, y: 10_000)).id
        let edge = w.network.edges[0]
        let platform = Int64(platformCars) * w.platformCarLength
        try w.addTrackPlatform(west, on: edge.id, from: 6_400, to: 6_400 + platform)
        try w.addTrackPlatform(east, on: edge.id, from: edge.length - 6_400 - platform, to: edge.length - 6_400)
        let line = try w.createLine(named: "L", stops: [west, east]).id
        try w.setLineServiceWindow(line, to: .allDay)
        let train = try w.purchaseTrain(named: "T").id
        if let type { try w.setTrainType(train, to: type) }
        try w.setTrainCars(train, to: cars)
        let session = GameSession(world: w, language: .traditionalChinese)
        session.assignTrain(train, toLine: line)
        let assigned = session.message?.text ?? ""
        session.place(session.world.train(id: train)!, atPlatformOf: session.world.station(id: west)!)
        XCTAssertNotNil(session.world.train(id: train)?.position, session.message?.text ?? "")
        return (session, train, assigned)
    }

    /// PLATSTOP (110.1): a train as long as its platforms (four 20 m cars
    /// at platforms of four cars, as the platform tool and the trains a
    /// line buys make them) stops with every car inside the platform, on
    /// the 3D map and the 2D one, at both ends of its line. Before decision
    /// 565 its first car's nose stood half a car, 10 m, past the end.
    func testATrainAsLongAsItsPlatformStopsInsideIt() throws {
        let (session, train, assigned) = try Self.line(cars: 4, platformCars: 4)
        XCTAssertFalse(assigned.contains("月台"), assigned)
        var world = session.world
        XCTAssertEqual(world.train(id: train)?.carPitch, Train.realStandardCarLength)
        let found = try Self.measure(&world, minutes: 240)
        let stops = found.filter { $0.train == train }
        XCTAssertFalse(stops.isEmpty, "the train never stood at a platform")
        for stop in stops {
            XCTAssertEqual(stop.body, 0, accuracy: 0.01, stop.description)
            XCTAssertLessThanOrEqual(stop.drawn3D, 0.5, stop.description)
            XCTAssertLessThanOrEqual(stop.drawn2D, 0.5, stop.description)
        }
        XCTAssertNil(world.shortPlatformCall(ofTrain: train), "it fits: nothing to tell")
    }

    /// Decision 565: a train a car longer than its platforms still stops
    /// there (GameCore fits it by its first car's centre to its last's),
    /// its last car past the end; the player is told which station and
    /// what fits when it is assigned, but the line does not hold it.
    func testATrainACarLongerThanItsPlatformIsToldItsLastCarStopsPastTheEnd() throws {
        let (session, train, assigned) = try Self.line(cars: 5, platformCars: 4)
        let world = session.world
        let short = try XCTUnwrap(world.shortPlatformCall(ofTrain: train))
        XCTAssertTrue(short.overhangs)
        XCTAssertEqual(short.station, world.stations[0].id)
        XCTAssertEqual(short.needed, 5 * Train.realStandardCarLength, "the whole train: 100 m")
        XCTAssertEqual(short.cars, 4)
        XCTAssertEqual(
            world.shortPlatformText(short, in: .traditionalChinese),
            "列車比 West 的月台長，停站時最後一節會在月台外：把月台加長到 100 公尺（點車站，在「月台」裡加長），或把列車移出軌道、減到 4 節"
        )
        XCTAssertEqual(
            world.shortPlatformText(short, in: .english),
            "Longer than the platforms at West, so its last car stops past the end: lengthen one to 100 m (tap the station, then Platforms), or take the train off the track and shorten it to 4 cars"
        )
        XCTAssertNil(world.lineDispatchHold(of: train), "it runs")
        XCTAssertTrue(assigned.hasSuffix("停站時最後一節會在月台外：把月台加長到 100 公尺（點車站，在「月台」裡加長），或把列車移出軌道、減到 4 節。"), assigned)
    }

    /// L9-2: four EMU3000 cars (20.3 m each, 81.2 m) on a four-car platform
    /// (80 m) are not told to drop to three; five cars still are, and told
    /// to drop to the four that stop there untold (REVIEW-L10, L10-3).
    func testAFlagshipTrainOnAFourCarPlatformIsNotToldToShorten() throws {
        let (session, train, assigned) = try Self.line(cars: 4, platformCars: 4, type: .emu3000)
        XCTAssertGreaterThan(session.world.train(id: train)?.carPitch ?? 0, Train.realStandardCarLength)
        XCTAssertNil(session.world.shortPlatformCall(ofTrain: train))
        XCTAssertFalse(assigned.contains("月台"), assigned)
        let (longer, five, _) = try Self.line(cars: 5, platformCars: 4, type: .emu3000)
        let short = try XCTUnwrap(longer.world.shortPlatformCall(ofTrain: five))
        XCTAssertEqual(short.cars, 4)
    }

    /// Decision 565's screenshot scene: its train stands at the far
    /// platform of a real-map line, every car inside it on both maps.
    func testThePlatformStopSceneStandsItsTrainInsideTheFarPlatform() throws {
        let world = ScreenshotScene.platformStop.make(in: .traditionalChinese)
        XCTAssertTrue(world.realCarLengths)
        let train = try XCTUnwrap(world.trains.first)
        XCTAssertEqual(train.cars, 4)
        let motion = TrainMotion(world: world, time: Double(world.clock.now.seconds))
        let found = Self.overruns(in: world, motion: motion, models: .standard).filter { $0.train == train.id }
        let stop = try XCTUnwrap(found.first, "the train is not standing at a platform")
        XCTAssertEqual(stop.platform, 80, accuracy: 0.01)
        XCTAssertLessThanOrEqual(stop.drawn3D, 0.5, stop.description)
        XCTAssertLessThanOrEqual(stop.drawn2D, 0.5, stop.description)
        XCTAssertEqual(world.station(id: world.stations[1].id)?.name, "S1", "it stands at the far station")
        // The 3D screenshot looks at the far station.
        let place = try XCTUnwrap(ScreenshotScene.platformStop.place)
        let at = try XCTUnwrap(RealWorldFrame(world: world)).worldPosition(latitude: place.latitude, longitude: place.longitude)
        let s1 = world.stations[1].point
        XCTAssertEqual(at.x, Double(s1.x), accuracy: 2 * Self.metre)
        XCTAssertEqual(at.y, Double(s1.y), accuracy: 2 * Self.metre)
    }
}
