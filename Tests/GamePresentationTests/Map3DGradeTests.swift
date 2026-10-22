import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 349: the picture's finish (the web view's tone mapping's
/// shoulder and its Picture) and the haze on the ground.
final class Map3DGradeTests: XCTestCase {
    private static func luminance(_ c: SIMD3<Float>) -> Float { Map3DGrade.luminance(c) }

    private static func colour(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF)) / 255
    }

    /// The colours the map is drawn in barely move: mid tones by a few
    /// hundredths, a touch toward green.
    func testMidTonesBarelyMove() {
        for hex: UInt32 in [0xD9DFEF, 0x4E5682, 0xB5D6A2, 0x8A8F99, 0x2C4A52, 0x163742] {
            let before = Self.colour(hex)
            let after = Map3DGrade.finish(before)
            for channel in 0..<3 {
                XCTAssertEqual(after[channel], before[channel], accuracy: 0.05, String(hex, radix: 16))
            }
            XCTAssertGreaterThanOrEqual(after.y - after.x, before.y - before.x - 0.001, "a touch toward green")
        }
    }

    /// Black stays black (no toe darkening the night), and the night's
    /// ground keeps its light (decision 229 續).
    func testTheNightIsNotDarkened() {
        XCTAssertEqual(Map3DGrade.finish(.zero), .zero)
        for minute: Double in [21 * 60, 0, 3 * 60] {
            let light = Map3DLighting(minute: minute)
            let ground = light.lit(Self.colour(0xD9DFEF), normal: .up)
            XCTAssertGreaterThanOrEqual(Self.luminance(Map3DGrade.finish(ground)), Self.luminance(ground) - 0.01)
        }
    }

    /// What passes white (a sunlit white roof, a street light's glow) rolls
    /// off toward it instead of clipping, keeping its order.
    func testBrightColoursRollOffInOrder() {
        var last: Float = -1
        for step in 0...30 {
            let v = Float(step) / 10
            let out = Self.luminance(Map3DGrade.finish(SIMD3(v, v * 0.9, v * 0.7)))
            XCTAssertGreaterThanOrEqual(out, last - 1e-5, "\(v)")
            XCTAssertLessThanOrEqual(out, 1)
            last = out
        }
        // A warm glow over white keeps some of its colour.
        let glow = Map3DGrade.finish(SIMD3(1.4, 1.0, 0.6))
        XCTAssertGreaterThan(glow.x - glow.z, 0.1)
        XCTAssertLessThanOrEqual(glow.x, 1)
    }

    /// Below the shoulder the tone mapping leaves the colour alone.
    func testTheShoulderStartsAt076() {
        let c = SIMD3<Float>(0.7, 0.5, 0.2)
        XCTAssertEqual(Map3DGrade.shoulder(c), c)
        let high = Map3DGrade.shoulder(SIMD3(2, 2, 2))
        XCTAssertLessThan(high.x, 1)
        XCTAssertGreaterThan(high.x, 0.9)
    }

    /// The haze: none near, more far away, much more seen from low down
    /// than from high up, and a ray along the ground to the horizon all
    /// but wholly in it, with no overflow for a high eye looking far down.
    func testTheHazeLiesOnTheGround() {
        let level = Map3DPoint(1, 0, 0)
        XCTAssertEqual(Map3DGrade.haze(eyeHeight: 2, way: level, distance: 0), 0)
        let near = Map3DGrade.haze(eyeHeight: 2, way: level, distance: 500)
        let far = Map3DGrade.haze(eyeHeight: 2, way: level, distance: 3_000)
        XCTAssertLessThan(near, 0.06)
        XCTAssertGreaterThan(far, 0.2)
        XCTAssertLessThan(far, 0.3)
        XCTAssertGreaterThan(Map3DGrade.haze(eyeHeight: 2, way: level, distance: Map3DGrade.skyDistance), 0.99)
        // Looking down at the map from 800 m: hardly any.
        let down = (Map3DPoint(0, -800, 0) - Map3DPoint(0, 0, 0) + Map3DPoint(700, 0, 0)).normalized!
        let fromAbove = Map3DGrade.haze(eyeHeight: 800, way: down, distance: 1_063)
        XCTAssertLessThan(fromAbove, 0.03)
        // Up at the sky: little.
        let up = Map3DPoint(0.6, 0.8, 0).normalized!
        XCTAssertLessThan(Map3DGrade.haze(eyeHeight: 2, way: up, distance: Map3DGrade.skyDistance), 0.05)
        // From 12 km up, a ray of the sky's length that ends far below sea
        // level: whole, not NaN.
        let steep = Map3DPoint(1, -0.5, 0).normalized!
        let deep = Map3DGrade.haze(eyeHeight: 12_000, way: steep, distance: Map3DGrade.skyDistance)
        XCTAssertFalse(deep.isNaN)
        XCTAssertEqual(deep, 1, accuracy: 0.001)
    }

    func testTheSkysFloatsCarryTheHaze() {
        let camera = Map3DCamera(distance: 300)
        let floats = Map3DSky(Map3DLighting(minute: 12 * 60)).floats(camera: camera)
        XCTAssertEqual(floats.count, 36)
        XCTAssertEqual(floats[33], camera.eye.y)
        XCTAssertEqual(floats[34], Map3DGrade.hazeDensity)
        XCTAssertEqual(floats[35], Map3DGrade.hazeHeight)
    }
}
