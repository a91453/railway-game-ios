@testable import GamePresentation
import XCTest

/// Decision 903: the local studio's Taiwan street light, pole and signals.
final class Map3DTaiwanStreetTests: XCTestCase {
    func testTheStudiosModelsAreTheProps() throws {
        for prop in [Map3DProp.lamp, .pole, .signalGo, .signalStop, .signalAmber] {
            let model = try XCTUnwrap(Map3DTaiwanStreet.model(prop), "\(prop)")
            XCTAssertEqual(model.name, prop.modelName)
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.01, "\(prop) stands on the ground")
        }
        XCTAssertNil(Map3DTaiwanStreet.model(.tree))
    }

    /// The three signals differ only in which light glows; that light
    /// faces the traffic (−x), red nearest the road's middle (+y).
    func testEachSignalLightsOnlyItsOwnLight() throws {
        let models = try [Map3DProp.signalStop, .signalAmber, .signalGo].map { try XCTUnwrap(Map3DTaiwanStreet.model($0)) }
        XCTAssertEqual(Set(models.map { $0.vertices.map { [$0.x, $0.y, $0.z] } }).count, 1, "one shape")
        var reach: [Float] = []
        for model in models {
            let glowing = model.vertices.filter(\.glows)
            XCTAssertEqual(glowing.count, 6 * 3)
            XCTAssertTrue(glowing.allSatisfy { $0.nx < -0.9 }, "toward the traffic")
            reach.append(glowing.map(\.y).reduce(0, +) / Float(glowing.count))
        }
        XCTAssertEqual(reach[0], 3.45, accuracy: 0.05, "red farthest over the road")
        XCTAssertEqual(reach[1], 3.05, accuracy: 0.05)
        XCTAssertEqual(reach[2], 2.65, accuracy: 0.05)
    }

    func testThePolesTransformerHangsAwayFromTheRoad() throws {
        let pole = try XCTUnwrap(Map3DTaiwanStreet.model(.pole))
        let transformer = pole.vertices.filter { $0.color == Map3DPalette.cityRoofs[1].color }
        XCTAssertFalse(transformer.isEmpty)
        XCTAssertLessThan(transformer.map(\.y).reduce(0, +) / Float(transformer.count), -0.3)
        XCTAssertFalse(pole.vertices.contains(where: \.glows))
    }
}
