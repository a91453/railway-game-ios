import XCTest
@testable import GamePresentation

/// Decision 840: the studio's reindeer decode, near and far, stand on the
/// ground, and only the sleigh's lamps glow.
final class Map3DReindeerTests: XCTestCase {
    func testEveryUnitDecodesNearAndFarWithinItsBudget() throws {
        let budget: [Map3DReindeer.Unit: (near: Int, far: Int)] = [
            .sleigh: (8_000, 2_000), .standing: (1_000, 250), .grazing: (1_000, 250), .sledRide: (2_500, 600),
        ]
        for unit in Map3DReindeer.Unit.allCases {
            let near = try XCTUnwrap(Map3DReindeer.model(unit), "\(unit)")
            let far = try XCTUnwrap(Map3DReindeer.model(unit, far: true), "\(unit) far")
            let limit = try XCTUnwrap(budget[unit])
            XCTAssertLessThanOrEqual(near.triangleCount, limit.near, "\(unit)")
            XCTAssertLessThanOrEqual(far.triangleCount, limit.far, "\(unit)")
            XCTAssertLessThan(far.triangleCount, near.triangleCount, "\(unit)")
        }
    }

    func testTheGroundReindeerStandOnTheGroundFacingPlusX() throws {
        for unit in [Map3DReindeer.Unit.standing, .grazing, .sledRide] {
            let model = try XCTUnwrap(Map3DReindeer.model(unit))
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.05, "\(unit)")
            XCTAssertGreaterThan(model.maximum.x - model.minimum.x, model.maximum.y - model.minimum.y, "\(unit)")
            XCTAssertFalse(model.vertices.contains { $0.layer == Map3DVertex.glowing }, "\(unit)")
        }
    }

    func testTheSleighIsTheSantaFlightModel() throws {
        let model = try XCTUnwrap(Map3DReindeer.model(.sleigh))
        XCTAssertEqual(model.name, SantaFlight.Model.name)
        XCTAssertEqual(model.maximum.x - model.minimum.x, SantaFlight.Model.length, accuracy: 0.05)
        XCTAssertEqual(model.maximum.z - model.minimum.z, SantaFlight.Model.height, accuracy: 0.05)
        XCTAssertTrue(model.vertices.contains { $0.layer == Map3DVertex.glowing && $0.color == Map3DPalette.lantern })
    }
}
