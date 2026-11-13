import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 721: after dark the city is dim and what is lit shows: the
/// windows, the street lights' pools, and the player's track and trains.
final class Map3DNightTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The numbers written after `name` in `text`, up to the next `;`.
    private func numbers(after name: String, in text: String) -> [Float] {
        guard let start = text.range(of: name) else { return [] }
        let rest = text[start.upperBound...].prefix { $0 != ";" }
        return rest.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Float(String($0)) }
    }

    /// The shader and the preview page work with ``Map3DNight``'s numbers.
    func testTheShaderAndThePreviewHoldTheSameNumbers() throws {
        let metal = try String(contentsOf: Self.root.appendingPathComponent("RailwayGameApp/Views/Map3D/Map3DShaders.metal"), encoding: .utf8)
        let page = try String(contentsOf: Self.root.appendingPathComponent("tools/map3d-preview/index.html"), encoding: .utf8)
        let pool = Map3DNight.roadPool
        let held: [(String, String, [Float])] = [
            ("constant float nightDim =", "const float NIGHT_DIM =", [Map3DNight.dim]),
            ("constant float trackLit =", "const float TRACK_LIT =", [Map3DNight.trackLit]),
            ("constant float stockLit =", "const float STOCK_LIT =", [Map3DNight.stockLit]),
            ("constant float3 roadPool =", "const vec3 ROAD_POOL = vec", [pool.between, pool.middle, pool.spread]),
            ("constant float roadPoolCell =", "const float ROAD_POOL_CELL =", [Map3DNight.roadPoolCell]),
            ("constant float2 nightWindowsMore =", "const vec2 NIGHT_WINDOWS_MORE = vec", [Map3DNight.windowsShare, Map3DNight.windowsLight]),
            ("constant float nightBays =", "const float NIGHT_BAYS =", [Map3DNight.bays]),
            ("constant float2 nightFall =", "const vec2 NIGHT_FALL = vec", [Map3DNight.fall.from, Map3DNight.fall.to]),
        ]
        for (inMetal, inPage, values) in held {
            XCTAssertEqual(numbers(after: inMetal, in: metal), values, "Map3DShaders.metal: \(inMetal)")
            XCTAssertEqual(numbers(after: inPage, in: page).suffix(values.count), values[...], "index.html: \(inPage)")
        }
        // The track bed is told by its ballast's layer.
        XCTAssertEqual(Map3DNight.trackSurface.rawValue, 2)
        XCTAssertTrue(metal.contains("if (packed == 2u) { kept = 1.0;"))
        XCTAssertTrue(page.contains("if (packed == 2) { kept = 1.0;"))
    }

    /// Lit as the shader lights them at full night (a colour times the
    /// night's light, dimmed; or kept, plus its own colour's share), the
    /// ballast is lighter than the ground and a white train lighter than
    /// the ballast, whatever the night's light between a twentieth and
    /// three tenths of the day's.
    func testTheTrackAndItsTrainsAreLighterThanTheGroundAfterDark() {
        func value(_ colour: UInt32) -> Float { Float((colour & 0xFF) + ((colour >> 8) & 0xFF) + ((colour >> 16) & 0xFF)) / 765 }
        for light in stride(from: Float(0.05), through: 0.3, by: 0.05) {
            let ground = max(value(Map3DPalette.ground), value(Map3DPalette.paved), value(Map3DPalette.yard)) * Map3DNight.dim * light
            let track = value(Map3DPalette.ballast) * (light + Map3DNight.trackLit)
            let train = value(Map3DColor.rgb(0xF2F2F2)) * (light + Map3DNight.stockLit)
            XCTAssertGreaterThan(track, ground * 1.8, "the night's light \(light)")
            XCTAssertGreaterThan(train, track * 1.5, "the night's light \(light)")
        }
    }

    /// Night falls on the map within ten minutes of dusk, and has fallen
    /// before the lights are fully on.
    func testNightFallsFast() {
        func fall(_ minute: Double) -> Float {
            let lights = Map3DLighting(minute: minute).lights
            let t = min(max((lights - Map3DNight.fall.from) / (Map3DNight.fall.to - Map3DNight.fall.from), 0), 1)
            return t * t * (3 - 2 * t)
        }
        let minutes = stride(from: 17.0 * 60, through: 19 * 60, by: 1).filter { fall($0) > 0.02 && fall($0) < 0.98 }
        XCTAssertFalse(minutes.isEmpty)
        XCTAssertLessThanOrEqual(minutes.count, 10)
        XCTAssertEqual(fall(14 * 60), 0)
        XCTAssertEqual(fall(21 * 60), 1)
    }

    /// Only a train's cars are marked: the shader reads the mark as the
    /// instance's last float less 1.
    func testOnlyATrainIsMarkedLit() throws {
        let pack = Map3DModelPack.standard
        let model = try XCTUnwrap(pack.modelIndex(forType: "", carIndex: 0, count: 3))
        let car = Map3DTrains.instance(of: pack.models[model], index: model, from: Map3DPoint(0, 0, 0), to: Map3DPoint(20, 0, 0), stripe: Map3DColor.rgb(0x2F6DB5))
        XCTAssertEqual(car.lit, 1)
        XCTAssertEqual(car.floats.count, 20)
        XCTAssertEqual(car.floats[19], 2)
        let other = Map3DInstance(model: 0, transform: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1], stripe: (0, 0, 0))
        XCTAssertEqual(other.floats[19], 1)
    }

    /// A road between two pools keeps a little light and a pool's middle
    /// has the most, as the shader's `map3dRoadPool` gives them.
    func testARoadIsLitInPools() {
        let pool = Map3DNight.roadPool
        XCTAssertLessThan(pool.between, 0.2)
        XCTAssertGreaterThan(pool.between + pool.middle, 1)
        // Six metres from a pool's middle about a quarter of its light is left.
        XCTAssertEqual(exp(-36 / pool.spread), 0.276, accuracy: 0.01)
    }
}
