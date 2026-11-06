import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 607 (the owner's screenshot, 2026-11-05: a motorway interchange
/// over the railway beside a river, its decks overlapping in V-shaped
/// gaps, ramps landing on the roads under them, broken parapets): where
/// two roads' surfaces meet in plan, they either meet at one height (a
/// junction, a ramp running on, two carriageways side by side) or pass a
/// storey apart (one over the other). A meeting between the two, half a
/// metre to 4.5 m apart, is a surface through another or a step.
extension Map3DSceneMemoryTests {
    /// Where two roads' surfaces clash: one road's middle on another's
    /// carriageway, `gap` metres apart in height.
    struct RoadClash {
        enum Kind: String { case decks, deckAndGround, ramps }
        let x: Double
        let z: Double
        let gap: Float
        let kind: Kind
        /// The two roads and their heights over the ground, for the log.
        var detail = ""
    }

    /// The least and most height apart of two roads' surfaces that meet in
    /// plan and clash, metres: closer is one surface (the paint's lifts,
    /// a ramp's grade over a sample); farther is one over the other.
    static let clashBand: ClosedRange<Float> = 0.5...4.5

    /// The clashes of `map`'s roads drawn inside `inside` as `builder` lays
    /// them (``Map3DScene/Builder/roadRise(at:along:onDeck:)``), every
    /// 4 m along each road near a raised one, each site (a 25 m square)
    /// once at its worst.
    static func clashes(of map: Map3DBaseMap, builder: inout Map3DScene.Builder, inside: Map3DBaseMap.Bounds) -> [RoadClash] {
        typealias Point = Map3DBaseMap.Point
        struct Segment { let road: Int; let a: Point; let b: Point }
        let cell = 8.0
        func key(_ x: Double, _ z: Double) -> Map3DScene.ChunkKey {
            Map3DScene.ChunkKey(column: Int((x / cell).rounded(.down)), row: Int((z / cell).rounded(.down)))
        }
        var segments: [Segment] = []
        var cells: [Map3DScene.ChunkKey: [Int]] = [:]
        for (number, road) in map.roads.enumerated() where road.points.count >= 2 {
            let half = Double(road.kind.width(ramp: road.isRamp)) / 2
            for (a, b) in zip(road.points, road.points.dropFirst()) {
                guard let (start, end) = Map3DScene.Builder.clipSegment(a, b, to: road.bounds) else { continue }
                let low = key(min(start.x, end.x) - half, min(start.z, end.z) - half), high = key(max(start.x, end.x) + half, max(start.z, end.z) + half)
                for row in low.row...high.row {
                    for column in low.column...high.column { cells[Map3DScene.ChunkKey(column: column, row: row), default: []].append(segments.count) }
                }
                segments.append(Segment(road: number, a: start, b: end))
            }
        }
        // A road's surface over `ground` (both roads' at the one point, so
        // the drawn ground's own steps are not counted), its rise taken
        // on its middle at `p`.
        func top(_ segment: Segment, at p: Point, ground: Float) -> (top: Float, raised: Bool) {
            let road = map.roads[segment.road]
            let dx = segment.b.x - segment.a.x, dz = segment.b.z - segment.a.z, length = max((dx * dx + dz * dz).squareRoot(), 1e-9)
            let rise = builder.roadRise(at: p, along: (dx / length, dz / length), onDeck: road.bridgeLevel > 0).rise
            return (ground + Map3DScene.Builder.lift(of: road.kind) + rise, rise > 0.05)
        }
        var worst: [Map3DScene.ChunkKey: RoadClash] = [:]
        for segment in segments {
            let dx = segment.b.x - segment.a.x, dz = segment.b.z - segment.a.z, length = (dx * dx + dz * dz).squareRoot()
            guard length > 0.01, builder.nearRaisedRoad(from: segment.a, to: segment.b) else { continue }
            let steps = max(1, Int((length / 4).rounded(.up)))
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                let p = Point(x: segment.a.x + dx * t, z: segment.a.z + dz * t)
                guard p.x >= inside.minX, p.x < inside.maxX, p.z >= inside.minZ, p.z < inside.maxZ else { continue }
                let here = builder.drawnGround(x: Float(p.x), z: Float(p.z))
                let mine = top(segment, at: p, ground: here)
                for other in cells[key(p.x, p.z)] ?? [] {
                    let them = segments[other]
                    guard them.road != segment.road else { continue }
                    let on = Map3DRoadBridges.nearest(p, them.a, them.b)
                    guard on.distance <= Double(map.roads[them.road].kind.width(ramp: map.roads[them.road].isRamp)) / 2 - 0.25 else { continue }
                    let theirs = top(them, at: on.point, ground: here)
                    let gap = abs(mine.top - theirs.top)
                    guard Self.clashBand.contains(gap) else { continue }
                    let bridges = [map.roads[segment.road].bridgeLevel > 0, map.roads[them.road].bridgeLevel > 0]
                    let kind: RoadClash.Kind = bridges.allSatisfy { $0 } ? .decks : bridges.contains(true) ? .deckAndGround : .ramps
                    let site = Map3DScene.ChunkKey(column: Int((p.x / 25).rounded(.down)), row: Int((p.z / 25).rounded(.down)))
                    if (worst[site]?.gap ?? 0) < gap {
                        let ground = builder.drawnGround(x: Float(p.x), z: Float(p.z))
                        func describe(_ road: Map3DBaseMap.Road, _ top: Float) -> String {
                            let ends = [road.points[0], road.points[road.points.count - 1]].map { ((p.x - $0.x) * (p.x - $0.x) + (p.z - $0.z) * (p.z - $0.z)).squareRoot() }.min()!
                            return "\(road.kind)\(road.isRamp ? " ramp" : "") L\(road.bridgeLevel) +\(String(format: "%.1f", top - ground)) end \(Int(ends))"
                        }
                        worst[site] = RoadClash(x: p.x, z: p.z, gap: gap, kind: kind,
                                                detail: describe(map.roads[segment.road], mine.top) + " | " + describe(map.roads[them.road], theirs.top))
                    }
                }
            }
        }
        return worst.values.sorted { ($0.gap, $0.x, $0.z) > ($1.gap, $1.x, $1.z) }
    }

    /// Scene point (`x`, `z`) metres of a scene at the world's origin, as
    /// latitude and longitude near enough to find it on a map.
    static func place(_ x: Double, _ z: Double, frame: RealWorldFrame) -> String {
        let metre = Map3DScene.Builder.metre
        let off = frame.metresFromAnchor(worldX: x * metre, worldY: z * metre)
        let latitude = frame.anchor.latitudeDegrees - off.south / 111_320
        let longitude = frame.anchor.longitudeDegrees + off.east / (111_320 * cos(latitude * .pi / 180))
        return String(format: "%.5f, %.5f", latitude, longitude)
    }

    /// Decision 607: every road the high-speed demo's base map draws in the
    /// 2,048 m squares its track runs through out of a tunnel, each square
    /// built as a chunk of the app's scene is: few places where two roads'
    /// surfaces meet in plan half a metre to 4.5 m apart.
    func testTheDemosInterchangesMeetAtOneHeightOrAStoreyApart() throws {
        let world = try HighSpeedDemoTests.opened.get()
        let tiles = try BaseMapTiles(data: Data(contentsOf: Map3DTrenchTests.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                                options: .alwaysMapped))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let snapshot = world.railwaySnapshot()
        let metre = Map3DScene.Builder.metre
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: 0, minY: 0, maxX: 1, maxY: 1), world: world,
                                         heights: HighSpeedDemoTests.heights)
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        let side = 2_048.0
        var squares = Set<Map3DScene.ChunkKey>()
        for piece in builder.trackCover.pieces where !piece.isTunnel {
            for p in [piece.a, piece.b] { squares.insert(Map3DScene.ChunkKey(column: Int((Double(p.x) / side).rounded(.down)), row: Int((Double(p.z) / side).rounded(.down)))) }
        }
        var all: [RoadClash] = []
        var nearRailAndRiver: [RoadClash] = []
        let started = Date()
        for square in squares.sorted(by: { ($0.row, $0.column) < ($1.row, $1.column) }) {
            let region = WorldRegion(minX: Double(square.column) * side * metre, minY: Double(square.row) * side * metre,
                                     maxX: Double(square.column + 1) * side * metre, maxY: Double(square.row + 1) * side * metre)
            let map = Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: 0, originY: 0)
            builder.roadBridges = builder.bridgeDecks(of: map, frame: frame)
            let inside = Map3DBaseMap.Bounds(minX: Double(square.column) * side, minZ: Double(square.row) * side,
                                             maxX: Double(square.column + 1) * side, maxZ: Double(square.row + 1) * side)
            let found = Self.clashes(of: map, builder: &builder, inside: inside)
            all += found
            // The owner's kind: the track under it, a river beside it.
            for clash in found where builder.nearTrack(x: Float(clash.x), z: Float(clash.z), within: 120) {
                let river = map.waterways.contains { way in
                    zip(way.points, way.points.dropFirst()).contains { Map3DRoadBridges.nearest(Map3DBaseMap.Point(x: clash.x, z: clash.z), $0.0, $0.1).distance < 400 }
                } || map.areas.contains { area in
                    area.cover == .water && area.rings.first.map { ring in ring.contains { abs($0.x - clash.x) < 400 && abs($0.z - clash.z) < 400 } } == true
                }
                if river { nearRailAndRiver.append(clash) }
            }
        }
        all.sort { $0.gap > $1.gap }
        let kinds = Dictionary(grouping: all, by: \.kind).mapValues(\.count)
        print("Map3DSceneMemoryTests (decision 607): \(squares.count) squares in \(Int(Date().timeIntervalSince(started))) s, \(all.count) clashing sites", kinds)
        for clash in all.prefix(20) {
            print(String(format: "  %.2f m apart, %@, scene %.0f, %.0f", clash.gap, clash.kind.rawValue, clash.x, clash.z), Self.place(clash.x, clash.z, frame: frame), clash.detail)
        }
        if ProcessInfo.processInfo.environment["ROADIX_ALL"] != nil {
            for clash in all { print(String(format: "ALL %.2f %@ %.0f %.0f", clash.gap, clash.kind.rawValue, clash.x, clash.z), Self.place(clash.x, clash.z, frame: frame), clash.detail) }
        }
        print("  over the track and beside a river: \(nearRailAndRiver.count)")
        for clash in nearRailAndRiver.sorted(by: { $0.gap > $1.gap }).prefix(8) {
            print(String(format: "  %.2f m apart, %@, scene %.0f, %.0f", clash.gap, clash.kind.rawValue, clash.x, clash.z), Self.place(clash.x, clash.z, frame: frame))
        }
        // main before decision 607: 236 sites, 104 of them a deck and a
        // road on the ground (a link road leaving a deck at the ground);
        // after it, 213, 76 of them. The rest are the side streets a ramp
        // run on along the ground crosses, kept on the ground (they are
        // there in the real world): in docs/decisions/607.md. Lower these
        // as they are mended.
        XCTAssertLessThanOrEqual(kinds[.deckAndGround] ?? 0, 80, "\(kinds[.deckAndGround] ?? 0) sites where a deck and a road on the ground meet 0.5–4.5 m apart")
        XCTAssertLessThanOrEqual(all.count, 215, "\(all.count) sites where two roads' surfaces meet 0.5–4.5 m apart, worst \(all.first?.gap ?? 0) m")
    }
}

