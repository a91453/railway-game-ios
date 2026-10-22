import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 357: the sun's shadow map, worked out without a GPU: which
/// quality draws it, the square it covers, how the sun sees it, when it is
/// drawn again, and the numbers the shaders and the Metal view keep.
final class Map3DSunShadowTests: XCTestCase {
    private static let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp/Views/Map3D")

    /// Saving draws none, and Automatic none when it saves; a GPU over its
    /// budget (or High on a phone about to slow down) draws a smaller map
    /// less often.
    func testWhichQualityDrawsTheSunsShadows() {
        let full = Map3DSunShadow.Plan(size: 2_048, interval: 0.25), lowered = Map3DSunShadow.Plan(size: 1_024, interval: 1)
        for heat in [Map3DQuality.Heat.nominal, .critical] {
            XCTAssertNil(Map3DSunShadow.plan(.saving, lowPower: false, heat: heat, overBudget: false))
        }
        XCTAssertEqual(Map3DSunShadow.plan(.automatic, lowPower: false, heat: .fair, overBudget: false), full)
        XCTAssertEqual(Map3DSunShadow.plan(.automatic, lowPower: false, heat: .nominal, overBudget: true), lowered)
        XCTAssertNil(Map3DSunShadow.plan(.automatic, lowPower: true, heat: .nominal, overBudget: false))
        XCTAssertNil(Map3DSunShadow.plan(.automatic, lowPower: false, heat: .serious, overBudget: false))
        XCTAssertEqual(Map3DSunShadow.plan(.high, lowPower: true, heat: .serious, overBudget: true), full)
        XCTAssertEqual(Map3DSunShadow.plan(.high, lowPower: false, heat: .critical, overBudget: false), lowered)
    }

    /// The square grows with the camera's distance in steps of 1.3, from
    /// 220 m half a side; out past 4 km there are none.
    func testTheSquareGrowsInSteps() {
        XCTAssertEqual(Map3DSunShadow.extent(distance: 60), 220)
        XCTAssertEqual(Map3DSunShadow.extent(distance: 200), 220)
        XCTAssertEqual(Map3DSunShadow.extent(distance: 210), 220 * 1.3, accuracy: 0.01)
        // The map's usual 800 m view: 880 m wanted, 1,062 m given.
        XCTAssertEqual(Map3DSunShadow.extent(distance: 800), 220 * powf(1.3, 6), accuracy: 0.1)
        var last: Float = 0
        for distance in stride(from: Float(60), through: 4_000, by: 10) {
            let extent = Map3DSunShadow.extent(distance: distance)
            XCTAssertGreaterThanOrEqual(extent, last)
            XCTAssertGreaterThanOrEqual(extent, min(distance * 1.1, 1_800) - 0.01, "covers what the camera sees round its target")
            last = extent
        }
        XCTAssertLessThan(last, 1_800 * 1.3)
        XCTAssertNotNil(Map3DSunShadow.region(target: .zero, distance: 4_000, sun: .up, size: 2_048))
        XCTAssertNil(Map3DSunShadow.region(target: .zero, distance: 4_001, sun: .up, size: 2_048))
        // A metre a texel or so at the usual view.
        let region = try? XCTUnwrap(Map3DSunShadow.region(target: .zero, distance: 800, sun: .up, size: 2_048))
        XCTAssertEqual(region?.texel ?? 0, 1.04, accuracy: 0.01)
    }

    /// The sun at the horizon is lifted, so a shadow stays finite.
    func testTheSunNeverGrazes() {
        let low = Map3DSunShadow.sunWay(Map3DPoint(1, 0.01, 0.2))
        XCTAssertEqual(low.y, Map3DSunShadow.lowestSun, accuracy: 1e-5)
        XCTAssertEqual(low.length, 1, accuracy: 1e-5)
        XCTAssertGreaterThan(low.x, 0)
        let noon = Map3DLighting(minute: 12 * 60).sunDirection
        XCTAssertEqual(Map3DSunShadow.sunWay(noon), noon.normalized)
        // Every hour of daylight keeps the game's own sun.
        for hour in 7...17 {
            let sun = Map3DLighting(minute: Double(hour * 60)).sunDirection
            XCTAssertGreaterThan(sun.y, Map3DSunShadow.lowestSun, "\(hour)")
        }
    }

