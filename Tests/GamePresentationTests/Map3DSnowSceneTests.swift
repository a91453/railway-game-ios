import Foundation
import GameCore
import XCTest
@testable import GamePresentation

/// Decision 833: the rest of the snow scene of a map under snow
/// (Rovaniemi's): the trees under snow, the rivers and lakes frozen, a
/// day of rain falling as snow in a day of snow's light. Every other map
/// is drawn as before.
final class Map3DSnowSceneTests: XCTestCase {
    private func rovaniemi() throws -> GameWorld { GameWorld.newOverseasGame(try RovaniemiRailwaysTests.ground()) }

    // MARK: Snowfall

    /// Under snow a day of rain falls as the reference's flakes: its
    /// counts, white, slow, drifting, no lightning; harder in a storm and
    /// a gale. Without snow the rain is the rain it was.
    func testADayOfRainFallsAsSnow() {
        for sky in [MapWeather.Sky.rain, .thunderstorm, .typhoon] {
            XCTAssertEqual(Map3DRain(MapWeather(sky: sky), snow: false), Map3DRain(MapWeather(sky: sky)))
        }
        let snow = Map3DRain(MapWeather(sky: .rain), snow: true)
        XCTAssertTrue(snow.snow)
        XCTAssertEqual(Map3DStreetDetail.allCases.map(snow.streakCount), [500, 1_000, 1_800])
        XCTAssertEqual(snow.look(night: 0).colour, 0xFFFFFF)
        XCTAssertEqual(snow.look(night: 0).opacity, 0.8, accuracy: 1e-9)
        XCTAssertEqual(snow.look(night: 1).opacity, 0.6, accuracy: 1e-9)
        XCTAssertEqual(snow.slant, Map3DRain.snowSlant)
        let storm = Map3DRain(MapWeather(sky: .thunderstorm), snow: true), gale = Map3DRain(MapWeather(sky: .typhoon), snow: true)
        XCTAssertFalse(storm.flashes)
        XCTAssertEqual((0..<600).map { storm.flash(at: Double($0) * 0.1) }.max(), 0)
        XCTAssertGreaterThan(gale.streakCount(.full), snow.streakCount(.full))
        XCTAssertEqual(gale.slant, Map3DRain.blizzardSlant)
        XCTAssertLessThanOrEqual(gale.look(night: 0).opacity, 0.8)
        XCTAssertEqual(Map3DRain(.clear, snow: true).streakCount(.full), 0)
    }

    /// The flakes are small and slow: each 1.4 to 3.2 points high on the
    /// flake's width, falling at 0.7 to 1.3 times the snow's pace, a fifth
    /// of the rain's; the same flakes every time.
    func testTheFlakesAreSmallAndSlow() {
        let snow = Map3DRain(MapWeather(sky: .rain), snow: true)
        for index in 0..<snow.streakCount(.full) {
            let seed = Map3DRain.seed(index, snow: true)
            XCTAssertTrue((1.4...3.2).contains(seed.length))
            XCTAssertTrue((0.7 * Map3DRain.snowSpeed...1.3 * Map3DRain.snowSpeed).contains(seed.speed))
            XCTAssertTrue((0..<1).contains(seed.x) && (0..<1).contains(seed.y))
        }
        XCTAssertLessThan(Map3DRain.snowSpeed, Map3DRain.speed / 4)
        XCTAssertEqual(snow.seeds(.reduced), snow.seeds(.reduced))
        // The shader's flakes are the CPU's.
        let seeds = snow.seeds(.full)
        let uniforms = snow.uniforms(seconds: 37.5, width: 390, height: 844, night: 0, flash: 0, count: seeds.count / 4)
        XCTAssertEqual(uniforms[12], Float(Map3DRain.flakeWidth / 2))
        let flakes = snow.streaks(at: 37.5, width: 390, height: 844, detail: .full)
        for index in stride(from: 0, to: flakes.count, by: 97) {
            let gpu = Map3DRain.shaderStreak(index, of: seeds, uniforms: uniforms)
            XCTAssertEqual(gpu.x0, flakes[index].x0, accuracy: 0.05)
            XCTAssertEqual(gpu.y0, flakes[index].y0, accuracy: 0.05)
        }
    }

