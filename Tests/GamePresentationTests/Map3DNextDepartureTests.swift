import GameCore
@testable import GamePresentation
import XCTest

/// Decision 334: a train on a station's board shown in 3D at the platform
/// it stops at, ringed.
final class Map3DNextDepartureTests: XCTestCase {
    private func playedDemo(ticks: Int = 30) throws -> GameWorld {
        var world = DemoWorld.make(in: .english)
        try world.advance(ticks: ticks)
        return world
    }

    private func central(in world: GameWorld) throws -> StationID {
        try XCTUnwrap(world.stations.first { $0.name == "Central" }).id
    }

    /// Every train calling at Central is shown at one of Central's
    /// platforms; one standing at it, at the one it stands along.
    func testATrainIsShownAtAPlatformOfTheStation() throws {
        var world = DemoWorld.make(in: .english)
        let station = try central(in: world)
        XCTAssertFalse(world.trackPlatforms(of: station).isEmpty)
        var sawStanding = false
        for _ in 0..<400 {
            try world.advance(ticks: 1)
            for row in DepartureBoard(world: world, station: station).directions.flatMap(\.rows) where !row.passes {
                let train = try XCTUnwrap(row.train)
                let departure = Map3DNextDeparture(train: train, station: station, in: world)
                let platform = try XCTUnwrap(departure.platform)
                XCTAssertEqual(platform.station, station)
                XCTAssertTrue(world.trackPlatforms(of: station).contains(platform))
                if let standing = world.trackPlatformsAlongWholeTrain(train).first(where: { $0.station == station }) {
                    sawStanding = true
                    XCTAssertEqual(platform, standing)
                }
            }
            if sawStanding { break }
        }
        XCTAssertTrue(sawStanding, "a train stands at Central within 400 ticks")
    }

    /// A station with no platform on the track has nothing to show.
    func testAStationWithoutPlatformsHasNone() throws {
        let world = try playedDemo()
        let train = try XCTUnwrap(world.trains.first).id
        let departure = Map3DNextDeparture(train: train, station: StationID(rawValue: 9_999), in: world)
        XCTAssertNil(departure.platform)
        XCTAssertNil(departure.opening(in: world))
        XCTAssertNil(departure.camera(in: world, scene: Map3DScene(world: world), from: Map3DCamera()))
    }

    /// The 3D map opens over the platform's middle and the camera looks at
    /// it there, as the map's own camera.
    func testTheCameraLooksAtThePlatformsMiddle() throws {
        let world = try playedDemo()
        let station = try central(in: world)
        let train = try XCTUnwrap(DepartureBoard(world: world, station: station).directions.flatMap(\.rows).first { !$0.passes }?.train)
        let departure = Map3DNextDeparture(train: train, station: station, in: world)
        let opening = try XCTUnwrap(departure.opening(in: world))
        let scene = Map3DScene(world: world, focus: (opening.x, opening.y))
        let camera = try XCTUnwrap(departure.camera(in: world, scene: scene, from: Map3DCamera(distance: 3_000, viewport: (390, 844))))
        let middle = scene.point(worldX: opening.x, worldY: opening.y, height: 0)
        XCTAssertEqual(camera.target.x, middle.x, accuracy: 0.5)
        XCTAssertEqual(camera.target.z, middle.z, accuracy: 0.5)
        XCTAssertNil(camera.pitch, "the map tilts as its own once there")
        XCTAssertTrue(Map3DNextDeparture.distances.contains(camera.distance))
    }