extension Map3DSceneMemoryTests {
    /// Decision 607, for looking into one site: `ROADIX_AT=x,z` (scene
    /// metres) prints the roads, ends and heights round it.
    func testROADIXLookAtOneSite() throws {
        guard let at = ProcessInfo.processInfo.environment["ROADIX_AT"]?.split(separator: ",").compactMap({ Double($0) }), at.count == 2 else {
            throw XCTSkip("ROADIX_AT not set")
        }
        let world = try HighSpeedDemoTests.opened.get()
        let tiles = try BaseMapTiles(data: Data(contentsOf: Map3DTrenchTests.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                                options: .alwaysMapped))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Map3DScene.Builder.metre
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: 0, minY: 0, maxX: 1, maxY: 1), world: world,
                                         heights: HighSpeedDemoTests.heights)
        builder.trackCover = Map3DTrackCover(world.railwaySnapshot(), builder: &builder)
        let side = 2_048.0
        let square = (column: (at[0] / side).rounded(.down), row: (at[1] / side).rounded(.down))
        let region = WorldRegion(minX: square.column * side * metre, minY: square.row * side * metre,
                                 maxX: (square.column + 1) * side * metre, maxY: (square.row + 1) * side * metre)
        let map = Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: 0, originY: 0)
        builder.roadBridges = builder.bridgeDecks(of: map, frame: frame)
        let p = Map3DBaseMap.Point(x: at[0], z: at[1])
        let radius = Double(ProcessInfo.processInfo.environment["ROADIX_R"] ?? "40") ?? 40
        let bridges = builder.roadBridges
        print("ROADIX site", at, Self.place(at[0], at[1], frame: frame), "ground", builder.drawnGround(x: Float(p.x), z: Float(p.z)))
        for (number, road) in map.roads.enumerated() {
            guard let near = zip(road.points, road.points.dropFirst()).map({ Map3DRoadBridges.nearest(p, $0.0, $0.1) }).min(by: { $0.distance < $1.distance }),
                  near.distance < radius else { continue }
            let a = road.points[0], b = road.points[road.points.count - 1]
            var heights: [String] = []
            for (u, v) in zip(road.points, road.points.dropFirst()) {
                let length = ((v.x - u.x) * (v.x - u.x) + (v.z - u.z) * (v.z - u.z)).squareRoot()
                guard length > 0.01 else { continue }
                for step in 0...Int(length / 10) {
                    let q = Map3DBaseMap.Point(x: u.x + (v.x - u.x) * Double(step) * 10 / length, z: u.z + (v.z - u.z) * Double(step) * 10 / length)
                    guard ((q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)).squareRoot() < radius else { continue }
                    let rise = builder.roadRise(at: q, along: ((v.x - u.x) / length, (v.z - u.z) / length), onDeck: road.bridgeLevel > 0)
                    heights.append(String(format: "(%.0f,%.0f)%.1f%@", q.x, q.z, rise.rise, rise.onBridge ? "b" : ""))
                }
            }
            print(String(format: "ROADIX road %d %@%@ L%d ramp %d, %.0f,%.0f → %.0f,%.0f, nearest %.1f:", number, "\(road.kind)", road.isRamp ? " link" : "",
                         road.bridgeLevel, road.isRamp ? 1 : 0, a.x, a.z, b.x, b.z, near.distance), heights.joined(separator: " "))
        }
        for (number, end) in bridges.ends.enumerated() where ((end.point.x - p.x) * (end.point.x - p.x) + (end.point.z - p.z) * (end.point.z - p.z)).squareRoot() < radius * 3 {
            print(String(format: "ROADIX end %d at %.0f,%.0f out %.2f,%.2f rise %.1f plateau %.0f grade %.2f, ground roads %@", number, end.point.x, end.point.z,
                         end.outward.x, end.outward.z, end.rise, (Mirror(reflecting: end).children.first { $0.label == "plateau" }?.value as? Float) ?? 0, end.grade, "\(Set(end.roads.map(\.road)).sorted())"))
        }
        for (number, piece) in bridges.pieces.enumerated() {
            guard zip(piece.points, piece.points.dropFirst()).contains(where: { Map3DRoadBridges.nearest(p, $0.0, $0.1).distance < radius }) else { continue }
            let deck = bridges.decks[piece.deck]
            print("ROADIX piece \(number) deck \(piece.deck) points", piece.points.map { String(format: "%.0f,%.0f", $0.x, $0.z) }.joined(separator: " "),
                  "lifts", deck.lifts.map { String(format: "%.0f,%.0f/%.0f", $0.point.x, $0.point.z, $0.rise) }.joined(separator: " "),
                  "bounds", deck.bounds.map { String(format: "%.0f,%.0f %.1f %@", $0.point.x, $0.point.z, $0.height, $0.isFloor ? "floor" : "ceiling") }.joined(separator: "; "))
        }
        for (number, ground) in bridges.grounds.enumerated() {
            guard zip(ground.points, ground.points.dropFirst()).contains(where: { Map3DRoadBridges.nearest(p, $0.0, $0.1).distance < radius }) else { continue }
            print(String(format: "ROADIX ground %d %@ %.0f,%.0f → %.0f,%.0f (%d points)", number, "\(ground.kind)", ground.points[0].x, ground.points[0].z,
                         ground.points[ground.points.count - 1].x, ground.points[ground.points.count - 1].z, ground.points.count))
        }
    }
}

