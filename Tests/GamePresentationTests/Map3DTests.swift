import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 229: the native 3D map's geometry, camera and light,
/// worked out without a GPU.
final class Map3DTests: XCTestCase {
    // MARK: - Geometry

    func testABoxHasATopAndFourSidesFacingOut() {
        var mesh = Map3DMesh()
        mesh.addBox(base: Map3DPoint(10, 0, 20), length: 8, width: 4, height: 6, top: 1, side: 2)
        XCTAssertEqual(mesh.vertices.count, 20)
        XCTAssertEqual(mesh.triangleCount, 10)
        let centre = Map3DPoint(10, 3, 20)
        for quad in 0..<5 {
            let corner = mesh.vertices[quad * 4]
            let normal = Map3DPoint(corner.nx, corner.ny, corner.nz)
            XCTAssertEqual(normal.length, 1, accuracy: 1e-5)
            XCTAssertGreaterThan(normal.dot(corner.position - centre), 0, "face \(quad) faces out")
        }
        XCTAssertEqual(mesh.vertices[0].ny, 1, accuracy: 1e-6, "the top faces up")
        let bounds = try! XCTUnwrap(mesh.bounds)
        XCTAssertEqual(bounds.min, Map3DPoint(8, 0, 16))
        XCTAssertEqual(bounds.max, Map3DPoint(12, 6, 24))
    }

    func testARibbonFacesUpAndItsSidesFaceOut() {
        var mesh = Map3DMesh()
        let line = [Map3DPoint(0, 5, 0), Map3DPoint(0, 5, -10), Map3DPoint(5, 5, -20)]
        let top = Map3DColor.rgb(0xFF0000), side = Map3DColor.rgb(0x00FF00)
        mesh.addRibbon(along: line, width: 2, depth: 1, top: top, side: side)
        XCTAssertEqual(mesh.triangleCount, 2 * 3 * 2)
        for quad in stride(from: 0, to: mesh.vertices.count, by: 4) {
            let corner = mesh.vertices[quad]
            if corner.color == top {
                XCTAssertGreaterThan(corner.ny, 0.99, "the top faces up")
            } else {
                // A side faces away from the line's middle.
                let middle = line[0] + (line[1] - line[0]) * 0.5
                if corner.z > -10, corner.z <= 0 {
                    XCTAssertGreaterThan(Map3DPoint(corner.nx, 0, corner.nz).dot(Map3DPoint(corner.x - middle.x, 0, 0)), 0)
                }
            }
        }
    }

    func testTheHashIsRail3DsRandomAt() {
        // Node: geo.js `randomAt(1, 2, 0)`, `randomAt(-37, 512, 9)`, `randomAt(100000, -3, 77)`.
        XCTAssertEqual(map3DRandom(1, 2), 0.5127752334810793, accuracy: 1e-7)
        XCTAssertEqual(map3DRandom(-37, 512, salt: 9), 0.599290736252442, accuracy: 1e-7)
        XCTAssertEqual(map3DRandom(100_000, -3, salt: 77), 0.3857711707241833, accuracy: 1e-7)
    }

    func testAShadedColourKeepsItsAlpha() {
        let white = Map3DColor.rgb(0xFFFFFF)
        XCTAssertEqual(white, 0xFFFF_FFFF)
        XCTAssertEqual(Map3DColor.shaded(white, 0.5), 0xFF80_8080)
        XCTAssertEqual(Map3DColor.rgb(0x112233) & 0xFF, 0x11, "red in the low byte")
    }

    // MARK: - Camera

