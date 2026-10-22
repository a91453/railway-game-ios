import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 356: glass and water mirror the sky by Fresnel's share, the sun
/// glints in them, the city's lights show in the glass at night, and the
/// water ripples (still with Reduce Motion, none on the saving quality).
final class Map3DReflectionTests: XCTestCase {
    private static let shaders = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp/Views/Map3D/Map3DShaders.metal")

    /// Each mirrors little head on and most at a glancing angle: window
    /// glass from a tenth, a shop's display glass from about a fifth (but
    /// never wholly a mirror), water from a twentieth.
    func testFresnelGrowsTowardAGlancingAngle() {
        XCTAssertEqual(Map3DReflection.windowFresnel(1), 0.1, accuracy: 1e-6)
        XCTAssertEqual(Map3DReflection.shopFresnel(1), 0.18, accuracy: 1e-6)
        XCTAssertEqual(Map3DReflection.waterFresnel(1), 0.05, accuracy: 1e-6)
        XCTAssertEqual(Map3DReflection.windowFresnel(0), 1, accuracy: 1e-6)
        XCTAssertEqual(Map3DReflection.shopFresnel(0), 0.8, accuracy: 1e-6)
        XCTAssertEqual(Map3DReflection.waterFresnel(0), 1, accuracy: 1e-6)
        for f in [Map3DReflection.windowFresnel, Map3DReflection.shopFresnel, Map3DReflection.waterFresnel] {
            var last: Float = 0
            for step in stride(from: Float(1), through: 0, by: -0.05) {
                XCTAssertGreaterThanOrEqual(f(step), last)
                last = f(step)
            }
        }
        // The map's usual view looks down at the water about 40–60° off
        // flat: it keeps nearly all its own colour.
        XCTAssertLessThan(Map3DReflection.waterFresnel(sinf(40 * .pi / 180)), 0.1)
    }

    /// Glass that mirrors: the office curtain wall most, homes and flats
    /// less, a shop's display glass by the street scene's rule; walls,
    /// roofs, ground and paint none.
    func testWhichGlassMirrors() {
        XCTAssertEqual(Map3DReflection.glass(.officeGlass).share, 1)
        for surface in Map3DSurface.shops { XCTAssertTrue(Map3DReflection.glass(surface).shop) }
        for surface in Map3DSurface.flats + [.homeWindows, .homeBalcony] {
            XCTAssertGreaterThan(Map3DReflection.glass(surface).share, 0)
            XCTAssertLessThan(Map3DReflection.glass(surface).share, 1)
            XCTAssertFalse(Map3DReflection.glass(surface).shop)
        }
        for surface: Map3DSurface in [.grass, .paving, .roof, .plaster, .shutter, .metalSheet, .brickTile, .crosswalk] {
            XCTAssertEqual(Map3DReflection.glass(surface).share, 0)
        }
        // The glass that lights at night is the glass that mirrors.
        for surface in Map3DSurface.allCases where Map3DReflection.glass(surface).share > 0 {
            XCTAssertGreaterThan(Map3DNightWindows.rule(surface).share, 0, "\(surface)")
        }
    }

    /// The shader's tables are these: its `glassMirror` in surface order,
    /// and its four waves.
    func testTheShaderKeepsTheSameNumbers() throws {
        let source = try String(contentsOf: Self.shaders, encoding: .utf8)
        func block(after name: String) throws -> [Float] {
            let start = try XCTUnwrap(source.range(of: name))
            let end = try XCTUnwrap(source.range(of: "};", range: start.upperBound..<source.endIndex))
            let text = source[start.upperBound..<end.lowerBound]
            return text.split(whereSeparator: { !"0123456789.-".contains($0) }).compactMap { Float($0) }
        }
        let table = try block(after: "constant float2 glassMirror[24] = {")
        XCTAssertEqual(table.count, 48)
        XCTAssertLessThanOrEqual(Map3DSurface.allCases.count, 24)
        for surface in Map3DSurface.allCases {
            let glass = Map3DReflection.glass(surface)
            XCTAssertEqual(table[surface.rawValue * 2], glass.share, "\(surface)")
            XCTAssertEqual(table[surface.rawValue * 2 + 1], glass.shop ? 1 : 0, "\(surface)")
        }
        let waves = try block(after: "constant float4 rippleWaves[4] = {")
        let runs = try block(after: "constant float2 rippleRuns[4] = {")
        XCTAssertEqual(waves.count, 16)
        for (index, wave) in Map3DReflection.waves.enumerated() {
            XCTAssertEqual(Array(waves[index * 4..<index * 4 + 4]), [wave.x, wave.z, wave.number, wave.height])
            XCTAssertEqual(Array(runs[index * 2..<index * 2 + 2]), [wave.speed, wave.phase])
        }
        XCTAssertTrue(source.contains("return slope * \(Map3DReflection.amplitude);"))
        XCTAssertTrue(source.contains("step(bright, \(Map3DReflection.brightestGlass))"))
    }