    /// The map hands its GPU the flakes again when the rain turns to snow,
    /// even at the same count.
    func testTheDrawingRemakesItsSeedsForSnow() {
        var drawing = Map3DRainDrawing()
        let rain = Map3DRain(MapWeather(sky: .rain)), snow = Map3DRain(MapWeather(sky: .rain), snow: true)
        XCTAssertTrue(drawing.update(rain, detail: .full))
        XCTAssertFalse(drawing.update(rain, detail: .full))
        XCTAssertTrue(drawing.update(snow, detail: .full))
        XCTAssertEqual(drawing.count, 1_800)
        XCTAssertFalse(drawing.update(snow, detail: .full))
        XCTAssertEqual(drawing.seeds, snow.seeds(.full))
        XCTAssertEqual(drawing.builds, 2)
    }

    /// A day of snow's light is the reference's `PRESETS.snow`: paler and
    /// brighter than rain's. On a map under snow every wet day is lit so;
    /// a clear day is clear. The maps of Taiwan and Hong Kong keep rain.
    func testADayOfSnowIsLitAsTheReferences() throws {
        let snow = Map3DWeather.snow
        XCTAssertEqual(snow.daySunScale, 0.9)
        XCTAssertEqual(snow.skyTint, 0xC4D1DF)
        XCTAssertEqual(snow.fogTint, 0xBAC6D1)
        XCTAssertEqual(snow.fogNear, 0.9)
        XCTAssertEqual(snow.fogFar, 0.84)
        XCTAssertGreaterThan(snow.daySunScale, Map3DWeather.rain.daySunScale)
        for sky in [MapWeather.Sky.rain, .thunderstorm, .typhoon] {
            XCTAssertEqual(Map3DWeather(MapWeather(sky: sky), snow: true), .snow)
            XCTAssertEqual(Map3DWeather(MapWeather(sky: sky)), .rain)
        }
        XCTAssertEqual(Map3DWeather(.clear, snow: true), .clear)
        let rovaniemi = try rovaniemi()
        XCTAssertEqual(Map3DWeather(world: rovaniemi), Map3DWeather(MapWeather(world: rovaniemi), snow: true))
        XCTAssertEqual(Map3DRain(world: rovaniemi), Map3DRain(MapWeather(world: rovaniemi), snow: true))
        for world in [GameWorld.newGame(), GameWorld.newOverseasGame(try HongKongBaseMapTests.ground())] {
            XCTAssertEqual(Map3DWeather(world: world), Map3DWeather(MapWeather(world: world)))
            XCTAssertEqual(Map3DRain(world: world), Map3DRain(MapWeather(world: world)))
            XCTAssertFalse(Map3DRain(world: world).snow)
        }
    }

    // MARK: Ice

    /// Under snow the water is the frozen bog's blue-grey, matte, and still
    /// water to whatever asks where the water is.
    func testTheWaterFreezes() {
        XCTAssertEqual(Map3DSnowGround.ice, Map3DPalette.cover(.wetland))
        var mesh = Map3DMesh()
        mesh.addQuad(Map3DPoint(0, 0, 0), Map3DPoint(1, 0, 0), Map3DPoint(1, 0, 1), Map3DPoint(0, 0, 1), color: Map3DPalette.ground)
        let start = mesh.vertices.count
        mesh.addQuad(Map3DPoint(0, 0, 0), Map3DPoint(1, 0, 0), Map3DPoint(1, 0, 1), Map3DPoint(0, 0, 1), color: Map3DPalette.water)
        mesh.makeWater(from: start)
        Map3DSnowGround.cover(&mesh)
        XCTAssertEqual(mesh.vertices.prefix(start).map(\.layer), Array(repeating: Map3DVertex.plain, count: start))
        XCTAssertEqual(Set(mesh.vertices.suffix(from: start).map(\.color)), [Map3DSnowGround.ice])
        XCTAssertEqual(Set(mesh.vertices.suffix(from: start).map(\.layer)), [Map3DVertex.ice])
        XCTAssertNotEqual(Map3DSnowGround.ice, Map3DSnowGround.field)
    }

    // MARK: Trees

