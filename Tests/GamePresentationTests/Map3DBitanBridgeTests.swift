import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1018 (continued 5): 碧潭吊橋 stands over the Xindian River on
/// Taiwan's map, its deck level with the drawn ground at its two ends.
final class Map3DBitanBridgeTests: XCTestCase {
    /// Taiwan's heights, as the app draws its ground.
    private static let heights = Result {
        try HeightGrid(data: Data(contentsOf: BundledRealData.directory.deletingLastPathComponent().appendingPathComponent("RealWorld/taiwan_heights.dat")))
    }

    func testTheDeckMeetsTheBanks() throws {
        let bridge = Map3DBitanBridge.registration
        let deck = try XCTUnwrap(bridge.deck)
        var world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: bridge.latitude, longitudeDegrees: bridge.longitude)))
        // On Taiwan's real ground, as the app opens a new game.
        try world.mapGround()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let at = frame.worldPosition(latitude: bridge.latitude, longitude: bridge.longitude)
        let metre = Double(WorldCoordinate.unitsPerMetre), half = 400.0
        let region = WorldRegion(minX: at.x - half * metre, minY: at.y - half * metre, maxX: at.x + half * metre, maxY: at.y + half * metre)
        var builder = Map3DScene.Builder(originX: at.x, originY: at.y, region: region, world: world, heights: try Self.heights.get())
        let ends = try XCTUnwrap(Map3DScene.Builder.deckEnds(of: bridge.model(full: true), deck: deck))
        // The deck and its abutments' tops, 193 m to 198 m end to end,
        // along 85.3° (east, a little north).
        let length = hypot(ends[0].x - ends[1].x, ends[0].y - ends[1].y)
        XCTAssertEqual(length, 196, accuracy: 3, "the deck's two ends")
        let bearing = atan2(Double(ends[1].x - ends[0].x), Double(ends[1].y - ends[0].y)) * 180 / .pi
        XCTAssertEqual(abs(cos(bearing * .pi / 180)), abs(cos(85.3 * .pi / 180)), accuracy: 0.04, "its line")
        let banks = ends.map { builder.drawnGround(x: $0.x, z: -$0.y) }
        XCTAssertTrue(builder.addHongKongLandmarks(frame: frame).contains(bridge.id))
        let timber = builder.nearMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.timber && hypot($0.x, $0.z) < 120 }
        let top = try XCTUnwrap(timber.map(\.y).max())
        XCTAssertEqual(top, banks.reduce(0, +) / Float(banks.count), accuracy: 0.05, "its deck on the banks' mean")
        for bank in banks { XCTAssertEqual(top, bank, accuracy: 3, "its deck against a bank's ground") }
        // Its foot 7 m under the deck.
        let concrete = builder.nearMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.concrete && hypot($0.x, $0.z) < 120 }
        XCTAssertEqual(try XCTUnwrap(concrete.map(\.y).min()), top - deck, accuracy: 0.05)
        print("Bitan banks \(banks), deck \(top), water \(builder.drawnGround(x: 0, z: 0))")
    }
}
