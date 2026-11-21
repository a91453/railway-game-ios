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
