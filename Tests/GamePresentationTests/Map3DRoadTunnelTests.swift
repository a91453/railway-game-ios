import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 611: the real roads' tunnel portals in the 3D map.
final class Map3DRoadTunnelTests: XCTestCase {
    private typealias Builder = Map3DScene.Builder
    private typealias Point = Map3DBaseMap.Point

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let tiles: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }
    private static let heights: Result<HeightGrid, Error> = Result { try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat")) }

    /// A builder and the base map `half` metres each way round (`latitude`,
    /// `longitude`), on the heights file's ground.
    private func real(latitude: Double, longitude: Double, half: Double) throws -> (Builder, Map3DBaseMap) {
        var world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)))
        try world.mapGround()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let at = frame.worldPosition(latitude: latitude, longitude: longitude)
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let region = WorldRegion(minX: at.x - half * metre, minY: at.y - half * metre, maxX: at.x + half * metre, maxY: at.y + half * metre)
        let map = Map3DBaseMap(tiles: try Self.tiles.get(), frame: frame, region: region, originX: at.x, originY: at.y)
        let builder = Builder(originX: at.x, originY: at.y, region: region, world: world, heights: try Self.heights.get())
        return (builder, map)
    }

    // MARK: Which ends open

    private let tile = Map3DBaseMap.Bounds(minX: 0, minZ: 0, maxX: 1000, maxZ: 1000)

    /// A tunnel drawn as two ways end to end opens at its two far ends
    /// only; an end the tile's edge cut (on it or past it) does not open.
    func testATunnelOpensOnlyAtItsOwnEnds() {
        let lines: [(kind: Map3DBaseMap.RoadKind, ramp: Bool, oneway: Bool, points: [Point])] = [
            (.trunk, false, false, [Point(x: 100, z: 500), Point(x: 300, z: 500)]),
            (.trunk, false, false, [Point(x: 300, z: 500), Point(x: 500, z: 500)]),
            (.minor, false, true, [Point(x: 700, z: 200), Point(x: 1000, z: 200)]),
            (.minor, false, false, [Point(x: 800, z: 900), Point(x: 1010, z: 900)]),
        ]
        let open = Map3DBaseMap.openEnds(of: lines, tile: tile, bounds: tile)
        XCTAssertEqual(open.map { [$0.point.x, $0.point.z] }, [[100, 500], [500, 500], [700, 200], [800, 900]])
        XCTAssertEqual(open.map(\.oneway), [false, false, true, false])
        // Each one's line goes inward.
        XCTAssertEqual(open[1].inward.map(\.x), [500, 300])
        // Outside the region drawn, none.
        let left = Map3DBaseMap.Bounds(minX: 0, minZ: 0, maxX: 400, maxZ: 1000)
        XCTAssertEqual(Map3DBaseMap.openEnds(of: lines, tile: tile, bounds: left).map(\.point.x), [100])
    }

    /// The portal for each class, one way and both ways.
    func testTheStyleFollowsTheRoad() {
        func style(_ kind: Map3DBaseMap.RoadKind, oneway: Bool = false, ramp: Bool = false, paired: Bool = false, gentle: Bool = false)
            -> String {
            let picked = Builder.portalStyle(kind: kind, oneway: oneway, ramp: ramp, paired: paired, gentle: gentle)
            return "\(picked.style.rawValue) \(picked.width.rawValue)"
        }
        XCTAssertEqual(style(.motorway, oneway: true, paired: true), "dividedExpressway oneWay")
        XCTAssertEqual(style(.motorway, oneway: true), "nameplate oneWay")
        XCTAssertEqual(style(.trunk), "nameplate twoWay")
        XCTAssertEqual(style(.primary, ramp: true), "nameplate oneWay")
        XCTAssertEqual(style(.secondary), "mountainArch twoWay")
        XCTAssertEqual(style(.tertiary, oneway: true), "mountainArch oneWay")
        XCTAssertEqual(style(.minor), "narrowLane twoWay")
        XCTAssertEqual(style(.service), "narrowLane twoWay")
        XCTAssertEqual(style(.trunk, gentle: true), "daylightGallery twoWay")
        XCTAssertEqual(style(.motorway, oneway: true, paired: true, gentle: true), "dividedExpressway oneWay")
    }

    // MARK: The portal

    /// No flat roof over the lining (#1885's review, 1), and the lining
    /// and its cap face down, so the map's sun and sky leave them dark
    /// (review, 2), in every one of the 14.
    func testTheLiningFacesDownAndNoFlatRoofStandsOverIt() {
        var parts = Map3DRoadTunnelPortals.Style.allCases.flatMap { style in
            Map3DRoadTunnelPortals.Width.allCases.map { Map3DRoadTunnelPortals.make(style, width: $0) }
        }
        parts += Map3DRoadTunnelPortals.RailTracks.allCases.flatMap { tracks in [false, true].map { Map3DRoadTunnelPortals.makeRail(tracks, daylight: $0) } }
        XCTAssertEqual(parts.count, 14)
        let lining = Set(Map3DRoadTunnelPortals.liningShades + [Map3DRoadTunnelPortals.capColor])
        for part in parts {
            let inner = part.mesh.vertices.filter { lining.contains($0.color) }
            XCTAssertFalse(inner.isEmpty)
            XCTAssertTrue(inner.allSatisfy { $0.nx == 0 && $0.ny == -1 && $0.nz == 0 })
            // Nothing level at the head wall's top over the lining (a
            // gallery's own roof is out in front of the mountain face).
            let roof = part.mesh.vertices.filter { abs($0.y - part.top) < 1e-3 && $0.ny > 0.99 && $0.x > Map3DRoadTunnelPortals.wallThickness }
            XCTAssertTrue(roof.isEmpty, "\(roof.count) at \(part.top)")
        }
        // A shallower lining's cap stands nearer.
        let shallow = Map3DRoadTunnelPortals.make(.mountainArch, width: .twoWay, depth: 4)
        XCTAssertEqual(shallow.innerEnd, Map3DRoadTunnelPortals.wallThickness + 4)
        XCTAssertEqual(shallow.mesh.vertices.map(\.x).max() ?? 0, shallow.innerEnd, accuracy: 1e-4)
    }

    /// A portal stood on a slope: its foot at or under the drawn ground
    /// everywhere, its road at the road's end, the hillside's front edge on
    /// the head wall's top and the floor inside over the ground.
    func testAPortalStandsOnTheGroundUnderTheHillside() throws {
        var (builder, _) = try real(latitude: 24.86, longitude: 121.78, half: 300)
        // Into the ground's rise, wherever it is steepest round the middle.
        let start = Map3DPoint(0, builder.drawnGround(x: 0, z: 0), 0)
        var best = (rise: -Float.infinity, into: Map3DPoint(1, 0, 0))
        for degrees in stride(from: 0, to: 360, by: 15) {
            let a = Float(degrees) * .pi / 180, into = Map3DPoint(cos(a), 0, sin(a))
            let rise = builder.drawnGround(x: into.x * 30, z: into.z * 30) - start.y
            if rise > best.rise { best = (rise, into) }
        }
        let portal = Builder.RoadPortal(point: start, into: best.into, style: .nameplate, width: .twoWay, depth: 6)
        var mesh = Map3DMesh()
        let cover = Map3DPalette.cover(.wood)
        builder.addRoadPortal(portal, cover: (cover, nil), into: &mesh)
        let part = Map3DRoadTunnelPortals.make(.nameplate, width: .twoWay, depth: 6)
        // Every concrete foot under the ground it stands on.
        for vertex in mesh.vertices where vertex.color == Map3DPalette.concrete && vertex.y < start.y + part.floor + 0.01 {
            XCTAssertLessThanOrEqual(vertex.y, builder.drawnGround(x: vertex.x, z: vertex.z) + 0.01)
        }
        // The hillside starts on the head wall's top, and its edges go
        // into the ground.
        let hill = mesh.vertices.filter { $0.color == cover }
        XCTAssertFalse(hill.isEmpty)
        XCTAssertTrue(hill.contains { abs($0.y - (start.y + part.top)) < 0.01 })
        XCTAssertTrue(hill.allSatisfy { $0.y >= builder.drawnGround(x: $0.x, z: $0.z) - 0.51 })
        // The dark floor inside: over the ground, and facing down.
        let floor = mesh.vertices.filter { $0.color == Map3DRoadTunnelPortals.liningShades[3] && $0.ny == -1 && $0.y > start.y - 0.5 }
        XCTAssertFalse(floor.isEmpty)
        XCTAssertTrue(floor.allSatisfy { $0.y >= builder.drawnGround(x: $0.x, z: $0.z) })
    }

    // MARK: Real places

    /// Provincial Highway 9's tunnels north of Pinglin and the freeway's
    /// Hsuehshan Tunnel at Toucheng have portals; Taipei's flat middle,
    /// whose tunnels are underpasses, has none.
    func testRealHillTunnelsHavePortalsAndTheCitysUnderpassesNone() throws {
        var portals: [String: [Builder.RoadPortal]] = [:]
        var triangles: [String: Int] = [:]
        for (name, latitude, longitude) in [("toucheng", 24.86, 121.78), ("pinglin", 24.94, 121.71), ("taipei", 25.0478, 121.5170)] {
            var (builder, map) = try real(latitude: latitude, longitude: longitude, half: 3_000)
            let found = builder.roadPortals(map.tunnelEnds)
            portals[name] = found
            for portal in found {
                XCTAssertEqual(portal.point.y, builder.drawnGround(x: portal.point.x, z: portal.point.z), accuracy: 0.01)
                XCTAssertTrue((Builder.shallowestLining...Map3DRoadTunnelPortals.liningDepth).contains(portal.depth))
            }
            var mesh = Map3DMesh()
            for portal in found { builder.addRoadPortal(portal, into: &mesh) }
            triangles[name] = mesh.indices.count / 3
            if ProcessInfo.processInfo.environment["ROAD_TUNNEL_PROBE"] != nil {
                print("PROBE \(name): \(map.tunnelEnds.count) tunnel ends, \(found.count) portals, \(mesh.indices.count / 3) triangles, \(mesh.vertices.count) vertices")
                for portal in found { print("PROBE portal \(portal.style) \(portal.width) \(portal.point) depth \(portal.depth)") }
            }
        }
        // The Hsuehshan Tunnel's two bores at Toucheng, each under its name.
        let toucheng = try XCTUnwrap(portals["toucheng"])
        XCTAssertEqual(toucheng.filter { $0.style == .nameplate && $0.width == .oneWay }.count, 2)
        XCTAssertGreaterThanOrEqual(portals["pinglin"]?.count ?? 0, 4)
        XCTAssertEqual(portals["taipei"]?.count, 0)
        // A few hundred triangles each: next to nothing in a chunk.
        XCTAssertLessThan(try XCTUnwrap(triangles["pinglin"]) / max(portals["pinglin"]?.count ?? 1, 1), 1_500)
    }

    /// #1925's review, 1: on level ground the hill over a portal is wide
    /// and low, in the ground's own colour: it reaches 20 m and more out
    /// beside it, and most of it falls no steeper than 1 : 2.
    func testOnLevelGroundTheHillIsWideAndGentle() throws {
        var (builder, _) = try real(latitude: 25.0478, longitude: 121.5170, half: 300)
        let start = Map3DPoint(0, builder.drawnGround(x: 0, z: 0), 0)
        let portal = Builder.RoadPortal(point: start, into: Map3DPoint(1, 0, 0), style: .nameplate, width: .twoWay, depth: 6)
        var mesh = Map3DMesh()
        builder.addRoadPortal(portal, into: &mesh)
        let hill = Map3DPalette.ground
        var faces = 0, steep = 0, widest: Float = 0
        var index = 0
        while index + 2 < mesh.indices.count {
            let corners = mesh.indices[index..<index + 3].map { mesh.vertices[Int($0)] }
            index += 3
            guard corners.allSatisfy({ $0.color == hill }),
                  corners.allSatisfy({ $0.y > builder.drawnGround(x: $0.x, z: $0.z) + 0.05 }) else { continue }
            faces += 1
            if corners[0].ny < 0.894 { steep += 1 } // steeper than 1 : 2
            widest = max(widest, corners.map { abs($0.z) }.max() ?? 0)
        }
        XCTAssertGreaterThan(faces, 0)
        XCTAssertGreaterThanOrEqual(widest, 20)
        XCTAssertLessThan(Double(steep), Double(faces) * 0.25)
    }

    /// #1925's review, 1: two bores side by side 13 m apart: each one's
    /// hill keeps out of the other's way in, which stays clear.
    func testAHillKeepsOutOfTheNextBoresWayIn() throws {
        var (builder, _) = try real(latitude: 25.0478, longitude: 121.5170, half: 300)
        let y = builder.drawnGround(x: 0, z: 0)
        let a = Builder.RoadPortal(point: Map3DPoint(0, y, 0), into: Map3DPoint(1, 0, 0), style: .nameplate, width: .oneWay, depth: 4)
        let b = Builder.RoadPortal(point: Map3DPoint(0, y, 13), into: Map3DPoint(1, 0, 0), style: .nameplate, width: .oneWay, depth: 4)
        let zone = Builder.clearZone(of: b)
        XCTAssertTrue(zone.contains(Map3DPoint(-4, y, 13)))
        XCTAssertFalse(zone.contains(Map3DPoint(4, y, 13)))
        var mesh = Map3DMesh()
        builder.addRoadPortal(a, clear: [zone], into: &mesh)
        let inside = mesh.vertices.filter { $0.color == Map3DPalette.ground && zone.contains(Map3DPoint($0.x, $0.y, $0.z)) }
        XCTAssertFalse(inside.isEmpty)
        XCTAssertTrue(inside.allSatisfy { $0.y <= builder.drawnGround(x: $0.x, z: $0.z) - 0.49 })
    }

    /// #1925's review, 2: a gallery is a roof on columns, open at the
    /// sides: no wall down its sides, a column every 3 m, and no wing
    /// walls at its outer end.
    func testAGalleryStandsOnColumnsOpenAtItsSides() {
        let part = Map3DRoadTunnelPortals.make(.daylightGallery, width: .oneWay)
        let feet = part.mesh.vertices.filter { abs($0.y - part.floor) < 1e-4 && $0.x > part.front + 0.01 && $0.x < -0.01 }
        // Only columns stand there, inside the roof's edge.
        XCTAssertFalse(feet.isEmpty)
        XCTAssertTrue(feet.allSatisfy { abs($0.z) < part.outerHalfWidth - 0.01 && $0.color == Map3DPalette.concrete })
        // Four along each side, 3 m apart: the faces of all but the first
        // one's outer face (at the end, not counted).
        XCTAssertEqual(Set(feet.map { ($0.x * 10).rounded() }).count, 2 * Int((-part.front / 3).rounded()) - 1)
        // Nothing in front of the gallery's outer end.
        XCTAssertGreaterThanOrEqual(part.mesh.vertices.map(\.x).min() ?? 0, part.front - 0.25)
    }

    /// The hill takes the colour of the cover drawn on top where the
    /// portal stands, else the plain ground's.
    func testTheHillTakesTheCoverUnderIt() {
        let square = [Point(x: -50, z: -50), Point(x: 50, z: -50), Point(x: 50, z: 50), Point(x: -50, z: 50)]
        let bounds = Map3DBaseMap.Bounds(minX: -50, minZ: -50, maxX: 50, maxZ: 50)
        let areas = [Map3DBaseMap.Area(cover: .grass, rings: [square], bounds: bounds),
                     Map3DBaseMap.Area(cover: .wood, rings: [square], bounds: bounds)]
        XCTAssertEqual(Builder.cover(at: Map3DPoint(0, 0, 0), in: areas).color, Map3DPalette.cover(.wood))
        XCTAssertEqual(Builder.cover(at: Map3DPoint(80, 0, 0), in: areas).color, Map3DPalette.ground)
        XCTAssertNil(Builder.cover(at: Map3DPoint(80, 0, 0), in: areas).paint)
    }

    /// The screenshot scene at Toucheng: the whole scene, as the app
    /// builds it, draws the two portals there, in full detail only, and
    /// the camera looks at them on the hill's ground, not 60 m under it.
    func testTheHsuehshanScreenshotSceneDrawsItsPortals() throws {
        let world = ScreenshotScene.hsuehshanTunnel.make(in: .english)
        let scene = Map3DScene(world: world, baseMap: try Self.tiles.get(), heights: try Self.heights.get())
        // The look leaves the lining's dark shades and the cap as they are.
        for shade in Map3DRoadTunnelPortals.liningShades + [Map3DRoadTunnelPortals.capColor] {
            XCTAssertEqual(Map3DLook.colour(shade), shade)
        }
        let cap = Map3DRoadTunnelPortals.capColor
        let capped = scene.chunks.filter { chunk in chunk.mesh.vertices.contains { $0.color == cap } }
        XCTAssertFalse(capped.isEmpty)
        // None in the far city or the closest detail.
        XCTAssertTrue(scene.chunks.allSatisfy { chunk in !chunk.far.vertices.contains { $0.color == cap } && !chunk.close.vertices.contains { $0.color == cap } })
        let place = try XCTUnwrap(ScreenshotScene.hsuehshanTunnel.place)
        let camera = try XCTUnwrap(Map3DScreenshotView("160,0,60")?.camera(at: place, in: scene, of: world, viewport: (874, 402)))
        XCTAssertEqual(camera.target.y, scene.drawnGround.height(x: camera.target.x, z: camera.target.z, world: world), accuracy: 0.01)
        XCTAssertGreaterThan(camera.target.y, 30)
    }

    // MARK: Decision 661 (review L13-7)

    /// Three freeway ends crowded together, two of them the closer pair:
    /// the closer two pair whichever order the three come in.
    func testCrowdedCarriagewaysPairTheClosestWhateverTheirOrder() {
        let into = Map3DPoint(0, 0, 1)
        let ends: [(paired: Bool, point: Map3DPoint, into: Map3DPoint)] = [
            (true, Map3DPoint(0, 0, 0), into),
            (true, Map3DPoint(13, 0, 0), into),
            (true, Map3DPoint(20, 0, 0), into),
        ]
        func pairs(_ order: [Int]) -> Set<Set<Int>> {
            let partner = Builder.pairedCarriageways(order.map { ends[$0] })
            return Set(partner.indices.compactMap { index in partner[index].map { Set([order[index], order[$0]]) } })
        }
        XCTAssertEqual(pairs([0, 1, 2]), [[1, 2]], "13 m and 20 m apart: the 7 m pair")
        for order in [[0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
            XCTAssertEqual(pairs(order), [[1, 2]], "\(order)")
        }
        // A ramp (not `paired`) or another way does not pair.
        XCTAssertEqual(Builder.pairedCarriageways([ends[1], (false, ends[2].point, into)]), [nil, nil])
        XCTAssertEqual(Builder.pairedCarriageways([ends[1], (true, ends[2].point, Map3DPoint(1, 0, 0))]), [nil, nil])
    }

    /// The portals do not depend on the order of the tunnel ends.
    func testThePortalsAreTheSameWhateverTheEndsOrder() throws {
        var (builder, map) = try real(latitude: 24.86, longitude: 121.78, half: 3_000)
        let ends = map.tunnelEnds
        XCTAssertGreaterThan(ends.count, 2)
        let forward = builder.roadPortals(ends)
        XCTAssertFalse(forward.isEmpty)
        let reversed: [Map3DBaseMap.TunnelEnd] = ends.reversed()
        XCTAssertEqual(builder.roadPortals(reversed), forward)
        let half = ends.count / 2
        let turned: [Map3DBaseMap.TunnelEnd] = Array(ends[half...]) + Array(ends[..<half])
        XCTAssertEqual(builder.roadPortals(turned), forward)
    }

    /// The chunks round the Hsuehshan Tunnel's portals at Toucheng built a
    /// block at a time (streaming, a local rebuild: their tiles and the
    /// apron) stand the same portals as the whole scene, vertex for vertex.
    func testChunksBuiltApartStandTheWholeScenesPortals() throws {
        var world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 24.86, longitudeDegrees: 121.78)))
        try world.mapGround()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let at = frame.worldPosition(latitude: 24.86, longitude: 121.78)
        let origin = (x: at.x.rounded(), y: at.y.rounded())
        let grid = Map3DStreaming(originX: origin.x, originY: origin.y, map: WorldRegion(bounds: world.bounds))
        let tiles = try Self.tiles.get(), heights = try Self.heights.get()
        typealias Key = Map3DStreaming.Key
        let whole = try XCTUnwrap(grid.region(of: [Key(column: -4, row: -4), Key(column: 3, row: 3)]))
        let scene = Map3DScene(world: world, snapshot: nil, skyline: nil, frame: (whole, origin.x, origin.y), baseMap: tiles, cityTiles: [],
                               heights: heights, lineBands: nil, railways: nil, temples: nil)
        let cap = Map3DRoadTunnelPortals.capColor
        func capped(_ mesh: Map3DMesh) -> [Map3DVertex] { mesh.vertices.filter { $0.color == cap } }
        let inner = (-3...2).flatMap { row in (-3...2).map { Key(column: $0, row: row) } }
        let wholeChunks = Dictionary(uniqueKeysWithValues: scene.chunks.map { (Key(column: $0.column, row: $0.row), $0) })
        var portals = 0
        for block in [inner.filter { $0.column < 0 && $0.row < 0 }, inner.filter { $0.column >= 0 && $0.row < 0 },
                      inner.filter { $0.column < 0 && $0.row >= 0 }, inner.filter { $0.column >= 0 && $0.row >= 0 }] {
            for chunk in Map3DScene.chunks(block, of: grid, world: world, baseMap: tiles, heights: heights) {
                let key = Key(column: chunk.column, row: chunk.row)
                let same = try XCTUnwrap(wholeChunks[key])
                XCTAssertEqual(capped(chunk.mesh), capped(same.mesh), "\(key)")
                portals += capped(chunk.mesh).count
            }
        }
        XCTAssertGreaterThan(portals, 0, "The Hsuehshan Tunnel's portals are in the chunks compared")
    }
}