    /// Above the horizon the mirror sees the sky as decision 347 draws it
    /// (horizon to zenith); below, the street, darker than the horizon.
    func testWhatAMirrorSees() {
        let horizon = SIMD3<Float>(0.8, 0.85, 0.9), zenith = SIMD3<Float>(0.3, 0.5, 0.8)
        XCTAssertEqual(Map3DReflection.seen(toward: .up, horizon: horizon, zenith: zenith), zenith)
        XCTAssertEqual(Map3DReflection.seen(toward: Map3DPoint(1, 0, 0), horizon: horizon, zenith: zenith), horizon)
        let sky = Map3DSky(Map3DLighting(minute: 12 * 60))
        let way = Map3DPoint(0.3, 0.6, 0.2).normalized!
        let seen = Map3DReflection.seen(toward: way, horizon: sky.horizon, zenith: sky.zenith)
        let drawn = Map3DLighting.mix(sky.horizon, sky.zenith, way.y.squareRoot())
        XCTAssertEqual(seen.x, drawn.x, accuracy: 1e-6)
        var last = horizon.x
        for y in stride(from: Float(-0.05), through: -1, by: -0.05) {
            let below = Map3DReflection.seen(toward: Map3DPoint(1, y, 0).normalized!, horizon: horizon, zenith: zenith)
            XCTAssertLessThanOrEqual(below.x, last)
            last = below.x
        }
        XCTAssertEqual(last, horizon.x * 0.55, accuracy: 1e-5)
    }

    /// The glint is brightest straight at the sun's mirror image, a soft
    /// glare round it, nothing facing away.
    func testTheSunsGlint() {
        let sun = Map3DPoint(0.3, 0.8, 0.5).normalized!
        XCTAssertEqual(Map3DReflection.glassGlint(reflected: sun, sun: sun), 3.45, accuracy: 0.01)
        XCTAssertEqual(Map3DReflection.waterGlint(reflected: sun, sun: sun), 2.2, accuracy: 0.01)
        XCTAssertEqual(Map3DReflection.glassGlint(reflected: -sun, sun: sun), 0)
        let off = (sun + Map3DPoint(0.2, 0, 0)).normalized!
        XCTAssertLessThan(Map3DReflection.glassGlint(reflected: off, sun: sun), 0.2)
        XCTAssertGreaterThan(Map3DReflection.glassGlint(reflected: off, sun: sun), 0)
    }

    /// The city's lights only where the mirrored ray goes down to the
    /// street; a pane high up sees them small and far, with the haze.
    func testTheCitysLightsInTheGlass() {
        let pane = Map3DPoint(100, 30, 200)
        XCTAssertEqual(Map3DReflection.cityLights(world: pane, drop: 30, reflected: Map3DPoint(0, 0.2, 1).normalized!), .zero)
        // Over a street of panes, lights show: bright where the ray meets
        // the street near, dimmer far along a nearly flat ray, where only
        // their haze is left between them.
        func sweep(_ way: Map3DPoint) -> (brightest: Float, dimmest: Float) {
            var brightest: Float = 0, dimmest: Float = .infinity
            for step in 0..<400 {
                let light = Map3DReflection.cityLights(world: Map3DPoint(Float(step) * 0.7, 30, 0), drop: 30, reflected: way.normalized!)
                brightest = max(brightest, light.x)
                dimmest = min(dimmest, light.x)
            }
            return (brightest, dimmest)
        }
        let near = sweep(Map3DPoint(0, -0.3, 1)), far = sweep(Map3DPoint(0, -0.02, 1))
        XCTAssertGreaterThan(near.brightest, 1)
        XCTAssertLessThan(far.brightest, near.brightest / 2)
        XCTAssertGreaterThan(far.dimmest, 0.03)
    }