    /// The sun sees the target in the middle of the square, a building's
    /// top where its shadow falls on the ground, and what is nearer the
    /// sun nearer in depth.
    func testTheSunSeesTheSquare() throws {
        let sun = Map3DLighting(minute: 15 * 60).sunDirection
        let target = Map3DPoint(1_234, 8, -567)
        let region = try XCTUnwrap(Map3DSunShadow.region(target: target, distance: 800, sun: sun, size: 2_048))
        let matrix = region.matrix
        let middle = try XCTUnwrap(matrix.project(region.centre))
        XCTAssertEqual(middle.x, 0, accuracy: region.texel / region.extent)
        XCTAssertEqual(middle.y, 0, accuracy: region.texel / region.extent)
        XCTAssertEqual(middle.z, 0.5, accuracy: 1e-4)
        // The target is within a quarter of the square of its middle.
        let seen = try XCTUnwrap(matrix.project(target))
        XCTAssertLessThan(max(abs(seen.x), abs(seen.y)), 0.2)
        // A 40 m roof's corner and its shadow's corner on the ground.
        let top = target + Map3DPoint(30, 40, 20)
        let way = Map3DSunShadow.sunWay(sun)
        let shadow = top - way * ((top.y - target.y) / way.y)
        let a = try XCTUnwrap(matrix.project(top)), b = try XCTUnwrap(matrix.project(shadow))
        XCTAssertEqual(a.x, b.x, accuracy: 1e-4)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-4)
        XCTAssertLessThan(a.z, b.z, "the roof is nearer the sun")
        XCTAssertEqual(b.z - a.z, (top - shadow).length / (2 * Map3DSunShadow.depthReach), accuracy: 1e-4)
        // The square's side is twice the extent across the sun's way.
        let (right, _, _) = region.axes
        let edge = try XCTUnwrap(matrix.project(region.centre + right * region.extent))
        XCTAssertEqual(edge.x - middle.x, 1, accuracy: 1e-4)
        // The chunks the sun sees round it are found as the camera's are.
        XCTAssertTrue(Map3DCamera.sees(minimum: target - Map3DPoint(10, 10, 10), maximum: target + Map3DPoint(10, 50, 10), through: matrix))
        XCTAssertFalse(Map3DCamera.sees(minimum: target + Map3DPoint(5_000, 0, 5_000), maximum: target + Map3DPoint(5_100, 30, 5_100), through: matrix))
    }

    /// Moving the square moves it by whole texels, so a shadow's edge
    /// falls on the same texels after the map is drawn again.
    func testTheSquareMovesByWholeTexels() throws {
        let sun = Map3DLighting(minute: 10 * 60).sunDirection
        let a = try XCTUnwrap(Map3DSunShadow.region(target: Map3DPoint(0, 0, 0), distance: 800, sun: sun, size: 2_048))
        let b = try XCTUnwrap(Map3DSunShadow.region(target: Map3DPoint(700, 0, -300), distance: 800, sun: sun, size: 2_048))
        XCTAssertNotEqual(a.centre, b.centre)
        let point = Map3DPoint(321.7, 12.3, -98.1)
        let p = try XCTUnwrap(a.matrix.project(point)), q = try XCTUnwrap(b.matrix.project(point))
        let texels = Float(a.size) / 2
        for shift in [(p.x - q.x) * texels, (p.y - q.y) * texels] {
            XCTAssertEqual(shift, shift.rounded(), accuracy: 0.02)
        }
    }

    /// Drawn again when the sun turns half a degree, the target moves a
    /// quarter of the square or the camera pulls out a step; not for less.
    func testWhenTheMapIsDrawnAgain() throws {
        func region(_ target: Map3DPoint, _ distance: Float = 800, minute: Double = 12 * 60) throws -> Map3DSunShadow.Region {
            try XCTUnwrap(Map3DSunShadow.region(target: target, distance: distance, sun: Map3DLighting(minute: minute).sunDirection, size: 2_048))
        }
        let drawn = try region(.zero)
        XCTAssertFalse(drawn.isStale(for: try region(.zero)))
        XCTAssertFalse(drawn.isStale(for: try region(Map3DPoint(80, 3, -60))), "within an eighth of the square")
        XCTAssertTrue(drawn.isStale(for: try region(Map3DPoint(300, 0, 0))), "moved on")
        XCTAssertFalse(drawn.isStale(for: try region(.zero, 820)), "the same step")
        XCTAssertTrue(drawn.isStale(for: try region(.zero, 1_200)), "a step out")
        XCTAssertFalse(drawn.isStale(for: try region(.zero, minute: 12 * 60 + 1)), "a game minute: the sun turns a quarter of a degree")
        XCTAssertTrue(drawn.isStale(for: try region(.zero, minute: 12 * 60 + 5)), "five game minutes")
        let small = try XCTUnwrap(Map3DSunShadow.region(target: .zero, distance: 800, sun: Map3DLighting(minute: 12 * 60).sunDirection, size: 1_024))
        XCTAssertTrue(drawn.isStale(for: small), "a smaller map")
    }

    /// By day the sun's shadows show; as it sets they go, and at night
    /// there are none. Decision 232's soft ones stay, fainter beside them.
    func testTheShadowsFollowTheDay() {
        let noon = Map3DLighting(minute: 12 * 60), midnight = Map3DLighting(minute: 0)
        XCTAssertEqual(Map3DSunShadow.strength(noon), 1, accuracy: 1e-5)
        XCTAssertEqual(Map3DSunShadow.strength(midnight), 0, accuracy: 1e-5)
        XCTAssertEqual(Map3DSunShadow.strength(Map3DLighting(minute: 20 * 60)), 0, accuracy: 1e-5)
        var last: Float = 2
        for minute in stride(from: 17 * 60, through: 20 * 60, by: 10) {
            let strength = Map3DSunShadow.strength(Map3DLighting(minute: Double(minute)))
            XCTAssertLessThanOrEqual(strength, last + 1e-5, "fades as the sun sets")
            last = strength
        }
        XCTAssertEqual(Map3DSunShadow.blobStrength(noon, drawn: true), Map3DShadow.strength(noon) * Map3DSunShadow.blobShare, accuracy: 1e-5)
        XCTAssertEqual(Map3DSunShadow.blobStrength(noon, drawn: false), Map3DShadow.strength(noon))
        XCTAssertEqual(Map3DSunShadow.blobStrength(midnight, drawn: true), Map3DShadow.strength(midnight), accuracy: 1e-5)
    }

    /// The rows: the matrix, then the strength, a texel, the normal's
    /// offset and the bias; none drawn, strength 0.
    func testTheRows() throws {
        let noon = Map3DLighting(minute: 12 * 60)
        let region = try XCTUnwrap(Map3DSunShadow.region(target: .zero, distance: 800, sun: noon.sunDirection, size: 2_048))
        let rows = Map3DSunShadow.rows(region, lighting: noon)
        XCTAssertEqual(rows.count, 20)
        XCTAssertEqual(Array(rows.prefix(16)), region.matrix.columns)
        XCTAssertEqual(rows[16], 1, accuracy: 1e-5)
        XCTAssertEqual(rows[17], 1 / 2_048)
        XCTAssertEqual(rows[18], region.texel, accuracy: 1e-5)
        XCTAssertEqual(rows[19], 0.3 / 8_000, accuracy: 1e-9)
        let none = Map3DSunShadow.rows(nil, lighting: noon)
        XCTAssertEqual(none.count, 20)
        XCTAssertEqual(none[16], 0)
    }

    /// The shader reads the rows where the uniforms end, fades the shadows
    /// at the square's edge and looks them up as here; the Metal view
    /// biases the depth it draws by these numbers.
    func testTheShaderAndTheViewKeepTheSameNumbers() throws {
        let shaders = try String(contentsOf: Self.app.appendingPathComponent("Map3DShaders.metal"), encoding: .utf8)
        let layout = try XCTUnwrap(shaders.range(of: "float4 glint;\n    float4x4 sunMatrix;\n    float4 sunShadow;\n};"))
        XCTAssertFalse(layout.isEmpty)
        XCTAssertTrue(shaders.contains("smoothstep(\(Map3DSunShadow.fadeFrom), 1.0, edge)"))
        XCTAssertTrue(shaders.contains("compare_func::less_equal"))
        let view = try String(contentsOf: Self.app.appendingPathComponent("Map3DMetalView.swift"), encoding: .utf8)
        XCTAssertTrue(view.contains("Map3DSunShadow.rows("))
        XCTAssertTrue(view.contains("slopeScale: Map3DSunShadow.slopeScale, clamp: Map3DSunShadow.slopeClampDepth"))
        XCTAssertTrue(view.contains("Map3DSunShadow.blobStrength("))
    }
}
