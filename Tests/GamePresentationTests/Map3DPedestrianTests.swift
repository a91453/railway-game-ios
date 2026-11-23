import GameCore
import XCTest
@testable import GamePresentation

/// Decision 918: the five more people seen close up.
final class Map3DPedestrianTests: XCTestCase {
    private typealias Kind = Map3DPedestrian.Kind

    /// Each decodes in the game's colours, its own height, standing on
    /// the ground, at most 360 triangles; what marks each is there.
    func testEachModelDecodesInTheGamesColours() throws {
        let heights: [Kind: Float] = [.office: 1.72, .student: 1.60, .elderly: 1.52, .umbrella: 2.05, .traveller: 1.74]
        let marks: [Kind: UInt32] = [.office: Map3DPalette.sidewalk, .student: Map3DPalette.sidewalk, .elderly: Map3DPalette.tankSteel,
                                     .umbrella: Map3DPalette.tankBlue, .traveller: Map3DStreetModel.tyre]
        for kind in Kind.allCases {
            for walking in [false, true] {
                let name = Map3DPedestrian.name(kind, walking: walking)
                let model = try XCTUnwrap(Map3DPedestrian.model(kind, walking: walking), name)
                XCTAssertEqual(model.name, name)
                XCTAssertLessThanOrEqual(model.triangleCount, 360, name)
                XCTAssertTrue(model.vertices.allSatisfy { Map3DPedestrian.palette.contains($0.color) }, name)
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.02, name)
                // Mid-stride a figure is up to 8 cm lower (the student's
                // 1.52 m), as the studio measured them.
                let height = try XCTUnwrap(heights[kind])
                XCTAssertLessThanOrEqual(model.maximum.z, height + 0.02, name)
                XCTAssertGreaterThanOrEqual(model.maximum.z, height - (walking ? 0.09 : 0.02), name)
                XCTAssertTrue(model.vertices.contains { $0.color == Map3DStreetModel.skin }, name)
                XCTAssertTrue(model.vertices.contains { $0.color == marks[kind] }, name)
                XCTAssertFalse(model.vertices.contains { $0.layer == Map3DVertex.glowing }, name)
                // No wider than a person with a bag or an umbrella.
                XCTAssertLessThan(model.maximum.y - model.minimum.y, 1.3, name)
            }
            // Mid-stride, the feet are apart along the way it faces.
            let standing = try XCTUnwrap(Map3DPedestrian.model(kind, walking: false)), walking = try XCTUnwrap(Map3DPedestrian.model(kind, walking: true))
            let feet = { (model: Map3DModelPack.Model) -> Float in
                let low = model.vertices.filter { $0.z < 0.12 }.map(\.x)
                return (low.max() ?? 0) - (low.min() ?? 0)
            }
            if kind != .traveller { XCTAssertGreaterThan(feet(walking), feet(standing) + 0.1, "\(kind)") }
        }
        XCTAssertEqual(Map3DPedestrian.drawn.count, 10)
        XCTAssertEqual(Set(Map3DStreetLife.pedestrianModels.keys), Set(Map3DPedestrian.drawn.map(\.name)))
    }

    /// The elder, the umbrella's holder and the traveller wear the
    /// instance's colour; the office worker's and the student's shirts
    /// stay white.
    func testWhoWearsTheInstancesColour() throws {
        for kind in Kind.allCases {
            let model = try XCTUnwrap(Map3DPedestrian.model(kind, walking: false))
            let tinted = model.vertices.contains { $0.color >> 24 == 0 }
            XCTAssertEqual(tinted, kind != .office && kind != .student, "\(kind)")
        }
    }

    /// Every one of the six stands among the people, the commuter a
    /// quarter of them, the same for the same number.
    func testTheMix() {
        var seen: [Kind?: Int] = [:]
        for step in 0..<1_200 { seen[Map3DPedestrian.kind(Float(step) / 1_200), default: 0] += 1 }
        XCTAssertEqual(seen[nil], 300)
        XCTAssertEqual(seen[.office], 300)
        XCTAssertEqual(seen[.student], 200)
        XCTAssertEqual(seen[.elderly], 200)
        XCTAssertEqual(seen[.traveller], 100)
        XCTAssertEqual(seen[.umbrella], 100)
        XCTAssertNil(Map3DPedestrian.kind(1))
        XCTAssertEqual(Map3DPedestrian.kind(0), .office)
    }
}
