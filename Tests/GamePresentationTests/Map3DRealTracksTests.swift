import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 402: the 3D map's real lines on their real tracks, single or
/// double as they are, at the heights the owner's site shows them.
final class Map3DRealTracksTests: XCTestCase {
    static let tracks: RealRailTracks? = try? RealRailTracks(
        data: Data(contentsOf: Map3DRealTrainsTests.resources.appendingPathComponent("RealRailways/rail_tracks.json")))

    private let weekday = RealServiceDay(weekday: 3)
    private let tuesday = RealServiceDay(weekday: 2)

    /// A real-world game round (`latitude`, `longitude`) with a line 10 km
    /// across (``Map3DRealTrainsTests``'s), its scene there with the real
    /// railways, and a builder of the same ground.
    private func scene(latitude: Double, longitude: Double) throws -> (scene: Map3DScene, builder: Map3DScene.Builder) {
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let at = frame.worldPosition(latitude: latitude, longitude: longitude)
        let across = Int64(5_000 * WorldCoordinate.unitsPerMetre)
        let middle = (x: Int64(at.x), y: Int64(at.y))
        let built = try LineBuilder.line(through: [PlanPoint(x: middle.x - across, y: middle.y + across / 2),
                                                   PlanPoint(x: middle.x, y: middle.y + across / 3),
                                                   PlanPoint(x: middle.x + across, y: middle.y + across / 2)], in: world)
        let scene = Map3DScene(world: built, focus: (at.x, at.y), railways: try XCTUnwrap(Map3DRealTrainsTests.railways))
        return (scene, Map3DScene.Builder(originX: scene.originX, originY: scene.originY, region: scene.region, world: built))
    }

    /// The samples of `system`'s line `id` in `scene` within `metres` of
    /// the scene's origin (seen from above) where a car shows both ways:
    /// the rails each way.
    private func samples(_ scene: Map3DScene, _ system: String, _ id: String, within metres: Float) throws -> [(Map3DPoint, Map3DPoint)] {
        let real = try XCTUnwrap(scene.realTrains)
        let line = try XCTUnwrap(real.traffic.lines.firstIndex { $0.system == system && $0.line.id == id }, "\(system) \(id)")
        return real.tracks[line].flatMap { track in
            track.km.indices.compactMap { index in
                let a = track.lanes[0][index], b = track.lanes[1][index]
                guard track.shown[0][index], track.shown[1][index], a.x * a.x + a.z * a.z < metres * metres else { return nil }
                return (a, b)
            }
        }
    }

    private static func across(_ a: Map3DPoint, _ b: Map3DPoint) -> Float { ((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)).squareRoot() }

