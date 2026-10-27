import Foundation
import GameCore
import XCTest
@testable import GamePresentation

/// Decision 450: the trains' window glass and stainless bodies, marked as
/// the pack is made, and what the shader does with them.
final class Map3DTrainMaterialTests: XCTestCase {
    private let pack = Map3DModelPack.standard
    private let recipes = Map3DModelPack.unbaked

    static let shaders = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp/Views/Map3D/Map3DShaders.metal")

    /// Every recipe's glass is glass; the colours beside it are not.
    func testWhichColoursAreGlass() {
        let glass = [Map3DEMU800.glass, Map3DEMU500.glass, Map3DEMU900.glass, Map3DC341.glass, Map3DE500.glassColor,
                     Map3DTEMU2000.glass, Map3DTEMU1000.passengerGlass, Map3DTrainStyle.glass, Map3DColor.shaded(Map3DTrainStyle.glass, 0.7),
                     Map3DTrainShapeRefresh.highSpeedGlassColor, Map3DSevenCarBlue.glass]
        for colour in glass { XCTAssertTrue(Map3DTrainMaterial.isGlassColour(colour), String(colour, radix: 16)) }
        let other = [Map3DTrainStyle.doorColour, Map3DTrainStyle.darkLine, Map3DTrainStyle.under, Map3DEMU800.rubber,
                     Map3DColor.shaded(Map3DColor.rgb(0x283944), 0.4), Map3DColor.rgb(0x1E2D4A), Map3DEMU500.silver,
                     Map3DEMU800.bodyColor, Map3DPalette.tankStand, Map3DTrainStyle.glass & 0x00FF_FFFF]
        for colour in other { XCTAssertFalse(Map3DTrainMaterial.isGlassColour(colour), String(colour, radix: 16)) }
    }

    func testWhichColoursAndSetsAreStainless() {
        for colour in [Map3DEMU800.bodyColor, Map3DEMU900.bodyColor, Map3DEMU500.silver, Map3DColor.rgb(0xBFC8C9)] {
            XCTAssertTrue(Map3DTrainMaterial.isSteelColour(colour), String(colour, radix: 16))
        }
        for colour in [Map3DPalette.tankStand, Map3DColor.rgb(0x3E8C8C), Map3DColor.rgb(0xE89A27), Map3DEMU800.bodyColor & 0x00FF_FFFF] {
            XCTAssertFalse(Map3DTrainMaterial.isSteelColour(colour), String(colour, radix: 16))
        }
        for name in ["set-emu800-head", "set-emu800Far-car", "emu800-ed", "c341-dm", "set-metroC381-head", "set-dieselExpress-tail"] {
            XCTAssertTrue(Map3DTrainMaterial.isStainless(name), name)
        }
        for name in ["set-taroko-head", "temu1000-leading", "set-emu3000-head", "commuter-cab", "prop-bench"] {
            XCTAssertFalse(Map3DTrainMaterial.isStainless(name), name)
        }
    }

    /// The pack is the recipes with only the layer of whole triangles
    /// changed (and their shade kept in `u`): glass, lit glass, stainless;
    /// a lamp stays lit, nothing else moves, and the street's models are
    /// not touched.
    func testThePackMarksWholeTrianglesAndNothingElse() {
        let materials: Set<Float> = [Map3DVertex.trainGlass, Map3DVertex.trainSteel, Map3DVertex.trainGlassLit]
        for (marked, recipe) in zip(pack.models, recipes.models) {
            let train = Map3DTrainOcclusion.isTrain(recipe.name), stainless = Map3DTrainMaterial.isStainless(recipe.name)
            // Decision 449: a running car's lamps are lit only at its train's ends.
            let running = Map3DTrainLights.isRunning(recipe.name)
            for start in stride(from: 0, to: recipe.vertices.count, by: 3) {
                let after = marked.vertices[start..<start + 3], before = recipe.vertices[start]
                XCTAssertEqual(Set(after.map(\.layer)).count, 1, recipe.name)
                let lamp = before.glows && !running
                XCTAssertEqual(after.first!.glows, lamp, "\(recipe.name): a lamp stays a lamp")
                let layer = after.first!.layer
                guard materials.contains(layer) else {
                    XCTAssertEqual(layer, before.glows && running ? Map3DVertex.plain : before.layer, recipe.name)
                    XCTAssertFalse(after.contains { $0.isTrainMaterial }, recipe.name)
                    continue
                }
                XCTAssertTrue(train, "\(recipe.name): only a train's faces")
                XCTAssertTrue(before.layer == Map3DVertex.plain || before.layer == Map3DVertex.glowing, recipe.name)
                XCTAssertGreaterThanOrEqual(before.nz, Map3DTrainMaterial.lowestNormal, recipe.name)
                XCTAssertTrue(after.allSatisfy { (0...1).contains($0.u) }, recipe.name)
                if layer == Map3DVertex.trainSteel {
                    XCTAssertTrue(stainless, recipe.name)
                    XCTAssertTrue(Map3DTrainMaterial.isSteelColour(before.color), recipe.name)
                } else {
                    XCTAssertTrue(Map3DTrainMaterial.isGlassColour(before.color), recipe.name)
                    XCTAssertEqual(layer == Map3DVertex.trainGlassLit, lamp, recipe.name)
                }
            }
        }
    }

