import GameCore
import XCTest
@testable import GamePresentation

/// Decision 923: Japan's utility poles (the owner's old models) and
/// pedestrian signals (the studio's) on Fukuoka's map.
final class Map3DJapanStreetTests: XCTestCase {
    private typealias Unit = Map3DJapanStreet.Unit

    /// Every model decodes in its palette; only a pole's light and a lit
    /// figure glow.
    func testEachModelDecodesInTheGamesColours() throws {
        for unit in Unit.allCases {
            let model = try XCTUnwrap(Map3DJapanStreet.model(unit), "\(unit)")
            let palette = unit.isStudios ? Map3DJapanStreet.studioPalette : Map3DJapanStreet.polePalette
            XCTAssertTrue(model.vertices.allSatisfy { palette.contains($0.color) }, "\(unit)")
            let glowing = Set(model.vertices.filter { $0.layer == Map3DVertex.glowing }.map(\.color))
            switch unit {
            case .poleLamp: XCTAssertEqual(glowing, [Map3DProp.lampLight])
            case .walkStop: XCTAssertEqual(glowing, [Map3DProp.signalLights[0].lit])
            case .walkWalk: XCTAssertEqual(glowing, [Map3DProp.signalLights[2].lit])
            default: XCTAssertTrue(glowing.isEmpty, "\(unit)")
            }
        }
        XCTAssertEqual(Map3DJapanStreet.drawn.map(\.name), Unit.allCases.map(\.rawValue))
    }

    /// The poles stand on the ground, the old sizes (8 to 10 m), the
    /// concrete shaft at the foot and their arms toward the model's left
    /// (the road).
    func testThePolesReachTowardTheRoad() throws {
        let heights: [Unit: Float] = [.pole: 9.97, .poleTransformer: 8.57, .poleTransformers: 9.95, .polePlain: 8.0, .poleLamp: 7.0]
        for (unit, height) in heights {
            let model = try XCTUnwrap(Map3DJapanStreet.model(unit))
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.01, "\(unit)")
            XCTAssertEqual(model.maximum.z, height, accuracy: 0.02, "\(unit)")
            XCTAssertTrue(model.vertices.filter { $0.z < 1 }.allSatisfy { $0.color == Map3DPalette.concrete }, "\(unit)")
        }
        for unit in [Unit.pole, .poleTransformer, .poleTransformers] {
            let model = try XCTUnwrap(Map3DJapanStreet.model(unit))
            XCTAssertGreaterThan(model.maximum.y, 1.2, "\(unit)")
            XCTAssertGreaterThan(model.maximum.y, -model.minimum.y, "\(unit)")
        }
        let lamp = try XCTUnwrap(Map3DJapanStreet.model(.poleLamp))
        let lens = lamp.vertices.filter { $0.color == Map3DProp.lampLight }
        XCTAssertFalse(lens.isEmpty)
        let reach = lens.map(\.y).reduce(0, +) / Float(lens.count)
        XCTAssertEqual(reach, Map3DJapanStreet.lampReach, accuracy: 0.15)
    }

    /// The bus stop is the sign alone on its post, 2.4 m tall, its red
    /// route block on it, nothing lit; Japan's streets stand it.
    func testTheBusStop() throws {
        let stop = try XCTUnwrap(Map3DJapanStreet.model(.busStop))
        XCTAssertEqual(stop.maximum.z, 2.4, accuracy: 0.02)
        XCTAssertEqual(stop.minimum.z, 0, accuracy: 0.01)
        XCTAssertTrue(stop.vertices.contains { $0.color == Map3DScene.Builder.barrierRed })
        XCTAssertFalse(stop.vertices.contains { $0.layer == Map3DVertex.glowing })
        XCTAssertLessThan(stop.maximum.x - stop.minimum.x, 0.5)
        XCTAssertLessThan(stop.maximum.y - stop.minimum.y, 0.5)
    }

    /// The mix picks every pole, the same for the same number.
    func testThePoleMix() {
        var seen = Set<Unit>()
        for step in 0..<200 { seen.insert(Map3DJapanStreet.pole(Float(step) / 200)) }
        XCTAssertEqual(seen, [.pole, .poleTransformer, .poleTransformers, .polePlain, .poleLamp])
        XCTAssertEqual(Map3DJapanStreet.pole(0.999_999), .poleLamp)
        XCTAssertEqual(Map3DJapanStreet.pole(0), .pole)
    }

    /// The pedestrian signals face the model's left, the red figure above
    /// the green, and the pack swaps Japan's faces as the clock says while
    /// other regions keep theirs.
    func testThePedestrianSignalsAreJapans() throws {
        let stop = try XCTUnwrap(Map3DJapanStreet.model(.walkStop))
        func middle(_ color: UInt32) throws -> Map3DPoint {
            let face = stop.vertices.filter { $0.color == color }
            XCTAssertFalse(face.isEmpty)
            let n = Float(face.count)
            return Map3DPoint(face.map(\.x).reduce(0, +) / n, face.map(\.y).reduce(0, +) / n, face.map(\.z).reduce(0, +) / n)
        }
        let red = try middle(Map3DProp.signalLights[0].lit), green = try middle(Map3DProp.signalLights[2].unlit)
        XCTAssertGreaterThan(red.z, green.z)
        XCTAssertGreaterThan(red.y, 0.2)
        let pack = Map3DModelPack.standard
        let models = try XCTUnwrap(Map3DPedestrianSignal.Models(pack: pack))
        let japan = try XCTUnwrap(models.japan)
        XCTAssertEqual(pack.models[japan.stop].name, Unit.walkStop.rawValue)
        XCTAssertEqual(pack.models[japan.dark].name, Unit.walkDark.rawValue)
        XCTAssertEqual(pack.models[japan.walk].name, Unit.walkWalk.rawValue)
        XCTAssertEqual(models.placedPlain(.japan), japan.stop)
        XCTAssertNotEqual(models.placedPlain(.hongKong), japan.stop)
        XCTAssertTrue(models.places(japan.stop))
        var shown = Set<Int>()
        for second in Int64(0)..<Map3DSignalTiming.cycle {
            let clock = Map3DSignalTiming.Clock(GameClock(now: GameTime(seconds: second), speed: .x1), region: .japan)
            if let model = models.model(japan.stop, group: 0, clock: clock, time: Double(second), pace: .init(), reduceMotion: false) {
                shown.insert(model)
            }
        }
        XCTAssertTrue(shown.isSubset(of: [japan.stop, japan.dark, japan.walk]))
        XCTAssertTrue(shown.contains(japan.stop))
        XCTAssertTrue(shown.contains(japan.walk))
        XCTAssertTrue(Map3DStreetRegion.japan.hasJapaneseFurniture)
        XCTAssertFalse(Map3DStreetRegion.taiwan.hasJapaneseFurniture)
        XCTAssertFalse(Map3DStreetRegion.finland.hasJapaneseFurniture)
        for unit in Unit.allCases { XCTAssertNotNil(Map3DScene.Builder.japanModels[unit], "\(unit)") }
    }
}
