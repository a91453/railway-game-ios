import Foundation
import GameCore
import XCTest
@testable import GamePresentation

/// Decision 708: the real coaches and the coach stops in the 3D map.
final class Map3DCoachesTests: XCTestCase {
    private static let taipei = GeoAnchor(latitudeDegrees: 25.047882, longitudeDegrees: 121.517219)
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let tiles: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }
    private static let routes: Result<RealCoaches, Error> = Result {
        try RealCoaches(data: RealWorldDataLoadTests.file("real_coaches", "json"))
    }
    /// Taipei with its coach stops, its scene on the base map's roads, and
    /// the coaches laid in it.
    private static let laid: Result<(world: GameWorld, scene: Map3DScene, coaches: Map3DCoaches), Error> = Result {
        var world = GameWorld.newGame(anchor: taipei)
        world = CoachCatalog.withCoachStops(world, network: try CoachNetwork(data: RealWorldDataLoadTests.file("coach_network", "json")))
        let scene = Map3DScene(world: world, baseMap: try tiles.get())
        return (world, scene, Map3DCoaches(world: world, scene: scene, coaches: try routes.get()))
    }

    // MARK: The timetable

    func testACoachGoesEvenlyFromStopToStopAndStandsAtTheStopsOnTheWay() {
        let timing = Map3DCoaches.Timing(stopMinutes: [0, 10, 30], stopMetres: [0, 5_000, 25_000])
        XCTAssertEqual(timing.runMinutes, 30)
        XCTAssertNil(timing.metres(after: -0.1))
        XCTAssertNil(timing.metres(after: 30.1))
        XCTAssertEqual(timing.metres(after: 0), 0)
        XCTAssertEqual(try XCTUnwrap(timing.metres(after: 5)), 2_500, accuracy: 0.001)
        // It stands half a minute at the second stop, then makes the rest
        // of the way in the time left.
        XCTAssertEqual(timing.metres(after: 10), 5_000)
        XCTAssertEqual(timing.metres(after: 10.5), 5_000)
        XCTAssertEqual(try XCTUnwrap(timing.metres(after: 20.25)), 15_000, accuracy: 0.001)
        XCTAssertEqual(timing.metres(after: 30), 25_000)
        // And back: when it is first that far along.
        for elapsed in [0.0, 3, 9.9, 12, 20.25, 29] {
            let metres = try! XCTUnwrap(timing.metres(after: elapsed))
            XCTAssertEqual(timing.minutes(at: metres), elapsed, accuracy: 0.0001)
        }
        XCTAssertEqual(timing.minutes(at: 5_000), 10)
    }

    func testStopsThatShareAMinuteArePassedOnTheWay() {
        // TDX's minutes are whole: three stops in minute 4. The coach does
        // not jump from the first of them to the last.
        let timing = Map3DCoaches.Timing(stopMinutes: [0, 4, 4, 4, 8, 8], stopMetres: [0, 2_000, 2_400, 2_900, 4_000, 4_300])
        XCTAssertEqual(timing.minutes, [0, 4, 8])
        XCTAssertEqual(timing.metres, [0, 2_000, 4_300])
        var last = -1.0
        for step in 0...160 {
            let metres = try! XCTUnwrap(timing.metres(after: Double(step) * 0.05))
            XCTAssertGreaterThanOrEqual(metres, last)
            XCTAssertLessThan(metres - max(last, 0), 60, "no jump at \(Double(step) * 0.05) min")
            last = metres
        }
        XCTAssertEqual(last, 4_300)
    }

    // MARK: Laying

    func testOnlyTheStretchesInsideTheSceneAreKept() {
        let points = [Map3DPoint(-300, 0, 50), Map3DPoint(100, 0, 50), Map3DPoint(100, 0, 400), Map3DPoint(40, 0, 400), Map3DPoint(40, 0, 20)]
        var metres: [Double] = [0]
        for index in 1..<points.count { metres.append(metres[index - 1] + Double((points[index] - points[index - 1]).length)) }
        let runs = Map3DCoaches.runs(points, metres: metres, low: (0, 0), high: (200, 200))
        XCTAssertEqual(runs.count, 2)
        // In at the west edge, out at the south (z 200) edge.
        XCTAssertEqual(runs[0].first?.point.x ?? 1, 0, accuracy: 0.01)
        XCTAssertEqual(runs[0].first?.metres ?? 0, 300, accuracy: 0.01)
        XCTAssertEqual(runs[0].last?.point.z ?? 0, 200, accuracy: 0.01)
        XCTAssertEqual(runs[0].last?.metres ?? 0, 550, accuracy: 0.01)
        // And back in further on.
        XCTAssertEqual(runs[1].first?.metres ?? 0, 400 + 350 + 60 + 200, accuracy: 0.01)
        for run in runs {
            for (a, b) in zip(run, run.dropFirst()) {
                XCTAssertGreaterThan(b.metres, a.metres)
                XCTAssertLessThanOrEqual(b.metres - a.metres, Map3DCoaches.step + 0.01)
            }
        }
    }

    func testAMapWithNoCoachStopsHasNoCoaches() throws {
        let world = GameWorld.newGame(anchor: Self.taipei)
        let coaches = Map3DCoaches(world: world, scene: Map3DScene(world: world), coaches: try Self.routes.get())
        XCTAssertTrue(coaches.isEmpty)
        var frame = Map3DTrains.Frame()
        coaches.add(to: &frame, pack: .standard, second: 8 * 3_600, eye: Map3DPoint(0, 300, 0))
        XCTAssertTrue(frame.instances.isEmpty)
    }

    func testTaipeisCoachStopsStandBesideTheirRoads() throws {
        let (world, scene, coaches) = try Self.laid.get()
        XCTAssertFalse(coaches.stops.isEmpty)
        XCTAssertLessThanOrEqual(coaches.stops.count, world.coachStops.count)
        let roads = Map3DCoaches.Roads(lanes: scene.streetLife.lanes)
        var beside = 0
        for stop in coaches.stops {
            guard let road = roads.kerb(near: stop.point, within: 40) else { continue }
            let off = Map3DPoint(stop.point.x - road.foot.x, 0, stop.point.z - road.foot.z).length
            // Off the carriageway, and no further than its own depth from it.
            if off > road.half, off < road.half + Map3DCoachStop.depth + 1 { beside += 1 }
        }
        XCTAssertGreaterThanOrEqual(Double(beside) / Double(coaches.stops.count), 0.8, "\(beside) of \(coaches.stops.count)")
    }

    func testTaipeisCoachesRunOnTheRoadsByTheirTimetables() throws {
        let (_, scene, coaches) = try Self.laid.get()
        XCTAssertGreaterThan(coaches.routeCount, 50)
        // A Wednesday (game day 2: day 0 is a Monday), 08:00.
        XCTAssertEqual(Map3DCoaches.weekday(ofDay: 2), 2)
        let second = Double(2 * GameTime.secondsPerDay + 8 * 3_600)
        let now = coaches.coaches(second: second)
        XCTAssertGreaterThan(now.count, 20)
        let roads = Map3DBuses.RoadIndex(lanes: scene.streetLife.lanes.map { lane in
            Map3DStreetLife.Lane(path: lane.path, half: lane.half, twoWay: true, speed: lane.speed, perHundred: lane.perHundred,
                                 scooters: lane.scooters, seed: lane.seed)
        }, near: now.map(\.point))
        let onRoads = now.filter { coach in roads.nearest(to: coach.point, within: 12).map { $0.distance < $0.half + 1 } ?? false }
        XCTAssertGreaterThan(Double(onRoads.count) / Double(now.count), 0.9, "\(onRoads.count) of \(now.count)")
        // Ten seconds on, each coach still there has gone ahead, no faster
        // than a coach goes.
        let later = coaches.coaches(second: second + 10)
        var compared = 0
        for coach in now {
            guard let then = later.first(where: { $0.route == coach.route && $0.departure == coach.departure && $0.day == coach.day }) else { continue }
            let moved = then.point - coach.point
            XCTAssertLessThan(moved.length, 10 * 40, coach.route)
            if moved.length > 1 {
                XCTAssertGreaterThan(moved.x * coach.along.x + moved.z * coach.along.z, 0, coach.route)
            }
            compared += 1
        }
        XCTAssertGreaterThan(compared, now.count / 2)
        // None is drawn before it leaves: an hour with no departures yet.
        for coach in now { XCTAssertLessThanOrEqual(coach.departure, 8 * 60) }
    }

    func testAFrameDrawsTheStopsAndAtMostItsShareOfCoaches() throws {
        let (_, _, coaches) = try Self.laid.get()
        let second = Double(2 * GameTime.secondsPerDay + 8 * 3_600)
        let all = coaches.coaches(second: second)
        let middle = try XCTUnwrap(all.first).point
        var frame = Map3DTrains.Frame()
        coaches.add(to: &frame, pack: .standard, second: second, eye: middle + Map3DPoint(0, 150, 0))
        let pack = Map3DModelPack.standard
        let names = frame.instances.map { pack.models[$0.model].name }
        let drawn = names.filter { $0.hasPrefix("life-coachBus-") }
        XCTAssertFalse(drawn.isEmpty)
        XCTAssertLessThanOrEqual(drawn.count, Map3DCoaches.mostNear + Map3DCoaches.mostFar)
        XCTAssertLessThanOrEqual(drawn.filter { $0.hasSuffix("-near") }.count, Map3DCoaches.mostNear)
        XCTAssertTrue(names.contains { $0.hasPrefix("coach-stop-roadside") })
        XCTAssertFalse(names.contains { $0.contains("tourism") })
    }

    func testEveryCompanyHasOneLivery() {
        XCTAssertEqual(Map3DCoaches.liveries.count, 7)
        XCTAssertEqual(Map3DCoaches.livery(of: ["國光客運"]), Map3DCoaches.livery(of: ["國光客運", "統聯客運"]))
        XCTAssertEqual(Map3DCoaches.livery(of: []), 0)
        XCTAssertEqual(Map3DCoaches.drawn.count, 16)
    }
}