    /// The file as the app bundles it: every running track of the ten
    /// systems, read by the loader.
    func testTheFileReads() throws {
        let tracks = try XCTUnwrap(Self.tracks)
        XCTAssertEqual(tracks.tracks.count, 4_229)
        XCTAssertEqual(tracks.systems, ["tra_sched", "thsr_sched", "afr_sched", "mrt", "tymc", "ntdlrt", "ntalrt", "sanying", "krtc", "tmrt"])
        XCTAssertTrue(tracks.tracks.allSatisfy { $0.points.count >= 2 && $0.points.count == $0.heights.count })
        XCTAssertTrue(tracks.tracks.allSatisfy { track in track.points.allSatisfy { (21.8...25.4).contains($0.latitude) && (119.8...122.1).contains($0.longitude) } })
        XCTAssertEqual(Map3DRealTrainsTests.railways?.tracks, tracks)
        // Out of shape: points not in threes, a system it does not list.
        XCTAssertThrowsError(try RealRailTracks(data: Data(#"{"systems":["tra_sched"],"ways":[{"system":0,"kind":"s","points":[1,2,3,4]}]}"#.utf8)))
        XCTAssertThrowsError(try RealRailTracks(data: Data(#"{"systems":["tra_sched"],"ways":[{"system":1,"kind":"s","points":[1,2,3,4,5,6]}]}"#.utf8)))
    }

    /// Where two systems' lines cross, the one OpenStreetMap's `layer`
    /// puts above is higher (the site's `data/rail_crossing_levels.json`,
    /// its crossings of two systems).
    func testCrossingsAreTheRightWayUp() throws {
        let tracks = try XCTUnwrap(Self.tracks)
        let crossings: [(latitude: Double, longitude: Double, above: String, below: String)] = [
            (24.182086, 120.702288, "tmrt", "tra_sched"), // Taichung metro over the TRA Mountain Line
            (24.951978, 121.351441, "sanying", "tra_sched"), // the Sanying Line over the TRA
            (25.047662, 121.509945, "tra_sched", "mrt"), // the TRA over the Songshan–Xindian Line
            (23.328529, 120.336978, "thsr_sched", "tra_sched"), // the High Speed Rail over the TRA
            (25.047485, 121.509933, "thsr_sched", "mrt"),
            (25.036113, 121.506376, "mrt", "thsr_sched"), // the Bannan Line over the High Speed Rail
            (25.014785, 121.465227, "mrt", "tra_sched"), // the Circular Line over the TRA
        ]
        func height(of system: String, at latitude: Double, _ longitude: Double) -> Double? {
            let metresPerDegree = 111_320.0, east = cos(latitude * .pi / 180)
            var best: (distance: Double, height: Double)?
            for track in tracks.tracks where track.system == system {
                let flat = track.points.map { ((($0.longitude - longitude) * metresPerDegree * east), ($0.latitude - latitude) * metresPerDegree) }
                for index in flat.indices.dropFirst() {
                    let a = flat[index - 1], b = flat[index], dx = b.0 - a.0, dy = b.1 - a.1
                    let squared = dx * dx + dy * dy
                    let t = squared > 0 ? max(0, min(1, -(a.0 * dx + a.1 * dy) / squared)) : 0
                    let distance = ((a.0 + dx * t) * (a.0 + dx * t) + (a.1 + dy * t) * (a.1 + dy * t)).squareRoot()
                    if distance < 60, distance < (best?.distance ?? .infinity) {
                        best = (distance, track.heights[index - 1] + (track.heights[index] - track.heights[index - 1]) * t)
                    }
                }
            }
            return best?.height
        }
        for crossing in crossings {
            let above = try XCTUnwrap(height(of: crossing.above, at: crossing.latitude, crossing.longitude), "\(crossing)")
            let below = try XCTUnwrap(height(of: crossing.below, at: crossing.latitude, crossing.longitude), "\(crossing)")
            XCTAssertGreaterThan(above, below + 3, "\(crossing)")
        }
    }

    /// Round Taichung Station, the TRA's double track on its viaduct: two
    /// tracks 4 m or so apart, each way's trains on the left one, 8 m over
    /// the ground as the site's profile has it.
    func testADoubleLineIsTwoTracks() throws {
        var (scene, builder) = try scene(latitude: 24.1369, longitude: 120.6850)
        let pairs = try samples(scene, "tra", try taichungLine(scene), within: 600)
        XCTAssertGreaterThan(pairs.count, 100)
        let apart = pairs.filter { (3...6).contains(Self.across($0.0, $0.1)) }
        XCTAssertGreaterThan(Double(apart.count), Double(pairs.count) * 0.9, "two tracks")
        // Going up the km on the left one: the other way's is on its right
        // (the scene's z is south).
        var left = 0
        for (index, pair) in apart.enumerated().dropFirst() {
            let previous = apart[index - 1].0, step = pair.0 - previous
            guard step.length > 1, step.length < 20 else { continue }
            let toOther = pair.1 - pair.0
            if -(step.x * toOther.z - step.z * toOther.x) < 0 { left += 1 } else { left -= 1 }
        }
        XCTAssertGreaterThan(left, apart.count / 2, "left-hand running")
        // On the viaduct, as high as the profile puts it.
        let lifts = pairs.filter { $0.0.x * $0.0.x + $0.0.z * $0.0.z < 200 * 200 }.map { $0.0.y - Map3DScene.railLift - builder.drawnGround(x: $0.0.x, z: $0.0.z) }
        XCTAssertFalse(lifts.isEmpty)
        XCTAssertTrue(lifts.allSatisfy { $0 > 6 && $0 < 10 }, "\(lifts)")
    }

    /// The TRA line through Taichung Station.
    private func taichungLine(_ scene: Map3DScene) throws -> String {
        let real = try XCTUnwrap(scene.realTrains)
        return try XCTUnwrap(real.traffic.lines.first { $0.system == "tra" && $0.line.name.contains("山線") }?.line.id
            ?? real.traffic.lines.first { $0.system == "tra" }?.line.id)
    }

    /// The Pingxi Line through Shifen is single track: both ways' trains on
    /// the one.
    func testASingleLineIsOneTrack() throws {
        let (scene, _) = try scene(latitude: 25.0473, longitude: 121.7556)
        let pairs = try samples(scene, "tra", "PINGXI", within: 2_000)
        XCTAssertGreaterThan(pairs.count, 100)
        XCTAssertGreaterThan(Double(pairs.filter { Self.across($0.0, $0.1) < 0.5 }.count), Double(pairs.count) * 0.8)
    }

    /// The Wenhu line's trains keep to the right, as the metros' do.
    func testTheMetrosKeepRight() throws {
        let (scene, _) = try scene(latitude: 25.0521, longitude: 121.5440)
        let pairs = try samples(scene, "trtc", "BR", within: 2_000).filter { (2...8).contains(Self.across($0.0, $0.1)) }
        XCTAssertGreaterThan(pairs.count, 50)
        var right = 0
        for (index, pair) in pairs.enumerated().dropFirst() {
            let step = pair.0 - pairs[index - 1].0
            guard step.length > 1, step.length < 20 else { continue }
            let toOther = pair.1 - pair.0
            if -(step.x * toOther.z - step.z * toOther.x) > 0 { right += 1 } else { right -= 1 }
        }
        XCTAssertGreaterThan(right, pairs.count / 2)
        // And a train drawn on it.
        var frame = Map3DTrains.Frame()
        try XCTUnwrap(scene.realTrains).add(to: &frame, second: 8 * 3_600, day: weekday, dayBefore: tuesday, models: nil, eye: nil)
        XCTAssertFalse(frame.boxes.vertices.isEmpty)
    }

    /// Only the real track the player's lies on is left out: the other of
    /// a double line, 4.2 m beside, is laid, and a train shows on it.
    func testOnlyTheTrackUnderThePlayersIsLeftOut() throws {
        let latitude = 25.0478, longitude = 121.5170
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let origin = frame.worldPosition(latitude: latitude, longitude: longitude)
        var builder = Map3DScene.Builder(originX: origin.x, originY: origin.y,
                                         region: WorldRegion(minX: origin.x - 2_000 * metre, minY: origin.y - 2_000 * metre,
                                                             maxX: origin.x + 2_000 * metre, maxY: origin.y + 2_000 * metre),
                                         world: world)
        // Two tracks 400 m long east to west, 4.2 m apart (38 millionths
        // of a degree of latitude), on the ground.
        let (lon, lat) = (Int(longitude * 1e6) - 2_000, Int(latitude * 1e6))
        let json = #"{"systems":["tra_sched"],"ways":[{"system":0,"kind":"s","points":[\#(lon),\#(lat),0,4000,0,0]},"#
            + #"{"system":0,"kind":"s","points":[\#(lon),\#(lat - 38),0,4000,0,0]}]}"#
        let tracks = try RealRailTracks(data: Data(json.utf8))
        // The player's track on the first.
        let first = tracks.tracks[0].points.map { coordinate in
            let at = frame.worldPosition(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return builder.point(x: at.x, y: at.y, height: 0)
        }
        let laid = builder.realTracks(tracks, systems: ["tra_sched"], frame: frame, clearOf: Map3DRealTrains.PlayerTrack([first]))
        let segments = try XCTUnwrap(laid.segments["tra_sched"]).values.flatMap { $0 }
        XCTAssertTrue(segments.filter { $0.track == 0 }.allSatisfy { !$0.shown }, "under the player's")
        XCTAssertFalse(segments.filter { $0.track == 1 }.isEmpty)
        XCTAssertTrue(segments.filter { $0.track == 1 }.allSatisfy(\.shown), "beside it")
        XCTAssertFalse(builder.meshes.isEmpty)
        // A train going east (along +x) keeps left: on the first track,
        // north of the second (the scene's z is south).
        let middle = Map3DPoint(0, 0, 2)
        let lanes = try XCTUnwrap(laid.lanes(at: middle, along: Map3DPoint(1, 0, 0), system: "tra_sched"))
        XCTAssertLessThan(lanes[0].point.z, lanes[1].point.z, "east on the north track")
        XCTAssertFalse(lanes[0].shown, "the player's")
        XCTAssertTrue(lanes[1].shown)
    }

    /// How far the TRA demo's double track (decision 240) lies from the
    /// real Yilan Line's tracks: the real tracks within 30 m of it, by
    /// how far from it, and how many of those are left out
    /// (``Map3DRealTrains/overlap``). Only on request:
    /// `MAP3D_FRAME_REPORT=1`.
    func testTheTRADemoBesideTheRealTracks() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let world = try TRADemoTests.opened.get()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: 0, minY: 0, maxX: 1, maxY: 1), world: world)
        let snapshot = world.railwaySnapshot()
        let player = Map3DRealTrains.PlayerTrack(snapshot.edges.map { $0.geometry.points.map(builder.point) })
        var counts = [Int](repeating: 0, count: 6) // < 1, 1-2, 2-3.4, 3.4-8, 8-16, 16-30 m
        let bounds: [Float] = [1, 2, Map3DRealTrains.overlap, 8, 16, 30]
        for track in try XCTUnwrap(Self.tracks).tracks where track.system == "tra_sched" && track.kind != .tunnel {
            for coordinate in track.points {
                let at = frame.worldPosition(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let p = builder.point(x: at.x, y: at.y, height: 0)
                guard let band = bounds.firstIndex(where: { player.isNear(p, within: $0) }) else { continue }
                counts[band] += 1
            }
        }
        print("TRA demo: real TRA track points within 30 m of the player's, by distance (< 1, 1-2, 2-\(Map3DRealTrains.overlap), -8, -16, -30 m): \(counts)")
    }
}
