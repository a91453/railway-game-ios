import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The owner's report (2026-11-27, iPhone): the three guideway trains
/// (maglev, straddle monorail, suspended monorail) stood past the end of
/// their platforms at a line's terminus, the whole first car of a one-car
/// train past the end of the track, into the buildings beyond.
///
/// GameCore turns a train round at a terminus with its head where its tail
/// was (``GameWorld/reverseTrain(_:)``): its head is its first car's centre
/// and its length runs from that to its last car's. The maps draw its
/// first car's nose at its head (decision 565), so a train that arrived
/// stood inside its platform, but once turned round it was drawn a whole
/// car further on, past the end it had stopped at. ``TrainCars``
/// (``TrainMotion/Run/turnRoom``) now lays that car ahead of the turned
/// train, so it stays where it stood until it pulls out.
@MainActor
final class TrainCarsTurnbackTests: XCTestCase {
    typealias Point = TrainMotion.Point
    static let metre = Double(WorldCoordinate.unitsPerMetre)

    /// A line of two stations, each at a dead end of `system` track, its
    /// platform `platformCars` standard cars long running up to the end of
    /// the track, in a world with real car lengths (a new game's), and a
    /// train of `type` and `cars` running it, placed at the first stop.
    static func stubLine(system: TrackSystem, type: TrainType?, cars: Int, platformCars: Int) throws -> (GameWorld, TrainID) {
        var world = try makeWorld(width: 102_400, height: 20_480, balance: 100_000_000, speed: .normal)
        world.setRealCarLengths(true)
        let builder = GameSession(world: world)
        builder.selectTool(.network)
        builder.chooseNetworkSystem(system)
        builder.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
        builder.tapNetwork(at: PlanPoint(x: 61_440, y: 10_240), reach: 16)
        builder.buildNetworkTrack()
        var w = builder.world
        XCTAssertEqual(w.network.edges.count, 1, builder.message?.text ?? "")
        let edge = try XCTUnwrap(w.network.edges.first)
        XCTAssertEqual(edge.system, system)
        let west = try w.buildStation(named: "West", at: PlanPoint(x: 4_000, y: 10_000)).id
        let east = try w.buildStation(named: "East", at: PlanPoint(x: 59_000, y: 10_000)).id
        let platform = Int64(platformCars) * w.platformCarLength
        try w.addTrackPlatform(west, on: edge.id, from: 0, to: platform)
        try w.addTrackPlatform(east, on: edge.id, from: edge.length - platform, to: edge.length)
        let line = try w.createLine(named: "L", stops: [west, east]).id
        try w.setLineServiceWindow(line, to: .allDay)
        let train = try w.purchaseTrain(named: "T").id
        if let type { try w.setTrainType(train, to: type) }
        try w.setTrainCars(train, to: cars)
        let session = GameSession(world: w, language: .traditionalChinese)
        session.assignTrain(train, toLine: line)
        session.place(session.world.train(id: train)!, atPlatformOf: session.world.station(id: west)!)
        XCTAssertNotNil(session.world.train(id: train)?.position, session.message?.text ?? "")
        var running = session.world
        running.setSpeed(.normal)
        // A minute a tick, from 06:00, when the line runs.
        while running.clock.now.seconds < 6 * 3600 { try running.advance(ticks: 1) }
        return (running, train)
    }

    /// How far `point` is from the polyline `line`, in metres.
    static func distance(_ point: Point, to line: [Point]) -> Double {
        PlatformStopTests.distance(point, to: line)
    }

    struct Standing {
        var stops = 0
        var turned = 0
        var worst3D = 0.0
        var worst2D = 0.0
        var worst: String = ""
    }

    /// Runs `world` `minutes` game minutes; each time train `id` stands
    /// still (or has just been turned round) with its whole body along a
    /// platform, how far its cars as the 3D and 2D maps draw them reach
    /// past that platform, and how often it stood turned round (its head
    /// not at the platform's far end the way it faces).
    static func measure(_ world: inout GameWorld, train id: TrainID, minutes: Int) throws -> Standing {
        var motion = TrainMotion(world: world, time: Double(world.clock.now.seconds))
        var result = Standing()
        for _ in 0..<minutes {
            try world.advance(ticks: 1)
            motion = TrainMotion(world: world, previous: motion, time: Double(world.clock.now.seconds))
            guard let run = motion.runs.first(where: { $0.train == id }), run.lag == 0,
                  let train = world.train(id: id), case .onEdge(let traversal, let offset)? = train.position,
                  let platform = world.trackPlatformsAlongWholeTrain(id).first,
                  let edge = world.network.edge(traversal.edge),
                  let geometry = world.trackGeometry(of: edge.id) else { continue }
            result.stops += 1
            let at = traversal.direction == .forward ? offset : edge.length - offset
            if at != (traversal.direction == .forward ? platform.end : platform.start) { result.turned += 1 }
            let line = geometry.points(from: platform.start, to: platform.end).map(Point.init)
            let heights = Map3DTrains.Heights(world: world)
            func worst(_ cars: [[Point]]) -> Double {
                cars.flatMap { [$0.first, $0.last].compactMap { $0 } }.map { distance($0, to: line) }.max() ?? 0
            }
            let drawn3D = worst(Map3DTrains.cars(of: run, progress: 1, heights: heights, models: .standard).cars)
            let drawn2D = worst(TrainCars.mapCars(of: run, progress: 1))
            if max(drawn3D, drawn2D) > max(result.worst3D, result.worst2D) {
                result.worst = "at \(world.clock.now.seconds) s, head \(at) of platform \(platform.start)...\(platform.end): "
                    + "3D \(String(format: "%.1f", drawn3D)) m, 2D \(String(format: "%.1f", drawn2D)) m past it"
            }
            result.worst3D = max(result.worst3D, drawn3D)
            result.worst2D = max(result.worst2D, drawn2D)
        }
        return result
    }

    /// The owner's three trains, one car (the maglev and the monorail) and
    /// four (the suspended monorail), and an ordinary train, each on its
    /// own track: standing at either terminus, turned round or not, every
    /// car is drawn inside the platform on both maps.
    func testATrainTurnedRoundAtATerminusStaysInsideItsPlatform() throws {
        let cases: [(TrackSystem, TrainType?, Int)] = [
            (.maglev, .maglev, 1), (.straddle, .monorail, 1), (.suspended, .skyRail, 4), (.conventional, nil, 4),
        ]
        for (system, type, cars) in cases {
            var (world, train) = try Self.stubLine(system: system, type: type, cars: cars, platformCars: 4)
            let found = try Self.measure(&world, train: train, minutes: 180)
            let name = "\(type.map { Train.typeText($0, in: .english) } ?? "standard") × \(cars)"
            XCTAssertGreaterThan(found.stops, 0, "\(name): never stood at a platform")
            XCTAssertGreaterThan(found.turned, 0, "\(name): never stood turned round")
            XCTAssertLessThanOrEqual(found.worst3D, 0.5, "\(name) 3D: \(found.worst)")
            XCTAssertLessThanOrEqual(found.worst2D, 0.5, "\(name) 2D: \(found.worst)")
        }
    }
}