    func testTheMapTiltsAsItComesCloser() {
        XCTAssertEqual(Map3DCamera.tilt(atDistance: 5_000), 0)
        XCTAssertEqual(Map3DCamera.tilt(atDistance: Map3DCamera.flatFrom), 0)
        XCTAssertEqual(Map3DCamera.tilt(atDistance: Map3DCamera.tiltedFrom), Map3DCamera.mostTilt)
        XCTAssertEqual(Map3DCamera.tilt(atDistance: 60), Map3DCamera.mostTilt)
        // Decision 269: 34–40° at 150–200 m, the target picture's angle.
        for (distance, low, high) in [(Float(200), Float(34), Float(36)), (170, 37.5, 39), (150, 40, 41)] {
            let degrees = Map3DCamera.tilt(atDistance: distance) * 180 / .pi
            XCTAssertTrue((low...high).contains(degrees), "\(distance) m: \(degrees)°")
        }
        var last: Float = -1
        for distance in stride(from: Float(3_000), through: 100, by: -50) {
            let tilt = Map3DCamera.tilt(atDistance: distance)
            XCTAssertGreaterThanOrEqual(tilt, last)
            last = tilt
        }
    }

    func testFromFarAwayNorthIsUpAndEastIsRight() {
        let camera = Map3DCamera(target: Map3DPoint(100, 0, 200), distance: 4_000, viewport: (400, 800))
        let matrix = camera.viewProjection
        let middle = try! XCTUnwrap(matrix.project(camera.target))
        XCTAssertEqual(middle.x, 0, accuracy: 1e-4)
        XCTAssertEqual(middle.y, 0, accuracy: 1e-4)
        XCTAssertTrue((0...1).contains(middle.z))
        let east = try! XCTUnwrap(matrix.project(camera.target + Map3DPoint(100, 0, 0)))
        XCTAssertGreaterThan(east.x, 0.01)
        XCTAssertEqual(east.y, 0, accuracy: 1e-4)
        let north = try! XCTUnwrap(matrix.project(camera.target + Map3DPoint(0, 0, -100)))
        XCTAssertGreaterThan(north.y, 0.01)
        XCTAssertEqual(north.x, 0, accuracy: 1e-4)
    }

    func testCloseUpTheViewLeansNorthAndStillCentresTheTarget() {
        let camera = Map3DCamera(target: .zero, distance: 100, viewport: (800, 400))
        XCTAssertEqual(camera.tilt, Map3DCamera.mostTilt)
        XCTAssertGreaterThan(camera.eye.z, 0, "the eye stands south of the target")
        XCTAssertGreaterThan(camera.eye.y, 0)
        let matrix = camera.viewProjection
        let middle = try! XCTUnwrap(matrix.project(.zero))
        XCTAssertEqual(middle.x, 0, accuracy: 1e-4)
        XCTAssertEqual(middle.y, 0, accuracy: 1e-4)
        // A tower at the target rises up the screen.
        let top = try! XCTUnwrap(matrix.project(Map3DPoint(0, 50, 0)))
        XCTAssertGreaterThan(top.y, 0.05)
    }

    func testDraggingMovesTheGroundWithTheFinger() {
        let camera = Map3DCamera(target: .zero, distance: 1_000, viewport: (400, 800))
        let moved = camera.panned(dx: 100, dy: 0)
        XCTAssertLessThan(moved.target.x, 0, "dragging right brings the west into view")
        XCTAssertEqual(moved.target.z, 0, accuracy: 1e-4)
        let down = camera.panned(dx: 0, dy: 100)
        XCTAssertLessThan(down.target.z, 0, "dragging down brings the north into view")
        XCTAssertEqual(camera.zoomed(by: 2).distance, 500)
        XCTAssertEqual(camera.zoomed(by: 1_000).distance, Map3DCamera.nearest)
        XCTAssertEqual(camera.zoomed(by: 0.0001).distance, Map3DCamera.farthest)
    }

    func testOnlyBoxesInViewAreDrawn() {
        let camera = Map3DCamera(target: .zero, distance: 1_000, viewport: (400, 800))
        let matrix = camera.viewProjection
        XCTAssertTrue(Map3DCamera.sees(minimum: Map3DPoint(-10, 0, -10), maximum: Map3DPoint(10, 20, 10), through: matrix))
        XCTAssertFalse(Map3DCamera.sees(minimum: Map3DPoint(5_000, 0, 0), maximum: Map3DPoint(5_100, 20, 100), through: matrix))
        // A box wider than the view, round it, is seen.
        XCTAssertTrue(Map3DCamera.sees(minimum: Map3DPoint(-9_000, 0, -9_000), maximum: Map3DPoint(9_000, 1, 9_000), through: matrix))
    }

