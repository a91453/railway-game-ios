import XCTest
@testable import GamePresentation

/// Decision 935: the studio's Meshy night market pieces and Tiangong burner.
final class Map3DMeshyMarketTempleTests: XCTestCase {
    /// Each decodes with the studio's triangles and the brief's sizes
    /// (±2 cm), standing on z 0.
    func testTheModels() throws {
        let expected: [Map3DMeshyMarketTemple: (triangles: Int, size: (Float, Float, Float))] = [
            .bulbString: (524, (4.25, 0.25, 2.6)), .canopy: (384, (3.0, 2.0, 2.5)),
            .stallCart: (284, (1.5, 0.7, 1.35)), .tiangongBurner: (510, (0.588, 0.682, 1.6)),
        ]
        for piece in Map3DMeshyMarketTemple.allCases {
            let model = try XCTUnwrap(piece.model, "\(piece)")
            let want = try XCTUnwrap(expected[piece])
            XCTAssertEqual(model.triangleCount, want.triangles, "\(piece)")
            XCTAssertEqual(model.maximum.x - model.minimum.x, want.size.0, accuracy: 0.02, "\(piece)")
            XCTAssertEqual(model.maximum.y - model.minimum.y, want.size.1, accuracy: 0.02, "\(piece)")
            XCTAssertEqual(model.maximum.z - model.minimum.z, want.size.2, accuracy: 0.02, "\(piece)")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.002, "\(piece) on its foot")
            XCTAssertEqual(model.name, "meshy-" + piece.rawValue)
        }
    }

    /// Only the bulbs glow, and only the bulb string has them; every
    /// colour is the palette's.
    func testOnlyTheBulbsGlow() throws {
        let palette = Set(Map3DMeshyMarketTemple.palette)
        for piece in Map3DMeshyMarketTemple.allCases {
            let model = try XCTUnwrap(piece.model)
            let lit = model.vertices.filter { $0.layer == Map3DVertex.glowing }
            XCTAssertTrue(lit.allSatisfy { $0.color == Map3DPalette.tunnelLamp })
            XCTAssertEqual(lit.isEmpty, piece != .bulbString, "\(piece)")
            XCTAssertTrue(model.vertices.allSatisfy { palette.contains($0.color) }, "\(piece)")
        }
    }

    /// The alley's pieces are in the station squares' night market and the
    /// company's own, and the Tiangong burner before every size of temple.
    func testWhereTheyStand() throws {
        let pieces = Map3DMeshyMarketTemple.alleyParts(lift: 0)
        XCTAssertEqual(pieces.count, Map3DMeshyMarketTemple.alley.count)
        let added = pieces.reduce(0) { $0 + $1.model.triangleCount }
        var bare = StationKitBuilder()
        bare.add(Map3DCommercialKit.model(for: .nightMarketAlley), at: .zero)
        let alley = try XCTUnwrap(Map3DScene.Builder.commerceModels.first { $0.example == .nightMarketAlley })
        XCTAssertEqual(alley.model.mesh.indices.count / 3, bare.mesh.indices.count / 3 + added)
        let market = try XCTUnwrap(Map3DScene.Builder.placedKitLayouts[.nightMarket]?.first)
        XCTAssertTrue(market.boxes.allSatisfy { $0.height != Map3DMeshyMarketTemple.bulbString.model!.maximum.z }, "no box for the bulbs")
        // The temple and the shrine: hall (and gate), the Tiangong burner, no kit burner.
        let burner = try XCTUnwrap(Map3DMeshyMarketTemple.tiangongBurner.model).triangleCount
        let kit = { (part: Map3DCivicKit.Part) in Map3DCivicKit.model(for: part).triangleCount }
        let temple = try XCTUnwrap(Map3DScene.Builder.templeModels[.temple]), small = try XCTUnwrap(Map3DScene.Builder.templeModels[.small])
        XCTAssertEqual(temple.triangles, 12 + kit(.templeHall) + kit(.templeGate) + burner)
        XCTAssertEqual(small.triangles, 12 + kit(.templeSideHall) + burner)
        // Every piece within the alley's 26 m by 32 m square.
        for place in Map3DMeshyMarketTemple.alley {
            XCTAssertLessThan(abs(place.x) + 2.2, 13)
            XCTAssertLessThan(abs(place.z) + 2.2, 16)
        }
    }
}
