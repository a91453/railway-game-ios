import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 239: the real buildings round Kaohsiung and
/// Taichung Stations, read from the 3D city preview's tiles and raised in
/// the 3D map's own look.
final class Map3DRealBuildingsTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let city = root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/city")

    private static func area(_ id: String) throws -> CityTileArea {
        let folder = city.appendingPathComponent(id)
        return try CityTileArea(manifest: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) {
            try? Data(contentsOf: folder.appendingPathComponent($0))
        }
    }

    private static let base: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }

    // MARK: - Reading

    func testTheTilesReadAsTheCompilerWroteThem() throws {
        // The manifests' own counts of each tile's buildings.
        for (id, count) in [("kaohsiung", 1212), ("taichung", 1404)] {
            let area = try Self.area(id)
            XCTAssertEqual(area.id, id)
            XCTAssertEqual(area.buildings.count, count, id)
            XCTAssertEqual(area.minX, -750)
            XCTAssertEqual(area.maxZ, 750)
            XCTAssertTrue(area.buildings.allSatisfy { $0.height > 0 && $0.storeys > 0 && !$0.polygons.isEmpty }, id)
            // Every point inside the area's square (a tile keeps a
            // building whose middle is on it, so a few reach a little out).
            let points = area.buildings.flatMap { $0.polygons.flatMap { $0.flatMap { $0 } } }
            XCTAssertTrue(points.allSatisfy { abs($0.x) < 900 && abs($0.z) < 900 }, id)
            // The uses `taiwan.mjs` gives them, shophouses the most.
            let uses = Dictionary(grouping: area.buildings, by: \.usage).mapValues(\.count)
            XCTAssertTrue(Set(uses.keys).isSubset(of: [401, 404, 413, 414, 421, 422, 431, 441, 454]), "\(uses)")
            XCTAssertEqual(uses.max { $0.value < $1.value }?.key, 413, "\(uses)")
        }
        XCTAssertEqual(Map3DScene.Builder.RealKind(usage: 413), .shophouse)
        XCTAssertEqual(Map3DScene.Builder.RealKind(usage: 404), .office)
        XCTAssertEqual(Map3DScene.Builder.RealKind(usage: 454), .temple)
    }

    func testABrokenTileIsRefused() throws {
        let folder = Self.city.appendingPathComponent("kaohsiung")
        let bytes = try [UInt8](Data(contentsOf: folder.appendingPathComponent("t_0_0.bin")))
        XCTAssertFalse(try CityTileArea.buildings(in: bytes).isEmpty)
        // Cut short in its first building (the header is 36 bytes).
        XCTAssertThrowsError(try CityTileArea.buildings(in: Array(bytes.prefix(60))))
        XCTAssertThrowsError(try CityTileArea.buildings(in: [0, 0, 0, 0] + bytes.dropFirst(4)))
        // A tile that does not read is left out, not the area.
        let area = try CityTileArea(manifest: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) {
            $0 == "t_0_0.bin" ? Data([1, 2, 3]) : try? Data(contentsOf: folder.appendingPathComponent($0))
        }
        XCTAssertEqual(area.buildings.count, 1212 - (try CityTileArea.buildings(in: bytes).count))
        XCTAssertThrowsError(try CityTileArea(manifest: Data("{}".utf8)) { _ in nil })
    }

    // MARK: - Drawing

    private func builder() -> Map3DScene.Builder {
        let world = GameWorld.newGame()
        return Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
    }

    func testARealBuildingsWallsFaceOutAndItsHoleIn() {
        // A 20 m square courtyard block round a 6 m hole, its rings given
        // both ways round.
        let outer = [Map3DPoint(-10, 0, -10), Map3DPoint(10, 0, -10), Map3DPoint(10, 0, 10), Map3DPoint(-10, 0, 10)]
        let hole = [Map3DPoint(-3, 0, -3), Map3DPoint(3, 0, -3), Map3DPoint(3, 0, 3), Map3DPoint(-3, 0, 3)]
        for rings in [[outer, hole], [Array(outer.reversed()), Array(hole.reversed())]] {
            var builder = builder()
            builder.addRealBuilding([rings], ground: 0, height: 9, storeys: 3, kind: .industry)
            let mesh = builder.meshes.values.reduce(into: Map3DMesh()) { $0.append($1) }
            var outward = 0, inward = 0
            for at in stride(from: 0, to: mesh.indices.count, by: 3) {
                let a = mesh.vertices[Int(mesh.indices[at])], b = mesh.vertices[Int(mesh.indices[at + 1])], c = mesh.vertices[Int(mesh.indices[at + 2])]
                let normal = Map3DPoint(a.nx, a.ny, a.nz)
                XCTAssertGreaterThan((b.position - a.position).cross(c.position - a.position).dot(normal), 0, "wound the wrong way")
                guard abs(normal.y) < 0.5 else { continue }
                let middle = (a.position + b.position + c.position) * (1 / 3)
                let away = Map3DPoint(middle.x, 0, middle.z).dot(normal)
                // The outer walls look away from the middle, the hole's
                // toward it.
                if max(abs(middle.x), abs(middle.z)) > 5 { XCTAssertGreaterThan(away, 0); outward += 1 } else { XCTAssertLessThan(away, 0); inward += 1 }
            }
            XCTAssertEqual(outward, 8)
            XCTAssertEqual(inward, 8)
            // The roof: the square less the hole, at the top.
            let roof = mesh.vertices.filter { $0.ny > 0.99 && $0.y == 9 }
            XCTAssertFalse(roof.isEmpty)
        }
    }

    /// A scene that takes only the area's north or south half still
    /// stands its buildings, as one taking its east or west half does.
    func testAnAreaHalfInTheSceneNorthOrSouthStillStands() throws {
        let area = try Self.area("kaohsiung")
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 22.6394, longitudeDegrees: 120.3024))
        let world = GameWorld.newGame(anchor: anchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let m = Double(WorldCoordinate.unitsPerMetre), x = frame.middleX, y = frame.middleY
        let halves = [
            "north": WorldRegion(minX: x - 2_000 * m, minY: y - 2_000 * m, maxX: x + 2_000 * m, maxY: y + 300 * m),
            "south": WorldRegion(minX: x - 2_000 * m, minY: y - 300 * m, maxX: x + 2_000 * m, maxY: y + 2_000 * m),
            "west": WorldRegion(minX: x - 2_000 * m, minY: y - 2_000 * m, maxX: x + 300 * m, maxY: y + 2_000 * m),
            "east": WorldRegion(minX: x - 300 * m, minY: y - 2_000 * m, maxX: x + 2_000 * m, maxY: y + 2_000 * m),
        ]
        for (name, region) in halves.sorted(by: { $0.key < $1.key }) {
            var builder = Map3DScene.Builder(originX: x, originY: y, region: region, world: world)
            XCTAssertFalse(builder.addRealBuildings([area], frame: frame, clearOf: []).isEmpty, name)
        }
    }

    /// A real building looks the same wherever the scene's origin falls
    /// (the middle of what is built moves as track is laid): its colours
    /// and faces come from where it stands on the map.
    func testARealBuildingsLookDoesNotMoveWithTheScenesOrigin() {
        let world = GameWorld.newGame()
        let m = Double(WorldCoordinate.unitsPerMetre)
        func look(shift: Float) -> [UInt32] {
            var builder = Map3DScene.Builder(originX: Double(shift) * m, originY: Double(shift / 2) * m, region: WorldRegion(bounds: world.bounds), world: world)
            builder.target = .near
            let ring = [Map3DPoint(0, 0, 0), Map3DPoint(8, 0, 0), Map3DPoint(8, 0, 14), Map3DPoint(0, 0, 14)]
                .map { $0 - Map3DPoint(shift, 0, shift / 2) }
            builder.addRealBuilding([[ring]], ground: 0, height: 12, storeys: 4, kind: .shophouse)
            return builder.nearMeshes.values.flatMap(\.vertices).map { $0.color &+ UInt32($0.layer + 2) }
        }
        let home = look(shift: 0)
        for shift: Float in [137, 777, 1_003, 2_531, 4_099] {
            XCTAssertEqual(look(shift: shift), home, "origin moved \(shift) m")
        }
    }

    func testAKaohsiungMapStandsOnItsRealBuildings() throws {
        let tiles = try Self.base.get()
        // Every area the app's folder lists, as the 3D map reads them.
        let areas = CityTileArea.areas(in: Self.city)
        XCTAssertEqual(areas.map(\.id), ["kaohsiung", "taichung"])
        XCTAssertTrue(CityTileArea.areas(in: Self.city.appendingPathComponent("none")).isEmpty)
        // A real-world game at Kaohsiung Station (the tiles' origin).
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 22.6394, longitudeDegrees: 120.3024))
        let world = GameWorld.newGame(anchor: anchor)
        let plain = Map3DScene(world: world, baseMap: tiles)
        let real = Map3DScene(world: world, baseMap: tiles, cityTiles: areas)
        func triangles(_ scene: Map3DScene) -> Int { scene.chunks.reduce(0) { $0 + $1.mesh.triangleCount } }
        // Real buildings in the middle of the map: a temple's ridge and
        // sheet-steel works among them.
        XCTAssertGreaterThan(triangles(real), triangles(plain))
        let colors = Set(real.chunks.flatMap(\.mesh.vertices).map(\.color))
        XCTAssertTrue(colors.contains(Map3DPalette.templeRidge))
        // Afar, the same buildings, simplified: fewer triangles than near.
        let middle = try XCTUnwrap(real.chunks.first { $0.column == 0 && $0.row == 0 })
        XCTAssertFalse(middle.far.isEmpty)
        XCTAssertLessThan(middle.far.triangleCount, middle.mesh.triangleCount - middle.baseIndexCount / 3)
        // The same every time.
        XCTAssertEqual(Map3DScene(world: world, baseMap: tiles, cityTiles: areas).chunks.map(\.mesh.vertices), real.chunks.map(\.mesh.vertices))
        // Nowhere near Taipei: nothing changes.
        let taipei = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        XCTAssertEqual(Map3DScene(world: taipei, baseMap: tiles, cityTiles: areas).chunks.map(\.mesh.vertices),
                       Map3DScene(world: taipei, baseMap: tiles).chunks.map(\.mesh.vertices))
        // A blank map has no Earth to stand them on.
        let blank = GameWorld.newGame()
        XCTAssertEqual(Map3DScene(world: blank, cityTiles: areas).chunks.map(\.mesh.vertices), Map3DScene(world: blank).chunks.map(\.mesh.vertices))
    }

    func testNoRealBuildingStandsWhereTheTrackRuns() throws {
        let area = try Self.area("kaohsiung")
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 22.6394, longitudeDegrees: 120.3024))
        let world = GameWorld.newGame(anchor: anchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let region = WorldRegion(bounds: world.bounds)
        var all = Map3DScene.Builder(originX: frame.middleX, originY: frame.middleY, region: region, world: world)
        let standing = all.addRealBuildings([area], frame: frame, clearOf: [])
        XCTAssertGreaterThan(standing.count, 100)
        // Every cell they stand on cleared: none drawn.
        var none = Map3DScene.Builder(originX: frame.middleX, originY: frame.middleY, region: region, world: world)
        XCTAssertTrue(none.addRealBuildings([area], frame: frame, clearOf: standing).isEmpty)
        XCTAssertTrue(none.nearMeshes.isEmpty && none.meshes.isEmpty)
    }
}
