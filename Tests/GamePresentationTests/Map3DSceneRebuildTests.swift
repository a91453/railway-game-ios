import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 517 續 (PR 3b): after a change to the track or the platforms,
/// the 3D map builds again only the chunks round it, and the scene it
/// gets is the scene built whole for the changed world.
final class Map3DSceneRebuildTests: XCTestCase {
    private typealias Key = Map3DStreaming.Key
    private let metre = Int64(WorldCoordinate.unitsPerMetre)

    /// Round Taichung Station, with the real ground, buildings, temples
    /// and railways and a line of the player's across it (as
    /// ``Map3DStreamingTests/testChunksBuiltApartAreTheWholeScenes()``).
    private struct Place {
        let world: GameWorld
        let at: (x: Double, y: Double)
        let tiles: BaseMapTiles
        let city: [CityTileArea]
        let temples: RealTemples
        let railways: RealRailways
        let frame: (region: WorldRegion, originX: Double, originY: Double)

        func scene(of world: GameWorld) -> Map3DScene {
            Map3DScene(world: world, snapshot: world.railwaySnapshot(), skyline: CitySkyline(world: world), frame: frame, baseMap: tiles,
                       cityTiles: city, heights: nil, lineBands: Map3DLineBands(world: world, palette: .standard), railways: railways,
                       temples: temples)
        }

        func rebuilt(_ keys: Set<Key>, of old: Map3DScene, for world: GameWorld) -> Map3DScene {
            Map3DScene(rebuilding: keys, of: old, world: world, snapshot: world.railwaySnapshot(), skyline: CitySkyline(world: world),
                       baseMap: tiles, cityTiles: city, lineBands: Map3DLineBands(world: world, palette: .standard), railways: railways,
                       temples: temples)
        }

        func point(east: Int64, north: Int64) -> WorldCoordinate {
            let metre = Int64(WorldCoordinate.unitsPerMetre)
            return WorldCoordinate(x: Int64(at.x) + east * metre, y: Int64(at.y) - north * metre)
        }
    }

