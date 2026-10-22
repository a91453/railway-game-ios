import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 339: the real timetables' trains on the 3D map, on real track
/// of their own.
final class Map3DRealTrainsTests: XCTestCase {
    static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp/Resources")

    static let railways: RealRailways? = RealRailways.load { name, ext in
        try Data(contentsOf: resources.appendingPathComponent("RealRailways/\(name).\(ext)"))
    }.railways

    private let weekday = RealServiceDay(weekday: 3)
    private let tuesday = RealServiceDay(weekday: 2)

    /// A real-world game round (`latitude`, `longitude`), and its scene
    /// there with the real railways.
    private func scene(latitude: Double, longitude: Double) throws -> (GameWorld, Map3DScene) {
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let at = frame.worldPosition(latitude: latitude, longitude: longitude)
        // A line 10 km across, so the scene reaches its widest
        // (``Map3DScene/reach``), as a game's built network does.
        let across = Int64(5_000 * WorldCoordinate.unitsPerMetre)
        let middle = (x: Int64(at.x), y: Int64(at.y))
        let built = try LineBuilder.line(through: [PlanPoint(x: middle.x - across, y: middle.y + across / 2),
                                                   PlanPoint(x: middle.x, y: middle.y + across / 3),
                                                   PlanPoint(x: middle.x + across, y: middle.y + across / 2)], in: world)
        return (built, Map3DScene(world: built, focus: (at.x, at.y), railways: try XCTUnwrap(Self.railways)))
    }

    private func line(_ system: String, _ id: String) throws -> RealOperationLine {
        try XCTUnwrap(Self.railways?.operations?.system(id: system)?.lines.first { $0.id == id }, "\(system) \(id)")
    }

    /// Each line's trains are its own stock, as many cars as they have.
    func testEachLineHasItsStock() throws {
        func formation(_ system: String, _ id: String) throws -> Map3DRealTrains.Formation {
            Map3DRealTrains.formation(system: system, line: try line(system, id))
        }
        XCTAssertEqual(try formation("thsr", "THSR"), .init(key: "highSpeed", cars: 12))
        XCTAssertEqual(try formation("tra", "縱貫線北段"), .init(key: "emu800", cars: 8))
        XCTAssertEqual(try formation("tra", "PINGXI"), .init(key: "dieselRailcar", cars: 3))
        XCTAssertEqual(try formation("trtc", "BL"), .init(key: "metroC381", cars: 6))
        XCTAssertEqual(try formation("trtc", "BR"), .init(key: "wenhu", cars: 4))
        XCTAssertEqual(try formation("krtc", "KR"), .init(key: "metroC381", cars: 3))
        // Decision 331: the light rail as the green tram.
        for (system, id) in [("ntdlrt", "V"), ("ntalrt", "K"), ("krtc", "C")] {
            XCTAssertEqual(try formation(system, id).key, "greenTram", id)
        }
        // Every set but the forest railway's is one the game has.
        for system in try XCTUnwrap(Self.railways?.operations).orderedSystems where system.id != "afr" {
            for line in system.lines {
                let key = Map3DRealTrains.formation(system: system.id, line: line).key
                XCTAssertNotNil(Map3DModelPack.standard.models(forType: key), "\(system.id) \(line.id)")
            }
        }
    }

    /// A stretch's rails at a place along the line, but where a car does
    /// not show.
    func testATracksRails() {
        let track = Map3DRealTrains.Track(km: [0, 0.01, 0.02, 0.03], points: (0..<4).map { Map3DPoint(Float($0) * 10, 1, 0) },
                                          shown: [true, true, false, false])
        XCTAssertEqual(track.point(atKm: 0.005), Map3DPoint(5, 1, 0))
        XCTAssertNil(track.point(atKm: 0.015))
        XCTAssertNil(track.point(atKm: 0.04))
        XCTAssertNil(track.point(atKm: -0.001))
    }

