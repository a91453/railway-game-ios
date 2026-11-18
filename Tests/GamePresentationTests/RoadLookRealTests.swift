import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 822 (ROAD-LOOK-REAL; the owner's four screenshots of
/// 2026-11-17, the default real map's elevated roads over a river at
/// 07:40): what the real map's water and roads looked like, each a
/// measurement that was red on main `003a1bf`.
final class RoadLookRealTests: XCTestCase {
    /// A world 1,024 m square whose ground stands 20 m high.
    private func flatWorld() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 65_536, height: 65_536),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let side = GroundBlock.side
        try world.setGround([try XCTUnwrap(GroundBlock(block: LandBlock(row: 0, column: 0), heights: [Int16](repeating: 20, count: side * side)))])
        return world
    }

    private static let bounds = Map3DBaseMap.Bounds(minX: 0, minZ: 0, maxX: 1_024, maxZ: 1_024)

    private static func points(_ list: [(Double, Double)]) -> [Map3DBaseMap.Point] {
        list.map { Map3DBaseMap.Point(x: $0.0, z: $0.1) }
    }

    /// `map` laid on `world` as a real map's is.
    private func built(_ world: GameWorld, _ map: Map3DBaseMap) -> Map3DScene.Builder {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        builder.addGround(water: false)
        _ = builder.addBaseMap(map)
        return builder
    }

    /// The builder's triangles reaching into the square `minX`…`maxX`,
    /// `minZ`…`maxZ`.
    private func triangles(_ builder: Map3DScene.Builder, minX: Float = -.infinity, minZ: Float = -.infinity,
                           maxX: Float = .infinity, maxZ: Float = .infinity) -> [[Map3DVertex]] {
        (Array(builder.meshes.values) + Array(builder.nearMeshes.values)).flatMap { mesh in
            stride(from: 0, to: mesh.indices.count - 2, by: 3).compactMap { index -> [Map3DVertex]? in
                let triangle = (0..<3).map { mesh.vertices[Int(mesh.indices[index + $0])] }
                let xs = triangle.map(\.x), zs = triangle.map(\.z)
                guard xs.max()! >= minX, xs.min()! <= maxX, zs.max()! >= minZ, zs.min()! <= maxZ else { return nil }
                return triangle
            }
        }
    }

    /// The faces over (`x`, `z`): each one's height, colour and layer.
    private func faces(over x: Float, _ z: Float, in triangles: [[Map3DVertex]]) -> [(y: Float, color: UInt32, layer: Float)] {
        triangles.compactMap { triangle in
            Map3DTrenchTests.heights(over: x, z, in: [triangle], colours: [triangle[0].color]).first.map { ($0, triangle[0].color, triangle[0].layer) }
        }
    }

    /// Whether (`x`, `z`) lies inside `ring` (even and odd).
    private func inside(_ x: Double, _ z: Double, _ ring: [Map3DBaseMap.Point]) -> Bool {
        var inside = false
        var previous = ring[ring.count - 1]
        for point in ring {
            if (point.z > z) != (previous.z > z), x < (previous.x - point.x) * (z - point.z) / (previous.z - point.z) + point.x { inside.toggle() }
            previous = point
        }
        return inside
    }

    /// A river 824 m square with an island in it, across several of the
    /// ground's 64 m cells.
    private static let river = points([(100, 100), (924, 100), (924, 924), (100, 924)])
    private static let island = points([(300, 330), (560, 300), (700, 520), (520, 700), (330, 600)])

    /// The points of the island 3 m or more inside its shore, every 4 m.
    private func islandPoints() -> [(Double, Double)] {
        var found: [(Double, Double)] = []
        for x in stride(from: 300.0, through: 700, by: 4) {
            for z in stride(from: 300.0, through: 700, by: 4) where inside(x, z, Self.island) {
                let near = [(-3.0, 0.0), (3, 0), (0, -3), (0, 3)].contains { !inside(x + $0.0, z + $0.1, Self.island) }
                if !near { found.append((x, z)) }
            }
        }
        return found
    }

    /// IMG_5325 and IMG_5322: sharp triangles of water over the river's
    /// islands. A river's outline, cut to each 64 m cell's triangle with
    /// its island's cut beside it, was triangulated with the island's
    /// piece touching the cell's edge, and the whole triangle came out
    /// water.
    func testNoWaterLiesOverARiversIsland() throws {
        let map = Map3DBaseMap(areas: [Map3DBaseMap.Area(cover: .water, rings: [Self.river, Self.island], bounds: Self.bounds)])
        let builder = built(try flatWorld(), map)
        let triangles = triangles(builder, minX: 290, minZ: 290, maxX: 710, maxZ: 710) + triangles(builder, minX: 140, minZ: 140, maxX: 160, maxZ: 160)
        let points = islandPoints()
        XCTAssertGreaterThan(points.count, 3_000)
        let wet = points.filter { faces(over: Float($0.0), Float($0.1), in: triangles).contains { $0.layer == Map3DVertex.water } }
        print("ROADLOOK island points \(points.count), under water \(wet.count)")
        XCTAssertEqual(wet.count, 0, "the island's points with water drawn over them")
        // And the river round it stays water.
        let shore = [(150.0, 150.0), (620, 300), (680, 420), (360, 660)]
        for (x, z) in shore {
            XCTAssertTrue(faces(over: Float(x), Float(z), in: triangles).contains { $0.layer == Map3DVertex.water }, "water at \(x), \(z)")
        }
    }

    /// IMG_5324: grey strips in the water. An island the tiles give no
    /// cover of its own (a hole in a river's outline, a sandbar or a
    /// mudflat such as the Tamsui's beside 華江) showed the bare ground
    /// under the river, grey at 07:40.
    func testARiversIslandIsNoBareGround() throws {
        let map = Map3DBaseMap(areas: [Map3DBaseMap.Area(cover: .water, rings: [Self.river, Self.island], bounds: Self.bounds)])
        let drawn = triangles(built(try flatWorld(), map), minX: 290, minZ: 290, maxX: 710, maxZ: 710)
        let points = islandPoints()
        let bare = points.filter { point in
            faces(over: Float(point.0), Float(point.1), in: drawn).max { $0.y < $1.y }.map { $0.color == Map3DPalette.ground } ?? true
        }
        print("ROADLOOK island points \(points.count), bare ground \(bare.count)")
        XCTAssertEqual(bare.count, 0, "the island's points showing the ground under the river")
        // The sea's holes are the land: no island drawn over them.
        var sea = Map3DBaseMap.Area(cover: .water, rings: [Self.river, Self.island], bounds: Self.bounds)
        sea.isSea = true
        let land = triangles(built(try flatWorld(), Map3DBaseMap(areas: [sea])), minX: 290, minZ: 290, maxX: 710, maxZ: 710)
        let covered = points.filter { point in
            faces(over: Float(point.0), Float(point.1), in: land).contains { $0.color == Map3DPalette.cover(Map3DScene.Builder.islandCover) }
        }
        XCTAssertEqual(covered.count, 0, "the land in a sea's hole")
    }

    /// IMG_5324: a flat road on the river under a raised bridge. 華江橋's
    /// scooter lane is a bridge of its own on the map, beside the
    /// carriageway, its ends 4 m and its line 12 m from the carriageway's: decision 391
    /// joined bridges by their ends only, so the carriageway rose over the
    /// road it crosses and the lane lay on the water beside it.
    func testALaneBesideARaisedBridgeRisesWithIt() throws {
        func road(_ points: [(Double, Double)], level: Int, kind: Map3DBaseMap.RoadKind) -> Map3DBaseMap.Road {
            Map3DBaseMap.Road(kind: kind, isRamp: false, points: Self.points(points), bounds: Self.bounds, bridgeLevel: level)
        }
        let roads = [
            road([(100, 500), (900, 500)], level: 1, kind: .secondary),
            road([(104, 512), (896, 512)], level: 1, kind: .service),
            // The street the carriageway crosses, ending before the lane.
            road([(500, 300), (500, 503)], level: 0, kind: .tertiary),
        ]
        let world = try flatWorld()
        var builder = built(world, Map3DBaseMap(roads: roads))
        let drawn = triangles(builder, minX: 250, minZ: 480, maxX: 750, maxZ: 520)
        let ground = builder.drawnGround(x: 500, z: 512)
        for x: Float in [350, 500, 650] {
            let carriageway = try XCTUnwrap(faces(over: x, 500, in: drawn).filter { $0.color == Map3DPalette.road(.secondary) }.map(\.y).max())
            let lane = try XCTUnwrap(faces(over: x, 512, in: drawn).filter { $0.color == Map3DPalette.road(.service) }.map(\.y).max())
            print(String(format: "ROADLOOK at %.0f carriageway %.2f m, lane %.2f m over the ground", x, carriageway - ground, lane - ground))
            XCTAssertGreaterThan(carriageway - ground, 5, "the carriageway over the street at \(x)")
            XCTAssertEqual(lane, carriageway, accuracy: 0.2, "the lane at the carriageway's height at \(x)")
        }
    }

    private func road(_ points: [(Double, Double)], level: Int, kind: Map3DBaseMap.RoadKind, ramp: Bool = false) -> Map3DBaseMap.Road {
        Map3DBaseMap.Road(kind: kind, isRamp: ramp, points: Self.points(points), bounds: Self.bounds, bridgeLevel: level)
    }

    /// IMG_5323 (台北橋's ramp in 三重): a street running beside a trunk's
    /// ramp down from a bridge's end rose with the ramp, as if on it, and
    /// stood 2 m under the deck: the ramp was taken as wide as a trunk
    /// with its pavements (9 m each side), not its own 3.5 m.
    func testAStreetBesideARampStaysOnTheGround() throws {
        let roads = [
            road([(100, 500), (500, 500)], level: 1, kind: .trunk),
            // The street the bridge crosses.
            road([(420, 300), (420, 700)], level: 0, kind: .tertiary),
            // Its ramp down, on the ground, and a street beside it.
            road([(500, 500), (700, 500)], level: 0, kind: .trunk, ramp: true),
            road([(480, 507.5), (700, 507.5)], level: 0, kind: .tertiary),
        ]
        var builder = built(try flatWorld(), Map3DBaseMap(roads: roads))
        let drawn = triangles(builder, minX: 540, minZ: 490, maxX: 600, maxZ: 515)
        for x: Float in [560, 580] {
            let ground = builder.drawnGround(x: x, z: 508)
            let ramp = try XCTUnwrap(faces(over: x, 500, in: drawn).filter { $0.color == Map3DPalette.road(.trunk) }.map(\.y).max())
            let street = try XCTUnwrap(faces(over: x, 508, in: drawn).filter { $0.color == Map3DPalette.road(.tertiary) }.map(\.y).max())
            print(String(format: "ROADLOOK at %.0f ramp %.2f m, street %.2f m over the ground", x, ramp - ground, street - ground))
            XCTAssertGreaterThan(ramp - ground, 1.5, "the ramp at \(x)")
            XCTAssertLessThan(street - ground, 0.5, "the street beside the ramp at \(x)")
        }
    }

    /// IMG_5323 (忠孝橋's east end): a ramp's bridge ends under the main
    /// deck it joins, and the road running on from it ramped down at once,
    /// under the deck: two slabs 1–4 m apart. It stays at the deck's
    /// height while it lies under it, as a road leaving a raised one at a
    /// junction does (decision 607).
    func testARoadLeavingADeckUnderItKeepsItsHeight() throws {
        let roads = [
            road([(100, 500), (900, 500)], level: 1, kind: .secondary),
            road([(500, 300), (500, 700)], level: 0, kind: .tertiary),
            // The ramp's bridge, joined to the deck, its end under it.
            road([(600, 500), (450, 505)], level: 1, kind: .secondary),
            // The road running on from it, out from under the deck.
            road([(450, 505), (250, 535)], level: 0, kind: .secondary),
        ]
        let builder = built(try flatWorld(), Map3DBaseMap(roads: roads))
        let drawn = triangles(builder, minX: 380, minZ: 490, maxX: 460, maxZ: 530)
        var stacked = 0, looked = 0
        // Past the end: the strip's half width laid back behind it is a
        // wedge of its own (NEXT_PRIORITIES, decision 822's leftovers).
        for x in stride(from: Float(390), through: 446, by: 2) {
            for z in stride(from: Float(494), through: 520, by: 2) {
                let tops = faces(over: x, z, in: drawn).filter { [Map3DPalette.road(.secondary)].contains($0.color) }.map(\.y).sorted()
                guard tops.count >= 2 else { continue }
                looked += 1
                if zip(tops, tops.dropFirst()).contains(where: { $1 - $0 > 0.5 && $1 - $0 < 4.5 }) { stacked += 1 }
            }
        }
        print("ROADLOOK points with two road surfaces \(looked), stacked 0.5–4.5 m apart \(stacked)")
        XCTAssertGreaterThan(looked, 10)
        XCTAssertEqual(stacked, 0, "points where a road lies 0.5–4.5 m under another")
    }

    /// ROAD-RAMP-HEIGHT (decision 822's next step): a link road's bridge
    /// joined to the main road's deck stood all of it at the deck's height
    /// (24 m on a fourth level), and only the road on the ground past its
    /// end came down, beside and under the deck: the slabs left round
    /// 三重 and 忠孝橋. It comes down inside itself from where it meets
    /// the ground, at its grade (slop-taipei's `build-elevated.mjs`).
    func testALinkRoadsBridgeComesDownInsideItself() throws {
        let roads = [
            road([(100, 500), (900, 500)], level: 4, kind: .secondary),
            // The street the deck crosses.
            road([(500, 300), (500, 700)], level: 0, kind: .tertiary),
            // The link road's bridge, leaving the deck at (700, 500), and
            // the road on the ground it runs on to.
            road([(700, 500), (650, 540), (300, 540)], level: 4, kind: .secondary, ramp: true),
            road([(300, 540), (100, 540)], level: 0, kind: .secondary, ramp: true),
        ]
        var builder = built(try flatWorld(), Map3DBaseMap(roads: roads))
        let drawn = triangles(builder, minX: 150, minZ: 490, maxX: 720, maxZ: 560)
        func top(_ x: Double) throws -> Float {
            // On the link road's line.
            let z = x > 650 ? 500 + (700 - x) * 0.8 : 540
            let tops = faces(over: Float(x), Float(z), in: drawn).filter { $0.color == Map3DPalette.road(.secondary) }.map(\.y)
            return try XCTUnwrap(tops.max(), "a road at \(x)") - builder.drawnGround(x: Float(x), z: Float(z))
        }
        for x in [200.0, 304, 400, 500, 600, 680] {
            print(String(format: "ROADRAMP link road at x %.0f: %.2f m over the ground", x, try top(x)))
        }
        // Where it reaches the ground and the road running on from it.
        XCTAssertLessThan(try top(200), 0.5)
        XCTAssertLessThan(try top(304), 1)
        // 100 m and 200 m in: a little over the 6 % of a main road, its
        // 414 m being 36 m short of the fourth level's 27 m at that
        // (ELEVATED-ROAD-HEIGHT; 24 m before it, which they reached at 6 %:
        // 6.3 m and 12.3 m).
        XCTAssertEqual(try top(400), 7.1, accuracy: 1)
        XCTAssertEqual(try top(500), 13.9, accuracy: 1)
        // It climbs all the way to the deck.
        XCTAssertLessThan(try top(600), try top(680))
        XCTAssertGreaterThan(try top(680), 20)
        // The main road keeps its deck's height (within 150 m of the street
        // it crosses at x 500).
        let main = try XCTUnwrap(faces(over: 400, 500, in: drawn).filter { $0.color == Map3DPalette.road(.secondary) }.map(\.y).max())
        XCTAssertGreaterThan(main - builder.drawnGround(x: 400, z: 500), 23)
    }

    /// ROAD-RAMP-HEIGHT: a link road drawn beside its main road, their
    /// surfaces overlapping as the map's widths draw them (忠孝橋's east
    /// end), comes down only once it leaves the main road's surface: had
    /// it come down from where it met the main road, it lay 1–4 m under
    /// the main road's edge (the first try's new slabs).
    func testALinkRoadBesideItsMainRoadComesDownPastIt() throws {
        let roads = [
            road([(100, 500), (900, 500)], level: 4, kind: .secondary),
            road([(500, 300), (500, 700)], level: 0, kind: .tertiary),
            // Beside the deck, 6 m off its middle, for 300 m, then away.
            road([(800, 500), (780, 506), (480, 506), (450, 540), (250, 540)], level: 4, kind: .secondary, ramp: true),
            road([(250, 540), (100, 540)], level: 0, kind: .secondary, ramp: true),
        ]
        let builder = built(try flatWorld(), Map3DBaseMap(roads: roads))
        let drawn = triangles(builder, minX: 470, minZ: 495, maxX: 790, maxZ: 520)
        var stacked = 0, looked = 0
        for x in stride(from: Float(490), through: 770, by: 4) {
            for z in stride(from: Float(500), through: 510, by: 1) {
                let tops = faces(over: x, z, in: drawn).filter { $0.color == Map3DPalette.road(.secondary) }.map(\.y).sorted()
                guard tops.count >= 2 else { continue }
                looked += 1
                if zip(tops, tops.dropFirst()).contains(where: { $1 - $0 > 0.5 && $1 - $0 < 4.5 }) { stacked += 1 }
            }
        }
        print("ROADRAMP beside: points with two road surfaces \(looked), stacked 0.5–4.5 m apart \(stacked)")
        XCTAssertGreaterThan(looked, 10)
        XCTAssertEqual(stacked, 0)
    }

    /// The road surface over level point (`x`, `z`) of `kind`, highest
    /// first, over the drawn ground.
    private func roadTops(_ builder: inout Map3DScene.Builder, _ drawn: [[Map3DVertex]], kind: Map3DBaseMap.RoadKind,
                          at x: Double, _ z: Double) -> [Float] {
        let ground = builder.drawnGround(x: Float(x), z: Float(z))
        return faces(over: Float(x), Float(z), in: drawn).filter { $0.color == Map3DPalette.road(kind) }.map { $0.y - ground }.sorted(by: >)
    }

    /// Decision 822 (後來三, 三重's approach to 台北橋): a lower level's
    /// bridge beside a higher one of its deck (a street's or a scooter
    /// lane's, `layer` 1 beside the trunk's `layer` 2), ending beside it
    /// while the higher one goes on, stood all of it at the deck's height,
    /// and the street on the ground running on from its end, under the
    /// viaduct, stayed at it or ramped down 1–6 m beneath it. It comes
    /// down inside itself, as a link road's bridge does, and the street
    /// stays on the ground.
    func testALowerBridgeEndingBesideAHigherOneComesDownInsideItself() throws {
        let roads = [
            road([(100, 500), (900, 500)], level: 2, kind: .trunk),
            road([(500, 300), (500, 700)], level: 0, kind: .tertiary),
            // The lower bridge, joined to the deck at (800, 500), 6 m off
            // the trunk's middle, ending beside it at x 250.
            road([(800, 500), (780, 506), (250, 506)], level: 1, kind: .secondary),
            // The street running on from it, under the viaduct, then away.
            road([(250, 506), (150, 506), (100, 600)], level: 0, kind: .secondary),
        ]
        var builder = built(try flatWorld(), Map3DBaseMap(roads: roads))
        let drawn = triangles(builder, minX: 140, minZ: 495, maxX: 760, maxZ: 515)
        let street = try XCTUnwrap(roadTops(&builder, drawn, kind: .secondary, at: 200, 507).last)
        let end = try XCTUnwrap(roadTops(&builder, drawn, kind: .secondary, at: 262, 507).last)
        let high = try XCTUnwrap(roadTops(&builder, drawn, kind: .secondary, at: 700, 507).first)
        print(String(format: "ROADLOWER street %.2f m, the bridge's end %.2f m, its far part %.2f m over the ground", street, end, high))
        XCTAssertLessThan(street, 0.5, "the street under the viaduct")
        XCTAssertLessThan(end, 1.5, "the lower bridge by its end")
        XCTAssertGreaterThan(high, 11, "the lower bridge where it joins the deck")
    }

    /// Decision 822 (後來三, 三重's link from 忠孝橋): a link road's bridge
    /// whose end meets another link's side (its middle, not its end) had
    /// no way to the main road, so it stood at the deck's height, and the
    /// road on the ground past its end ramped down from there. It comes
    /// down inside itself.
    func testALinkMeetingAnotherLinksSideComesDown() throws {
        let roads = [
            road([(100, 500), (900, 500)], level: 2, kind: .secondary),
            road([(500, 300), (500, 700)], level: 0, kind: .tertiary),
            // A link leaving the main road and coming back to it.
            road([(850, 500), (650, 530), (450, 500)], level: 2, kind: .secondary, ramp: true),
            // A link from its middle down to the ground, and on.
            road([(650, 530), (650, 700)], level: 2, kind: .secondary, ramp: true),
            road([(650, 700), (650, 800)], level: 0, kind: .secondary, ramp: true),
        ]
        var builder = built(try flatWorld(), Map3DBaseMap(roads: roads))
        let drawn = triangles(builder, minX: 640, minZ: 540, maxX: 660, maxZ: 790)
        let onGround = try XCTUnwrap(roadTops(&builder, drawn, kind: .secondary, at: 650, 750).first)
        let middle = try XCTUnwrap(roadTops(&builder, drawn, kind: .secondary, at: 650, 620).first)
        print(String(format: "ROADLINKSIDE the link at z 620 %.2f m, the road past it at z 750 %.2f m", middle, onGround))
        XCTAssertLessThan(onGround, 0.5, "the road on the ground past the link's end")
        XCTAssertLessThan(middle, 10, "the link halfway down")
        XCTAssertGreaterThan(middle, 2, "the link halfway down")
    }
    /// ROAD-LAYER-HEIGHT: a deck stood every bridge of it at its highest
    /// level's height, so a lower level's bridge crossing under a higher
    /// one of the same deck met it at the same height (忠孝橋, `layer` 1,
    /// under 市民大道's viaduct, both 24 m; in 三重 78 crossings so). Each
    /// stands at its own level, lifted only where it meets a higher one.
    func testALowerLevelsBridgeCrossesUnderAHigherOneOfItsDeck() throws {
        let roads = [
            road([(100, 500), (900, 500)], level: 3, kind: .trunk),
            // The street the trunk crosses.
            road([(450, 300), (450, 700)], level: 0, kind: .tertiary),
            // A lower bridge leaving the trunk's side, round and back under it.
            road([(600, 500), (600, 700), (500, 700), (500, 300)], level: 1, kind: .secondary),
        ]
        var builder = built(try flatWorld(), Map3DBaseMap(roads: roads))
        let drawn = triangles(builder, minX: 480, minZ: 480, maxX: 620, maxZ: 720)
        let trunk = try XCTUnwrap(roadTops(&builder, drawn, kind: .trunk, at: 500, 500).first)
        let under = try XCTUnwrap(roadTops(&builder, drawn, kind: .secondary, at: 500, 500).first)
        let joined = try XCTUnwrap(roadTops(&builder, drawn, kind: .secondary, at: 600, 520).first)
        let away = try XCTUnwrap(roadTops(&builder, drawn, kind: .secondary, at: 550, 700).first)
        print(String(format: "ROADLAYER trunk %.2f m, the lower bridge under it %.2f m, by where it joins %.2f m, away %.2f m", trunk, under, joined, away))
        XCTAssertGreaterThan(trunk, 20, "the trunk, a third level")
        XCTAssertLessThan(under, 10, "the lower bridge under the trunk")
        XCTAssertGreaterThan(trunk - under, 4.5, "clear of each other")
        XCTAssertGreaterThan(joined, 14, "the lower bridge where it meets the trunk")
        XCTAssertEqual(away, 9.3, accuracy: 0.5, "the lower bridge at its own level")
    }
    /// RAMP-EDGE-OVERLAP (decision 822 後來三's leftover): a lower bridge
    /// drawn 6 m off a higher one's middle, their widths overlapping as
    /// the map draws them, came down inside itself with its edge under
    /// the higher one's, 0.5–4.5 m beneath it, for the first 30–40 m
    /// (三重, some 420 m²). It is cut back to where it leaves the higher
    /// one's surface.
    func testALowerBridgeComingDownBesideAHigherOneIsNotUnderItsEdge() throws {
        let roads = [
            road([(100, 500), (900, 500)], level: 2, kind: .trunk),
            road([(500, 300), (500, 700)], level: 0, kind: .tertiary),
            road([(800, 500), (780, 506), (250, 506)], level: 1, kind: .secondary),
            road([(250, 506), (150, 506), (100, 600)], level: 0, kind: .secondary),
        ]
        let builder = built(try flatWorld(), Map3DBaseMap(roads: roads))
        let drawn = triangles(builder, minX: 240, minZ: 490, maxX: 600, maxZ: 520)
        var stacked = 0, looked = 0
        for x in stride(from: Float(250), through: 600, by: 2) {
            for z in stride(from: Float(496), through: 516, by: 1) {
                let tops = faces(over: x, z, in: drawn).filter { [Map3DPalette.road(.trunk), Map3DPalette.road(.secondary)].contains($0.color) }
                    .map(\.y).sorted()
                guard !tops.isEmpty else { continue }
                looked += 1
                if zip(tops, tops.dropFirst()).contains(where: { $1 - $0 > 0.5 && $1 - $0 < 4.5 }) { stacked += 1 }
            }
        }
        print("ROADEDGE points with a road surface \(looked), stacked 0.5–4.5 m apart \(stacked)")
        XCTAssertGreaterThan(looked, 1_000)
        XCTAssertEqual(stacked, 0, "points where the lower bridge lies 0.5–4.5 m under the higher one's edge")
    }
}
