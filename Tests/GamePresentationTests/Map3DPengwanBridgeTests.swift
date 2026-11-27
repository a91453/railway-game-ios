import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1018 (continued 6): 鵬灣跨海大橋 stands in the mouth of
/// Dapeng Bay on Taiwan's map, its piers sunk under the water, and the
/// base map's two carriageways cross on its deck and come down their
/// approaches to the banks.
final class Map3DPengwanBridgeTests: XCTestCase {
    private static let tiles = Result {
        try BaseMapTiles(data: Data(contentsOf: HongKongBaseMapTests.taiwan, options: .alwaysMapped))
    }
    /// Taiwan's heights, as the app draws its ground.
    private static let heights = Result {
        try HeightGrid(data: Data(contentsOf: BundledRealData.directory.deletingLastPathComponent().appendingPathComponent("RealWorld/taiwan_heights.dat")))
    }

    /// A new game at the bridge on Taiwan's real ground, a scene `reach`
    /// metres round the point `station` metres along it, with the app's
    /// base map.
    private func scene(station: Float = 0, reach: Double = 700) throws -> (builder: Map3DScene.Builder, bridge: Map3DArchBridgeDeck.Placed) {
        let deck = Map3DPengwanBridge.deck
        var world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: deck.latitude, longitudeDegrees: deck.longitude)))
        try world.mapGround()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let origin = frame.worldPosition(latitude: deck.latitude, longitude: deck.longitude)
        let placed = try XCTUnwrap(deck.placed(frame: frame, origin: origin))
        let middle = placed.point(along: station)
        let at = (x: origin.x + Double(middle.x) * metre, y: origin.y + Double(middle.z) * metre)
        let region = WorldRegion(minX: at.x - reach * metre, minY: at.y - reach * metre, maxX: at.x + reach * metre, maxY: at.y + reach * metre)
        var builder = Map3DScene.Builder(originX: origin.x, originY: origin.y, region: region, world: world, heights: try Self.heights.get())
        _ = builder.addBaseMap(Map3DBaseMap(tiles: try Self.tiles.get(), frame: frame, region: region, originX: origin.x, originY: origin.y))
        return (builder, placed)
    }

    /// The highest road top across the bridge `station` metres along it,
    /// metres over the water at its middle; nil where no road bridge is.
    private func road(_ builder: inout Map3DScene.Builder, _ bridge: Map3DArchBridgeDeck.Placed, at station: Float, across: Float = 25) -> Float? {
        let water = builder.drawnGround(x: bridge.middle.x, z: bridge.middle.z)
        var top: Float?
        var offset = -across
        while offset <= across {
            defer { offset += 0.5 }
            let p = bridge.point(along: station) + bridge.across * offset
            let raised = builder.roadRise(at: Map3DBaseMap.Point(x: Double(p.x), z: Double(p.z)),
                                          along: (Double(bridge.along.x), Double(bridge.along.z)), onDeck: true)
            guard raised.onBridge else { continue }
            let here = builder.drawnGround(x: p.x, z: p.z) + raised.rise - water
            top = max(top ?? here, here)
        }
        return top
    }

    /// Along the model the roads stand just over its deck (17.5 m over the
    /// water, plus the roads' own lift), with no pier of their own; past
    /// its ends they come down at their grade, and the model stands on the
    /// water with its piers' feet 5.5 m under it.
    func testTheRoadsCrossOnItsDeck() throws {
        var (builder, bridge) = try scene()
        var station: Float = -110
        while station <= 110 {
            let top = try XCTUnwrap(road(&builder, bridge, at: station), "a road bridge \(station) m along")
            // The road's top is this plus its kind's lift (tertiary's 0.32 m).
            XCTAssertEqual(top, 17.5 + Map3DArchBridgeDeck.roadOver - 0.32, accuracy: 0.15, "\(station) m along")
            XCTAssertTrue(builder.standsOnArchBridge(x: bridge.point(along: station).x, z: bridge.point(along: station).z))
            station += 10
        }
        // Past each end the roads come down their approaches at their
        // grade (6 %, over ground that is not quite level), with no step, to the map's own bridge height.
        for side: Float in [-1, 1] {
            var last = try XCTUnwrap(road(&builder, bridge, at: side * 110, across: 60))
            for step in 12...28 {
                let here = try XCTUnwrap(road(&builder, bridge, at: side * Float(step) * 10, across: 60), "\(side * Float(step) * 10) m along")
                XCTAssertLessThanOrEqual(last - here, 0.7, "\(side * Float(step) * 10) m along")
                XCTAssertGreaterThanOrEqual(last - here, -0.05, "\(side * Float(step) * 10) m along")
                last = here
            }
            XCTAssertLessThan(last, 12, "the approach by \(side * 280) m along")
        }
        let frame = try XCTUnwrap(RealWorldFrame(world: builder.world))
        let water = builder.drawnGround(x: 0, z: 0)
        XCTAssertTrue(builder.addHongKongLandmarks(frame: frame).contains(Map3DPengwanBridge.registration.id))
        let vertices = builder.nearMeshes.values.flatMap(\.vertices).filter { hypot($0.x, $0.z) < 130 }
        let foot = try XCTUnwrap(vertices.filter { $0.color == Map3DPalette.portal }.map(\.y).min())
        XCTAssertEqual(foot, water - Map3DPengwanBridge.registration.sink, accuracy: 0.05, "its piers' feet")
        let tower = try XCTUnwrap(vertices.filter { $0.color == Map3DPalette.tileWhite }.map(\.y).max())
        XCTAssertEqual(tower - water, 72, accuracy: 0.5, "its tower")
    }

    /// A scene built round one end of the bridge finds the roads at the
    /// height the whole one does.
    func testASceneBuiltApartFindsTheSameDeck() throws {
        var (whole, bridge) = try scene()
        var (apart, _) = try scene(station: 350, reach: 300)
        for station: Float in [80, 100, 110] {
            let a = try XCTUnwrap(road(&whole, bridge, at: station)), b = try XCTUnwrap(road(&apart, bridge, at: station))
            XCTAssertEqual(a, b, accuracy: 0.01, "\(station) m along")
        }
    }
}