extension Map3DSceneMemoryTests {
    /// Decision 607's cost, on request (`ROADIX_SIZE=1`, some minutes):
    /// the scenes of decision 391's tables, their triangles, bytes and how
    /// long each took to build.
    func testROADIXSceneSizes() throws {
        guard ProcessInfo.processInfo.environment["ROADIX_SIZE"] != nil else { throw XCTSkip("Set ROADIX_SIZE=1.") }
        let world = try HighSpeedDemoTests.opened.get()
        for (name, latitude, longitude) in [("Banqiao", 25.0133, 121.4637), ("Taichung", 24.1372, 120.6869), ("Tainan", 22.9971, 120.2126)] {
            let focus = try Map3DOpenHereTests.point(latitude, longitude, in: world)
            let started = Date()
            let scene = Map3DScene(world: world, snapshot: world.railwaySnapshot(), focus: focus,
                                   heights: HighSpeedDemoTests.heights, railways: try HighSpeedDemoTests.railways())
            let seconds = Date().timeIntervalSince(started)
            var bytes = 0, triangles = 0
            for chunk in scene.chunks {
                for mesh in [chunk.mesh, chunk.far, chunk.close, chunk.standIn, chunk.shadows] {
                    bytes += mesh.vertices.count * MemoryLayout<Map3DVertex>.stride + mesh.indices.count * MemoryLayout<UInt32>.stride
                    triangles += mesh.indices.count / 3
                }
                bytes += chunk.farBoxes.count * MemoryLayout<Map3DBoxInstance>.stride
            }
            print(String(format: "ROADIX size %@: %d triangles, %d bytes, %.1f s", name, triangles, bytes, seconds))
        }
    }
}
