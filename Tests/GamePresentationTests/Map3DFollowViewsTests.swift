@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 403 (續): the 3D follow camera beside the train (the owner's
/// OpenWorld reference's watch view) and from the platform of its stop.
final class Map3DFollowViewsTests: XCTestCase {
    private let train = TrainID(rawValue: 7)

    /// A train running toward `heading` (radians clockwise from north),
    /// its cars' middle at (x, z) and `length` metres long.
    private func head(x: Float, z: Float, heading: Float, length: Float) -> Map3DTrains.Head {
        let forward = Map3DPoint(sinf(heading), 0, -cosf(heading))
        let middle = Map3DPoint(x, 2, z)
        let nose = middle + forward * (length / 2)
        var head = Map3DTrains.Head(train: train, point: nose + Map3DPoint(0, Map3DTrains.carHeight + Map3DTrains.headClearance, 0),
                                    forward: forward, nose: nose)
        head.middle = middle
        head.length = length
        return head
    }

    /// The reference's offsets for one car on a screen as wide as tall: 33 m
    /// to the train's left, 16 m back, 10 m up, looking at the middle of
    /// the cars half way up them, through 58°.
    func testBesideTheTrainStandsAsTheReferenceWatches() {
        let running = head(x: 100, z: -50, heading: .pi / 2, length: 20)  // east: left is north
        let camera = Map3DFollow(train: train, view: .side)
            .camera(following: running, from: Map3DCamera(viewport: (800, 800)), elapsed: 0, turnsAtOnce: true)
        let middle = running.middle! + Map3DPoint(0, Map3DTrains.carHeight / 2, 0)
        XCTAssertEqual(camera.eye.x, middle.x - 16, accuracy: 0.01, "16 m back")
        XCTAssertEqual(camera.eye.z, middle.z - 33, accuracy: 0.01, "33 m to its left, north of a train running east")
        XCTAssertEqual(camera.eye.y, middle.y + 10, accuracy: 0.01, "10 m up")
        XCTAssertEqual(camera.fieldOfViewTall * 180 / .pi, 58, accuracy: 0.001)
        // Nearer than the camera comes, so it looks on past the middle.
        XCTAssertEqual(camera.distance, Map3DCamera.nearest)
        let look = (camera.target - camera.eye).normalized!, toMiddle = (middle - camera.eye).normalized!
        XCTAssertEqual(look.dot(toMiddle), 1, accuracy: 0.0001, "looking at the middle of the cars")
        XCTAssertEqual(Map3DCamera.turnFromNorth(camera.heading - .pi / 2), Map3DFollow.sideBearing, accuracy: 0.0001)
    }

    /// A longer train, a phone held upright and a pinch stand it farther:
    /// by its length over one car, by 0.92 over the screen's width to
    /// height (at most 2.3), and by the pinch's scale.
    func testBesideALongTrainStandsFartherOut() {
        XCTAssertEqual(Map3DFollow.sideScale(length: 10, viewport: (800, 800)), 1, "never nearer than for one car")
        XCTAssertEqual(Map3DFollow.sideScale(length: 27.75 * 8, viewport: (800, 800)), 8, accuracy: 0.001)
        XCTAssertEqual(Map3DFollow.sideScale(length: 27.75, viewport: (390, 844)), 0.92 / (390.0 / 844), accuracy: 0.001)
        XCTAssertEqual(Map3DFollow.sideScale(length: 27.75, viewport: (100, 844)), 2.3, accuracy: 0.001)
        XCTAssertEqual(Map3DFollow.sideScale(length: 27.75, viewport: (1_000, 400)), 1)
        let running = head(x: 0, z: 0, heading: 0, length: 222)
        var follow = Map3DFollow(train: train, view: .side)
        let start = Map3DCamera(viewport: (844, 390))
        let near = follow.camera(following: running, from: start, elapsed: 0, turnsAtOnce: true)
        let away = Map3DPoint(running.middle!.x - near.eye.x, 0, running.middle!.z - near.eye.z).length
        XCTAssertEqual(away, Map3DFollow.sideAway * 8, accuracy: 0.05)
        follow = follow.zoomed(by: 0.5)
        let far = follow.camera(following: running, from: start, elapsed: 0, turnsAtOnce: true)
        XCTAssertEqual(Map3DPoint(running.middle!.x - far.eye.x, 0, running.middle!.z - far.eye.z).length, away * 2, accuracy: 0.1)
    }

    /// Beside it, the camera turns after the train as from behind: 2 % of
    /// the way a 60th of a second.
    func testBesideTheTrainTurnsAfterItSlowly() {
        let follow = Map3DFollow(train: train, view: .side)
        let start = follow.camera(following: head(x: 0, z: 0, heading: 0, length: 100), from: Map3DCamera(viewport: (390, 844)),
                                  elapsed: 0, turnsAtOnce: true)
        let turned = follow.camera(following: head(x: 0, z: 0, heading: 0.5, length: 100), from: start, elapsed: 1 / 60)
        XCTAssertEqual(Map3DCamera.turnFromNorth(turned.heading - Map3DFollow.sideBearing), 0.01, accuracy: 0.0001)
    }

    /// From the station the eye stays where the lookout stands, looking at
    /// the front of the train half way up it; a pinch does not move it.
    /// With no platform to stand on, it follows from behind.
    func testFromTheStationTheEyeStaysOnThePlatform() {
        let eye = Map3DPoint(500, 4.75, -3.2)
        var follow = Map3DFollow(train: train, view: .station)
        follow.lookout = .init(station: StationID(rawValue: 2), eye: eye)
        for scale: Float in [1, 0.25] {
            let running = head(x: 0, z: 0, heading: .pi / 2, length: 100)
            let camera = follow.zoomed(by: scale).camera(following: running, from: Map3DCamera(viewport: (390, 844)), elapsed: 0)
            XCTAssertEqual((camera.eye - eye).length, 0, accuracy: 0.01)
            let look = (camera.target - camera.eye).normalized!
            let toFront = (running.nose + Map3DPoint(0, Map3DTrains.carHeight / 2, 0) - eye).normalized!
            XCTAssertEqual(look.dot(toFront), 1, accuracy: 0.0001)
            XCTAssertEqual(camera.fieldOfViewTall, Map3DFollow.watchLens)
        }
        follow.lookout = nil
        let running = head(x: 0, z: 0, heading: 0, length: 100)
        let behind = follow.camera(following: running, from: Map3DCamera(viewport: (390, 844)), elapsed: 0, turnsAtOnce: true)
        let back = Map3DFollow(train: train).camera(following: running, from: Map3DCamera(viewport: (390, 844)), elapsed: 0, turnsAtOnce: true)
        XCTAssertEqual(behind, back)
    }

    func testTheButtonsSayWhatTheyDo() {
        XCTAssertEqual(Map3DFollow.View.side.text(in: .traditionalChinese), "旁邊")
        XCTAssertEqual(Map3DFollow.View.station.text(in: .traditionalChinese), "從車站看")
        XCTAssertEqual(Map3DFollow.View.side.text(in: .english), "Side")
        XCTAssertEqual(Map3DFollow.View.station.text(in: .english), "Station")
        for view in Map3DFollow.View.allCases {
            XCTAssertFalse(view.hint(in: .english).isEmpty)
            XCTAssertFalse(view.hint(in: .traditionalChinese).isEmpty)
        }
    }

    /// Station A, 1 km east, station B; one train on the line A–B, as
    /// `Map3DDriverHUDTests` (without the curve).
    private func world() throws -> (GameWorld, TrainID, StationID, StationID) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 500))
        )
        let x: Int64 = 8_192, y: Int64 = 8_192
        let points = [WorldCoordinate(x: x, y: y), WorldCoordinate(x: x + 4_096, y: y), WorldCoordinate(x: x + 68_096, y: y),
                      WorldCoordinate(x: x + 72_192, y: y)]
        let nodes = try points.map { try world.buildTrackNode(at: $0) }
        let first = try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        _ = try world.buildTrackEdge(from: nodes[1], to: nodes[2])
        let last = try world.buildTrackEdge(from: nodes[2], to: nodes[3])
        let a = try world.buildStation(named: "A", at: PlanPoint(x: x + 2_048, y: y + 512)).id
        try world.addTrackPlatform(a, on: first, from: 0, to: 4_096)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: x + 70_144, y: y + 512)).id
        try world.addTrackPlatform(b, on: last, from: 0, to: 4_096)
        try world.createLine(named: "Main", stops: [a, b])
        let line = LineID(rawValue: 1)
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        world.setRealisticOperation(true)
        let train = try world.purchaseTrain(named: "Blue").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: first, direction: .forward), offset: 4_096))
        try world.setTrainMovementRate(train, to: 1024)
        try world.assignTrain(train, to: line)
        world.setSpeed(.normal)
        return (world, train, a, b)
    }

    /// The station watched: A while it stands there and just after it
    /// leaves (until twice its length and 100 m past), then B, and B on
    /// arriving; the eye on A's platform, 3.2 m to the left of the track
    /// (north of a track running east), a person's eye over it.
    func testTheStationWatchedMovesOnOnceTheTrainIsWellPast() throws {
        var (world, train, a, b) = try world()
        var seen: [StationID] = [], sawLeft = false
        for _ in 0..<1_500 {
            try world.advance(ticks: 1)
            guard let stop = world.map3DLookoutStop(of: train) else { continue }
            if seen.last != stop.station { seen.append(stop.station) }
            if stop.left {
                sawLeft = true
                XCTAssertEqual(stop.station, a, "only A is left here")
                if case .travellingToStop? = world.train(id: train)?.execution {} else { XCTFail("left only while running on") }
            }
            if seen.count == 2, case .waitingAtStop? = world.train(id: train)?.execution { break }
        }
        XCTAssertEqual(Array(seen.prefix(2)), [a, b])
        XCTAssertTrue(sawLeft, "A stays watched as the train sets off")
        XCTAssertEqual(Map3DFollow.stationLingerMetres(trainLength: 64 * 40), 180)

        let scene = Map3DScene(world: world)
        let lookout = try XCTUnwrap(Map3DFollow.lookout(of: train, in: world, scene: scene))
        XCTAssertEqual(lookout.station, b)
        let platform = try XCTUnwrap(world.trackPlatforms(of: b).first)
        let middle = try XCTUnwrap(Map3DNextDeparture.middle(of: platform, in: world, scene: scene))
        XCTAssertEqual(lookout.eye.x, middle.point.x, accuracy: 0.01)
        XCTAssertEqual(lookout.eye.z, middle.point.z - Map3DFollow.stationEyeAcross, accuracy: 0.01, "north, the track's left")
        XCTAssertEqual(lookout.eye.y, middle.point.y + Map3DFollow.stationEyeHeight, accuracy: 0.01)
    }
}
