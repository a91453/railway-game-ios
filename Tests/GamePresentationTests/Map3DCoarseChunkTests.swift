import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 368: on a real-world map the 3D scene builds the city in full
/// only round where the camera looks (``Map3DScene/detailRadius``), and
/// the window builds it in full as the camera comes near and simplified
/// again once it is far behind. The owner's iPhone 17 Pro (83.1): the
/// high-speed demo's scene round Taipei, all in full, was killed for
/// memory (JetsamEvent, per-process-limit, 3.4 GB) a few seconds after
/// following a train into the 3D map.
final class Map3DCoarseChunkTests: XCTestCase {
    private typealias Key = Map3DStreaming.Key
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    /// A scene three kilometres square round Taichung Station, with the
    /// real buildings, built in full round `detail` (everywhere when `nil`).
    private func taichung(detail: Map3DPoint?) throws -> Map3DScene {
        let resources = Map3DRealTrainsTests.resources
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 24.1372, longitudeDegrees: 120.6869)))
        let at = try XCTUnwrap(RealWorldFrame(world: world)).worldPosition(latitude: 24.1372, longitude: 120.6869)
        let origin = (x: at.x.rounded(), y: at.y.rounded())
        let grid = Map3DStreaming(originX: origin.x, originY: origin.y, map: WorldRegion(bounds: world.bounds))
        let region = try XCTUnwrap(grid.region(of: [Key(column: -3, row: -3), Key(column: 2, row: 2)]))
        let tiles = try BaseMapTiles(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
        let city = CityTileArea.areas(in: resources.appendingPathComponent("BaseMap/city"))
        return Map3DScene(world: world, snapshot: nil, skyline: nil, frame: (region, origin.x, origin.y), baseMap: tiles, cityTiles: city,
                          heights: nil, lineBands: nil, railways: nil, temples: nil, detail: detail)
    }

    /// Round the scene's north-west corner, the chunks more than 2 km from
    /// it have their ground, track and simplified city, as built in full,
    /// and nothing of the city in full; the others are as built in full.
    func testOnlyTheChunksNearTheCameraHaveTheCityInFull() throws {
        let corner = Map3DPoint(-1_280, 0, -1_280)
        let full = try taichung(detail: nil), round = try taichung(detail: corner)
        let wholes = Dictionary(uniqueKeysWithValues: full.chunks.map { (Key(column: $0.column, row: $0.row), $0) })
        var coarse = 0, saved = 0
        for chunk in round.chunks {
            let key = Key(column: chunk.column, row: chunk.row)
            let whole = try XCTUnwrap(wholes[key])
            XCTAssertFalse(whole.coarse)
            XCTAssertEqual(chunk.coarse, Map3DStreaming.distance(of: key, to: corner) > Map3DScene.detailRadius, "\(key)")
            XCTAssertEqual(chunk.far.vertices, whole.far.vertices, "\(key)")
            XCTAssertEqual(chunk.farBoxes, whole.farBoxes, "\(key)")
            XCTAssertEqual(chunk.baseIndexCount, whole.baseIndexCount, "\(key)")
            XCTAssertEqual(Array(chunk.mesh.indices.prefix(chunk.baseIndexCount)), Array(whole.mesh.indices.prefix(whole.baseIndexCount)), "\(key)")
            if chunk.coarse {
                coarse += 1
                XCTAssertEqual(chunk.mesh.indices.count, chunk.baseIndexCount, "no city in full at \(key)")
                XCTAssertTrue(chunk.close.isEmpty, "\(key)")
                saved += whole.mesh.vertices.count + whole.close.vertices.count - chunk.mesh.vertices.count
            } else {
                XCTAssertEqual(chunk.mesh.vertices, whole.mesh.vertices, "\(key)")
                XCTAssertEqual(chunk.close.vertices, whole.close.vertices, "\(key)")
            }
        }
        XCTAssertGreaterThan(coarse, 0)
        XCTAssertGreaterThan(saved, 100_000, "a city's worth less")
    }

    /// The public scene of a real-world map is built in full round its
    /// middle only; a made-up map's, which never builds ahead, everywhere.
    func testOnlyAStreamingMapsSceneIsCoarse() throws {
        let made = Map3DScene(world: DemoWorld.make(in: .english))
        XCTAssertTrue(made.chunks.allSatisfy { !$0.coarse })
    }

    // MARK: - The window

    private func streaming() -> Map3DStreaming {
        let half = 50_000 * metre
        return Map3DStreaming(originX: half, originY: half, map: WorldRegion(minX: 0, minY: 0, maxX: 2 * half, maxY: 2 * half))
    }

    /// A window on a scene 12 km square round the origin, coarse more than
    /// ``Map3DScene/detailRadius`` from it, as the public scene is built.
    private func window() -> Map3DStreaming.Window {
        let grid = streaming()
        let region = WorldRegion(minX: grid.originX - 6_000 * metre, minY: grid.originY - 6_000 * metre,
                                 maxX: grid.originX + 6_000 * metre, maxY: grid.originY + 6_000 * metre)
        let whole = grid.keys(within: region)
        let coarse = whole.filter { Map3DStreaming.distance(of: $0, to: .zero) > Map3DScene.detailRadius }
        return Map3DStreaming.Window(grid: grid, region: region, coarse: coarse)
    }

    /// Steps `window` with the target at `target(seconds)` for `duration`
    /// seconds at 60 frames a second, every block asked for built at once
    /// (round the target it was asked for, as the app builds it).
    private func run(_ window: inout Map3DStreaming.Window, from start: Double = 0, for duration: Double,
                     target: (Double) -> Map3DPoint, check: (Map3DStreaming.Window, Map3DPoint) -> Void = { _, _ in }) {
        var seconds = start
        while seconds < start + duration {
            let at = target(seconds)
            let step = window.step(target: at, at: seconds)
            if !step.build.isEmpty { XCTAssertTrue(window.finished(step.build, generation: 0)) }
            check(window, at)
            seconds += 1.0 / 60
        }
    }

    /// The camera sent 4 km east: the chunks round it are built in full,
    /// those round the origin simplified again, and those in between left.
    func testTheWindowBuildsTheCityInFullWhereTheCameraGoes() {
        var window = window()
        let there = Map3DPoint(4_000, 0, 0)
        let near = window.grid.key(of: there)
        XCTAssertTrue(window.coarse.contains(near))
        run(&window, for: 30) { _ in there }
        for key in window.scene {
            let distance = Map3DStreaming.distance(of: key, to: there)
            if distance <= Map3DScene.detailRadius { XCTAssertFalse(window.coarse.contains(key), "\(key) near the camera") }
            if distance > Map3DScene.detailRadius + Map3DStreaming.slack { XCTAssertTrue(window.coarse.contains(key), "\(key) far behind") }
        }
        XCTAssertTrue(window.scene.isSubset(of: window.built), "the scene's own chunks are all kept")
    }

    /// Following a High Speed Rail train at ten times real time (833 m/s)
    /// across the scene and 30 km on: never more than a part of the scene's
    /// worth of chunks with the city in full, and once the train stops,
    /// only those round it.
    func testFollowingATrainKeepsTheCityInFullRoundIt() {
        var window = window()
        var most = 0
        let end = Map3DPoint(Float(833 * 50) - 6_000, 0, 200)
        run(&window, for: 50, target: { Map3DPoint(Float(833 * $0) - 6_000, 0, 200) }) { window, _ in
            most = max(most, window.built.subtracting(window.coarse).count)
        }
        // The whole 12 km scene is 576 chunks.
        XCTAssertLessThan(most, 200)
        run(&window, from: 50, for: 60, target: { _ in end })
        for key in window.built.subtracting(window.coarse) {
            XCTAssertLessThanOrEqual(Map3DStreaming.distance(of: key, to: end), Map3DScene.detailRadius + Map3DStreaming.slack, "\(key)")
        }
        XCTAssertFalse(window.coarse.contains(window.grid.key(of: end)))
    }
}
