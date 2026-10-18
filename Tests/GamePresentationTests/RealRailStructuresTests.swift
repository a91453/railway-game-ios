import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Where the real TRA lines are on bridges and in tunnels (decision 279):
/// `rail_structures.json` as the app bundles it, the stretches of a path it
/// carries, and the heights ``TrackRise`` lays along them.
final class RealRailStructuresTests: XCTestCase {
    private static func bundledFile(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)"))
    }

    private let metre = RealWorldDemo.metre

    // MARK: - The file

    func testTheBundledFileReads() throws {
        let structures = try RealRailStructures(data: Self.bundledFile("rail_structures.json")).structures
        XCTAssertGreaterThan(structures.count, 1_800)
        XCTAssertEqual(Set(structures.map(\.kind)), [.bridge, .tunnel])
        // The TRA's, the High Speed Rail's and the Alishan Forest Railway's,
        // each with both kinds.
        XCTAssertEqual(Set(structures.map(\.system)), ["tra_sched", "thsr_sched", "afr_sched"])
        for system in ["tra_sched", "thsr_sched", "afr_sched"] {
            XCTAssertEqual(Set(structures.filter { $0.system == system }.map(\.kind)), [.bridge, .tunnel], system)
        }
        XCTAssertTrue(structures.allSatisfy { $0.points.count >= 2 })
        // All in and round Taiwan.
        XCTAssertTrue(structures.allSatisfy { $0.points.allSatisfy { (21.8...25.4).contains($0.latitude) && (119.2...122.1).contains($0.longitude) } })
    }

    func testAFileOutOfShapeThrows() {
        func read(_ json: String) throws -> RealRailStructures { try RealRailStructures(data: Data(json.utf8)) }
        XCTAssertNoThrow(try read(#"{"structures":[{"system":"tra_sched","kind":"bridge","points":[[121.5,25.0],[121.6,25.1]]}]}"#))
        XCTAssertThrowsError(try read(#"{"structures":[{"system":"tra_sched","kind":"bridge","points":[[121.5,25.0]]}]}"#), "one point")
        XCTAssertThrowsError(try read(#"{"structures":[{"system":"tra_sched","kind":"bridge","points":[[121.5,95.0],[121.6,25.1]]}]}"#), "off the Earth")
        XCTAssertThrowsError(try read(#"{"structures":[{"system":"tra_sched","kind":"bridge","points":[[121.5],[121.6,25.1]]}]}"#), "not a point")
        XCTAssertThrowsError(try read(#"{"structures":[{"system":"tra_sched","kind":"culvert","points":[[121.5,25.0],[121.6,25.1]]}]}"#), "an unknown kind")
        XCTAssertThrowsError(try read(#"{"structures":[{"kind":"bridge","points":[[121.5,25.0],[121.6,25.1]]}]}"#), "no system")
    }

    // MARK: - Along a path

    /// A path due east from the demo's anchor, and the structures beside
    /// it: those on it and on the other track 4 m off become one stretch,
    /// one 50 m off is another line's, one that leaves it is not its, and
    /// one of another system on it is that system's.
    func testTheStretchesAlongAPath() throws {
        let frame = RealWorldFrame(anchor: RealWorldDemo.anchor, bounds: GameWorld.newGameBounds)
        let latitude = RealWorldDemo.anchor.latitudeDegrees, longitude = RealWorldDemo.anchor.longitudeDegrees
        // About a metre of longitude, and of latitude, here.
        let east = 1 / (111_320 * cos(latitude * .pi / 180)), north = 1 / 110_574.0
        func point(_ x: Double, _ y: Double = 0) -> [Double] { [longitude + x * east, latitude + y * north] }
        let path = WorldPath([0.0, 3_000].map { x in
            WorldVector(frame.worldPosition(latitude: latitude, longitude: longitude + x * east))
        })
        let json = try String(
            data: JSONSerialization.data(withJSONObject: ["structures": [
                ["system": "tra_sched", "kind": "bridge", "points": [point(500), point(800)]],
                ["system": "tra_sched", "kind": "bridge", "points": [point(700, 4), point(1_200, 4)]],
                ["system": "tra_sched", "kind": "tunnel", "points": [point(2_000), point(2_400)]],
                ["system": "tra_sched", "kind": "bridge", "points": [point(1_500, 50), point(1_900, 50)]],
                ["system": "tra_sched", "kind": "tunnel", "points": [point(2_600), point(2_900, 200)]],
                ["system": "thsr_sched", "kind": "bridge", "points": [point(1_500), point(1_900)]],
            ]]),
            encoding: .utf8
        )
        let structures = try RealRailStructures(data: Data(XCTUnwrap(json).utf8))
        let stretches = structures.stretches(along: path, frame: frame, system: "tra_sched")
        XCTAssertEqual(stretches.map(\.kind), [.bridge, .tunnel])
        let other = structures.stretches(along: path, frame: frame, system: "thsr_sched")
        XCTAssertEqual(other.map(\.kind), [.bridge])
        let ranges = stretches.map { ($0.range.lowerBound / metre, $0.range.upperBound / metre) }
        XCTAssertEqual(ranges[0].0, 500, accuracy: 2)
        XCTAssertEqual(ranges[0].1, 1_200, accuracy: 2)
        XCTAssertEqual(ranges[1].0, 2_000, accuracy: 2)
        XCTAssertEqual(ranges[1].1, 2_400, accuracy: 2)
    }

    /// The Yilan Line's two long viaducts (the reference's data, from
    /// OpenStreetMap and the National Land Surveying and Mapping Center):
    /// south of Yilan towards Erjie, and through Dongshan.
    func testTheYilanLineViaducts() throws {
        let railways = try RealRailways(
            lines: Self.bundledFile("track_lines.geojson"), stations: Self.bundledFile("track_stations.geojson"),
            names: Self.bundledFile("station_names.json"), structures: RealRailStructures(data: Self.bundledFile("rail_structures.json"))
        )
        let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)
        let line = try XCTUnwrap(railways.lines.first { $0.name.hasPrefix("宜蘭線") })
        let path = WorldPath(line.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) })
        func along(_ name: String) throws -> Double {
            let station = try XCTUnwrap(railways.stations.first { $0.id == "tra_sched|\(name)" })
            return path.project(WorldVector(frame.worldPosition(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude)))
        }
        let stretches = try XCTUnwrap(railways.structures).stretches(along: path, frame: frame, system: "tra_sched")
        let (yilan, erjie, dongshan) = (try along("宜蘭"), try along("二結"), try along("冬山"))
        let between = min(yilan, erjie)...max(yilan, erjie)
        XCTAssertTrue(stretches.contains { $0.kind == .bridge && $0.range.upperBound - $0.range.lowerBound > 3_500 * metre && between.contains($0.range.lowerBound) && between.contains($0.range.upperBound) }, "south of Yilan")
        XCTAssertTrue(stretches.contains { $0.kind == .bridge && $0.range.upperBound - $0.range.lowerBound > 3_000 * metre && $0.range.contains(dongshan) }, "through Dongshan")
        XCTAssertFalse(stretches.contains { $0.range.contains(yilan) || $0.range.contains(erjie) }, "Yilan and Erjie stand on the ground")
    }

    // MARK: - The heights

    /// A straight path 3 km long over flat ground.
    private func flat() -> WorldPath {
        WorldPath([WorldVector(x: 0, y: 0), WorldVector(x: 3_000 * metre, y: 0)])
    }

    /// A viaduct and a tunnel as far apart as the grade needs: 23 m of
    /// height takes over 920 m.
    func testTheTrackKeepsToTheRealStructures() throws {
        let rise = try XCTUnwrap(TrackRise(
            path: flat(), ground: { _ in 0 }, water: { _ in false }, levels: [],
            carried: [
                TrackRise.Carried(range: 600 * metre...1_200 * metre, kind: .bridge),
                TrackRise.Carried(range: 2_200 * metre...2_900 * metre, kind: .tunnel),
            ]
        ))
        for distance in stride(from: 664.0, through: 1_136, by: 8) {
            XCTAssertGreaterThanOrEqual(rise.height(at: distance * metre), TrackRise.carriedHeight - 1e-6, "on the viaduct at \(distance) m")
        }
        for distance in stride(from: 2_264.0, through: 2_836, by: 8) {
            XCTAssertLessThanOrEqual(rise.height(at: distance * metre), -TrackRise.carriedDepth + 1e-6, "in the tunnel at \(distance) m")
        }
        for distance in [0.0, 300, 1_300, 1_700, 2_100, 3_000] {
            let height = rise.height(at: distance * metre)
            XCTAssertTrue((TrackRise.surfaceBand.low - 1e-6...TrackRise.surfaceBand.high + 1e-6).contains(height), "on the ground at \(distance) m: \(height / metre) m")
        }
        // Without the structures, flat on the flat ground.
        let plain = try XCTUnwrap(TrackRise(path: flat(), ground: { _ in 0 }, water: { _ in false }, levels: []))
        XCTAssertTrue(plain.heights.allSatisfy { $0 == 0 })
    }

    /// A station level on the ground in the middle of a viaduct (the
    /// game's ground is coarser than the real line's): the viaduct's
    /// pieces that no grade reaches from it are let go, the rest kept.
    func testWhatNoGradeReachesIsLetGo() throws {
        let rise = try XCTUnwrap(TrackRise(
            path: flat(), ground: { _ in 0 }, water: { _ in false },
            levels: [TrackRise.Level(1_400 * metre...1_500 * metre, at: 0)],
            carried: [TrackRise.Carried(range: 200 * metre...2_800 * metre, kind: .bridge)]
        ))
        XCTAssertEqual(rise.height(at: 1_450 * metre), 0, "the station where it asks")
        XCTAssertGreaterThanOrEqual(rise.height(at: 400 * metre), TrackRise.carriedHeight - 1e-6, "the viaduct away from it")
        XCTAssertGreaterThanOrEqual(rise.height(at: 2_600 * metre), TrackRise.carriedHeight - 1e-6, "the viaduct away from it")
    }
}