    /// The ripples tilt the water a few degrees, move with the time, stand
    /// still with Reduce Motion, and fade where a wave comes to less than
    /// a few pixels (so the far water does not shimmer).
    func testTheRipples() {
        var steepest: Float = 0
        for step in 0..<200 {
            let slope = Map3DReflection.rippleSlope(x: Float(step) * 0.37, z: Float(step) * 0.61, seconds: 12, footprint: 0.05)
            let normal = Map3DReflection.waterNormal(slope: slope)
            steepest = max(steepest, acosf(normal.y) * 180 / .pi)
        }
        XCTAssertGreaterThan(steepest, 2)
        XCTAssertLessThan(steepest, 6)
        let now = Map3DReflection.rippleSlope(x: 3, z: 4, seconds: 10, footprint: 0.05)
        let later = Map3DReflection.rippleSlope(x: 3, z: 4, seconds: 10.5, footprint: 0.05)
        XCTAssertNotEqual(now.x, later.x)
        // From the map's usual 800 m (a pixel about 0.6 m) the longest
        // waves still show; from 12 km none.
        let near = Map3DReflection.rippleSlope(x: 3, z: 4, seconds: 10, footprint: 0.6)
        XCTAssertGreaterThan(abs(near.x) + abs(near.z), 0)
        let gone = Map3DReflection.rippleSlope(x: 3, z: 4, seconds: 10, footprint: 20)
        XCTAssertEqual(gone.x, 0)
        XCTAssertEqual(gone.z, 0)
        XCTAssertEqual(Map3DReflection.rippleSeconds(5_000, reduceMotion: true), 0)
        XCTAssertEqual(Map3DReflection.rippleSeconds(5_000, reduceMotion: false), 1_400)
    }

    /// The rows the shader reads after the night windows.
    func testTheRowsForTheShader() {
        let noon = Map3DLighting(minute: 12 * 60)
        let rows = Map3DReflection.rows(sky: Map3DSky(noon), sunLight: noon.sunLight, quality: .automatic, seconds: 100, reduceMotion: false)
        XCTAssertEqual(rows.count, Map3DReflection.rowCount)
        XCTAssertEqual(rows[0], 1)
        XCTAssertEqual(rows[1], 100)
        XCTAssertGreaterThan(rows[2], 0.9)
        XCTAssertEqual(Array(rows[4..<7]), [Map3DSky(noon).zenith.x, Map3DSky(noon).zenith.y, Map3DSky(noon).zenith.z])
        XCTAssertEqual(rows[8..<11].max(), 1)
        let saving = Map3DReflection.rows(sky: Map3DSky(noon), sunLight: noon.sunLight, quality: .saving, seconds: 100, reduceMotion: true)
        XCTAssertEqual(saving[0], 0)
        XCTAssertEqual(saving[1], 0)
        // No sun in the glass at midnight or under rain.
        let midnight = Map3DLighting(minute: 0)
        XCTAssertEqual(Map3DReflection.rows(sky: Map3DSky(midnight), sunLight: midnight.sunLight, quality: .high, seconds: 0, reduceMotion: false)[2], 0)
        var rain = noon
        rain.weather = Map3DWeather.rain
        XCTAssertEqual(Map3DReflection.rows(sky: Map3DSky(rain), sunLight: rain.sunLight, quality: .high, seconds: 0, reduceMotion: false)[2], 0)
    }

    /// Water is its own kind of vertex, apart from the glowing ones.
    func testWaterVertices() {
        var mesh = Map3DMesh()
        mesh.addQuad(Map3DPoint(0, 0, 0), Map3DPoint(0, 0, 1), Map3DPoint(1, 0, 1), Map3DPoint(1, 0, 0), color: Map3DPalette.water)
        mesh.makeWater(from: 0)
        XCTAssertTrue(mesh.vertices.allSatisfy(\.isWater))
        XCTAssertFalse(mesh.vertices.contains(where: \.glows))
        XCTAssertNil(mesh.vertices[0].surface)
        mesh.makeGlowing(from: 0)
        XCTAssertFalse(mesh.vertices.contains(where: \.isWater))
    }
}
