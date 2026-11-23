import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 944: 關渡大橋's red arches stand over the Tamsui River and
/// the base map's road crosses on their deck, 16 m over the water, as
/// decision 873 lifts 淡江大橋's.
final class Map3DGuanduBridgeTests: XCTestCase {
    private static let tiles = Result {
        try BaseMapTiles(data: Data(contentsOf: Map3DTrenchTests.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                    options: .alwaysMapped))
    }

    /// A game at the bridge, a scene `reach` metres round the point
    /// `station` metres along it from its middle, with the app's base map.
    private func scene(station: Float = 0, reach: Double = 900) throws -> (builder: Map3DScene.Builder, bridge: Map3DArchBridgeDeck.Placed) {
        let deck = Map3DGuanduBridge.deck
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: deck.latitude, longitudeDegrees: deck.longitude)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let origin = frame.worldPosition(latitude: deck.latitude, longitude: deck.longitude)
        let placed = try XCTUnwrap(deck.placed(frame: frame, origin: origin))
        let middle = placed.point(along: station)
        let at = (x: origin.x + Double(middle.x) * metre, y: origin.y + Double(middle.z) * metre)
        let region = WorldRegion(minX: at.x - reach * metre, minY: at.y - reach * metre, maxX: at.x + reach * metre, maxY: at.y + reach * metre)
        var builder = Map3DScene.Builder(originX: origin.x, originY: origin.y, region: region, world: world, heights: nil)
        _ = builder.addBaseMap(Map3DBaseMap(tiles: try Self.tiles.get(), frame: frame, region: region, originX: origin.x, originY: origin.y))
        return (builder, placed)
    }

    /// The highest road top across the bridge `station` metres along it,
    /// metres over the water at its middle; nil where no road bridge is.
    private func road(_ builder: inout Map3DScene.Builder, _ bridge: Map3DArchBridgeDeck.Placed, at station: Float) -> Float? {
        let water = builder.drawnGround(x: bridge.middle.x, z: bridge.middle.z)
        var top: Float?
        var offset: Float = -20
        while offset <= 20 {
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

    /// Along the arches the road stands just over the model's deck (16 m
    /// over the water, plus the road's own lift), and the model stands
    /// there on the water.
    func testTheRoadCrossesOnTheArches() throws {
        var (builder, bridge) = try scene()
        XCTAssertEqual(bridge.along.x, Float(sin(57.8 * Double.pi / 180)), accuracy: 0.02)
        var station: Float = -260
        while station <= 260 {
            let top = try XCTUnwrap(road(&builder, bridge, at: station), "a road bridge \(station) m along")
            // The road's top is this plus its kind's lift (0.28–0.36 m).
            XCTAssertEqual(top, 16 + Map3DArchBridgeDeck.roadOver - 0.32, accuracy: 0.1, "\(station) m along")
            XCTAssertTrue(builder.standsOnArchBridge(x: bridge.point(along: station).x, z: bridge.point(along: station).z))
            station += 20
        }
        let frame = try XCTUnwrap(RealWorldFrame(world: builder.world))
        XCTAssertTrue(builder.addHongKongLandmarks(frame: frame).contains("tw-guandu-bridge"))
    }

    /// A scene built round one end of the bridge finds the road at the
    /// height the whole one does.
    func testASceneBuiltApartFindsTheSameDeck() throws {
        var (whole, bridge) = try scene()
        var (apart, _) = try scene(station: 400, reach: 300)
        for station: Float in [150, 200, 250] {
            let a = try XCTUnwrap(road(&whole, bridge, at: station)), b = try XCTUnwrap(road(&apart, bridge, at: station))
            XCTAssertEqual(a, b, accuracy: 0.01, "\(station) m along")
        }
    }
}