    // MARK: - Light

    func testTheSunRisesInTheEastAndTheNightIsDark() {
        let noon = Map3DLighting(minute: 12 * 60)
        XCTAssertEqual(noon.night, 0)
        XCTAssertGreaterThan(noon.sunDirection.y, 0.7)
        XCTAssertGreaterThan(noon.sunDirection.z, 0, "the noon sun stands in the south")
        let morning = Map3DLighting(minute: 7 * 60)
        XCTAssertGreaterThan(morning.sunDirection.x, 0.5, "the morning sun is in the east")
        let evening = Map3DLighting(minute: 17 * 60)
        XCTAssertLessThan(evening.sunDirection.x, -0.5)
        XCTAssertEqual(Map3DLighting(minute: 0).night, 1)
        XCTAssertEqual(Map3DLighting(minute: 1_440), Map3DLighting(minute: 0))
        XCTAssertEqual(Map3DLighting(minute: -60), Map3DLighting(minute: 23 * 60))
    }

    // MARK: - Scene

    private func lineBetweenTwoTowns() throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        return try newGameLine(through: [towns[0], towns[1]])
    }

    func testTheSceneHoldsTheTrackTheCityAndNothingBroken() throws {
        let world = try lineBetweenTwoTowns()
        let scene = Map3DScene(world: world)
        XCTAssertFalse(scene.chunks.isEmpty)
        XCTAssertGreaterThan(scene.triangleCount, 1_000)
        for chunk in scene.chunks {
            let count = UInt32(chunk.mesh.vertices.count)
            XCTAssertTrue(chunk.mesh.indices.allSatisfy { $0 < count })
            XCTAssertTrue(chunk.mesh.vertices.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            XCTAssertLessThanOrEqual(chunk.minimum.x, chunk.maximum.x)
        }
        // Rails along the middle of every edge, at the rail's height, lifted
        // so the bed shows over the ground (decision 231).
        let colours = scene.chunks.flatMap(\.mesh.vertices).filter { $0.color == Map3DPalette.railTop }
        for alignment in world.railwaySnapshot().edges {
            let middle = alignment.geometry.location(at: alignment.geometry.length / 2).position
            let point = scene.point(middle)
            XCTAssertTrue(colours.contains { abs($0.x - point.x) < 20 && abs($0.z - point.z) < 20 && abs($0.y - (point.y + Map3DScene.railLift)) < 0.01 },
                          "a rail by edge \(alignment.edge.id)")
        }
        // Both towns stand: some houses' walls.
        XCTAssertTrue(scene.chunks.flatMap(\.mesh.vertices).contains { $0.y > 6 })
    }

    func testTheSceneIsTheSameEveryTime() throws {
        let world = try lineBetweenTwoTowns()
        let a = Map3DScene(world: world), b = Map3DScene(world: world)
        XCTAssertEqual(a.chunks.map(\.mesh.vertices), b.chunks.map(\.mesh.vertices))
        XCTAssertEqual(a.chunks.map(\.mesh.indices), b.chunks.map(\.mesh.indices))
    }

    func testAScenePointGoesBackToItsWorldPoint() throws {
        let scene = Map3DScene(world: try lineBetweenTwoTowns())
        let point = scene.point(worldX: scene.originX + 6_400, worldY: scene.originY - 1_280, height: 640)
        XCTAssertEqual(point, Map3DPoint(100, 10, -20))
        let back = scene.worldPosition(of: point)
        XCTAssertEqual(back.x, scene.originX + 6_400)
        XCTAssertEqual(back.y, scene.originY - 1_280)
    }

    func testAViaductStandsOnAPierEvery32Metres() {
        let world = GameWorld.newGame()
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        let line = stride(from: Float(0), through: 200, by: 16).map { Map3DPoint($0, 12, 100) }
        builder.addTrackPiece(line, kind: .viaduct)
        let mesh = builder.chunks().reduce(into: Map3DMesh()) { $0.append($1.mesh) }
        // Piers reach the ground; each is a box of five faces.
        let feet = mesh.vertices.filter { $0.y == 0 }
        XCTAssertEqual(feet.count / 8, 6, "piers at 16, 48, … 176 m")
        XCTAssertTrue(mesh.vertices.contains { $0.color == Map3DPalette.railTop && $0.y == 12 })
    }

    func testATunnelShowsNothingButARailOnTheGroundShowsItsBed() {
        let world = GameWorld.newGame()
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        let line = [Map3DPoint(0, -10, 0), Map3DPoint(100, -10, 0)]
        builder.addTrackPiece(line, kind: .tunnel)
        XCTAssertTrue(builder.chunks().isEmpty)
        builder.addTrackPiece([Map3DPoint(0, 0, 0), Map3DPoint(100, 0, 0)], kind: .surface)
        let mesh = builder.chunks().reduce(into: Map3DMesh()) { $0.append($1.mesh) }
        XCTAssertTrue(mesh.vertices.contains { $0.color == Map3DPalette.ballast })
        XCTAssertEqual(mesh.vertices.filter { $0.color == Map3DPalette.railTop }.count, 2 * 4)
    }

    // MARK: - Trains

    func testEveryCarStandsOnItsTrack() throws {
        var world = try lineBetweenTwoTowns()
        try world.advance(ticks: 30)
        let scene = Map3DScene(world: world)
        let motion = TrainMotion(world: world, time: 0)
        XCTAssertFalse(motion.runs.isEmpty)
        let mesh = Map3DTrains.mesh(motion, progress: 1, heights: Map3DTrains.Heights(world.railwaySnapshot()), in: scene)
        let cars = motion.runs.reduce(0) { $0 + TrainCars.count(length: $1.length, carPitch: $1.carPitch) }
        // A body box and a band box a car, five faces each.
        XCTAssertEqual(mesh.triangleCount, cars * 2 * 10)
        let bounds = try XCTUnwrap(mesh.bounds)
        XCTAssertEqual(bounds.max.y, Map3DTrains.carHeight + Map3DScene.railLift, accuracy: 0.01, "on the rails of the ground's level track")
    }
}

