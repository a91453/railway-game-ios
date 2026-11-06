import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 600: each real train on the track the owner's site assigns it
/// (`dispatch.json`), at the place its timetable gives along the line, as
/// the 2D map has it.
final class Map3DRealDispatchTests: XCTestCase {
    private let weekday = RealServiceDay(weekday: 3)
    private let tuesday = RealServiceDay(weekday: 2)

    private static func dispatch() throws -> RealRailDispatch {
        try XCTUnwrap(Map3DRealTrainsTests.railways?.tracks?.dispatch)
    }

    /// A real-world game round (`latitude`, `longitude`) with a line 10 km
    /// across, as ``Map3DRealTracksTests``'s, its scene with the real
    /// railways, and its frame and a builder of the same ground.
    private func scene(latitude: Double, longitude: Double) throws -> (scene: Map3DScene, builder: Map3DScene.Builder, frame: RealWorldFrame) {
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let at = frame.worldPosition(latitude: latitude, longitude: longitude)
        let across = Int64(5_000 * WorldCoordinate.unitsPerMetre)
        let middle = (x: Int64(at.x), y: Int64(at.y))
        let built = try LineBuilder.line(through: [PlanPoint(x: middle.x - across, y: middle.y + across / 2),
                                                   PlanPoint(x: middle.x, y: middle.y + across / 3),
                                                   PlanPoint(x: middle.x + across, y: middle.y + across / 2)], in: world)
        let scene = Map3DScene(world: built, focus: (at.x, at.y), railways: try XCTUnwrap(Map3DRealTrainsTests.railways))
        return (scene, Map3DScene.Builder(originX: scene.originX, originY: scene.originY, region: scene.region, world: built), frame)
    }

