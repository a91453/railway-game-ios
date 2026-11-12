import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 713 (PERF-OPEN3D): the airfields are laid off the main actor.
/// The frame that asks first gets none and never waits; once laid, they
/// are the airfields laying them on the main actor gave, and a stand's
/// jet bridge is found as before the bridges were placed once a field.
@MainActor
final class Map3DAircraftLayerTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let airfields: Result<RealAirfields, Error> = Result {
        try RealAirfields(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan_airfields.json")))
    }

    /// A new game round Taoyuan's airport (its stands and jet bridges
    /// within the map) and its scene.
    private func taoyuan() throws -> (world: GameWorld, scene: Map3DScene, airfields: RealAirfields) {
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0777, longitudeDegrees: 121.2328)))
        return (world, Map3DScene(world: world), try Self.airfields.get())
    }

    private func summary(_ laid: Map3DAircraft.Laid) -> [String] {
        laid.fields.map { field in
            let stands = field.stands.map { "\($0.nose.x),\($0.nose.y),\($0.nose.z),\($0.room),\($0.bridged),\($0.node ?? -1)" }
            let runways = field.runways.map { "\($0.a.x),\($0.a.z),\($0.b.x),\($0.b.z),\($0.heights.count)" }
            return "\(field.seed) \(field.airports) \(stands) \(runways) \(field.nodes.count) \(field.links.count) \(field.rotation)"
        }
    }

    func testTheFirstAskGetsNoneAndOnceLaidTheyAreTheSame() async throws {
        let map = try taoyuan()
        let direct = Map3DAircraft.Laid(world: map.world, scene: map.scene, airfields: map.airfields)
        XCTAssertFalse(direct.isEmpty)
        let layer = Map3DAircraft.Layer()
        XCTAssertNil(layer.aircraft(world: map.world, in: map.scene, airfields: map.airfields), "laid off the main actor: none yet")
        XCTAssertTrue(layer.isLaying)
        XCTAssertNil(layer.aircraft(world: map.world, in: map.scene, airfields: map.airfields))
        XCTAssertEqual(layer.started, 1, "asked again while laying, no second laying")
        await layer.settle()
        let laid = try XCTUnwrap(layer.aircraft(world: map.world, in: map.scene, airfields: map.airfields))
        XCTAssertFalse(layer.isLaying)
        XCTAssertEqual(layer.laidSerial, 1)
        XCTAssertEqual(summary(laid), summary(direct))
        _ = layer.aircraft(world: map.world, in: map.scene, airfields: map.airfields)
        XCTAssertEqual(layer.started, 1, "kept while the scene and the airports are the same")
    }

    func testAnotherSceneIsLaidAgainAndTheOldOneNotHandedOut() async throws {
        let map = try taoyuan()
        let layer = Map3DAircraft.Layer()
        _ = layer.aircraft(world: map.world, in: map.scene, airfields: map.airfields)
        await layer.settle()
        XCTAssertNotNil(layer.aircraft(world: map.world, in: map.scene, airfields: map.airfields))
        // Built again round a place 5 km east: the scene's own space moved.
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let focus = (x: Double(map.world.bounds.width) / 2 + 5_000 * metre, y: Double(map.world.bounds.height) / 2)
        let moved = Map3DScene(world: map.world, focus: focus)
        try XCTSkipIf(moved.originX == map.scene.originX && moved.originY == map.scene.originY, "the scene did not move")
        XCTAssertNil(layer.aircraft(world: map.world, in: moved, airfields: map.airfields), "laid for the other scene: not these")
        XCTAssertEqual(layer.started, 2)
        await layer.settle()
        XCTAssertEqual(layer.laidSerial, 2)
        let direct = Map3DAircraft.Laid(world: map.world, scene: moved, airfields: map.airfields)
        XCTAssertEqual(summary(try XCTUnwrap(layer.aircraft(world: map.world, in: moved, airfields: map.airfields))), summary(direct))
    }

    /// A laying a later ask replaced is not kept when it finishes late.
    func testALayingReplacedIsNotKept() async throws {
        let map = try taoyuan()
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let moved = Map3DScene(world: map.world, focus: (x: Double(map.world.bounds.width) / 2 + 5_000 * metre, y: Double(map.world.bounds.height) / 2))
        try XCTSkipIf(moved.originX == map.scene.originX && moved.originY == map.scene.originY, "the scene did not move")
        let layer = Map3DAircraft.Layer()
        _ = layer.aircraft(world: map.world, in: map.scene, airfields: map.airfields)
        let first = layer.laying?.task
        _ = layer.aircraft(world: map.world, in: moved, airfields: map.airfields)
        await first?.value
        await layer.settle()
        XCTAssertEqual(layer.laidSerial, 2)
        XCTAssertNil(layer.aircraft(world: map.world, in: map.scene, airfields: map.airfields), "the first scene's were never kept")
    }

    /// A stand has a jet bridge when one ends within 35 m of its nose, as
    /// when every bridge was placed again for every stand.
    func testAStandsBridgeIsFoundAsBefore() throws {
        let map = try taoyuan()
        let laid = Map3DAircraft.Laid(world: map.world, scene: map.scene, airfields: map.airfields)
        let frame = try XCTUnwrap(RealWorldFrame(world: map.world))
        let source = try XCTUnwrap(map.airfields.fields.first { $0.iata == "TPE" })
        func level(_ point: RealAirfields.Point) -> Map3DPoint? {
            let at = frame.worldPosition(latitude: point.latitude, longitude: point.longitude)
            guard at.x >= 0, at.y >= 0, at.x < Double(map.world.bounds.width), at.y < Double(map.world.bounds.height) else { return nil }
            return map.scene.point(worldX: at.x, worldY: at.y, height: 0)
        }
        let noses = source.stands.compactMap { level($0.nose) }
        let field = try XCTUnwrap(laid.fields.first { $0.stands.count == noses.count })
        var bridged = 0
        for (stand, nose) in zip(field.stands, noses) {
            XCTAssertEqual(stand.nose.x, nose.x)
            XCTAssertEqual(stand.nose.z, nose.z)
            let expected = source.bridges.contains { bridge in
                level(bridge.to).map { Map3DPoint($0.x - nose.x, 0, $0.z - nose.z).length < 35 } ?? false
            }
            XCTAssertEqual(stand.bridged, expected)
            if expected { bridged += 1 }
        }
        XCTAssertGreaterThan(bridged, 20, "Taoyuan's terminals' stands")
    }
}

