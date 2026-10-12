import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 182: trains glide along the track they covered in
/// the last tick, from where they were to where they are, and jump when
/// they turned back or went somewhere their path did not lead.
final class TrainMotionTests: XCTestCase {
    typealias Point = TrainMotion.Point

    func testATrailFindsPointsAndPlacesAlongIt() throws {
        let trail = TrainMotion.Trail([Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 5)])
        XCTAssertEqual(trail.points.count, 3, "a repeated point is dropped")
        XCTAssertEqual(trail.length, 15)
        XCTAssertEqual(trail.point(at: 4), Point(x: 4, y: 0))
        XCTAssertEqual(trail.point(at: 12), Point(x: 10, y: 2))
        XCTAssertEqual(trail.point(at: -3), Point(x: 0, y: 0), "held at its start")
        XCTAssertEqual(trail.point(at: 99), Point(x: 10, y: 5), "and at its end")
        XCTAssertEqual(trail.direction(at: 12), Point(x: 0, y: 1))
        XCTAssertEqual(trail.points(from: 5, to: 13), [Point(x: 5, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 3)])
        let found = try XCTUnwrap(trail.locate(Point(x: 7, y: 2)))
        XCTAssertEqual(found.distance, 7, accuracy: 1e-9)
        XCTAssertEqual(found.error, 2, accuracy: 1e-9)
        XCTAssertNil(TrainMotion.Trail([]).point(at: 0))
        XCTAssertEqual(TrainMotion.Trail([Point(x: 3, y: 4)]).point(at: 2), Point(x: 3, y: 4))
    }

    func testAGlideTakesTheTickItCameAfter() {
        let none = TrainMotion()
        XCTAssertEqual(none.duration, TrainMotion.tickSeconds)
        XCTAssertFalse(none.isMoving)
        let empty = try! makeWorld()
        let first = TrainMotion(world: empty, time: 100)
        XCTAssertEqual(first.duration, 0.1, "the game's tick when the one before is not known")
        XCTAssertEqual(TrainMotion(world: empty, previous: first, time: 100.12).duration, 0.12, accuracy: 1e-9)
        XCTAssertEqual(TrainMotion(world: empty, previous: first, time: 103).duration, 0.5, "never longer than the longest step")
        XCTAssertEqual(TrainMotion(world: empty, previous: first, time: 100.001).duration, 0.05)
        XCTAssertEqual(first.progress(at: 99), 0)
        XCTAssertEqual(first.progress(at: 100.05), 0.5, accuracy: 1e-9)
        XCTAssertEqual(first.progress(at: 101), 1)
    }

    /// A line's train over its run there and back: each tick it glides
    /// from exactly where it was to exactly where it is, along the track
    /// (never off it, never further than it went), across the edges'
    /// joins; it is drawn in its line's colour.
    func testATrainGlidesFromWhereItWasToWhereItIsAlongTheTrack() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .x10)
        let track = TestLine(tiles: 7, row: 1)
        try track.build(in: &world)
        let alpha = try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let gamma = try track.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let main = try world.createLine(named: "Main", stops: [alpha, gamma]).id
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: track.at(1, facingEast: true))
        try world.setTrainMovementRate(train.id, to: 1_024)
        try world.assignTrain(train.id, to: main)

        var motion = TrainMotion(world: world, time: 0)
        var glides = 0, acrossJoins = 0, jumps = 0
        for tick in 1...3_000 {
            let before = try XCTUnwrap(world.train(id: train.id)?.position)
            let was = try XCTUnwrap(world.location(of: before)).position
            try world.advance(ticks: 1)
            motion = TrainMotion(world: world, previous: motion, time: Double(tick) / 10)
            let position = try XCTUnwrap(world.train(id: train.id)?.position)
            let now = try XCTUnwrap(world.location(of: position))
            let run = try XCTUnwrap(motion.runs.first)
            XCTAssertEqual(run.look, .line(main, nil))
            let end = try XCTUnwrap(run.head(at: 1))
            XCTAssertEqual(end.point.x, Double(now.position.x), accuracy: 0.5)
            XCTAssertEqual(end.point.y, Double(now.position.y), accuracy: 0.5)
            let moved = was.x != now.position.x || was.y != now.position.y
            if run.lag > 0 {
                glides += 1
                let start = try XCTUnwrap(run.head(at: 0))
                XCTAssertEqual(start.point.x, Double(was.x), accuracy: 0.5, "tick \(tick)")
                XCTAssertEqual(start.point.y, Double(was.y), accuracy: 0.5)
                // On this straight track the glide is the distance gone.
                XCTAssertEqual(run.lag, abs(Double(now.position.x - was.x)), accuracy: 0.5)
                let middle = try XCTUnwrap(run.head(at: 0.5))
                XCTAssertEqual(middle.point.x, Double(was.x + now.position.x) / 2, accuracy: 0.5)
                XCTAssertEqual(middle.point.y, Double(now.position.y), accuracy: 0.5, "on the track")
                // It faces the way it goes.
                XCTAssertEqual(middle.heading.x.sign, Double(now.position.x - was.x).sign)
                if case .onEdge(let from, _) = before, case .onEdge(let to, _) = position, from.edge != to.edge { acrossJoins += 1 }
            } else if moved {
                jumps += 1
            }
        }
        XCTAssertGreaterThan(glides, 100)
        XCTAssertGreaterThan(acrossJoins, 4, "glides over the joins between edges")
        XCTAssertLessThan(jumps, glides / 10, "it jumps only when it turns back")
    }

    /// A train of several cars draws its whole body behind its gliding
    /// head, along the track it was on.
    func testABodyFollowsItsHead() throws {
        var world = try makeWorld(width: 16_384, height: 4_096, balance: 1_000_000, speed: .x10)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 2_048))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 15_360, y: 2_048))
        let edge = try world.buildTrackEdge(from: west, to: east)
        let train = try world.purchaseTrain(named: "T1").id
        try world.setTrainCars(train, to: 4)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: 4 * Train.carLength))
        try world.setTrainMovementRate(train, to: 6_000)
        var motion = TrainMotion(world: world, time: 0)
        try world.advance(ticks: 1)
        motion = TrainMotion(world: world, previous: motion, time: 0.1)
        let run = try XCTUnwrap(motion.runs.first)
        XCTAssertEqual(run.look, .plain, "on no line")
        XCTAssertGreaterThan(run.lag, 0)
        XCTAssertEqual(run.length, Double(3 * Train.carLength))
        for progress in [0, 0.3, 1.0] {
            let body = run.body(at: progress)
            let head = try XCTUnwrap(run.head(at: progress)).point
            XCTAssertEqual(try XCTUnwrap(body.first), head)
            XCTAssertEqual(head.x - (try XCTUnwrap(body.last)).x, run.length, accuracy: 0.5, "its whole length behind")
        }
    }

    /// Turned back, it jumps: no glide backwards through itself.
    func testATrainTurnedBackJumps() throws {
        var world = try makeWorld(width: 16_384, height: 4_096, balance: 1_000_000, speed: .x10)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 2_048))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 15_360, y: 2_048))
        let edge = try world.buildTrackEdge(from: west, to: east)
        let train = try world.purchaseTrain(named: "T1").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: 4_096))
        let motion = TrainMotion(world: world, time: 0)
        try world.reverseTrain(train)
        let after = TrainMotion(world: world, previous: motion, time: 0.1)
        XCTAssertEqual(after.runs.first?.lag, 0)
        XCTAssertFalse(after.isMoving)
    }

    /// A freight line's trains are grey.
    func testAFreightLinesTrainLooksLikeFreight() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        world.enableFreight()
        let track = TestLine(tiles: 7, row: 1)
        try track.build(in: &world)
        let alpha = try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let gamma = try track.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let line = try world.createLine(named: "Goods", stops: [alpha, gamma]).id
        try world.setLineFreight(line, to: true)
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: track.at(1, facingEast: true))
        try world.assignTrain(train.id, to: line)
        XCTAssertEqual(TrainMotion(world: world, time: 0).runs.first?.look, .freight)
    }
}