    private func place() throws -> Place {
        let resources = Map3DRealTrainsTests.resources
        let start = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 24.1372, longitudeDegrees: 120.6869)))
        let frame = try XCTUnwrap(RealWorldFrame(world: start))
        let at = frame.worldPosition(latitude: 24.1372, longitude: 120.6869)
        let across = 2_000 * metre
        let world = try LineBuilder.line(through: [PlanPoint(x: Int64(at.x) - across, y: Int64(at.y) - across / 3),
                                                   PlanPoint(x: Int64(at.x) + across, y: Int64(at.y) + across / 3)], in: start)
        let origin = (x: at.x.rounded(), y: at.y.rounded())
        let grid = Map3DStreaming(originX: origin.x, originY: origin.y, map: WorldRegion(bounds: world.bounds))
        // Six chunks by six.
        let region = try XCTUnwrap(grid.region(of: [Key(column: -3, row: -3), Key(column: 2, row: 2)]))
        return Place(world: world, at: at,
                     tiles: try BaseMapTiles(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan.pmtiles"), options: .alwaysMapped)),
                     city: CityTileArea.areas(in: resources.appendingPathComponent("BaseMap/city")),
                     temples: try RealTemples(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan_temples.json"))),
                     railways: try XCTUnwrap(Map3DRealTrainsTests.railways), frame: (region, origin.x, origin.y))
    }

    /// 300 m of track on its own, from `from` metres east and north of
    /// the place's middle, east.
    private func spur(_ world: GameWorld, in place: Place, east: Int64, north: Int64) throws -> (world: GameWorld, edge: TrackEdgeID) {
        var world = world
        let a = try world.buildTrackNode(at: place.point(east: east, north: north))
        let b = try world.buildTrackNode(at: place.point(east: east + 300, north: north))
        let edge = try world.buildTrackEdge(from: a, to: b)
        return (world, edge)
    }

    /// The triangles of `mesh` from `range` of its indices, each as its
    /// three vertices, in no order: a chunk built apart may lay the same
    /// pieces in another order (from sets of another size), which draws
    /// the same picture.
    private static func triangles(_ mesh: Map3DMesh, _ range: Range<Int>) -> [String] {
        stride(from: range.lowerBound, to: range.upperBound, by: 3).map { start in
            (0..<3).map { "\(mesh.vertices[Int(mesh.indices[start + $0])])" }.joined(separator: "|")
        }.sorted()
    }

    private static func triangles(_ mesh: Map3DMesh) -> [String] { triangles(mesh, 0..<mesh.indices.count) }

    /// What of `chunk` draws otherwise than `same`.
    static func differences(_ chunk: Map3DScene.Chunk, _ same: Map3DScene.Chunk) -> [String] {
        func differ(_ a: Map3DMesh, _ b: Map3DMesh) -> Bool {
            (a.vertices != b.vertices || a.indices != b.indices) && triangles(a) != triangles(b)
        }
        var fields: [String] = []
        if chunk.baseIndexCount != same.baseIndexCount { fields.append("base") }
        if chunk.mesh.vertices != same.mesh.vertices || chunk.mesh.indices != same.mesh.indices {
            if triangles(chunk.mesh, 0..<chunk.baseIndexCount) != triangles(same.mesh, 0..<same.baseIndexCount) { fields.append("ground") }
            if triangles(chunk.mesh, chunk.baseIndexCount..<chunk.mesh.indices.count)
                != triangles(same.mesh, same.baseIndexCount..<same.mesh.indices.count) { fields.append("mesh") }
        }
        if differ(chunk.far, same.far) { fields.append("far") }
        if chunk.farBoxes.map({ "\($0)" }).sorted() != same.farBoxes.map({ "\($0)" }).sorted() { fields.append("farBoxes") }
        if differ(chunk.close, same.close) { fields.append("close") }
        if differ(chunk.standIn, same.standIn) { fields.append("standIn") }
        if differ(chunk.shadows, same.shadows) { fields.append("shadows") }
        if chunk.props.map({ "\($0.floats)" }).sorted() != same.props.map({ "\($0.floats)" }).sorted() { fields.append("props") }
        if chunk.signs.map({ "\($0)" }).sorted() != same.signs.map({ "\($0)" }).sorted() { fields.append("signs") }
        if chunk.cityTops != same.cityTops { fields.append("cityTops") }
        if chunk.coarse != same.coarse { fields.append("coarse") }
        return fields
    }

    /// `rebuilt` draws as `whole`: every chunk, in no order but for
    /// `allowing` (what a chunk built apart may draw otherwise, decision
    /// 358: the kit scenes kept to a scene's budget), and what the whole
    /// scene works out over all of it.
    private func assertSame(_ rebuilt: Map3DScene, _ whole: Map3DScene, allowing: Set<String> = [],
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rebuilt.region, whole.region, file: file, line: line)
        XCTAssertEqual(rebuilt.chunks.map { Key(column: $0.column, row: $0.row) }, whole.chunks.map { Key(column: $0.column, row: $0.row) },
                       file: file, line: line)
        // Which chunks differ, and in what (one line each, not the meshes).
        var differing: [String] = []
        for (chunk, same) in zip(rebuilt.chunks, whole.chunks) {
            let fields = Self.differences(chunk, same).filter { !allowing.contains($0) }
            if !fields.isEmpty { differing.append("\(chunk.column),\(chunk.row): \(fields.joined(separator: " "))") }
        }
        XCTAssertEqual(differing, [], file: file, line: line)
        XCTAssertEqual(rebuilt.trackCover.openings, whole.trackCover.openings, file: file, line: line)
        XCTAssertEqual(rebuilt.trackCover.pieces.count, whole.trackCover.pieces.count, file: file, line: line)
        XCTAssertTrue(rebuilt.drawnGround.heights == whole.drawnGround.heights, "drawn ground", file: file, line: line)
        XCTAssertEqual(rebuilt.realTrains?.tracks.map { $0.map(\.lanes) }, whole.realTrains?.tracks.map { $0.map(\.lanes) }, file: file, line: line)
        XCTAssertEqual(rebuilt.realTrains?.tracks.map { $0.map(\.shown) }, whole.realTrains?.tracks.map { $0.map(\.shown) }, file: file, line: line)
        XCTAssertEqual(rebuilt.streetLife.lanes.map(\.path.points), whole.streetLife.lanes.map(\.path.points), file: file, line: line)
        func spots(_ scene: Map3DScene) -> [String] {
            scene.streetLife.spots.map { "\($0.kind) \(String(describing: $0.station)) \($0.people) \($0.width) \($0.path.points)" }.sorted()
        }
        XCTAssertEqual(spots(rebuilt), spots(whole), file: file, line: line)
    }

    /// `a`'s chunks are `b`'s, bit for bit.
    private func assertBitForBit(_ a: Map3DScene, _ b: Map3DScene, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.chunks.map { Key(column: $0.column, row: $0.row) }, b.chunks.map { Key(column: $0.column, row: $0.row) },
                       file: file, line: line)
        let differing = zip(a.chunks, b.chunks).filter { x, y in
            x.mesh.vertices != y.mesh.vertices || x.mesh.indices != y.mesh.indices || x.baseIndexCount != y.baseIndexCount
                || x.far.vertices != y.far.vertices || x.far.indices != y.far.indices || x.farBoxes != y.farBoxes
                || x.close.vertices != y.close.vertices || x.standIn.vertices != y.standIn.vertices
                || x.shadows.vertices != y.shadows.vertices || x.props.map(\.floats) != y.props.map(\.floats)
                || x.signs != y.signs || x.cityTops != y.cityTops || x.coarse != y.coarse
        }.map { "\($0.0.column),\($0.0.row)" }
        XCTAssertEqual(differing, [], file: file, line: line)
    }

    /// `keys` of `old` built again for `world` is the whole scene of
    /// `world`: bit for bit as the same chunks of that scene built again
    /// (so every other chunk is the same in `old` and in it, and what
    /// changed is in `keys`), and drawing as it does but for what a chunk
    /// built apart draws otherwise (`allowing`, decision 358).
    private func assertCaught(_ keys: Set<Key>, of old: Map3DScene, for world: GameWorld, in place: Place, allowing: Set<String>,
                              file: StaticString = #filePath, line: UInt = #line) {
        let rebuilt = place.rebuilt(keys, of: old, for: world), whole = place.scene(of: world)
        assertBitForBit(rebuilt, place.rebuilt(keys, of: whole, for: world), file: file, line: line)
        assertSame(rebuilt, whole, allowing: allowing, file: file, line: line)
    }

    /// Track laid: only the chunks round it are built again (of 36), and
    /// the scene is the one built whole.
    func testTrackLaidBuildsOnlyItsChunksAgain() throws {
        let place = try place()
        let old = place.scene(of: place.world)
        // 300 m east from 700 m east and 800 m north: in the chunk two
        // east and two north of the middle's (column 1, row −2), well
        // inside the chunk's square in z, within ``reach`` of the next
        // chunk east.
        let laid = try spur(place.world, in: place, east: 700, north: 800).world
        let keys = Map3DSceneRebuild.keys(round: Map3DSceneRebuild.changes(from: place.world.railwaySnapshot(), place.world,
                                                                            to: laid.railwaySnapshot(), laid),
                                          in: old, map: WorldRegion(bounds: laid.bounds))
        XCTAssertFalse(keys.isEmpty)
        XCTAssertLessThanOrEqual(keys.count, 9, "\(keys.sorted())")
        XCTAssertTrue(keys.contains(Key(column: 1, row: -2)), "\(keys.sorted())")
        // Nothing near the player's line, which runs south of it.
        XCTAssertFalse(keys.contains(Key(column: 0, row: 0)), "\(keys.sorted())")
        // Built apart, its kit scenes keep to the block's budget (decision
        // 358), as the chunks the camera comes to.
        assertCaught(keys, of: old, for: laid, in: place, allowing: ["close"])
    }

    /// A station's platform added on track already there, and the track
    /// taken up again: each time only the chunks round it are built
    /// again, and the scene is the one built whole but for what building
    /// apart draws otherwise.
    func testAPlatformAddedAndTrackTakenUpBuildOnlyTheirChunksAgain() throws {
        let place = try place()
        let (laid, edge) = try spur(place.world, in: place, east: -1_100, north: -900)
        let before = place.scene(of: laid)
        var platformed = laid
        let station = try platformed.buildStation(named: "New", at: place.point(east: -950, north: -900).plan)
        try platformed.addTrackPlatform(station.id, on: edge, from: 40 * metre, to: 260 * metre)
        let keys = Map3DSceneRebuild.keys(round: Map3DSceneRebuild.changes(from: laid.railwaySnapshot(), laid,
                                                                            to: platformed.railwaySnapshot(), platformed),
                                          in: before, map: WorldRegion(bounds: laid.bounds))
        XCTAssertFalse(keys.isEmpty)
        XCTAssertLessThan(keys.count, 36 / 2, "\(keys.sorted())")
        // Here the parks' and temples' scenes, nearest the middle of what
        // is built first, also fall otherwise built apart, and the city
        // lots they keep clear with them (decision 358).
        let apart: Set<String> = ["close", "mesh", "far", "cityTops", "props", "shadows", "farBoxes", "signs", "standIn"]
        assertCaught(keys, of: before, for: platformed, in: place, allowing: apart)
        // Taken up again: back to the scene without it.
        let back = Map3DSceneRebuild.keys(round: Map3DSceneRebuild.changes(from: laid.railwaySnapshot(), laid,
                                                                            to: place.world.railwaySnapshot(), place.world),
                                          in: before, map: WorldRegion(bounds: laid.bounds))
        XCTAssertFalse(back.isEmpty)
        XCTAssertLessThan(back.count, 36 / 2, "\(back.sorted())")
        assertCaught(back, of: before, for: place.world, in: place, allowing: apart)
    }

    /// Nothing changed, nothing to build; an edge changed counts where it
    /// was and where it is.
    func testChangesAreWhereTheTrackWasAndIs() throws {
        let place = try place()
        let world = place.world
        XCTAssertTrue(Map3DSceneRebuild.changes(from: world.railwaySnapshot(), world, to: world.railwaySnapshot(), world).isEmpty)
        let laid = try spur(world, in: place, east: 700, north: 800).world
        let points = Map3DSceneRebuild.changes(from: world.railwaySnapshot(), world, to: laid.railwaySnapshot(), laid)
        let metre = Double(WorldCoordinate.unitsPerMetre)
        XCTAssertFalse(points.isEmpty)
        for point in points {
            XCTAssertGreaterThanOrEqual(point.x, place.at.x + 699 * metre)
            XCTAssertLessThanOrEqual(point.x, place.at.x + 1_001 * metre)
        }
        // And the other way, taken up.
        XCTAssertEqual(Map3DSceneRebuild.changes(from: laid.railwaySnapshot(), laid, to: world.railwaySnapshot(), world).count, points.count)
    }
}

