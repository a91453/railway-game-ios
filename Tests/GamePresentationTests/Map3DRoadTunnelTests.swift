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
        builder.addRoadPortal(portal, into: &mesh)
        let part = Map3DRoadTunnelPortals.make(.nameplate, width: .twoWay, depth: 6)
        // Every concrete foot under the ground it stands on.
        for vertex in mesh.vertices where vertex.color == Map3DPalette.concrete && vertex.y < start.y + part.floor + 0.01 {
            XCTAssertLessThanOrEqual(vertex.y, builder.drawnGround(x: vertex.x, z: vertex.z) + 0.01)
        }
        // The hillside starts on the head wall's top, and its edges go
        // into the ground.
        let hill = mesh.vertices.filter { $0.color == Map3DPalette.embankment }
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
        let camera = try XCTUnwrap(Map3DScreenshotView("160,270,60")?.camera(at: place, in: scene, of: world, viewport: (874, 402)))
        XCTAssertEqual(camera.target.y, scene.drawnGround.height(x: camera.target.x, z: camera.target.z, world: world), accuracy: 0.01)
        XCTAssertGreaterThan(camera.target.y, 30)
    }
}
