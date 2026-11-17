import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ROAD-STRIP-WEDGE (decision 822's leftovers, NEXT_PRIORITIES §29.29): a
/// strip was drawn a half width past each segment's ends so its bends
/// closed. Past a road's end under a bridge's deck that half width lay at
/// the ground's height, a sloping wedge under the deck; at a bend each
/// segment's half width stuck out past the other's edge. Each measurement
/// was red on main `0f44439`.
final class RoadStripJoinTests: XCTestCase {
    /// A world 1,024 m square whose ground stands 20 m high.
    private func flatWorld() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 65_536, height: 65_536),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let side = GroundBlock.side
        try world.setGround([try XCTUnwrap(GroundBlock(block: LandBlock(row: 0, column: 0), heights: [Int16](repeating: 20, count: side * side)))])
        return world
    }

    private static let bounds = Map3DBaseMap.Bounds(minX: 0, minZ: 0, maxX: 1_024, maxZ: 1_024)

    private func road(_ points: [(Double, Double)], level: Int, kind: Map3DBaseMap.RoadKind) -> Map3DBaseMap.Road {
        Map3DBaseMap.Road(kind: kind, isRamp: false, points: points.map { Map3DBaseMap.Point(x: $0.0, z: $0.1) },
                          bounds: Self.bounds, bridgeLevel: level)
    }

    private func built(_ world: GameWorld, _ map: Map3DBaseMap) -> Map3DScene.Builder {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        builder.addGround(water: false)
        _ = builder.addBaseMap(map)
        return builder
    }

    /// The builder's triangles of `color` reaching into the square
    /// `minX`…`maxX`, `minZ`…`maxZ`.
    private func triangles(_ builder: Map3DScene.Builder, color: UInt32, minX: Float, minZ: Float, maxX: Float, maxZ: Float) -> [[Map3DVertex]] {
        (Array(builder.meshes.values) + Array(builder.nearMeshes.values)).flatMap { mesh in
            stride(from: 0, to: mesh.indices.count - 2, by: 3).compactMap { index -> [Map3DVertex]? in
                let triangle = (0..<3).map { mesh.vertices[Int(mesh.indices[index + $0])] }
                guard triangle[0].color == color else { return nil }
                let xs = triangle.map(\.x), zs = triangle.map(\.z)
                guard xs.max()! >= minX, xs.min()! <= maxX, zs.max()! >= minZ, zs.min()! <= maxZ else { return nil }
                return triangle
            }
        }
    }

    /// IMG_5323 (忠孝橋's east end): the road running on from a ramp's
    /// bridge whose end lies under the main deck. Its half width laid back
    /// behind its first point, under the deck, sloped from the ground up to
    /// the deck's height: a second slab 0.5–4.5 m under the deck.
    func testARoadsEndUnderADeckLiesNoWedgeBehindIt() throws {
        let roads = [
            road([(100, 500), (900, 500)], level: 1, kind: .secondary),
            road([(500, 300), (500, 700)], level: 0, kind: .tertiary),
            road([(600, 500), (450, 505)], level: 1, kind: .secondary),
            road([(450, 505), (250, 535)], level: 0, kind: .secondary),
        ]
        let builder = built(try flatWorld(), Map3DBaseMap(roads: roads))
        let drawn = triangles(builder, color: Map3DPalette.road(.secondary), minX: 380, minZ: 490, maxX: 470, maxZ: 530)
        var stacked = 0, looked = 0
        // Behind the end (x over 450) as well as past it.
        for x in stride(from: Float(390), through: 460, by: 1) {
            for z in stride(from: Float(494), through: 520, by: 1) {
                let tops = Map3DTrenchTests.heights(over: x, z, in: drawn, colours: [Map3DPalette.road(.secondary)]).sorted()
                guard tops.count >= 2 else { continue }
                looked += 1
                if zip(tops, tops.dropFirst()).contains(where: { $1 - $0 > 0.5 && $1 - $0 < 4.5 }) { stacked += 1 }
            }
        }
        print("ROADSTRIP behind the end: points with two road surfaces \(looked), stacked 0.5–4.5 m apart \(stacked)")
        XCTAssertGreaterThan(looked, 10)
        XCTAssertEqual(stacked, 0, "points where a road lies 0.5–4.5 m under another")
    }

    /// One road bending by `degrees` at (500, 500), on the ground: what it
    /// covers outside its own width and its join (MapLibre's: a mitre
    /// while it is at most twice the half width long, else a bevel), and
    /// what it leaves uncovered inside them, square metres.
    private func bend(_ degrees: Double, kind: Map3DBaseMap.RoadKind = .secondary) throws -> (spikes: Double, gaps: Double) {
        let angle = degrees * .pi / 180
        let joint = (x: 500.0, z: 500.0), length = 120.0
        let start = (x: joint.x - length, z: joint.z)
        let along2 = (x: cos(angle), z: sin(angle))
        let finish = (x: joint.x + along2.x * length, z: joint.z + along2.z * length)
        let builder = built(try flatWorld(), Map3DBaseMap(roads: [road([start, joint, finish], level: 0, kind: kind)]))
        let colour = Map3DPalette.road(kind)
        let drawn = triangles(builder, color: colour, minX: 470, minZ: 470, maxX: 530, maxZ: 530)
        let half = Double(kind.width(ramp: false)) / 2
        // Where the road should lie: each segment (the way's own ends a
        // half width out, as it was), and the join on the bend's outside.
        let along1 = (x: 1.0, z: 0.0)
        func inSegment(_ x: Double, _ z: Double, from a: (x: Double, z: Double), along: (x: Double, z: Double),
                       back: Double, forth: Double, slack: Double) -> Bool {
            let s = (x - a.x) * along.x + (z - a.z) * along.z, l = (x - a.x) * along.z - (z - a.z) * along.x
            return s >= -back - slack && s <= forth + slack && abs(l) <= half + slack
        }
        let left1 = (x: along1.z, z: -along1.x), left2 = (x: along2.z, z: -along2.x)
        let outerIsLeft = left1.x * along2.x + left1.z * along2.z < 0
        let n1 = outerIsLeft ? left1 : (x: -left1.x, z: -left1.z), n2 = outerIsLeft ? left2 : (x: -left2.x, z: -left2.z)
        let o1 = (x: joint.x + n1.x * half, z: joint.z + n1.z * half), o2 = (x: joint.x + n2.x * half, z: joint.z + n2.z * half)
        var join = [joint, o1, o2]
        let cosHalf = cos(angle / 2)
        if 1 / cosHalf <= 2 {
            let bx = n1.x + n2.x, bz = n1.z + n2.z, bl = (bx * bx + bz * bz).squareRoot()
            join = [joint, o1, (x: joint.x + bx / bl * half / cosHalf, z: joint.z + bz / bl * half / cosHalf), o2]
        }
        func inJoin(_ x: Double, _ z: Double, slack: Double) -> Bool {
            var sign = 0.0
            for (index, a) in join.enumerated() {
                let b = join[(index + 1) % join.count]
                let ex = b.x - a.x, ez = b.z - a.z, el = (ex * ex + ez * ez).squareRoot()
                let side = (ex * (z - a.z) - ez * (x - a.x)) / el
                if sign == 0 { sign = side >= 0 ? 1 : -1 }
                if side * sign < -slack { return false }
            }
            return true
        }
        func inside(_ x: Double, _ z: Double, slack: Double) -> Bool {
            inSegment(x, z, from: start, along: along1, back: half, forth: length, slack: slack)
                || inSegment(x, z, from: joint, along: along2, back: 0, forth: length + half, slack: slack)
                || inJoin(x, z, slack: slack)
        }
        let step = 0.2
        var spikes = 0.0, gaps = 0.0
        for x in stride(from: 480.0, through: 520, by: step) {
            for z in stride(from: 480.0, through: 520, by: step) {
                let covered = !Map3DTrenchTests.heights(over: Float(x), Float(z), in: drawn, colours: [colour]).isEmpty
                if covered && !inside(x, z, slack: 0.05) { spikes += step * step }
                if !covered && inside(x, z, slack: -0.05) { gaps += step * step }
            }
        }
        print("ROADSTRIP bend \(degrees)°: outside the road and its join \(spikes) m², uncovered inside \(gaps) m²")
        return (spikes, gaps)
    }

    /// A bend's outside: each segment's half width past the joint stuck out
    /// past the other's edge, an ear at a gentle bend and a square corner
    /// at a sharp one. A square bend's two half widths are its mitre, so it
    /// was right.
    func testABendIsClosedByAJoinWithNoSpikes() throws {
        for degrees in [10.0, 45, 90, 135, 170] {
            let found = try bend(degrees)
            XCTAssertLessThan(found.spikes, 0.1, "road outside its width and join at a \(degrees)° bend, m²")
            XCTAssertLessThan(found.gaps, 0.1, "road missing inside its width and join at a \(degrees)° bend, m²")
        }
    }

    /// The join of a bend lies on the road's surface: no step between it
    /// and the segments it joins, on a bend near a raised road too.
    func testABendsJoinLiesAtTheRoadsHeight() throws {
        let roads = [
            road([(100, 500), (900, 500)], level: 1, kind: .secondary),
            road([(500, 300), (500, 700)], level: 0, kind: .tertiary),
            // Running on from the deck's end, bending 15° as it comes down.
            road([(900, 500), (930, 500), (958.98, 507.76)], level: 0, kind: .secondary),
        ]
        let builder = built(try flatWorld(), Map3DBaseMap(roads: roads))
        let colour = Map3DPalette.road(.secondary)
        let drawn = triangles(builder, color: colour, minX: 920, minZ: 490, maxX: 945, maxZ: 515)
        var looked = 0, stepped = 0
        for x in stride(from: Float(924), through: 940, by: 0.25) {
            for z in stride(from: Float(494), through: 510, by: 0.25) {
                let tops = Map3DTrenchTests.heights(over: x, z, in: drawn, colours: [colour]).sorted()
                guard let low = tops.first, let high = tops.last else { continue }
                looked += 1
                if high - low > 0.05 { stepped += 1 }
            }
        }
        print("ROADSTRIP raised bend: points \(looked), two surfaces more than 5 cm apart \(stepped)")
        XCTAssertGreaterThan(looked, 100)
        XCTAssertEqual(stepped, 0)
    }
}
