import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 873 (TW-BRIDGES): 淡江大橋 was two carriageways on piers
/// across the river's mouth. Its mast stands between them, 180 m over the
/// road, the stays run from it down to the deck's middle in two planes,
/// and no pier stands under the spans they carry.
final class Map3DCableStayedBridgeTests: XCTestCase {
    private typealias Bridge = Map3DSuspensionBridge

    private static let tiles = Result {
        try BaseMapTiles(data: Data(contentsOf: Map3DTrenchTests.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                    options: .alwaysMapped))
    }

    /// A game at the river's mouth, a scene `reach` metres round the
    /// point `station` metres along 淡江大橋 from its mast (towards 八里),
    /// with the app's base map (its roads and their bridges) when `road`.
    private func scene(station: Float = 137, reach: Double = 900, road: Bool = true) throws -> (builder: Map3DScene.Builder, bridge: Bridge.Placed) {
        let mast = Bridge.danjiang.towers[0]
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: mast.latitude, longitudeDegrees: mast.longitude)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let origin = frame.worldPosition(latitude: mast.latitude, longitude: mast.longitude)
        let placed = try XCTUnwrap(Bridge.danjiang.placed(frame: frame, origin: origin))
        let middle = placed.point(along: station, across: 0)
        let at = (x: origin.x + Double(middle.x) * metre, y: origin.y + Double(middle.z) * metre)
        let region = WorldRegion(minX: at.x - reach * metre, minY: at.y - reach * metre, maxX: at.x + reach * metre, maxY: at.y + reach * metre)
        var builder = Map3DScene.Builder(originX: origin.x, originY: origin.y, region: region, world: world, heights: nil)
        if road {
            _ = builder.addBaseMap(Map3DBaseMap(tiles: try Self.tiles.get(), frame: frame, region: region, originX: origin.x, originY: origin.y))
        }
        return (builder, placed)
    }

    /// The spans as published: 450 m from the mast towards 八里, 175 m
    /// behind it, both carried by the stays.
    func testTheSpansAsPublished() throws {
        let (_, bridge) = try scene(road: false)
        XCTAssertEqual(bridge.span, 450, accuracy: 3)
        XCTAssertEqual(bridge.hung, -175...bridge.span)
        XCTAssertEqual(bridge.ends, -175...bridge.span)
        // Towards 八里: south and a little west.
        XCTAssertGreaterThan(bridge.along.z, 0.9)
        XCTAssertLessThan(bridge.along.x, 0)
    }

    /// The stays: as many to the main span as behind the mast, the
    /// farther anchored the higher held, each a straight line from the
    /// mast down to the deck, drawn in pieces that leave no gap.
    func testTheStaysFanFromTheMast() throws {
        let look = try XCTUnwrap(Bridge.danjiang.stays)
        let stays = look.stays
        XCTAssertEqual(stays.count, 2 * look.count)
        XCTAssertEqual(stays.filter { $0.anchor > 0 }.count, look.count)
        for side in [stays.filter { $0.anchor > 0 }, stays.filter { $0.anchor < 0 }] {
            for (near, far) in zip(side, side.dropFirst()) {
                XCTAssertGreaterThan(abs(far.anchor), abs(near.anchor))
                XCTAssertGreaterThan(far.hold, near.hold)
            }
        }
        XCTAssertLessThanOrEqual(try XCTUnwrap(stays.map(\.anchor).max()), 450)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(stays.map(\.anchor).min()), -175)
        XCTAssertLessThan(try XCTUnwrap(stays.map(\.hold).max()), look.top)
        for stay in stays {
            XCTAssertEqual(look.height(of: stay, at: 0), stay.hold)
            XCTAssertEqual(look.height(of: stay, at: abs(stay.anchor)), Map3DCableStays.anchorRise, accuracy: 0.01)
            XCTAssertEqual(look.across(of: stay, at: abs(stay.anchor)), look.plane.deck, accuracy: 0.01)
            let pieces = look.pieces(of: stay)
            XCTAssertEqual(pieces.first?.from, 0)
            XCTAssertEqual(try XCTUnwrap(pieces.last?.to), abs(stay.anchor), accuracy: 0.01)
            for (piece, next) in zip(pieces, pieces.dropFirst()) { XCTAssertEqual(piece.to, next.from) }
            XCTAssertTrue(pieces.allSatisfy { $0.to - $0.from > 5 && $0.to - $0.from < 40 }, "\(pieces)")
        }
    }

    /// On the map: the mast between the carriageways, 180 m over the
    /// road and down to the river; the stays down to the deck; one deck
    /// from edge to edge; nothing under the spans down to the water.
    func testOnTaiwansMap() throws {
        var (builder, bridge) = try scene()
        let look = try XCTUnwrap(bridge.bridge.stays)
        let deck = try XCTUnwrap(builder.suspendedDeck(bridge, at: 0))
        XCTAssertGreaterThan(deck.road, 5)
        // A carriageway each side of the mast, none through it.
        XCTAssertLessThan(deck.left, -10)
        XCTAssertGreaterThan(deck.right, 10)
        var offset = -look.sections[0].across - 1
        while offset <= look.sections[0].across + 1 {
            let p = bridge.point(along: 0, across: offset)
            let raised = builder.roadRise(at: Map3DBaseMap.Point(x: Double(p.x), z: Double(p.z)), along: (Double(bridge.along.x), Double(bridge.along.z)), onDeck: true)
            XCTAssertFalse(raised.onBridge, "a carriageway through the mast, \(offset) m across")
            offset += 0.5
        }
        // A road bridge all the way under the stays.
        var station = bridge.hung.lowerBound
        while station <= bridge.hung.upperBound {
            XCTAssertEqual(try XCTUnwrap(builder.suspendedDeck(bridge, at: station), "at \(station)").road, deck.road, accuracy: 2.5, "at \(station)")
            station += 25
        }
        let before = builder.meshes.values.reduce(0) { $0 + $1.indices.count }
        builder.addSuspensionBridges()
        let added = (builder.meshes.values.reduce(0) { $0 + $1.indices.count } - before) / 3
        XCTAssertGreaterThan(added, 2_000)
        XCTAssertLessThan(added, 8_000)
        XCTAssertTrue(builder.nearMeshes.isEmpty || builder.nearMeshes.values.allSatisfy { mesh in
            !mesh.vertices.contains { $0.y > deck.road + 30 }
        }, "the stays are drawn from any distance")
        let all = builder.meshes.values.flatMap(\.vertices).map { (at: bridge.station(x: $0.x, z: $0.z), y: $0.y) }
        // The mast's top, and its foot in the river.
        let mast = all.filter { abs($0.at.along) < 14 && abs($0.at.across) < 14 }.map(\.y)
        XCTAssertEqual(try XCTUnwrap(mast.max()), deck.road + look.top, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(all.map(\.y).max()), deck.road + look.top, accuracy: 0.5)
        XCTAssertLessThan(try XCTUnwrap(mast.min()), 4)
        // The farthest stay each way: by the road at its anchorage, both
        // planes, and half way up half way along.
        for anchor in [look.mainAnchors.upperBound, -look.backAnchors.upperBound] {
            let here = try XCTUnwrap(builder.suspendedDeck(bridge, at: anchor))
            for side in [Float(-1), 1] {
                XCTAssertTrue(all.contains { abs($0.at.along - anchor) < 1 && abs($0.at.across - side * look.plane.deck) < 1 && abs($0.y - here.road - Map3DCableStays.anchorRise) < 1 },
                              "the stay anchored at \(anchor), side \(side)")
            }
        }
        let half = look.mainAnchors.upperBound / 2
        XCTAssertTrue(all.contains { abs($0.at.along - half) < 13 && abs($0.at.across) < 5 && abs($0.y - deck.road - look.holds.upperBound / 2) < 8 })
        // One deck between the carriageways, a little under the road.
        let amid = all.filter { abs($0.at.along - 200) < 13 && abs($0.at.across) < 2 && abs($0.y - deck.road) < 0.5 }
        XCTAssertFalse(amid.isEmpty, "the deck's middle")
        XCTAssertTrue(amid.allSatisfy { $0.y < deck.road }, "under the road's top")
        // Under the spans, clear of the mast, nothing reaches down to the
        // water: no pier of the road's.
        let under = all.filter { $0.at.along > -165 && $0.at.along < bridge.span - 10 && abs($0.at.along) > 20 && abs($0.at.across) < Bridge.corridor
            && $0.y < deck.road - 8 && $0.y > 0.5 }
        XCTAssertTrue(under.isEmpty, "\(under.count) vertices under the spans")
        print("Map3DCableStayedBridgeTests: 淡江大橋 road \(deck.road) m, carriageways \(deck.left)…\(deck.right) m, \(added) triangles")
    }

    /// A chunk built apart draws what the whole scene does: a scene round
    /// the middle of the main span, the mast not in it, holds its stays
    /// where the whole scene draws them.
    func testASceneAmidTheSpanHoldsItsStays() throws {
        var (whole, bridge) = try scene()
        whole.addSuspensionBridges()
        var (part, _) = try scene(station: 225, reach: 160)
        part.addSuspensionBridges()
        let road = try XCTUnwrap(whole.suspendedDeck(bridge, at: 225)).road
        func stays(_ builder: Map3DScene.Builder) -> [Float] {
            builder.meshes.values.flatMap(\.vertices).filter { $0.y > road + 3 && abs(bridge.station(x: $0.x, z: $0.z).along - 225) < 60 }
                .map { ($0.y * 100).rounded() / 100 }.sorted()
        }
        XCTAssertGreaterThan(stays(part).count, 100)
        XCTAssertEqual(stays(part), stays(whole))
        // And not the mast.
        XCTAssertLessThan(try XCTUnwrap(part.meshes.values.flatMap(\.vertices).map(\.y).max()), road + Map3DCableStays.danjiang.top - 10)
    }

    /// Without the base map's road there is no deck, so no bridge; and
    /// none on Hong Kong's map, as 青馬大橋 is not on Taiwan's.
    func testNoBridgeWithoutItsRoadOrOffItsMap() throws {
        var (builder, _) = try scene(road: false)
        builder.addSuspensionBridges()
        XCTAssertTrue(builder.meshes.isEmpty)
        XCTAssertEqual(builder.suspensionBridges().map(\.bridge.towers.first?.latitude), [Bridge.danjiang.towers[0].latitude])
        let world = GameWorld.newOverseasGame(try HongKongBaseMapTests.ground())
        var hongKong = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        XCTAssertFalse(hongKong.suspensionBridges().contains { $0.bridge.stays != nil })
    }
}