/// Decision 517 續 (PR 3b): how long the 3D scene takes to build again
/// after 300 m of track is laid on decision 614's late-game save, whole
/// and only round the change. Run on request:
///
///     PERF_SAVE=/tmp/big8.json swift test -c release -Xswiftc -enable-testing --skip-build \
///       --filter Map3DSceneRebuildReportTests
///
/// `PERF_BASEMAP=1` builds with the base map, the city's buildings and
/// the temples, as the app does (without, as decision 614 measured).
@MainActor
final class Map3DSceneRebuildReportTests: XCTestCase {
    func testWhatBuildingAgainCosts() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["PERF_SAVE"] else { throw XCTSkip("set PERF_SAVE=<save> to time building the 3D scene again") }
        let world = try SaveLibrary.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        let session = try BuildCommandCostReportTests.session(of: world)
        let resources = Map3DRealTrainsTests.resources
        let files = environment["PERF_BASEMAP"] != nil
        let tiles = files ? try BaseMapTiles(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan.pmtiles"), options: .alwaysMapped)) : nil
        let city = files ? CityTileArea.areas(in: resources.appendingPathComponent("BaseMap/city")) : []
        let temples = files ? try RealTemples(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan_temples.json"))) : nil
        // Round the middle of the own track, as decision 614's measurement.
        let nodes = world.network.nodes
        let middle = (x: Double(nodes.map(\.position.x).reduce(0, +)) / Double(nodes.count),
                      y: Double(nodes.map(\.position.y).reduce(0, +)) / Double(nodes.count))
        let clock = ContinuousClock()
        func scene(of world: GameWorld) -> Map3DScene {
            Map3DScene(world: world, snapshot: world.railwaySnapshot(), skyline: CitySkyline(world: world), focus: middle, baseMap: tiles,
                       cityTiles: city, heights: session.heights, lineBands: Map3DLineBands(world: world, palette: .standard),
                       railways: session.railways, temples: temples)
        }
        var old: Map3DScene!
        let first = clock.measure { old = scene(of: world) }
        // 300 m of track from the dead end nearest the middle, as the
        // app's track tool lays it.
        let metre = Int64(WorldCoordinate.unitsPerMetre)
        var laid: GameWorld?
        let ends = nodes.filter { $0.ends.count == 1 }.sorted {
            let a = (Double($0.position.x) - middle.x, Double($0.position.y) - middle.y)
            let b = (Double($1.position.x) - middle.x, Double($1.position.y) - middle.y)
            return a.0 * a.0 + a.1 * a.1 < b.0 * b.0 + b.1 * b.1
        }
        session.setNetworkMode(.build)
        search: for end in ends {
            for (dx, dy) in [(300, 0), (-300, 0), (0, 300), (0, -300)] {
                session.clearNetworkDraft()
                let at = end.position.plan
                session.tapNetwork(at: at, reach: 20 * metre)
                session.tapNetwork(at: PlanPoint(x: at.x + Int64(dx) * metre, y: at.y + Int64(dy) * metre), reach: 20 * metre)
                guard session.networkPreview(now: true)?.problem == nil else { continue }
                let count = session.world.network.edges.count
                session.buildNetworkTrack()
                if session.world.network.edges.count > count {
                    laid = session.world
                    break search
                }
            }
        }
        let after = try XCTUnwrap(laid, "no dead end to lay track from")
        XCTAssertTrue(Map3DSceneRebuild.fits(old, world: after, focus: middle))
        var whole: Map3DScene!
        let wholeTime = clock.measure { whole = scene(of: after) }
        var keys = Set<Map3DStreaming.Key>()
        var part: Map3DScene!
        let partTime = clock.measure {
            keys = Map3DSceneRebuild.keys(round: Map3DSceneRebuild.changes(from: world.railwaySnapshot(), world, to: after.railwaySnapshot(), after),
                                          in: old, map: WorldRegion(bounds: after.bounds))
            part = Map3DScene(rebuilding: keys, of: old, world: after, snapshot: after.railwaySnapshot(), skyline: CitySkyline(world: after),
                              baseMap: tiles, cityTiles: city, heights: session.heights,
                              lineBands: Map3DLineBands(world: after, palette: .standard), railways: session.railways, temples: temples,
                              detail: Map3DStreaming.streams(after) ? Map3DPoint(0, 0, 0) : nil)
        }
        // In no order (decision 358: built apart may lay the same pieces
        // in another order); what differs beyond the kit scenes' budget.
        let different = zip(part.chunks, whole.chunks).map { Map3DSceneRebuildTests.differences($0, $1) }.filter { !$0.isEmpty }
        let differing = different.count, beyondKits = different.filter { $0 != ["close"] }.count
        let ms = BuildCommandCostReportTests.ms
        let firstMs = ms(first), wholeMs = ms(wholeTime), partMs = ms(partTime)
        let compared = min(part.chunks.count, whole.chunks.count)
        print("PERF3B base map \(files ? "on" : "off"): first \(Int(firstMs)) ms")
        print("PERF3B after 300 m of track: whole \(Int(wholeMs)) ms, \(whole.chunks.count) chunks, \(whole.triangleCount) triangles")
        print("PERF3B only round it: \(Int(partMs)) ms, \(keys.count) chunks built again; chunks drawing otherwise \(differing) of \(compared), beyond the kit scenes \(beyondKits)")
        XCTAssertEqual(part.chunks.count, whole.chunks.count)
    }
}