    /// Laid along the line, but in its tunnel and beside the player's
    /// track; cars show only where it is laid.
    func testTheRealTrackKeepsClearOfThePlayers() throws {
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let origin = frame.worldPosition(latitude: 25.0478, longitude: 121.5170)
        var builder = Map3DScene.Builder(originX: origin.x, originY: origin.y,
                                         region: WorldRegion(minX: origin.x - 3_000 * metre, minY: origin.y - 3_000 * metre,
                                                             maxX: origin.x + 3_000 * metre, maxY: origin.y + 3_000 * metre),
                                         world: world)
        // The player's track across the real line at x 0.
        builder.trackLines = [(stride(from: Float(-200), through: 200, by: 4).map { Map3DPoint(0, Map3DScene.railLift, $0) }, .surface)]
        let player = Map3DRealTrains.PlayerTrack(builder.trackLines.map(\.points))
        // The real line along x, 2 km, its km from 0.
        let stretch = stride(from: -1_000.0, through: 1_000, by: 50).map { x in
            (point: WorldVector(x: origin.x + x * metre, y: origin.y), km: (x + 1_000) / 1_000)
        }
        let track = try XCTUnwrap(builder.realTrack(stretch, system: "tra_sched", structures: nil, frame: frame, clearOf: player))
        XCTAssertEqual(try XCTUnwrap(track.km.first), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(track.km.last), 2, accuracy: 1e-6)
        XCTAssertEqual(track.points.count, 251, "every 8 m")
        for (point, shown) in zip(track.points, track.shown) {
            XCTAssertEqual(shown, abs(point.x) >= Map3DRealTrains.playerClearance, "\(point.x)")
        }
        XCTAssertNotNil(track.point(atKm: 0.5))
        XCTAssertNil(track.point(atKm: 1))
        XCTAssertFalse(builder.meshes.isEmpty, "laid")
        XCTAssertFalse(builder.realTrackCells.isEmpty)
        let laid = builder.meshes.values.flatMap(\.vertices)
        XCTAssertFalse(laid.contains { abs($0.x) < Map3DRealTrains.playerClearance - 4 && abs($0.z) < 3 }, "none over the player's")
    }

    /// In Taipei: the High Speed Rail and Taiwan Railway underground, so
    /// none of theirs drawn; the elevated Wenhu line's are.
    func testTaipeisTrains() throws {
        let (_, scene) = try scene(latitude: 25.0478, longitude: 121.5170)
        let real = try XCTUnwrap(scene.realTrains)
        let lines = real.traffic.lines.map { "\($0.system) \($0.line.id)" }
        XCTAssertTrue(lines.contains("trtc BR"))
        XCTAssertTrue(lines.contains("thsr THSR"))
        // From afar, boxes; close by, models.
        var far = Map3DTrains.Frame()
        real.add(to: &far, second: 8 * 3_600, day: weekday, dayBefore: tuesday, models: .standard, eye: nil)
        XCTAssertTrue(far.instances.isEmpty)
        XCTAssertFalse(far.boxes.vertices.isEmpty)
        XCTAssertFalse(far.shadows.vertices.isEmpty)
        XCTAssertTrue(far.heads.isEmpty, "no label, follow or ring")
        let car = try XCTUnwrap(far.boxes.vertices.first)
        var near = Map3DTrains.Frame()
        real.add(to: &near, second: 8 * 3_600, day: weekday, dayBefore: tuesday, models: .standard, eye: Map3DPoint(car.x, car.y, car.z))
        XCTAssertFalse(near.instances.isEmpty)
        XCTAssertLessThan(near.boxes.vertices.count, far.boxes.vertices.count)
        // Under Taipei Main Station, nothing of the High Speed Rail's.
        let thsr = try XCTUnwrap(real.traffic.lines.firstIndex { $0.system == "thsr" })
        let taipeiKm = real.traffic.lines[thsr].stationKm[1]
        let underMain = real.tracks[thsr].flatMap { zip($0.km, $0.shown) }.filter { abs($0.0 - taipeiKm) < 1 }
        XCTAssertFalse(underMain.isEmpty)
        XCTAssertTrue(underMain.allSatisfy { !$0.1 }, "underground through Taipei")
        // The Wenhu line on its viaduct, over the ground.
        let wenhu = try XCTUnwrap(real.traffic.lines.firstIndex { $0.line.id == "BR" })
        XCTAssertGreaterThan(real.tracks[wenhu].flatMap(\.shown).filter { $0 }.count, 100)
    }

