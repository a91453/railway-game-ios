import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The owner's TestFlight report on the native 3D map (2026-10-16): "晚上
/// 3D 是不是偏暗？然後地形能不能平緩一點，3D 直接突然突起。" The night's
/// light as the shaders finally give it (decision 229 續), and the ground
/// of a real-world map, whose blocks the world has not read no longer
/// fall to 0 m beside those it has (decision 234 續).
final class Map3DNightAndGroundTests: XCTestCase {
    // MARK: - Night

    /// How bright a lit colour looks (Rec. 709 weights on the values the
    /// screen shows; the view draws them as they are, no tone mapping).
    private static func luminance(_ colour: SIMD3<Float>) -> Float {
        0.2126 * colour.x + 0.7152 * colour.y + 0.0722 * colour.z
    }

    private static func colour(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF)) / 255
    }

    private static let ground = colour(0xD9DFEF)
    private static let primaryRoad = colour(0x4E5682)
    private static let park = colour(0xB5D6A2)
    private static let whiteWall = colour(0xFFFFFF)

    /// The night and dusk minutes the owner's screenshots were taken at,
    /// and the rest of the dark hours.
    private static let darkMinutes: [Double] = [18 * 60 + 30, 19 * 60, 19 * 60 + 30, 20 * 60, 21 * 60, 23 * 60, 0, 2 * 60, 4 * 60, 5 * 60]

    func testAtNightTheGroundRoadsParksAndWallsCanBeMadeOut() {
        for minute in Self.darkMinutes {
            let light = Map3DLighting(minute: minute)
            let ground = Self.luminance(light.lit(Self.ground, normal: .up))
            let road = Self.luminance(light.lit(Self.primaryRoad, normal: .up))
            let park = Self.luminance(light.lit(Self.park, normal: .up))
            // A wall facing the camera's side, away from the moon (its lit
            // windows show the rest of the building).
            let wall = Self.luminance(light.lit(Self.whiteWall, normal: Map3DPoint(0, 0, -1)))
            let hour = minute / 60
            XCTAssertGreaterThanOrEqual(ground, 0.33, "the ground at \(hour) h")
            XCTAssertGreaterThanOrEqual(ground - road, 0.15, "a road stands out from the ground at \(hour) h")
            XCTAssertGreaterThanOrEqual(ground - park, 0.02, "a park stands out from the ground at \(hour) h")
            XCTAssertGreaterThanOrEqual(wall, 0.22, "a wall at \(hour) h")
        }
    }

    func testTheNightStaysANightBlueAndDarkerThanTheDay() {
        let noon = Self.luminance(Map3DLighting(minute: 12 * 60).lit(Self.ground, normal: .up))
        for minute: Double in [21 * 60, 0, 3 * 60] {
            let light = Map3DLighting(minute: minute)
            let ground = light.lit(Self.ground, normal: .up)
            XCTAssertLessThanOrEqual(Self.luminance(ground), noon * 0.6, "the night is darker than the day")
            XCTAssertGreaterThan(ground.z, ground.x, "a blue night")
        }
    }

    // MARK: - The city's lights

    func testTheCitysLightsAreOnAtNightAndOffByDay() {
        for minute: Double in [21 * 60, 0, 3 * 60] {
            let light = Map3DLighting(minute: minute)
            XCTAssertEqual(light.lights, 1, "\(minute / 60) h")
            XCTAssertGreaterThan(Self.luminance(light.lampGlow(Self.colour(0xFFE3B0))), 0.8, "a street light shines")
        }
        XCTAssertGreaterThan(Map3DLighting(minute: 18 * 60 + 30).lights, 0.9, "on while the dusk is still light")
        for minute: Double in [8 * 60, 12 * 60, 15 * 60] {
            let light = Map3DLighting(minute: minute)
            XCTAssertEqual(light.lights, 0, "\(minute / 60) h")
            XCTAssertEqual(light.lampGlow(Self.colour(0xFFE3B0)), .zero)
        }
    }

    func testAStreetLightsHeadGlowsAndNothingElseOfIt() throws {
        let pack = Map3DModelPack.standard
        let lamp = pack.models[try XCTUnwrap(pack.index(of: Map3DProp.lamp.modelName))]
        let glowing = lamp.vertices.filter(\.glows)
        XCTAssertFalse(glowing.isEmpty)
        // The head, out on the arm (+y) at the top (+z, model space).
        XCTAssertTrue(glowing.allSatisfy { $0.z > 8.4 && $0.y > 1.8 }, "only the head")
        XCTAssertTrue(lamp.vertices.filter { $0.z < 8 }.allSatisfy { !$0.glows }, "not the mast")
        for model in ["prop-tree", "prop-pole"] {
            XCTAssertFalse(pack.models[try XCTUnwrap(pack.index(of: model))].vertices.contains(where: \.glows), model)
        }
    }

    func testEveryStreetLightCastsAPoolUnderItsHead() throws {
        let tiles = try BaseMapTiles(data: Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let scene = Map3DScene(world: world, baseMap: tiles)
        let lamp = try XCTUnwrap(Map3DModelPack.standard.index(of: Map3DProp.lamp.modelName))
        let lamps = scene.chunks.flatMap(\.props).filter { $0.model == lamp }
        // A pool's middle: a coloured shadow vertex that is not clear.
        let pools = scene.chunks.flatMap(\.shadows.vertices).filter { $0.color & 0x00FF_FFFF != 0 && $0.color >> 24 > 0 }
        XCTAssertGreaterThan(lamps.count, 100)
        XCTAssertEqual(pools.count, lamps.count, "one pool a light")
        // Each under its own head: 2.25 m out from its foot, toward the road.
        for instance in lamps.prefix(50) {
            let t = instance.transform
            let head = Map3DPoint(t[12] + t[4] * 2.25, 0, t[14] + t[6] * 2.25)
            XCTAssertTrue(pools.contains { abs($0.x - head.x) < 0.01 && abs($0.z - head.z) < 0.01 }, "a pool under \(head)")
        }
        // Shadows stay black: only the pools carry a colour.
        XCTAssertTrue(scene.chunks.flatMap(\.shadows.vertices).allSatisfy { $0.color & 0x00FF_FFFF == 0 || $0.color & 0x00FF_FFFF == Map3DProp.lampLight & 0x00FF_FFFF })
    }

    /// The light on a roof turns from the sun to the moon without a step at
    /// 18:00 (and back at 06:00): on main the roof's green fell from 0.334
    /// to 0.274 between 17:59:59 and 18:00.
    func testARoofsLightHasNoStepAtDawnOrDusk() {
        let grey = SIMD3<Float>(repeating: 0.6)
        for minute in [360.0, 1_080.0] {
            let before = Map3DLighting(minute: minute - 0.01).lit(grey, normal: .up)
            let after = Map3DLighting(minute: minute).lit(grey, normal: .up)
            XCTAssertEqual(before.y, after.y, accuracy: 0.01, "a roof at \(minute - 0.01) and \(minute) minutes")
        }
    }

    /// A chunk's box holds its street trees, lights and poles too: the
    /// renderer leaves out a chunk whose box is off screen, and a box of
    /// the ground and buildings alone cut off a 10 m pole's top while it
    /// was still in view.
    func testAChunksBoxHoldsItsProps() throws {
        let tiles = try BaseMapTiles(data: Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let scene = Map3DScene(world: world, baseMap: tiles)
        let pack = Map3DModelPack.standard
        var checked = 0, outside: [String] = []
        for chunk in scene.chunks {
            for instance in chunk.props {
                let model = pack.models[instance.model], t = instance.transform
                for x in [model.minimum.x, model.maximum.x] {
                    for y in [model.minimum.y, model.maximum.y] {
                        for z in [model.minimum.z, model.maximum.z] {
                            let p = Map3DPoint(t[0] * x + t[4] * y + t[8] * z + t[12], t[1] * x + t[5] * y + t[9] * z + t[13], t[2] * x + t[6] * y + t[10] * z + t[14])
                            let inside = (chunk.minimum.x - 0.01...chunk.maximum.x + 0.01).contains(p.x)
                                && (chunk.minimum.y - 0.01...chunk.maximum.y + 0.01).contains(p.y)
                                && (chunk.minimum.z - 0.01...chunk.maximum.z + 0.01).contains(p.z)
                            if !inside, outside.count < 5 { outside.append("\(model.name) \(p) outside \(chunk.minimum)…\(chunk.maximum)") }
                        }
                    }
                }
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 100)
        XCTAssertTrue(outside.isEmpty, "\(outside)")
    }

    func testShopsAreLitMoreOftenThanOfficesAndOfficesThanHomes() {
        let rows = Map3DLighting.nightWindowRows
        XCTAssertEqual(rows.count, Map3DLighting.nightWindowRowCount * 4, "as many as the shader's rows")
        for surface in Map3DSurface.allCases {
            let rule = Map3DNightWindows.rule(surface)
            XCTAssertEqual(rows[surface.rawValue * 2], rule.share, "\(surface)")
            XCTAssertEqual(rows[surface.rawValue * 2 + 1], rule.brightest, "\(surface)")
        }
        let shop = Map3DNightWindows.rule(.shopEatery).share, office = Map3DNightWindows.rule(.officeGlass).share
        let home = Map3DNightWindows.rule(.homeWindows).share
        XCTAssertGreaterThan(shop, office)
        XCTAssertGreaterThan(office, home)
        XCTAssertGreaterThan(home, 0)
        for dark in [Map3DSurface.shutter, .plaster, .roof, .concrete, .formConcrete] {
            XCTAssertEqual(Map3DNightWindows.rule(dark).share, 0, "\(dark) has no windows to light")
        }
    }

    // MARK: - Ground

    private static let heights: HeightGrid = {
        do {
            return try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    /// The corner of the 64 m grid over `region` whose ground as
    /// `builder` lays it is furthest from the heights file's there, and how
    /// far, in metres.
    private static func furthestFromTheFile(_ builder: Map3DScene.Builder, in region: WorldRegion,
                                            frame: RealWorldFrame) -> (gap: Float, at: (x: Double, y: Double)) {
        let cell = Double(Land.cellLength)
        let firstColumn = Int((region.minX / cell).rounded(.down)), lastColumn = Int((region.maxX / cell).rounded(.up))
        let firstRow = Int((region.minY / cell).rounded(.down)), lastRow = Int((region.maxY / cell).rounded(.up))
        var furthest: (gap: Float, at: (x: Double, y: Double)) = (0, (0, 0))
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                let x = Double(column) * cell, y = Double(row) * cell
                let file = Float(heights.height(at: PlanPoint(x: Int64(x), y: Int64(y)), frame: frame).rounded())
                let gap = abs(builder.ground(x: x, y: y) - file)
                if gap > furthest.gap { furthest = (gap, (x, y)) }
            }
        }
        return furthest
    }

    /// The Puli basin, some 450 m up and nearly level: a game there has
    /// read the ground of the one block its first track came to.
    private static func puliWithOneBlockRead() throws -> (world: GameWorld, centre: (x: Double, y: Double)) {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 23.966, longitudeDegrees: 120.968))
        var world = GameWorld.newGame(anchor: anchor)
        try world.mapGround()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let block = LandBlock(row: 6, column: 6)
        try world.setGround(heights.ground(of: [block], frame: frame))
        let length = Double(Land.blockLength)
        return (world, ((Double(block.column) + 0.5) * length, (Double(block.row) + 0.5) * length))
    }

    func testTheBlocksNotYetReadMeetTheReadOnesWithoutACliff() throws {
        let (world, centre) = try Self.puliWithOneBlockRead()
        let scene = Map3DScene(world: world, focus: centre, heights: Self.heights)
        let read = Map3DScene.Builder(originX: scene.originX, originY: scene.originY, region: scene.region, world: world, heights: Self.heights)
        XCTAssertGreaterThan(read.ground(x: centre.x, y: centre.y), 300, "the read block lies high in the basin")
        // Every corner, read or not, at the heights file's ground there:
        // a block not read standing on 0 m would be some 450 m off.
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        // Round the read block's edges, where the cliffs stood.
        let half = Double(Land.blockLength) / 2 + 2 * Double(Land.cellLength)
        let round = WorldRegion(minX: centre.x - half, minY: centre.y - half, maxX: centre.x + half, maxY: centre.y + half)
        let furthest = Self.furthestFromTheFile(read, in: round, frame: frame)
        XCTAssertLessThanOrEqual(furthest.gap, 0.5, "no cliff, at \(furthest.at)")
        // The same ground the scene lays its squares and shadows on.
        var drawn = read
        let besideX = Float(Double(Land.blockLength) / Double(WorldCoordinate.unitsPerMetre))
        let inside = drawn.drawnGround(x: Float((centre.x - scene.originX) / Double(WorldCoordinate.unitsPerMetre)), z: 0)
        let outside = drawn.drawnGround(x: Float((centre.x - scene.originX) / Double(WorldCoordinate.unitsPerMetre)) + besideX, z: 0)
        XCTAssertLessThan(abs(inside - outside), 60, "a kilometre on in the basin is not a cliff away")
    }

    func testWithoutTheHeightsFileOrOnAFlatMapTheGroundIsAsBefore() throws {
        // A blank map's ground is 0 m everywhere, past its edge too.
        let blank = GameWorld.newGame()
        let builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: -2_000, minY: -2_000, maxX: 2_000, maxY: 2_000),
                                         world: blank, heights: Self.heights)
        XCTAssertEqual(builder.ground(x: 500, y: 500), 0)
        XCTAssertEqual(builder.ground(x: -500, y: -500), 0)
        // A real-world map with no heights file: what it has read.
        let (world, centre) = try Self.puliWithOneBlockRead()
        let alone = Map3DScene.Builder(originX: centre.x, originY: centre.y, region: WorldRegion(minX: centre.x - 100, minY: centre.y - 100,
                                                                                                  maxX: centre.x + 100, maxY: centre.y + 100), world: world)
        XCTAssertGreaterThan(alone.ground(x: centre.x, y: centre.y), 300)
        XCTAssertEqual(alone.ground(x: centre.x + Double(Land.blockLength), y: centre.y), 0)
    }

    /// Decision 271: by day the light a little stronger (a bright, clear
    /// day, as the owner's target picture), the night as it was.
    func testTheDayIsBrighterAndTheNightAsItWas() {
        let noon = Map3DLighting(minute: 12 * 60), midnight = Map3DLighting(minute: 0)
        XCTAssertEqual(noon.dayBoost, 1 + Map3DLighting.dayBrightening, accuracy: 1e-6)
        XCTAssertEqual(midnight.dayBoost, 1, accuracy: 1e-6)
        let plainNoon = Map3DLighting.rgb(noon.sun) * (noon.sunStrength * 0.16)
        XCTAssertEqual(noon.sunLight.x, plainNoon.x * (1 + Map3DLighting.dayBrightening), accuracy: 1e-5)
        let plainNight = Map3DLighting.rgb(midnight.sun) * (midnight.sunStrength * 0.16)
        XCTAssertEqual(midnight.sunLight.x, plainNight.x, accuracy: 1e-6)
        // A white roof at noon comes to about white, not far past it.
        let roof = noon.lit(SIMD3<Float>(0.77, 0.78, 0.84), normal: Map3DPoint(0, 1, 0))
        XCTAssertLessThan(roof.max(), 1.25)
    }
}