    /// The file as the app bundles it, read against the tracks: every
    /// assigned train of the site's, and the site's station names.
    func testTheFileReads() throws {
        let dispatch = try Self.dispatch()
        XCTAssertEqual(dispatch.plans.count, 1_286)
        XCTAssertEqual(Set(dispatch.plans.map(\.system)), ["tra_sched", "thsr_sched", "afr_sched"])
        XCTAssertEqual(dispatch.paths.count, 1_363)
        XCTAssertEqual(RealRailDispatch.key("臺北"), "台北")
        XCTAssertEqual(RealRailDispatch.key("左營(舊城)"), "左營")
        XCTAssertEqual(RealRailDispatch.key("新竹 （竹北）"), "新竹")
        XCTAssertEqual(RealRailDispatch.key("臺東-環島"), "台東")
        // Out of shape: a plan with a path short, a way the tracks lack.
        let tracks = try XCTUnwrap(Map3DRealTrainsTests.railways?.tracks)
        let way = try XCTUnwrap(tracks.tracks.first?.way)
        XCTAssertThrowsError(try RealRailDispatch(data: Data(#"{"systems":["tra_sched"],"stations":["a","b"],"paths":[["\#(way)",0,1]],"plans":[{"s":0,"n":"1","k":[0,1],"t":[0,1],"q":[1,1],"p":[]}]}"#.utf8), tracks: tracks))
        XCTAssertThrowsError(try RealRailDispatch(data: Data(#"{"systems":["tra_sched"],"stations":["a","b"],"paths":[["0",0,1]],"plans":[]}"#.utf8), tracks: tracks))
        XCTAssertNoThrow(try RealRailDispatch(data: Data(#"{"systems":["tra_sched"],"stations":["a","b"],"paths":[["\#(way)",0,1]],"plans":[{"s":0,"n":"1","k":[0,1],"t":[0,1],"q":[1,1],"p":[0]}]}"#.utf8), tracks: tracks))
    }

    /// Nearly every train of the game's week of Taiwan Railway trains and
    /// its day of High Speed Rail trains is bound: its own plan, or
    /// another's over the same stations; a station the site's plans do not
    /// have (平鎮, opened since) left out, as `plan-binding.js` does.
    func testNearlyEveryTrainIsBound() throws {
        let dispatch = try Self.dispatch()
        let operations = try XCTUnwrap(Map3DRealTrainsTests.railways?.operations)
        let week = try XCTUnwrap(operations.weekSchedule(forSystem: "tra"))
        let tra = week.trains.filter { train in
            dispatch.legs(system: "tra_sched", number: train.number, stops: train.stops.map { ($0.name, $0.stops) },
                          first: train.stops[0].departure, last: train.stops[train.stops.count - 1].arrival) != nil
        }
        XCTAssertGreaterThan(Double(tra.count), Double(week.trains.count) * 0.99, "\(tra.count) of \(week.trains.count)")
        let day = try XCTUnwrap(operations.schedule(forSystem: "thsr"))
        let thsr = day.trains.filter { train in
            dispatch.legs(system: "thsr_sched", number: train.number, stops: train.stops.map { ($0.name, $0.stops) },
                          first: train.stops[0].departureSecond, last: train.stops[train.stops.count - 1].arrivalSecond) != nil
        }
        XCTAssertGreaterThan(Double(thsr.count), Double(day.trains.count) * 0.95, "\(thsr.count) of \(day.trains.count)")
    }

    /// At Taipei Station the High Speed Rail's trains toward Nangang stop
    /// at more than one of its four tracks, as the site assigns them; the
    /// side rule put them all on one.
    func testTheHighSpeedTrainsAtTaipeiTakeTheirTracks() throws {
        let (scene, _, _) = try scene(latitude: 25.0478, longitude: 121.5170)
        let real = try XCTUnwrap(scene.realTrains)
        let line = try XCTUnwrap(real.traffic.lines.firstIndex { $0.system == "thsr" })
        let taipei = try XCTUnwrap(real.traffic.lines[line].line.stations.firstIndex { RealRailDispatch.key($0.name) == "台北" })
        let km = real.traffic.lines[line].stationKm[taipei]
        var places: [Map3DPoint] = []
        for legs in real.legs[line].values {
            guard let leg = legs.first(where: { $0.km.upperBound == km }) else { continue }
            for track in real.tracks[line] {
                guard let lo = track.km.lastIndex(where: { $0 <= km }), let point = track.routes[leg.path]?.at(lo)?.point else { continue }
                places.append(point)
                break
            }
        }
        XCTAssertGreaterThan(places.count, 20)
        var tracks: [Map3DPoint] = []
        for place in places where !tracks.contains(where: { Map3DRealTrains.Laid.across($0, place) < 2.5 }) { tracks.append(place) }
        XCTAssertGreaterThanOrEqual(tracks.count, 2, "\(tracks)")
    }

    /// Round Taichung Station, through the day, each bound train's cars on
    /// its assigned path where the scene has it, and every car within
    /// ``Map3DRealTrains/laneReach`` of the place the 2D map draws it at
    /// (the line's shape at the same km): the same train, the same place.
    func testA3DTrainIsWhereThe2DMapHasIt() throws {
        let (scene, builder, frame) = try scene(latitude: 24.1369, longitude: 120.6850)
        let real = try XCTUnwrap(scene.realTrains)
        var bound = 0, routed = 0, checked = 0
        for (index, line) in real.traffic.lines.enumerated() where line.system == "tra" || line.system == "thsr" {
            for hour in stride(from: 6.0, through: 22, by: 0.5) {
                for place in real.traffic.places(of: line, at: hour * 3_600, on: weekday, dayBefore: tuesday) {
                    let key = place.key.hasPrefix("-") ? String(place.key.dropFirst()) : place.key
                    guard let legs = real.legs[index][key] else { continue }
                    let way = RealTrainRun.way(from: place.km, to: place.towardKm, ringKm: nil) >= 0 ? 1.0 : -1.0
                    for car in 0..<4 {
                        let km = place.km - way * Double(car) * Map3DRealTrains.carPitch
                        guard let route = legs.first(where: { $0.km.contains(km) })?.path else { continue }
                        for track in real.tracks[index] {
                            guard let lo = track.km.lastIndex(where: { $0 <= km }), track.km.last.map({ km <= $0 }) ?? false else { continue }
                            // Where the line has a running track to fall back on.
                            guard track.shown[0][lo] || track.shown[1][lo] else { break }
                            bound += 1
                            if track.routes[route]?.at(lo) != nil { routed += 1 }
                            guard let point = track.point(atKm: km, way: way, route: route) else { break }
                            let coordinate = line.shape.coordinate(atKm: km)
                            let at = frame.worldPosition(latitude: coordinate.latitude, longitude: coordinate.longitude)
                            let drawn = builder.point(x: at.x, y: at.y, height: 0)
                            XCTAssertLessThan(Map3DRealTrains.Laid.across(point, drawn), Map3DRealTrains.laneReach, "\(line.line.id) \(place.key) \(km)")
                            checked += 1
                            break
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 200)
        XCTAssertGreaterThan(Double(routed), Double(bound) * 0.9, "\(routed) of \(bound) on their paths")
    }

    /// A siding, crossover or yard track only a dispatched train runs on:
    /// a train with no assignment of its own (a metro's) keeps to the
    /// running tracks.
    func testOnlyAnAssignedTrainTakesASiding() throws {
        let tracks = try XCTUnwrap(Map3DRealTrainsTests.railways?.tracks)
        let dispatch = try Self.dispatch()
        let used = Set(dispatch.paths.joined().map(\.track))
        XCTAssertTrue(tracks.tracks.indices.filter { tracks.tracks[$0].isService }.allSatisfy(used.contains))
        let (scene, _, _) = try scene(latitude: 24.1369, longitude: 120.6850)
        _ = scene
        var builder = Map3DScene.Builder(originX: scene.originX, originY: scene.originY, region: scene.region, world: GameWorld.newGame())
        let frame = try XCTUnwrap(RealWorldFrame(world: GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 24.1369, longitudeDegrees: 120.6850)))))
        let laid = builder.realTracks(tracks, systems: ["tra_sched"], frame: frame, clearOf: Map3DRealTrains.PlayerTrack([]))
        let segments = try XCTUnwrap(laid.segments["tra_sched"]).values.joined()
        XCTAssertTrue(segments.contains { $0.isService })
    }
}