    /// Without the real railways, or off the real world, none.
    func testNoneWithoutTheRealWorld() throws {
        XCTAssertNil(Map3DScene(world: GameWorld.newGame(), railways: Self.railways).realTrains)
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        XCTAssertNil(Map3DScene(world: world).realTrains)
    }

    /// What the real trains cost (decision 339): the scene's build time and
    /// the real track's triangles, and the trains drawn at the busiest
    /// hour from close by and from far out, round Taipei, Kaohsiung and
    /// Taichung Stations. Only on request: `MAP3D_FRAME_REPORT=1`.
    func testTheCost() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let models = Map3DCityBus.pack(file: Self.resources.appendingPathComponent("Models/city-bus.m3dmodel"))
        for key in ["highSpeed", "emu800", "dieselRailcar", "metroC381", "wenhu", "greenTram"] {
            let index = try XCTUnwrap(models.modelIndex(forType: key, carIndex: 1, count: 3))
            print("\(key): \(models.models[index].triangleCount) triangles a middle car")
        }
        for (name, latitude, longitude) in [("Taipei", 25.0478, 121.5170), ("Kaohsiung", 22.6394, 120.3025), ("Taichung", 24.1369, 120.6850)] {
            let (world, scene) = try self.scene(latitude: latitude, longitude: longitude)
            let start = Date()
            let plain = Map3DScene(world: world, focus: (scene.originX, scene.originY))
            let plainTime = Date().timeIntervalSince(start)
            let built = Date()
            _ = Map3DScene(world: world, focus: (scene.originX, scene.originY), railways: try XCTUnwrap(Self.railways))
            let time = Date().timeIntervalSince(built)
            let real = try XCTUnwrap(scene.realTrains)
            let samples = real.tracks.flatMap { $0 }.flatMap(\.shown)
            print("\(name): \(real.traffic.lines.count) lines; scene built in \(String(format: "%.2f", time)) s (\(String(format: "%.2f", plainTime)) s without);"
                  + " real track \(scene.triangleCount - plain.triangleCount) triangles; \(samples.filter { $0 }.count) of \(samples.count) samples shown")
            for (view, eye) in [("close", Map3DPoint(0, 200, 0)), ("far", Map3DPoint(0, 8_000, 0))] {
                var worst = (second: 0, instances: 0, triangles: 0, boxes: 0, cost: 0.0)
                var total = 0.0, frames = 0
                for hour in stride(from: 6.0, through: 22, by: 0.25) {
                    var drawn = Map3DTrains.Frame()
                    let clock = Date()
                    real.add(to: &drawn, second: hour * 3_600, day: weekday, dayBefore: tuesday, models: models, eye: eye)
                    let cost = Date().timeIntervalSince(clock)
                    total += cost
                    frames += 1
                    let triangles = drawn.instances.reduce(0) { $0 + models.models[$1.model].triangleCount }
                    if triangles + drawn.boxes.triangleCount > worst.triangles + worst.boxes {
                        worst = (Int(hour * 3_600), drawn.instances.count, triangles, drawn.boxes.triangleCount, cost)
                    }
                }
                print("  \(view): busiest \(worst.second / 3_600):\(String(format: "%02d", worst.second % 3_600 / 60)) —"
                      + " \(worst.instances) cars as models (\(worst.triangles) triangles), \(worst.boxes) box triangles,"
                      + " \(String(format: "%.2f", worst.cost * 1_000)) ms; \(String(format: "%.2f", total / Double(frames) * 1_000)) ms a frame on average")
            }
        }
    }
}
