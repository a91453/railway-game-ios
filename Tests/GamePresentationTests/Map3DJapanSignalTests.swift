import GameCore
import XCTest
@testable import GamePresentation

/// Decision 921: Japan's traffic signal (``Map3DJapanSignal``), the owner's
/// old model, on Fukuoka's map in place of Taiwan's.
final class Map3DJapanSignalTests: XCTestCase {
    private typealias Unit = Map3DJapanSignal.Unit

    /// Each model decodes in the game's colours, its one lit light
    /// glowing and nothing else.
    func testEachModelLightsItsOwnLamp() throws {
        let lights = Map3DProp.signalLights
        for (unit, index) in zip(Unit.allCases, [0, 1, 2]) {
            let model = try XCTUnwrap(Map3DJapanSignal.model(unit), "\(unit)")
            XCTAssertTrue(model.vertices.allSatisfy { Map3DJapanSignal.meshPalette.contains($0.color) })
            let glowing = Set(model.vertices.filter { $0.layer == Map3DVertex.glowing }.map(\.color))
            XCTAssertEqual(glowing, [lights[index].lit], "\(unit)")
            for (other, light) in lights.enumerated() where other != index {
                XCTAssertTrue(model.vertices.contains { $0.color == light.unlit }, "\(unit)")
                XCTAssertFalse(model.vertices.contains { $0.color == light.lit }, "\(unit)")
            }
        }
        XCTAssertEqual(Map3DJapanSignal.drawn.map(\.name), Unit.allCases.map(\.rawValue))
    }

    /// The lights hang over the lanes at Taiwan's height, looking toward
    /// −x, on an arm reaching toward −y (right of the traffic, Japan keeps
    /// left): green next to the post, red at the arm's end.
    func testTheLightsHangRightOfThePost() throws {
        let model = try XCTUnwrap(Map3DJapanSignal.model(.red))
        func middle(_ color: UInt32) throws -> Map3DPoint {
            let lens = model.vertices.filter { $0.color == color }
            XCTAssertFalse(lens.isEmpty)
            let n = Float(lens.count)
            return Map3DPoint(lens.map(\.x).reduce(0, +) / n, lens.map(\.y).reduce(0, +) / n, lens.map(\.z).reduce(0, +) / n)
        }
        let red = try middle(Map3DProp.signalLights[0].lit), green = try middle(Map3DProp.signalLights[2].unlit)
        XCTAssertEqual(red.z, 5.6, accuracy: 0.05)
        XCTAssertEqual(green.z, 5.6, accuracy: 0.05)
        XCTAssertLessThan(red.y, green.y)
        XCTAssertLessThan(green.y, -1.5)
        XCTAssertLessThan(red.x, -0.15)
        XCTAssertLessThan(model.minimum.z, 0.01)
        XCTAssertGreaterThan(model.maximum.y, -0.3)
    }

    /// The post and the arm are the galvanised grey all over, the head and
    /// the hoods the pale grey: each part takes one colour. Painted one
    /// colour a triangle, two of the post's long triangles and half the
    /// arm came out the housing's dark, and the post showed a black stripe
    /// on the iPhone (2026-11-27).
    func testThePostAndTheArmAreOneGrey() throws {
        for unit in Unit.allCases {
            let model = try XCTUnwrap(Map3DJapanSignal.model(unit))
            // Three vertices a triangle, each with the triangle's colour.
            let triangles = stride(from: 0, to: model.vertices.count, by: 3).map { Array(model.vertices[$0..<$0 + 3]) }
            // The post: a corner below the head, round the foot.
            let post = triangles.filter { $0.contains { $0.z < 5.3 && abs($0.x) < 0.2 && abs($0.y) < 0.2 } }
            // The arm: every corner on the post's line, at the arm's height.
            let arm = triangles.filter { $0.allSatisfy { abs($0.x) < 0.05 && $0.z > 5.5 && $0.z < 5.7 } }
            XCTAssertEqual(post.count, 6, "\(unit)")
            XCTAssertEqual(arm.count, 7, "\(unit)")
            XCTAssertEqual(Set((post + arm).map { $0[0].color }), [Map3DPalette.steel], "\(unit)")
            XCTAssertFalse(model.vertices.contains { $0.color == Map3DPalette.steel && $0.y < -1.9 && $0.x < -0.045 }, "\(unit): the head is the pale grey")
        }
    }

    /// The pack's signal models swap to Japan's lit as the clock says, red
    /// for red and amber together; Taiwan's stay Taiwan's.
    func testTheClockLightsJapansOwn() throws {
        let pack = Map3DModelPack.standard
        let models = try XCTUnwrap(Map3DSignalTiming.Models(pack: pack))
        let japan = try XCTUnwrap(models.japan)
        XCTAssertEqual(pack.models[japan.green].name, Map3DJapanSignal.placedName(.main))
        XCTAssertEqual(pack.models[japan.red].name, Map3DJapanSignal.placedName(.cross))
        XCTAssertEqual(Map3DJapanSignal.modelName(.redAmber), Unit.red.rawValue)
        XCTAssertEqual(models.model(japan.green, group: 0, clock: nil), japan.green)
        XCTAssertEqual(models.model(japan.red, group: 0, clock: nil), japan.red)
        XCTAssertEqual(models.model(models.green, group: 0, clock: nil), models.green)
        var shown = Set<Int>()
        for second in Int64(0)..<Map3DSignalTiming.cycle {
            let clock = Map3DSignalTiming.Clock(GameClock(now: GameTime(seconds: second), speed: .x1), region: .japan)
            shown.insert(models.model(japan.green, group: 0, clock: clock))
            shown.insert(models.model(japan.red, group: 0, clock: clock))
        }
        XCTAssertEqual(shown, [japan.red, japan.amber, japan.green])
        XCTAssertTrue(Map3DStreetRegion.japan.hasJapaneseSignals)
        XCTAssertFalse(Map3DStreetRegion.taiwan.hasJapaneseSignals)
        XCTAssertNotNil(Map3DScene.Builder.japanSignals[.main])
        XCTAssertNotNil(Map3DScene.Builder.japanSignals[.cross])
    }
}
