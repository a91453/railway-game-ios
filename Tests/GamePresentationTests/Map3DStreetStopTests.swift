import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 596: the 3D map's street traffic waits at its stop lines while
/// the signal is not green, a queue behind the first, and the pavements'
/// walkers wait at a zebra while its little green man is red or flashing;
/// every place still worked out from the clock alone.
final class Map3DStreetStopTests: XCTestCase {
    private typealias Stops = Map3DStreetStops
    private typealias Point = Map3DBaseMap.Point

    private let everywhere = Map3DBaseMap.Bounds(minX: -10_000, minZ: -10_000, maxX: 10_000, maxZ: 10_000)

    private func road(_ kind: Map3DBaseMap.RoadKind, _ points: [(Double, Double)]) -> Map3DBaseMap.Road {
        Map3DBaseMap.Road(kind: kind, isRamp: false, points: points.map { Point(x: $0.0, z: $0.1) }, bounds: everywhere)
    }

    private func builder() -> Map3DScene.Builder {
        Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                           world: GameWorld.newGame())
    }

    // MARK: The signals' windows

    func testAVehicleGoesOnGreenAndAWalkerBeforeTheFlashing() {
        let main = Stops.Window.driving(.main, group: 0), cross = Stops.Window.driving(.cross, group: 0)
        for second in 0..<Map3DSignalTiming.cycle {
            let time = Double(second) + 0.5
            XCTAssertEqual(main.isOpen(at: time), Map3DSignalTiming.light(.main, at: second) == .green, "\(second)")
            XCTAssertEqual(cross.isOpen(at: time), Map3DSignalTiming.light(.cross, at: second) == .green, "\(second)")
            // The little green man lit and not yet flashing.
            let walk = Stops.Window.walking(.main, group: 0)
            let left = Map3DPedestrianSignal.left(.main, at: second)
            XCTAssertEqual(walk.isOpen(at: time), left.map { $0 > Map3DPedestrianSignal.flashing } ?? false, "\(second)")
        }
        // The group's offset, as the signals read it.
        let late = Stops.Window.driving(.main, group: 2)
        for second in Int64(0)..<140 {
            XCTAssertEqual(late.isOpen(at: Double(second)), Map3DSignalTiming.light(.main, group: 2, at: second) == .green)
        }
        // Next: now when open and late enough; else the next opening and the wait.
        XCTAssertEqual(main.next(from: 10, delay: 2), 10)
        XCTAssertEqual(main.next(from: 0.5, delay: 2), 2)
        XCTAssertEqual(main.next(from: 33.2, delay: 2), 72)
        XCTAssertEqual(cross.next(from: 3, delay: 0), 36)
        XCTAssertEqual(main.next(from: -5, delay: 0), 0)
    }

    func testATripIsWholeCycles() {
        XCTAssertEqual(Stops.lap(moving: 20, stops: 1), 140)
        XCTAssertEqual(Stops.lap(moving: 61, stops: 2), 280)
        for moving in stride(from: 1.0, through: 500, by: 7) {
            for stops in 0...4 {
                let lap = Stops.lap(moving: moving, stops: stops)
                XCTAssertEqual(lap.truncatingRemainder(dividingBy: 70), 0)
                XCTAssertGreaterThanOrEqual(lap, moving + Double(stops) * 70)
            }
        }
    }

    // MARK: Vehicles

    /// A 300 m lane at 11 m/s with stops at 120 m (main road) and 260 m
    /// (crossing road, another group), and its vehicles every `headway` s.
    private func lane(headway: Double = Stops.headway(speed: 11)) -> (way: Stops.Lane, entries: [Double], halves: [(front: Float, rear: Float)]) {
        let way = Stops.Lane(stops: [(120, .driving(.main, group: 1)), (260, .driving(.cross, group: 3))], speed: 11, length: 300)
        let slots = Int((way.lap / headway).rounded())
        let entries = (0..<slots).map { -(Double($0) + 0.4 * Double(map3DRandom(Int32($0), 5, salt: 1))) * way.lap / Double(slots) }
        // Cars, vans, scooters (some with one beside) and a bus in twenty.
        let halves: [(front: Float, rear: Float)] = (0..<slots).map {
            $0 % 20 == 7 ? (6, 6) : [(2.2, 2.2), (0.9, 0.9), (0.9, 3.2), (2.3, 2.3), (0.9, 0.9)][$0 % 5]
        }
        return (way, entries, halves)
    }

    func testALoneVehicleStopsAtTheLineUntilGreen() throws {
        let way = Stops.Lane(stops: [(100, .driving(.main, group: 0))], speed: 10, length: 200)
        // Entering at 30 s it reaches the line at 40 s, red (the main road
        // is green 0–32 s): it waits there until 70 s and a moment.
        let trip = way.trip(entry: 30, half: 2.2, behind: nil)
        let stood = try XCTUnwrap(trip.stood[0])
        XCTAssertEqual(stood.at, 100)
        XCTAssertEqual(stood.from, 40, accuracy: 1e-9)
        XCTAssertEqual(stood.until, 70 + 10 / Stops.pulling / 2, accuracy: 1e-9)
        XCTAssertEqual(trip.end, stood.until + 10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(way.position(of: trip, entry: 30, at: 55)), 100, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(way.position(of: trip, entry: 30, at: 31)), 10, accuracy: 1e-9)
        // Entering at 0 s it is over the line at 10 s, green: it goes on.
        let green = way.trip(entry: 0, half: 2.2, behind: nil)
        XCTAssertNil(green.stood[0])
        XCTAssertEqual(green.end, 20, accuracy: 1e-9)
        // Gone once it leaves the lane, back at the trip's start a lap on.
        XCTAssertNil(way.position(of: green, entry: 0, at: 25))
        XCTAssertEqual(try XCTUnwrap(way.position(of: green, entry: 0, at: way.lap + 5)), 50, accuracy: 1e-9)
    }

    func testNoVehicleCrossesALineUnlessGreenNorRunsIntoTheOneAhead() {
        let (way, entries, halves) = lane()
        let trips = way.trips(entries: entries, halves: halves)
        var stood = 0
        for (slot, trip) in trips.enumerated() {
            XCTAssertLessThanOrEqual(trip.end - entries[slot], way.lap, "every trip ends within its lap")
            stood += trip.stood.compactMap { $0 }.count
        }
        XCTAssertGreaterThan(stood, trips.count / 2, "most wait somewhere")
        var queued = 0
        for step in 0..<Int(way.lap * 10) {
            let time = Double(step) / 10
            let at = trips.indices.map { way.position(of: trips[$0], entry: entries[$0], at: time) }
            let later = trips.indices.map { way.position(of: trips[$0], entry: entries[$0], at: time + 0.1) }
            for slot in trips.indices {
                // Off the lane (waiting to come onto it) is not drawn.
                guard let now = at[slot], now >= 0 else { continue }
                // Never past a line it reached while the light was not green.
                if let next = later[slot] {
                    XCTAssertLessThanOrEqual(next - now, 11 * 0.1 + 1e-6, "no jump")
                    XCTAssertGreaterThanOrEqual(next - now, -1e-9, "never backwards")
                    for stop in way.stops where now <= stop.at && next > stop.at + 1e-6 {
                        XCTAssertTrue(stop.window.isOpen(at: time) || stop.window.isOpen(at: time + 0.1), "\(slot) crossed \(stop.at) at \(time)")
                    }
                }
                // Behind the one that entered before it, by both halves.
                let ahead = slot + 1 < trips.count ? at[slot + 1] : nil
                if let ahead, ahead > now {
                    let gap = ahead - now - Double(halves[slot + 1].rear + halves[slot].front)
                    XCTAssertGreaterThan(gap, -0.05, "\(slot) into \(slot + 1) at \(time)")
                    if gap < 4 { queued += 1 }
                }
            }
        }
        XCTAssertGreaterThan(queued, 0, "some queue")
    }

    func testTheFirstOfATripQueuesBehindTheLastOfTheTripBefore() throws {
        // So dense the queue reaches round: the first slot waits behind
        // the last slot's earlier trip.
        let (way, entries, halves) = lane(headway: 2.6)
        let trips = way.trips(entries: entries, halves: halves)
        let again = way.trips(entries: entries, halves: halves)
        for (a, b) in zip(trips, again) { XCTAssertEqual(a.end, b.end) }
        let last = trips.count - 1
        let ahead = way.trip(entry: entries[last], half: halves[last].front, behind: (trips[0], -way.lap, halves[0].rear))
        XCTAssertEqual(ahead.end, trips[last].end, accuracy: 1e-9)
    }

    func testTheStreetsTrafficWaitsAtACrossroads() throws {
        var builder = builder(), taken = Set<Map3DScene.ChunkKey>()
        builder.addRoads([road(.primary, [(-300, 0), (0, 0), (300, 0)]), road(.secondary, [(0, -300), (0, 0), (0, 300)])], taking: &taken)
        let lanes = builder.streetLife.lanes
        XCTAssertFalse(lanes.isEmpty)
        // Each lane has a stop line each way, before the junction.
        for lane in lanes {
            XCTAssertEqual(lane.stops.count, 2, "\(lane.path.points.first!)")
            for stop in lane.stops {
                let middle = lane.path.length / 2
                XCTAssertEqual(stop.direction > 0, stop.at < middle)
                XCTAssertGreaterThan(abs(stop.at - middle), 10)
                XCTAssertLessThan(abs(stop.at - middle), 25)
            }
            let roads = Set(lane.stops.map(\.road))
            XCTAssertEqual(roads.count, 1)
            XCTAssertEqual(roads.first, abs(lane.path.points.last!.x - lane.path.points.first!.x) > 1 ? .main : .cross)
        }
        // The pavements cross the other road at its zebras, and walk with
        // their own road's little green man.
        let markings = Map3DRoadMarkings([road(.primary, [(-300, 0), (0, 0), (300, 0)]), road(.secondary, [(0, -300), (0, 0), (0, 300)])])
        for (kind, alongX) in [(Map3DBaseMap.RoadKind.primary, true), (.secondary, false)] {
            let off = kind.width(ramp: false) / 2 + Map3DScene.Builder.sidewalk(of: kind) / 2
            for side: Float in [1, -1] {
                let points = alongX ? [Map3DPoint(-300, 0, side * off), Map3DPoint(300, 0, side * off)]
                                    : [Map3DPoint(side * off, 0, -300), Map3DPoint(side * off, 0, 300)]
                let path = try XCTUnwrap(Map3DStreetLife.Path(points))
                let crossings = Map3DScene.Builder.pavementCrossings(path, crossings: markings.crossings)
                // Across the other road's arm on its side, kerb to kerb.
                XCTAssertEqual(crossings.count, 1, "\(kind) \(side)")
                let other = (alongX ? Map3DBaseMap.RoadKind.secondary : .primary).width(ramp: false)
                for crossing in crossings {
                    XCTAssertEqual(crossing.to - crossing.from, other, accuracy: 0.01)
                    XCTAssertEqual((crossing.to + crossing.from) / 2, 300, accuracy: 0.01)
                    XCTAssertEqual(crossing.road, alongX ? .main : .cross)
                }
            }
        }
        // A frame by the game's clock: vehicles stand at the stop lines
        // while the light is not green; without it, as before.
        let life = builder.streetLife
        let target = Map3DPoint(0, 0, 0)
        let group = Map3DSignalTiming.group(at: Point(x: 0, z: 0))
        // 50 s into the main road's cycle: the main road red.
        let second = Double(50 - Map3DSignalTiming.offset(group) + 70 * 1_000)
        let frame = life.frame(target: target, distance: 150, time: 0, detail: .full, activity: .init(), signals: second)
        XCTAssertGreaterThan(frame.vehicles, 0)
        let before = life.frame(target: target, distance: 150, time: 0, detail: .full, activity: .init())
        XCTAssertGreaterThan(before.vehicles, 0)
        // Along x (the main road) none is in the junction's middle now.
        let inJunction = frame.instances.filter { abs($0.transform[12]) < 8 && abs($0.transform[14]) < 3 && abs($0.transform[0]) > 0.9 }
        XCTAssertTrue(inJunction.isEmpty)
    }

    // MARK: Walkers

    func testAWalkerStepsOntoTheCrossingOnlyWhenTheGreenManIsLit() {
        let crossings = [Map3DStreetLife.Crossing(from: 40, to: 52, road: .main, group: 1),
                         Map3DStreetLife.Crossing(from: 130, to: 140, road: .cross, group: 2)]
        for seed in 0..<30 {
            let r = { (salt: Int32) in Double(map3DRandom(Int32(seed), 3, salt: salt)) }
            let phase = r(1) * 70, start = r(2) * 30
            let walk = Stops.Walk(route: Stops.Route(length: 200, crossings: crossings), start: start, pace: 0.98 + 0.52 * r(3), phase: phase, stepOff: 0.5)
            XCTAssertEqual(walk.lap.truncatingRemainder(dividingBy: 70), 0)
            XCTAssertLessThanOrEqual(walk.end(pace: walk.pace, phase: phase), walk.lap)
            XCTAssertEqual(walk.waits.count, 4)
            var last = walk.place(at: 0, phase: phase)
            XCTAssertEqual(last.at, start, accuracy: 1e-9)
            for step in 1...Int(walk.lap * 10) {
                let time = Double(step) / 10
                let place = walk.place(at: time, phase: phase)
                let moved = Stops.Lane.wrapped(place.at - last.at, walk.route.length)
                XCTAssertLessThanOrEqual(min(moved, walk.route.length - moved), 1.5 * 0.1 + 1e-6, "no jump at \(time)")
                // Onto a crossing (either way) only while it may go.
                for crossing in crossings {
                    let edges = [(Double(crossing.from), true), (2 * 200 - Double(crossing.to), false)]
                    for (edge, _) in edges {
                        let before = Stops.Lane.wrapped(edge - last.at, walk.route.length), after = Stops.Lane.wrapped(place.at - edge, walk.route.length)
                        guard before > 0, before < 1, after < 1, after > 0 else { continue }
                        let window = Stops.Window.walking(crossing.road, group: crossing.group)
                        XCTAssertTrue(window.isOpen(at: phase + time) || window.isOpen(at: phase + time - 1.2), "seed \(seed) at \(time)")
                    }
                }
                last = place
            }
            // Back where it set out at the end of its trip.
            XCTAssertEqual(walk.place(at: walk.lap - 0.01, phase: phase).at, start, accuracy: 1e-6)
        }
    }

    func testTheSameEveryTimeAndStillWithReduceMotion() {
        var builder = builder(), taken = Set<Map3DScene.ChunkKey>()
        builder.addRoads([road(.primary, [(-300, 0), (0, 0), (300, 0)]), road(.secondary, [(0, -300), (0, 0), (0, 300)])], taking: &taken)
        let life = builder.streetLife
        let target = Map3DPoint(0, 0, 0)
        let a = life.frame(target: target, distance: 150, time: 12, detail: .full, activity: .init(), signals: 123_456.5)
        let b = life.frame(target: target, distance: 150, time: 99, detail: .full, activity: .init(), signals: 123_456.5)
        // Places by the game's clock alone (the real one only turns legs).
        XCTAssertEqual(a.instances.filter { $0.model != Map3DStreetLife.models[.walking] && $0.model != Map3DStreetLife.models[.standing] }.map(\.transform),
                       b.instances.filter { $0.model != Map3DStreetLife.models[.walking] && $0.model != Map3DStreetLife.models[.standing] }.map(\.transform))
        // Reduce Motion: as before, everyone where they stand at the start.
        let still = life.frame(target: target, distance: 150, time: 12, still: true, detail: .full, activity: .init(), signals: 123_456.5)
        let before = life.frame(target: target, distance: 150, time: 0, still: true, detail: .full, activity: .init())
        XCTAssertEqual(still.instances.map(\.transform), before.instances.map(\.transform))
    }
}