    /// Every set's head has glass that mirrors; the stainless sets, and only
    /// they, a stainless body; the far versions too.
    func testEverySetHasGlassAndTheStainlessOnesSteel() throws {
        for key in Map3DTrainSet.byKey.keys.sorted() {
            guard let index = pack.index(of: "set-\(key)-head") else { continue }
            let layers = pack.models[index].vertices.map(\.layer)
            XCTAssertTrue(layers.contains(Map3DVertex.trainGlass), key)
            XCTAssertEqual(layers.contains(Map3DVertex.trainSteel), Map3DTrainMaterial.isStainless("set-\(key)-head"), key)
        }
        let emu800 = try XCTUnwrap(pack.index(of: "set-emu800-head"))
        let steel = pack.models[emu800].vertices.filter { $0.layer == Map3DVertex.trainSteel }.count
        XCTAssertGreaterThan(steel, pack.models[emu800].vertices.count / 20, "the EMU800's body is mostly steel")
    }

    /// A shut-in face (at a gangway, beside a frame) keeps its shade in
    /// `u`, so it mirrors less; by area, most of the glass and steel (the
    /// open side) keeps nearly all.
    func testShutInFacesMirrorLess() throws {
        let index = try XCTUnwrap(pack.index(of: "set-emu800-car"))
        let vertices = pack.models[index].vertices
        var open: Float = 0, all: Float = 0
        for start in stride(from: 0, to: vertices.count, by: 3) where vertices[start].isTrainMaterial {
            let p = (0..<3).map { vertices[start + $0].position }
            let area = (p[1] - p[0]).cross(p[2] - p[0]).length / 2
            all += area
            if (0..<3).allSatisfy({ vertices[start + $0].u < 0.1 }) { open += area }
        }
        XCTAssertTrue(vertices.contains { $0.isTrainMaterial && $0.u > 0.3 }, "some of it is shut in")
        XCTAssertGreaterThan(open, all * 0.75, "most of it is open")
        XCTAssertEqual(Map3DReflection.trainOpen(shade: 0), 1)
        XCTAssertEqual(Map3DReflection.trainOpen(shade: 0.6), 0.4, accuracy: 1e-6)
    }

    func testFresnelAndSheen() {
        XCTAssertEqual(Map3DReflection.trainGlassFresnel(1), 0.09, accuracy: 1e-6)
        XCTAssertEqual(Map3DReflection.trainGlassFresnel(0), 0.9, accuracy: 1e-6)
        XCTAssertEqual(Map3DReflection.steelFresnel(1), 0.22, accuracy: 1e-6)
        XCTAssertEqual(Map3DReflection.steelFresnel(0), 0.62, accuracy: 1e-6)
        var last: Float = -1
        for step in stride(from: Float(1), through: 0, by: -0.1) {
            XCTAssertGreaterThanOrEqual(Map3DReflection.steelFresnel(step), last)
            last = Map3DReflection.steelFresnel(step)
        }
        let sun = Map3DPoint(0, 1, 0)
        XCTAssertEqual(Map3DReflection.steelSheen(reflected: sun, sun: sun), 0.3, accuracy: 1e-6)
        // Broad, not a glint: still some sheen 25° off, where the glass's
        // sharp core is gone.
        let off = Map3DPoint(sinf(0.44), cosf(0.44), 0)
        XCTAssertGreaterThan(Map3DReflection.steelSheen(reflected: off, sun: sun), 0.01)
        XCTAssertLessThan(Map3DReflection.glassGlint(reflected: off, sun: sun), 0.07)
    }

    /// Off on the saving quality, and on automatic in Low Power Mode or
    /// once the phone runs hot; the shader reads it in the reflections' row.
    func testItCanBeSwitchedOff() {
        XCTAssertEqual(Map3DReflection.trainStrength(.automatic), 1)
        XCTAssertEqual(Map3DReflection.trainStrength(.high, heat: .serious), 1)
        XCTAssertEqual(Map3DReflection.trainStrength(.saving), 0)
        XCTAssertEqual(Map3DReflection.trainStrength(.off), 0)
        XCTAssertEqual(Map3DReflection.trainStrength(.automatic, lowPower: true), 0)
        XCTAssertEqual(Map3DReflection.trainStrength(.automatic, heat: .serious), 0)
        XCTAssertEqual(Map3DReflection.trainStrength(.high, heat: .critical), 0)
        let noon = Map3DLighting(minute: 12 * 60)
        func row(_ quality: Map3DQuality, _ trains: Float? = nil) -> Float {
            Map3DReflection.rows(sky: Map3DSky(noon), sunLight: noon.sunLight, quality: quality, seconds: 0, reduceMotion: false, trains: trains)[3]
        }
        XCTAssertEqual(row(.automatic), 1)
        XCTAssertEqual(row(.saving), 0)
        XCTAssertEqual(row(.automatic, 0), 0)
    }

    /// The shader's numbers are these, and its instanced vertex passes the
    /// three layers and the shade on.
    func testTheShaderKeepsTheSameNumbers() throws {
        let source = try String(contentsOf: Self.shaders, encoding: .utf8)
        XCTAssertTrue(source.contains("constant float4 trainMaterial = {\(Map3DReflection.trainGlassShare), \(Map3DReflection.steelBase), "
            + "\(Map3DReflection.steelEdge), \(Map3DReflection.steelTint)};"))
        let lobes = Map3DReflection.steelSheenLobes
        XCTAssertTrue(source.contains("constant float4 steelSheen = {\(lobes[0].power), \(lobes[0].strength), \(lobes[1].power), \(lobes[1].strength)};"))
        XCTAssertTrue(source.contains("constant float trainLitGlass = \(Map3DReflection.litGlassMirror);"))
        XCTAssertTrue(source.contains("bool material = layer < -12.5 && layer > -15.5;"))
        XCTAssertEqual([Map3DVertex.trainGlass, Map3DVertex.trainSteel, Map3DVertex.trainGlassLit], [-13, -14, -15])
        XCTAssertTrue(source.contains("float trains = uniforms.mirror.w;"))
    }
}
