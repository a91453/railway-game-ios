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
            // A wall facing the camera's side, away from the moon.
            let wall = Self.luminance(light.lit(Self.whiteWall, normal: Map3DPoint(0, 0, -1)))
            let hour = minute / 60
            XCTAssertGreaterThanOrEqual(ground, 0.33, "the ground at \(hour) h")
            XCTAssertGreaterThanOrEqual(ground - road, 0.15, "a road stands out from the ground at \(hour) h")
            XCTAssertGreaterThanOrEqual(ground - park, 0.02, "a park stands out from the ground at \(hour) h")
            XCTAssertGreaterThanOrEqual(wall, 0.25, "a wall at \(hour) h")
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
}
