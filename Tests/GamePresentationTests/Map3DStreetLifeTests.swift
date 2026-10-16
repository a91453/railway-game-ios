import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 256: the people, scooters and cars of the 3D map's
/// streets, worked out every frame from the clock, as many as the game's
/// passengers and towns say.
final class Map3DStreetLifeTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let tiles: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }
    private let pack = Map3DModelPack.standard

    private func model(_ kind: Map3DStreetModel) throws -> Map3DModelPack.Model {
        pack.models[try XCTUnwrap(pack.index(of: kind.modelName))]
    }

    func testTheModelsAreSmallAndTheirRealSizes() throws {
        for (kind, height, length, triangles) in [
            (Map3DStreetModel.standing, Float(1.67), Float(0.3), 60...90), (.walking, 1.67, 0.45, 60...90),
            (.scooter, 1.68, 1.8, 120...200), (.scooterPair, 1.68, 1.8, 150...260), (.car, 1.46, 4.5, 80...160), (.van, 1.9, 4.7, 80...160),
        ] {
            let shape = try model(kind)
            XCTAssertEqual(shape.minimum.z, 0, accuracy: 0.01, "\(kind) stands on the ground")
            XCTAssertEqual(shape.maximum.z, height, accuracy: 0.05, "\(kind)")
            XCTAssertEqual(shape.length, length, accuracy: 0.12, "\(kind)")
            XCTAssertTrue(triangles.contains(shape.triangleCount), "\(kind): \(shape.triangleCount) triangles")
            // Its top or paint takes the instance's colour (alpha 0).
            XCTAssertTrue(shape.vertices.contains { $0.color >> 24 == 0 }, "\(kind)")
        }
        // A walker's stride is wider than a standing figure's.
        XCTAssertGreaterThan(try model(.walking).length, try model(.standing).length + 0.1)
        // Vehicles' lamps glow at night (decision 229 續), a figure nothing.
        for kind in [Map3DStreetModel.scooter, .car, .van] {
            XCTAssertTrue(try model(kind).vertices.contains { $0.layer == Map3DVertex.glowing }, "\(kind)")
        }
        XCTAssertFalse(try model(.standing).vertices.contains { $0.layer == Map3DVertex.glowing })
    }

    func testABusierStationShowsMorePeopleButNeverTooMany() {
        XCTAssertEqual(Map3DStreetLife.platformCrowd(waiting: 0, platforms: 2), 0)
        XCTAssertEqual(Map3DStreetLife.frontCrowd(trips: 0), 2, "a few outside any station")
        var last = 0
        for waiting: Int64 in [10, 50, 150, 400] {
            let shown = Map3DStreetLife.platformCrowd(waiting: waiting, platforms: 1)
            XCTAssertGreaterThan(shown, last, "\(waiting) waiting")
            last = shown
        }
        XCTAssertLessThanOrEqual(Map3DStreetLife.platformCrowd(waiting: 1_000_000, platforms: 1), 36)
        // The waiting share the platforms.
        XCTAssertLessThan(Map3DStreetLife.platformCrowd(waiting: 300, platforms: 4), Map3DStreetLife.platformCrowd(waiting: 300, platforms: 1))
        last = 0
        for trips: Int64 in [100, 1_000, 5_000, 20_000] {
            let shown = Map3DStreetLife.frontCrowd(trips: trips)
            XCTAssertGreaterThan(shown, last, "\(trips) a day")
            last = shown
        }
        XCTAssertLessThanOrEqual(Map3DStreetLife.frontCrowd(trips: 10_000_000), 60)
        // A town's streets: livelier with more people, between 0 and 1.
        XCTAssertEqual(Map3DStreetLife.townLevel(0), 0)
        XCTAssertLessThan(Map3DStreetLife.townLevel(500), Map3DStreetLife.townLevel(5_000))
        XCTAssertLessThanOrEqual(Map3DStreetLife.townLevel(10_000_000), 1)
    }

    func testOlderDevicesDrawLessAndASlowOneStepsDown() {
        XCTAssertEqual(Map3DStreetDetail.forGPUFamily(9), .full, "A16 and on")
        XCTAssertEqual(Map3DStreetDetail.forGPUFamily(8), .full, "A15")
        XCTAssertEqual(Map3DStreetDetail.forGPUFamily(6), .reduced, "A13")
        XCTAssertEqual(Map3DStreetDetail.forGPUFamily(4), .off)
        XCTAssertLessThan(Map3DStreetDetail.reduced.people, Map3DStreetDetail.full.people)
        XCTAssertLessThan(Map3DStreetDetail.reduced.vehicles, Map3DStreetDetail.full.vehicles)
        XCTAssertEqual(Map3DStreetDetail.full.lowered, .reduced)
        XCTAssertEqual(Map3DStreetDetail.off.lowered, .off)
        XCTAssertTrue(Map3DStreetDetail.shouldLower(framesPerSecond: 40, aim: 60, windows: 3))
        XCTAssertFalse(Map3DStreetDetail.shouldLower(framesPerSecond: 40, aim: 60, windows: 2), "not for one slow moment")
        XCTAssertFalse(Map3DStreetDetail.shouldLower(framesPerSecond: 55, aim: 60, windows: 10))
    }

    // MARK: - Two towns and a line

    private func lineBetweenTwoTowns() throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        return try newGameLine(through: [towns[0], towns[1]])
    }

    /// The middle of the first station's platform spot.
    private func station(in life: Map3DStreetLife) throws -> (StationID, Map3DPoint) {
        let spot = try XCTUnwrap(life.spots.first { $0.kind == .platform })
        return (try XCTUnwrap(spot.station), spot.path.at(spot.path.length / 2).point)
    }

    func testATownHasStreetsShopsAndStationsCrowds() throws {
        let world = try lineBetweenTwoTowns()
        let life = Map3DScene(world: world).streetLife
        XCTAssertGreaterThan(life.lanes.count, 10, "streets between the lots")
        XCTAssertTrue(life.lanes.allSatisfy { $0.twoWay && $0.scooters && $0.path.length >= 1 })
        let kinds = Set(life.spots.map { "\($0.kind)" })
        for kind in ["platform", "stationFront", "shops", "sidewalk"] { XCTAssertTrue(kinds.contains(kind), kind) }
        // Every station with a platform has its crowd there.
        let stations = Set(world.network.platforms.map(\.station))
        XCTAssertEqual(Set(life.spots.filter { $0.kind == .platform }.compactMap(\.station)), stations)
        // Nothing but finite points.
        for spot in life.spots {
            XCTAssertTrue(spot.path.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        }
        // The same every time.
        let again = Map3DScene(world: world).streetLife
        XCTAssertEqual(again.lanes.map(\.path.points), life.lanes.map(\.path.points))
        XCTAssertEqual(again.spots.map(\.people), life.spots.map(\.people))
    }

    func testCloseUpTheStreetsAreAliveAndFromAfarEmpty() throws {
        let world = try lineBetweenTwoTowns()
        let life = Map3DScene(world: world).streetLife
        let (_, middle) = try station(in: life)
        let activity = Map3DStreetLife.Activity(world: world)
        let near = life.frame(target: middle, distance: 300, time: 1_000, detail: .full, activity: activity)
        XCTAssertGreaterThan(near.people, 20)
        XCTAssertGreaterThan(near.vehicles, 5)
        XCTAssertEqual(near.instances.count, near.people + near.vehicles)
        XCTAssertTrue(near.instances.allSatisfy { $0.floats.allSatisfy(\.isFinite) })
        // The same moment is the same picture; a later one, a moved one.
        let again = life.frame(target: middle, distance: 300, time: 1_000, detail: .full, activity: activity)
        XCTAssertEqual(again.instances.map(\.floats), near.instances.map(\.floats))
        let later = life.frame(target: middle, distance: 300, time: 1_004, detail: .full, activity: activity)
        XCTAssertNotEqual(later.instances.map(\.floats), near.instances.map(\.floats))
        // Farther, the people go first, then the vehicles.
        let mid = life.frame(target: middle, distance: 900, time: 1_000, detail: .full, activity: activity)
        XCTAssertEqual(mid.people, 0)
        XCTAssertGreaterThan(mid.vehicles, 0)
        XCTAssertTrue(life.frame(target: middle, distance: 2_000, time: 1_000, detail: .full, activity: activity).instances.isEmpty)
        // Off draws nothing; reduced at most its share.
        XCTAssertTrue(life.frame(target: middle, distance: 300, time: 1_000, detail: .off, activity: activity).instances.isEmpty)
        let reduced = life.frame(target: middle, distance: 600, time: 1_000, detail: .reduced, activity: activity)
        XCTAssertLessThanOrEqual(reduced.people, Map3DStreetDetail.reduced.people)
        XCTAssertLessThanOrEqual(reduced.vehicles, Map3DStreetDetail.reduced.vehicles)
    }

    func testWithReduceMotionNobodyMovesOrStrides() throws {
        let world = try lineBetweenTwoTowns()
        let life = Map3DScene(world: world).streetLife
        let (_, middle) = try station(in: life)
        let activity = Map3DStreetLife.Activity(world: world)
        let a = life.frame(target: middle, distance: 300, time: 1_000, still: true, detail: .full, activity: activity)
        let b = life.frame(target: middle, distance: 300, time: 5_000, still: true, detail: .full, activity: activity)
        XCTAssertEqual(a.instances.map(\.floats), b.instances.map(\.floats))
        let walking = try XCTUnwrap(pack.index(of: Map3DStreetModel.walking.modelName))
        XCTAssertFalse(a.instances.contains { $0.model == walking })
    }

    func testABusierStationDrawsMorePeopleOnItsPlatforms() throws {
        let world = try lineBetweenTwoTowns()
        let life = Map3DScene(world: world).streetLife
        let (id, middle) = try station(in: life)
        var quiet = Map3DStreetLife.Activity(), busy = Map3DStreetLife.Activity()
        quiet.platform[id] = Map3DStreetLife.platformCrowd(waiting: 5, platforms: 1)
        busy.platform[id] = Map3DStreetLife.platformCrowd(waiting: 600, platforms: 1)
        let few = life.frame(target: middle, distance: 200, time: 0, detail: .full, activity: quiet)
        let many = life.frame(target: middle, distance: 200, time: 0, detail: .full, activity: busy)
        XCTAssertGreaterThan(many.people - few.people, 10)
    }

    func testVehiclesKeepRightAndApart() throws {
        // A straight two-way road, 8 m wide, along +x.
        let path = try XCTUnwrap(Map3DStreetLife.Path([Map3DPoint(0, 0, 0), Map3DPoint(400, 0, 0)]))
        var life = Map3DStreetLife()
        life.lanes = [Map3DStreetLife.Lane(path: path, half: 4, twoWay: true, speed: 11, perHundred: 6, scooters: true, seed: (1, 2))]
        let frame = life.frame(target: Map3DPoint(200, 0, 0), distance: 300, time: 77, detail: .full, activity: .init())
        XCTAssertGreaterThan(frame.vehicles, 30)
        for instance in frame.instances {
            let t = instance.transform
            let heading = t[0] // the model's front along +x, times its size
            let z = t[14]
            // Going east (+x) they keep to the south (+z, the right); going
            // west, to the north.
            if heading > 0.1 { XCTAssertGreaterThan(z, 0.5) }
            if heading < -0.1 { XCTAssertLessThan(z, -0.5) }
            XCTAssertLessThan(abs(z), 4, "on the road")
        }
        // The same way and the same side of the lane: at least 8 m apart.
        let east = frame.instances.filter { $0.transform[0] > 0.9 }.map { ($0.transform[12], $0.transform[14]) }
        for (i, a) in east.enumerated() {
            for b in east[(i + 1)...] where abs(a.1 - b.1) < 0.5 {
                XCTAssertGreaterThan(abs(a.0 - b.0), 8)
            }
        }
    }

    func testAPathFindsItsPointsAndRight() throws {
        let path = try XCTUnwrap(Map3DStreetLife.Path([Map3DPoint(0, 0, 0), Map3DPoint(10, 0, 0), Map3DPoint(10, 0, 10)]))
        XCTAssertEqual(path.length, 20, accuracy: 1e-4)
        let place = path.at(15)
        XCTAssertEqual(place.point.x, 10, accuracy: 1e-4)
        XCTAssertEqual(place.point.z, 5, accuracy: 1e-4)
        // Going south (+z), the right is west (−x).
        XCTAssertEqual(place.right.x, -1, accuracy: 1e-4)
        XCTAssertNil(Map3DStreetLife.Path([Map3DPoint(0, 0, 0)]))
    }

    // MARK: - A real map

    func testTaipeiHasTrafficOnItsRoadsAndScootersOffTheMotorway() throws {
        let tiles = try Self.tiles.get()
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let life = Map3DScene(world: world, baseMap: tiles).streetLife
        XCTAssertGreaterThan(life.lanes.count, 500)
        XCTAssertGreaterThan(life.spots.filter { $0.kind == .sidewalk }.count, 100)
        XCTAssertTrue(life.lanes.contains { !$0.scooters }, "the motorway's")
        XCTAssertNil(Map3DScene.Builder.traffic(.service), "no traffic in a yard")
        let frame = life.frame(target: .zero, distance: 400, time: 0, detail: .full, activity: .init())
        XCTAssertGreaterThan(frame.vehicles, 50)
        XCTAssertLessThanOrEqual(frame.vehicles, Map3DStreetDetail.full.vehicles)
        XCTAssertLessThanOrEqual(frame.people, Map3DStreetDetail.full.people)
    }
}
