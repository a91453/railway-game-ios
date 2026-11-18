import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 869 (TSINGMA-TOWERS): 青馬大橋 was two rows of piers across the
/// strait. Its towers stand where the Lands Department surveyed them, the
/// main cables run over them down to the deck, hangers carry the deck,
/// and no pier stands under what the cables carry.
final class Map3DSuspensionBridgeTests: XCTestCase {
    private typealias Bridge = Map3DSuspensionBridge

    /// Hong Kong's world, a scene `reach` metres round the point `station`
    /// metres along 青馬大橋 from 馬灣's tower, with the map pack's base
    /// map (its roads and their bridges) when `road`.
    private func scene(station: Float? = nil, reach: Double = 1_900, road: Bool = true) throws -> (builder: Map3DScene.Builder, bridge: Bridge.Placed) {
        let world = GameWorld.newOverseasGame(try HongKongBaseMapTests.ground())
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let towers = Bridge.tsingMa.towers.map { frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude) }
        let origin = (x: (towers[0].x + towers[1].x) / 2, y: (towers[0].y + towers[1].y) / 2)
        let placed = try XCTUnwrap(Bridge.tsingMa.placed(frame: frame, origin: origin))
        let middle = placed.point(along: station ?? placed.span / 2, across: 0)
        let at = (x: origin.x + Double(middle.x) * metre, y: origin.y + Double(middle.z) * metre)
        let region = WorldRegion(minX: at.x - reach * metre, minY: at.y - reach * metre, maxX: at.x + reach * metre, maxY: at.y + reach * metre)
        var builder = Map3DScene.Builder(originX: origin.x, originY: origin.y, region: region, world: world, heights: nil)
        if road {
            _ = builder.addBaseMap(Map3DBaseMap(tiles: try HongKongBaseMapTests.tiles(), frame: frame, region: region, originX: origin.x, originY: origin.y))
        }
        return (builder, placed)
    }

    /// The towers 1,377 m apart, as surveyed.
    func testTheTowersStandAsSurveyed() throws {
        let (_, bridge) = try scene(road: false)
        XCTAssertEqual(bridge.span, 1_377, accuracy: 3)
        XCTAssertEqual(bridge.ends, -355...bridge.span + 300)
        // 馬灣's side span hangs from the cables, 青衣's stands on piers.
        XCTAssertEqual(bridge.hung, -355...bridge.span)
    }

    /// The cables: over the saddles at the towers, down by the road at
    /// the middle of the main span and at the anchorages, with no step
    /// between a hanger and the next, a tenth of the span and more their
    /// sag.
    func testTheCablesHangBetweenTheSaddles() throws {
        let (_, bridge) = try scene(road: false)
        XCTAssertEqual(bridge.cableHeight(at: 0), Bridge.saddle, accuracy: 0.01)
        XCTAssertEqual(bridge.cableHeight(at: bridge.span), Bridge.saddle, accuracy: 0.01)
        XCTAssertEqual(bridge.cableHeight(at: bridge.span / 2), Bridge.cableLow, accuracy: 0.01)
        XCTAssertEqual(bridge.cableHeight(at: -355), 1, accuracy: 0.01)
        XCTAssertEqual(bridge.cableHeight(at: bridge.span + 300), 1, accuracy: 0.01)
        XCTAssertEqual((Bridge.saddle - Bridge.cableLow) / bridge.span, 1 / 11, accuracy: 0.005)
        var s = bridge.ends.lowerBound
        while s < bridge.ends.upperBound {
            let here = bridge.cableHeight(at: s), next = bridge.cableHeight(at: min(s + 1, bridge.ends.upperBound))
            XCTAssertLessThan(abs(next - here), 0.5, "at \(s)")
            // Under the straight line from the saddle, never under the road.
            XCTAssertGreaterThanOrEqual(here, 1 - 0.01, "at \(s)")
            XCTAssertLessThanOrEqual(here, Bridge.saddle + 0.01, "at \(s)")
            s += 1
        }
    }

    /// No pier under the deck the cables carry; 青衣's side span and the
    /// roads beside the bridge keep theirs.
    func testNoPierStandsUnderWhatTheCablesCarry() throws {
        let (_, bridge) = try scene(road: false)
        let middle = bridge.point(along: bridge.span / 2, across: 12), side = bridge.point(along: -200, across: -12)
        XCTAssertTrue(bridge.carries(x: middle.x, z: middle.z))
        XCTAssertTrue(bridge.carries(x: side.x, z: side.z))
        let standing = bridge.point(along: bridge.span + 150, across: 0), beside = bridge.point(along: 400, across: 45)
        XCTAssertFalse(bridge.carries(x: standing.x, z: standing.z))
        XCTAssertFalse(bridge.carries(x: beside.x, z: beside.z))
        // The fairing stops short of the towers' legs, and where the deck
        // stands on piers.
        XCTAssertEqual(bridge.fairing(from: -18, to: 0), [-18...(-Bridge.fairingGap)])
        XCTAssertEqual(bridge.fairing(from: 0, to: 18), [Bridge.fairingGap...18])
        XCTAssertEqual(bridge.fairing(from: 36, to: 54), [36...54])
        XCTAssertEqual(bridge.fairing(from: bridge.span + 20, to: bridge.span + 38), [])
    }

    /// On the map: both towers as high over the road as surveyed, the
    /// cables from one anchorage to the other, hangers near, and under the
    /// main span nothing down to the sea.
    func testOnHongKongsMap() throws {
        var (builder, bridge) = try scene()
        let deck = try XCTUnwrap(builder.suspendedDeck(bridge, at: 0))
        XCTAssertGreaterThan(deck.road, 5)
        XCTAssertLessThan(deck.left, -5)
        XCTAssertGreaterThan(deck.right, 5)
        // A road bridge all the way between the anchorages, at one height.
        for station in bridge.marks {
            XCTAssertEqual(try XCTUnwrap(builder.suspendedDeck(bridge, at: station), "at \(station)").road, deck.road, accuracy: 0.5, "at \(station)")
        }
        let before = builder.meshes.values.reduce(0) { $0 + $1.indices.count }
        builder.addSuspensionBridges()
        let all = builder.meshes.values.flatMap(\.vertices)
        XCTAssertGreaterThan(builder.meshes.values.reduce(0) { $0 + $1.indices.count }, before)
        // The housing over each saddle, 135.9 m over the road.
        let top = try XCTUnwrap(all.map(\.y).max())
        XCTAssertEqual(top, deck.road + 135.9, accuracy: 1)
        for station in [Float(0), bridge.span] {
            // Astride the road as it is drawn: a leg each side of its
            // middle, clear of its edges.
            let here = try XCTUnwrap(builder.suspendedDeck(bridge, at: station))
            XCTAssertLessThanOrEqual(abs(here.middle), Bridge.mostOff)
            XCTAssertLessThanOrEqual(here.right - here.middle, Bridge.legOffset - Bridge.legSections[0].across)
            XCTAssertLessThanOrEqual(here.middle - here.left, Bridge.legOffset - Bridge.legSections[0].across)
            let leg = bridge.point(along: station, across: here.middle + Bridge.legOffset)
            let heights = all.filter { abs($0.x - leg.x) < 10 && abs($0.z - leg.z) < 10 }.map(\.y)
            XCTAssertEqual(try XCTUnwrap(heights.max()), deck.road + 135.9, accuracy: 1.5, "tower at \(station)")
            XCTAssertLessThan(try XCTUnwrap(heights.min()), 6, "its foot at \(station)")
        }
        // The cables over the middle of the main span, a little over the
        // road, over the legs each side of its middle; the fairing out to the
        // deck's edge.
        let half = try XCTUnwrap(builder.suspendedDeck(bridge, at: bridge.span / 2))
        let amid = all.filter { $0.y > half.road - 6 && abs(bridge.station(x: $0.x, z: $0.z).along - bridge.span / 2) < 12 && abs(bridge.station(x: $0.x, z: $0.z).across) < Bridge.corridor }
            .map { (across: bridge.station(x: $0.x, z: $0.z).across - half.middle, y: $0.y) }
        for side in [Float(-1), 1] {
            XCTAssertTrue(amid.contains { abs($0.across - side * Bridge.legOffset) < 1 && abs($0.y - half.road - Bridge.cableLow) < 1.2 }, "the cable, side \(side)")
            XCTAssertEqual(try XCTUnwrap(amid.map { side * $0.across }.max()), Bridge.deckHalf, accuracy: 0.3, "the fairing, side \(side)")
        }
        // Under the main span, clear of the towers, nothing reaches down
        // to the water: no pier of the road's.
        let under = all.filter { vertex in
            let at = bridge.station(x: vertex.x, z: vertex.z)
            return at.along > 40 && at.along < bridge.span - 40 && abs(at.across) < Bridge.corridor && vertex.y < deck.road - 8 && vertex.y > 0.5
        }
        XCTAssertTrue(under.isEmpty, "\(under.count) vertices under the main span")
        // 青衣's side span on its piers.
        let standing = all.filter { vertex in
            let at = bridge.station(x: vertex.x, z: vertex.z)
            return at.along > bridge.span + 30 && at.along < bridge.span + 270 && abs(at.across) < 10 && vertex.y < deck.road - 8
        }
        XCTAssertFalse(standing.isEmpty)
        // Hangers near only: two a station along the main span and 馬灣's
        // side span.
        let hangers = builder.nearMeshes.values.reduce(0) { $0 + $1.indices.count / 3 }
        XCTAssertGreaterThan(hangers, 2 * 8 * 80)
        XCTAssertLessThan(builder.meshes.values.reduce(0) { $0 + $1.indices.count / 3 } - before / 3, 12_000)
    }

    /// A chunk built apart draws what the whole scene does: a scene round
    /// the middle of the main span, neither tower in it, holds its cables
    /// at the height the whole scene draws them.
    func testASceneAmidTheSpanHoldsItsCables() throws {
        var (whole, bridge) = try scene()
        whole.addSuspensionBridges()
        var (part, _) = try scene(station: bridge.span / 2, reach: 256)
        part.addSuspensionBridges()
        func cables(_ builder: Map3DScene.Builder) -> [Float] {
            builder.meshes.values.flatMap(\.vertices).filter { $0.y > 20 && abs(bridge.station(x: $0.x, z: $0.z).along - bridge.span / 2) < 100 }
                .map { ($0.y * 100).rounded() / 100 }.sorted()
        }
        XCTAssertFalse(cables(part).isEmpty)
        XCTAssertEqual(cables(part), cables(whole))
    }

    /// A scene round one tower holds that tower and not the other.
    func testASceneRoundOneTowerHoldsThatTower() throws {
        var (builder, bridge) = try scene(station: -100, reach: 300)
        builder.addSuspensionBridges()
        let all = builder.meshes.values.flatMap(\.vertices)
        let stations = all.filter { $0.y > 60 }.map { bridge.station(x: $0.x, z: $0.z).along }
        XCTAssertFalse(stations.isEmpty)
        XCTAssertLessThan(try XCTUnwrap(stations.max()), 320)
        XCTAssertGreaterThan(try XCTUnwrap(stations.min()), -420)
    }

    /// Without the base map's road there is no deck to hang, so no bridge;
    /// and none on Taiwan's map.
    func testNoBridgeWithoutItsRoadOrOffItsMap() throws {
        var (builder, _) = try scene(road: false)
        builder.addSuspensionBridges()
        XCTAssertTrue(builder.meshes.isEmpty)
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        var taiwan = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        // (Taiwan's own, decision 873, is a cable-stayed bridge.)
        XCTAssertFalse(taiwan.suspensionBridges().contains { $0.bridge.stays == nil })
        XCTAssertFalse(taiwan.hangsFromCables(x: 100, z: 100))
    }
}
