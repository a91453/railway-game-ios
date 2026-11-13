import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 725: the Taipei temples from the city's religious buildings'
/// 3D models, their files in the app and where the scene stands them.
final class Map3DTaipeiTemplesTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static var files: [Map3DTaipeiTemple: URL] {
        Dictionary(uniqueKeysWithValues: Map3DTaipeiTemple.allCases.map { temple in
            (temple, root.appendingPathComponent("RailwayGameApp/Resources/Models/\(temple.fileName).\(Map3DTaipeiTemple.fileExtension)"))
        })
    }

    static let models = Map3DTaipeiTemple.models(files: files)

    /// The colours `tools/tpe-temples/recipes.mjs` paints the parts in,
    /// after taking them toward decision 720's paving (`soften`).
    static let palette: Set<UInt32> = Set([0xCDA38C, 0xADB1B5, 0xA2B6A8, 0xDDC694, 0x98B4A5, 0xC78774, 0xECE6DE, 0xDFBDB0, 0xB48075,
                                           0x978078, 0xC8C4BD, 0xDDD8CF, 0xB5B4AD, 0xD7A9A0, 0xBD7E74, 0xC8AA9C, 0x9F8A82, 0x837671,
                                           0x5C5855, 0xE1DCD1, 0xC7C4BE].map(Map3DColor.rgb))

    /// Each file reads, within the budget, untextured, credited to the
    /// dataset, a temple's size, its ground at 0 and in the game's colours.
    func testEachFileIsATempleInTheGamesColours() throws {
        XCTAssertEqual(Set(Self.models.keys), Set(Map3DTaipeiTemple.allCases))
        for temple in Map3DTaipeiTemple.allCases {
            let data = try Data(contentsOf: try XCTUnwrap(Self.files[temple]))
            let file = try Map3DModelFile(decoding: data, named: temple.fileName)
            XCTAssertTrue(file.provenance.contains("https://data.gov.tw/dataset/121136"), "\(temple)")
            XCTAssertTrue(file.provenance.contains("Open Government Data License"), "\(temple)")
            let model = file.model
            XCTAssertNil(model.texture)
            XCTAssertLessThanOrEqual(model.triangleCount, 6_000, "\(temple)")
            XCTAssertGreaterThan(model.triangleCount, 500, "\(temple)")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.01, "\(temple): its ground at 0")
            XCTAssertTrue((8...35).contains(model.maximum.z), "\(temple): \(model.maximum.z) m tall")
            XCTAssertLessThan(max(model.maximum.x - model.minimum.x, model.maximum.y - model.minimum.y), 100, "\(temple)")
            // The KMZ's point lies within 30 m of the model.
            XCTAssertLessThan(model.minimum.x, 30, "\(temple)")
            XCTAssertGreaterThan(model.maximum.x, -30, "\(temple)")
            XCTAssertLessThan(model.minimum.y, 30, "\(temple)")
            XCTAssertGreaterThan(model.maximum.y, -30, "\(temple)")
            let colours = Set(model.vertices.map(\.color))
            XCTAssertTrue(colours.isSubset(of: Self.palette), "\(temple): \(colours.subtracting(Self.palette))")
        }
    }

    /// Placed, its axes turn to the scene's (east, up, south), and from
    /// afar only its upward faces are drawn.
    func testPlacingTurnsTheAxesAndTheFarModelKeepsTheRoofs() throws {
        let model = try XCTUnwrap(Self.models[.longshan])
        let near = Map3DTaipeiTemple.placed(model, origin: Map3DPoint(100, 0, 200), ground: 5, roofOnly: false)
        let far = Map3DTaipeiTemple.placed(model, origin: Map3DPoint(100, 0, 200), ground: 5, roofOnly: true)
        XCTAssertEqual(near.vertices.count, model.vertices.count)
        let first = model.vertices[0], placed = near.vertices[0]
        XCTAssertEqual(placed.x, first.x + 100, accuracy: 1e-4)
        XCTAssertEqual(placed.y, first.z + 5, accuracy: 1e-4)
        XCTAssertEqual(placed.z, -first.y + 200, accuracy: 1e-4)
        XCTAssertGreaterThan(far.vertices.count, 0)
        XCTAssertLessThan(far.vertices.count, near.vertices.count / 2)
        XCTAssertTrue(far.vertices.allSatisfy { $0.ny >= 0.3 })
    }

    /// A new game at Longshan Temple stands the temples its scene holds,
    /// near and far, their colours kept, and the kit's temple (decision
    /// 331) finds no room on their ground.
    func testTheSceneStandsThemAndNoKitTempleOnThem() throws {
        let longshan = Map3DTaipeiTemple.longshan
        let world = GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: longshan.latitude, longitudeDegrees: longshan.longitude)!)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        var builder = Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
        var temples = RealTemples(temples: [.init(latitude: longshan.latitude, longitude: longshan.longitude, size: .large)])
        temples.landmarks = Self.models
        let cleared = builder.addTaipeiTemples(temples, frame: frame)
        XCTAssertFalse(cleared.isEmpty)
        let near = builder.nearMeshes.values.reduce(0) { $0 + $1.indices.count / 3 }
        XCTAssertGreaterThanOrEqual(near, try XCTUnwrap(Self.models[.longshan]).triangleCount)
        XCTAssertGreaterThan(builder.farMeshes.values.reduce(0) { $0 + $1.indices.count / 3 }, 0)
        XCTAssertTrue(Set(try XCTUnwrap(Self.models[.longshan]).vertices.map(\.color)).isSubset(of: builder.keptColours))
        XCTAssertTrue(builder.addTemples(temples, frame: frame, clearOf: cleared).isEmpty)
        // Without the models, nothing.
        var plain = Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
        XCTAssertTrue(plain.addTaipeiTemples(RealTemples(temples: []), frame: frame).isEmpty)
        XCTAssertTrue(plain.nearMeshes.isEmpty)
    }
}