/// PERF-OPEN3D: what laying a save's airfields costs, the work that was on
/// the frame the 3D map opened on. A report, not a check: it runs only
/// with `PERF_SAVE` naming a save file (the player's own, never in the
/// repository).
///
///     PERF_SAVE=/path/to/save.json swift test -c release -Xswiftc -enable-testing --skip-build \
///       --filter Map3DAircraftLayingReportTests
@MainActor
final class Map3DAircraftLayingReportTests: XCTestCase {
    func testWhatLayingTheAirfieldsCosts() throws {
        guard let path = ProcessInfo.processInfo.environment["PERF_SAVE"] else { throw XCTSkip("set PERF_SAVE=<save> to time laying its airfields") }
        let world = try SaveLibrary.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        let session = try BuildCommandCostReportTests.session(of: world)
        let resources = Map3DRealTrainsTests.resources
        let airfields = try RealAirfields(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan_airfields.json")))
        // Round the first station (the owner's whole-Taiwan save: Nangang).
        let focus = world.stations.first.map { (x: Double($0.location.x), y: Double($0.location.y)) }
        let scene = Map3DScene(world: world, snapshot: world.railwaySnapshot(), skyline: CitySkyline(world: world), focus: focus,
                               heights: session.heights, lineBands: Map3DLineBands(world: world, palette: .standard), railways: session.railways)
        let clock = ContinuousClock()
        var fields = 0, stands = 0
        var times: [Duration] = []
        for _ in 0..<5 {
            times.append(clock.measure {
                let laid = Map3DAircraft.Laid(world: world, scene: scene, airfields: airfields)
                fields = laid.fields.count
                stands = laid.fields.reduce(0) { $0 + $1.stands.count }
            })
        }
        let traffic = clock.measure { _ = Map3DAircraft.Traffic(world: world) }
        func ms(_ duration: Duration) -> String { String(format: "%.1f", Double(duration.components.attoseconds) * 1e-15 + Double(duration.components.seconds) * 1_000) }
        print("PERF-OPEN3D laying \(fields) airfields, \(stands) stands of \(world.airports.count) airports: \(times.map(ms).joined(separator: " ")) ms; the day's flights \(ms(traffic)) ms")
    }
}