    /// Far enough to show the platform and a fifth more, within limits;
    /// turned the least so it runs across a wide view and up a tall one.
    func testThePlatformRunsAcrossAWideViewAndUpATallOne() {
        let east = Map3DPoint(1, 0, 0)
        let wide = Map3DCamera(heading: 0.2, viewport: (844, 390))
        let across = Map3DNextDeparture.camera(platformAt: .zero, along: east, length: 300, from: wide)
        XCTAssertEqual(across.heading, 0, accuracy: 0.0001, "facing north, the platform runs left to right")
        XCTAssertEqual(across.distance, 300 * 1.2 / (2 * tanf(Map3DCamera.fieldOfView / 2)), accuracy: 0.01)
        let tall = Map3DCamera(heading: -1.4, viewport: (390, 844))
        let up = Map3DNextDeparture.camera(platformAt: .zero, along: east, length: 300, from: tall)
        XCTAssertEqual(up.heading, -.pi / 2, accuracy: 0.0001, "facing west, the platform runs up the screen")
        XCTAssertEqual(Map3DNextDeparture.camera(platformAt: .zero, along: east, length: 10, from: tall).distance,
                       Map3DNextDeparture.distances.lowerBound)
        XCTAssertEqual(Map3DNextDeparture.camera(platformAt: .zero, along: east, length: 5_000, from: tall).distance,
                       Map3DNextDeparture.distances.upperBound)
    }

    /// The train asked about has a flat ring round it, lit at night; no
    /// other train has one.
    func testTheRingedTrainHasARing() throws {
        let world = try playedDemo()
        let motion = TrainMotion(world: world, time: 0)
        let scene = Map3DScene(world: world)
        let heights = Map3DTrains.Heights(world.railwaySnapshot())
        let train = try XCTUnwrap(motion.runs.first).train
        let plain = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: nil, eye: nil)
        let ringed = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: nil, eye: nil, ringed: train)
        let unknown = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: nil, eye: nil, ringed: TrainID(rawValue: 9_999))
        XCTAssertEqual(unknown.boxes.vertices.count, plain.boxes.vertices.count)
        XCTAssertGreaterThan(ringed.boxes.vertices.count, plain.boxes.vertices.count)
        func glowing(_ frame: Map3DTrains.Frame) -> [Map3DVertex] { frame.boxes.vertices.filter { $0.layer == Map3DVertex.glowing } }
        XCTAssertEqual(glowing(ringed).count - glowing(plain).count, ringed.boxes.vertices.count - plain.boxes.vertices.count,
                       "all of the ring is lit at night")
        let head = try XCTUnwrap(ringed.heads.first { $0.train == train })
        let ring = glowing(ringed).filter { ($0.position - head.rail).length < 40 }
        let lowest = try XCTUnwrap(ring.map(\.position.y).min())
        XCTAssertGreaterThan(lowest, head.rail.y, "over the rails, clear of a platform's edge")
    }

    /// A ring round a straight line: two sides beside the cars and two
    /// ends across, clear of the cars by the gap.
    func testARingStandsClearOfTheCars() {
        var mesh = Map3DMesh()
        mesh.addRing(round: [Map3DPoint(0, 0, -20), Map3DPoint(0, 0, 20)])
        XCTAssertFalse(mesh.vertices.isEmpty)
        let xs = mesh.vertices.map(\.position.x), zs = mesh.vertices.map(\.position.z)
        let side = Map3DTrains.carWidth / 2 + Map3DTrains.ringGap
        XCTAssertEqual(xs.max() ?? 0, side + Map3DTrains.ringWidth, accuracy: 0.01)
        XCTAssertEqual(xs.min() ?? 0, -side - Map3DTrains.ringWidth, accuracy: 0.01)
        XCTAssertEqual(zs.max() ?? 0, 20 + Map3DTrains.ringGap + Map3DTrains.ringWidth, accuracy: 0.01)
        XCTAssertFalse(mesh.vertices.contains { abs($0.position.x) < side - 0.01 && abs($0.position.z) < 20 + Map3DTrains.ringGap - 0.01 },
                       "nothing over the cars")
        var empty = Map3DMesh()
        empty.addRing(round: [Map3DPoint(0, 0, 0)])
        XCTAssertTrue(empty.vertices.isEmpty)
    }
}