extension Map3DTests {
    /// Decision 227: a train of real cars (a standard car's 20 m) is drawn
    /// with as many cars as it has, not as many 16 m cars as its length
    /// holds.
    func testATrainOfRealCarsShowsItsOwnCars() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var start = GameWorld.newGame()
        start.setRealCarLengths(true)
        var world = try newGameLine(through: [towns[0], towns[1]], in: start)
        let id = try XCTUnwrap(world.trains.first?.id)
        try world.advance(ticks: 30)
        let train = try XCTUnwrap(world.trains.first { $0.id == id })
        XCTAssertNotEqual(train.carPitch, Train.carLength)
        let motion = TrainMotion(world: world, time: 0)
        let run = try XCTUnwrap(motion.runs.first { $0.train == id })
        let cars = TrainCars.count(length: run.length, carPitch: run.carPitch)
        XCTAssertNotEqual(cars, TrainCars.count(length: run.length), "16 m cars would be more")
        let scene = Map3DScene(world: world)
        let frame = Map3DTrains.frame(motion, progress: 1, heights: Map3DTrains.Heights(world.railwaySnapshot()), in: scene, models: nil, eye: nil)
        // A shadow of five faces under each car.
        let all = motion.runs.reduce(0) { $0 + TrainCars.count(length: $1.length, carPitch: $1.carPitch) }
        XCTAssertEqual(frame.shadows.triangleCount, all * 10)
    }
}