    /// Under snow each tree's green goes its share of the way to the
    /// snow's white: the conifers least, the bushes most; any other prop
    /// keeps its colour, and the place, size and the rest of the instance.
    func testTheTreesAreUnderSnow() throws {
        let catalog = Map3DModelCatalog.standard
        let tree = try XCTUnwrap(catalog.index(of: Map3DProp.tree.modelName))
        let pine = try XCTUnwrap(catalog.index(of: Map3DSceneryProp.pine.modelName))
        let bush = try XCTUnwrap(catalog.index(of: Map3DSceneryProp.bushes.modelName))
        let lamp = try XCTUnwrap(catalog.index(of: Map3DProp.lamp.modelName))
        let green = Map3DProp.greens[1]
        var lit = Map3DInstance.prop(tree, at: Map3DPoint(3, 0, 4), forward: Map3DPoint(1, 0, 0), scale: 1.3, tint: green)
        lit.group = 7
        let props = [lit,
                     .prop(pine, at: .init(5, 0, 5), forward: .init(0, 0, 1), scale: 1, tint: green),
                     .prop(bush, at: .init(6, 0, 5), forward: .init(0, 0, 1), scale: 1, tint: green),
                     .prop(lamp, at: .init(7, 0, 5), forward: .init(0, 0, 1), scale: 1, tint: 0x123456)]
        let snowed = Map3DSnowTrees.cover(props)
        XCTAssertEqual(snowed.map(\.model), props.map(\.model))
        XCTAssertEqual(snowed.map(\.transform), props.map(\.transform))
        XCTAssertEqual(snowed[0].group, 7)
        XCTAssertEqual([snowed[3].stripe.0, snowed[3].stripe.1, snowed[3].stripe.2], [props[3].stripe.0, props[3].stripe.1, props[3].stripe.2])
        let white = Map3DSnowGround.field
        func whiteness(_ i: Map3DInstance) -> Float { (i.stripe.0 + i.stripe.1 + i.stripe.2) / 3 }
        let snowWhite = Float((white & 0xFF) + (white >> 8 & 0xFF) + (white >> 16 & 0xFF)) / 3 / 255
        func share(_ index: Int) -> Float { (whiteness(snowed[index]) - whiteness(props[index])) / (snowWhite - whiteness(props[index])) }
        XCTAssertEqual(share(0), Map3DSnowTrees.broadleafShare, accuracy: 1e-4)
        XCTAssertEqual(share(1), Map3DSnowTrees.coniferShare, accuracy: 1e-4)
        XCTAssertEqual(share(2), Map3DSnowTrees.bushShare, accuracy: 1e-4)
        XCTAssertLessThan(Map3DSnowTrees.coniferShare, Map3DSnowTrees.broadleafShare)
        XCTAssertLessThan(Map3DSnowTrees.broadleafShare, Map3DSnowTrees.bushShare)
        // Every tree model the woods and streets plant is known.
        XCTAssertEqual(Map3DSnowTrees.shares.count, 1 + Map3DSceneryProp.conifers.count + 2)
    }

    // MARK: Rovaniemi's scene

    /// Round Rovaniemi's station no water ripples (the two rivers are
    /// ice) and no tree is in a summer green; Taiwan's scene is as before.
    func testRovaniemisSceneIsFrozenAndItsTreesUnderSnow() throws {
        let ground = try RovaniemiRailwaysTests.ground()
        let world = GameWorld.newOverseasGame(ground)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let focus = frame.worldPosition(latitude: 66.4977, longitude: 25.7143)
        let baseMap = try BaseMapTiles(data: Data(contentsOf: HongKongBaseMapTests.taiwan, options: .alwaysMapped), cities: [XCTUnwrap(ground.baseMap)])
        let scene = Map3DScene(world: world, focus: focus, baseMap: baseMap)
        var layers = Set<Float>()
        for chunk in scene.chunks { layers.formUnion(chunk.mesh.vertices.map(\.layer)); layers.formUnion(chunk.far.vertices.map(\.layer)) }
        XCTAssertFalse(layers.contains(Map3DVertex.water))
        XCTAssertTrue(layers.contains(Map3DVertex.ice))
        let shares = Map3DSnowTrees.shares
        let trees = scene.chunks.flatMap(\.props).filter { shares[$0.model] != nil }
        XCTAssertFalse(trees.isEmpty)
        let summer = Set((Map3DProp.greens + Map3DSceneryProp.coniferGreens + Map3DSceneryProp.bushGreens + Map3DScene.Builder.broadleafGreens).map { colour in
            [Float(colour & 0xFF) / 255, Float(colour >> 8 & 0xFF) / 255, Float(colour >> 16 & 0xFF) / 255]
        })
        for tree in trees { XCTAssertFalse(summer.contains([tree.stripe.0, tree.stripe.1, tree.stripe.2])) }
    }
}
