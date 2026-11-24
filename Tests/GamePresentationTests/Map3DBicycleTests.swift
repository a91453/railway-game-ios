import GameCore
import XCTest
@testable import GamePresentation

/// Decision 918: the bicycles parked by some of the streets' bus stops.
final class Map3DBicycleTests: XCTestCase {
    private typealias Unit = Map3DBicycle.Unit

    /// Each decodes in the game's colours, 1.8 m long with its front
    /// wheel at +x, standing on the ground, as wide as its handlebars;
    /// the ordinary one blue, the public one orange.
    func testEachModelDecodesInTheGamesColours() throws {
        for (unit, frame, triangles) in [(Unit.bicycle, Map3DPalette.trimBlue, 928), (.publicBike, Map3DPalette.temu1000Orange, 924)] {
            let model = try XCTUnwrap(Map3DBicycle.model(unit), "\(unit)")
            XCTAssertEqual(model.triangleCount, triangles, "\(unit)")
            XCTAssertTrue(model.vertices.allSatisfy { Map3DBicycle.palette.contains($0.color) }, "\(unit)")
            XCTAssertTrue(model.vertices.contains { $0.color == frame }, "\(unit)")
            XCTAssertEqual(model.maximum.x - model.minimum.x, 1.8, accuracy: 0.02, "\(unit)")
            XCTAssertEqual(model.maximum.y - model.minimum.y, 0.62, accuracy: 0.02, "\(unit)")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.01, "\(unit)")
            XCTAssertEqual(model.maximum.z, 1.07, accuracy: 0.03, "\(unit)")
            XCTAssertFalse(model.vertices.contains { $0.layer == Map3DVertex.glowing }, "\(unit)")
        }
        XCTAssertFalse(try XCTUnwrap(Map3DBicycle.model(.bicycle)).vertices.contains { $0.color == Map3DPalette.temu1000Orange })
        XCTAssertEqual(Map3DBicycle.drawn.map(\.name), Unit.allCases.map(\.rawValue))
        XCTAssertEqual(Set(Map3DScene.Builder.bicycleModels.keys), Set(Unit.allCases))
    }

    /// Decision 949: by about a third of Taiwan's stops, in a rack on a
    /// wide pavement, clear of each other and of the shelter and vending
    /// machine; none on a narrow one; public ones only where the map has
    /// them, in threes; fewer racks in Hong Kong.
    func testWhereTheyStand() {
        XCTAssertTrue(Map3DBicycle.parked(pavement: 3, region: .taiwan, random: (0.5, 0, 0)).isEmpty)
        XCTAssertTrue(Map3DBicycle.parked(pavement: 1.5, region: .taiwan, random: (0, 0, 0)).isEmpty)
        let dock = Map3DBicycle.parked(pavement: 3, region: .taiwan, random: (0, 0.1, 0.1))
        XCTAssertEqual(dock.map(\.unit), [.publicBike, .publicBike, .publicBike])
        let abroad = Map3DBicycle.parked(pavement: 3, region: .japan, random: (0, 0.1, 0.1))
        XCTAssertEqual(abroad.map(\.unit), [.bicycle, .bicycle])
        XCTAssertEqual(Map3DBicycle.parked(pavement: 3, region: .taiwan, random: (0, 0.9, 0.9)).map(\.unit), [.bicycle, .bicycle, .bicycle])
        XCTAssertTrue(Map3DBicycle.parked(pavement: 3, region: .hongKong, random: (0.2, 0.9, 0.9)).isEmpty)
        XCTAssertFalse(Map3DBicycle.parked(pavement: 3, region: .hongKong, random: (0.05, 0.9, 0.9)).isEmpty)
        for row in [dock, abroad] {
            // Beside the rack's hoops, past the vending machine (3.4 m).
            XCTAssertTrue(row.allSatisfy { $0.across && $0.ahead >= 5 })
            XCTAssertEqual(row.map(\.ahead), Map3DBikeParking.inRack(row.count).map { Map3DBicycle.rackAhead + $0 })
            // The whole bicycle on the pavement.
            XCTAssertTrue(row.allSatisfy { $0.fromBack - 0.9 >= 0 && $0.fromBack + 0.9 <= Map3DBicycle.rowPavement })
        }
        XCTAssertTrue(Map3DStreetRegion.taiwan.hasPublicBicycles)
        XCTAssertFalse(Map3DStreetRegion.hongKong.hasPublicBicycles)
    }
}
