import GameCore
@testable import GamePresentation
import XCTest

/// Decision 987 (PHOTO-MODE): which train and station the photo mode goes
/// to next, and where its camera stands at each spot.
final class PhotoSpotsTests: XCTestCase {
    private typealias Place = PhotoTour.Place

    private func playedDemo(ticks: Int = 30) throws -> GameWorld {
        var world = DemoWorld.make(in: .english)
        try world.advance(ticks: ticks)
        return world
    }

    // MARK: - The round

    /// Each tap goes to the nearest one not shown yet, from where the
    /// camera is then; ties go to the smaller ID.
    func testEachTapGoesToTheNearestNotShownYet() {
        let places = [Place(id: 3, x: 300, y: 0), Place(id: 1, x: 100, y: 0), Place(id: 2, x: -100, y: 0)]
        var shown: [Int] = []
        XCTAssertEqual(PhotoTour.next(among: places, nearX: 0, y: 0, shown: &shown), 1, "1 and 2 are as near: the smaller ID")
        XCTAssertEqual(PhotoTour.next(among: places, nearX: 100, y: 0, shown: &shown), 2)
        XCTAssertEqual(PhotoTour.next(among: places, nearX: -100, y: 0, shown: &shown), 3)
        XCTAssertEqual(shown, [1, 2, 3])
    }

    /// With every one shown the round starts over, never with the one the
    /// camera is at.
    func testTheRoundStartsOverWithoutTheOneShownLast() {
        let places = [Place(id: 1, x: 0, y: 0), Place(id: 2, x: 100, y: 0), Place(id: 3, x: 500, y: 0)]
        var shown = [1, 2, 3]
        XCTAssertEqual(PhotoTour.next(among: places, nearX: 500, y: 0, shown: &shown), 2, "not 3, where the camera is")
        XCTAssertEqual(shown, [3, 2])
        XCTAssertEqual(PhotoTour.next(among: places, nearX: 100, y: 0, shown: &shown), 1)
        XCTAssertEqual(PhotoTour.next(among: places, nearX: 0, y: 0, shown: &shown), 2, "a new round: not 1, the nearest of the others")
    }

    /// One place alone is shown each time; none gives none; one that is
    /// gone (a train taken off the track) is forgotten.
    func testOnePlaceNoPlaceAndOneThatIsGone() {
        var shown: [Int] = []
        XCTAssertNil(PhotoTour.next(among: [Place<Int>](), nearX: 0, y: 0, shown: &shown))
        let one = [Place(id: 7, x: 0, y: 0)]
        XCTAssertEqual(PhotoTour.next(among: one, nearX: 0, y: 0, shown: &shown), 7)
        XCTAssertEqual(PhotoTour.next(among: one, nearX: 0, y: 0, shown: &shown), 7)
        XCTAssertEqual(shown, [7])
        shown = [5, 7]
        XCTAssertEqual(PhotoTour.next(among: [Place(id: 7, x: 0, y: 0), Place(id: 8, x: 9, y: 0)], nearX: 0, y: 0, shown: &shown), 8)
        XCTAssertEqual(shown, [7, 8], "5 is gone and forgotten")
    }

    /// The trains are followed from beside, above and behind in turn,
    /// never from inside (no train in the picture).
    func testTheTrainsAreFollowedFromOutsideInTurn() throws {
        let world = try playedDemo()
        let trains = PhotoSpots.trains(in: world)
        XCTAssertFalse(trains.isEmpty)
        XCTAssertEqual(Set(trains.map(\.id)), Set(world.trains.filter { $0.position != nil }.map(\.id)))
        var tour = PhotoTour()
        var views: [Map3DFollow.View] = []
        for _ in 0..<4 {
            let next = try XCTUnwrap(tour.nextTrain(among: trains, nearX: 0, y: 0))
            XCTAssertNotNil(world.train(id: next.train)?.position, "a train a follow can hold")
            views.append(next.view)
        }
        XCTAssertEqual(views, [.side, .aboveBack, .back, .side])
        XCTAssertFalse(PhotoTour.trainViews.contains(.cab))
        XCTAssertFalse(PhotoTour.trainViews.contains(.window))
        XCTAssertNil(tour.nextTrain(among: [], nearX: 0, y: 0))
    }

    /// The stations are the player's, without depots, within the part of
    /// the map the scene shows; each is gone to once before any twice.
    func testTheStationsAreGoneToOnceEach() throws {
        let world = try playedDemo()
        let stations = PhotoSpots.stations(in: world)
        XCTAssertEqual(Set(stations.map(\.id)), Set(world.stations.filter { !$0.isDepot }.map(\.id)))
        XCTAssertGreaterThan(stations.count, 1)
        var tour = PhotoTour()
        var gone: [StationID] = []
        for _ in stations {
            gone.append(try XCTUnwrap(tour.nextStation(among: stations, nearX: 0, y: 0)))
        }
        XCTAssertEqual(Set(gone).count, stations.count)
        XCTAssertNotEqual(tour.nextStation(among: stations, nearX: 0, y: 0), gone.last)
        let first = try XCTUnwrap(stations.first)
        let small = WorldRegion(minX: first.x - 1, minY: first.y - 1, maxX: first.x + 1, maxY: first.y + 1)
        XCTAssertEqual(PhotoSpots.stations(in: world, within: small).map(\.id), [first.id])
    }

    /// The skyline keeps the way the camera faces the first time and turns
    /// a quarter turn each tap after, until the camera goes to another spot.
    func testTheSkylineTurnsAQuarterTurnEachTapAfterTheFirst() {
        var tour = PhotoTour()
        XCTAssertEqual(tour.nextSkylineTurn(), 0)
        XCTAssertEqual(tour.nextSkylineTurn(), .pi / 2)
        XCTAssertEqual(tour.nextSkylineTurn(), .pi / 2)
        _ = tour.nextStation(among: [Place(id: StationID(rawValue: 1), x: 0, y: 0)], nearX: 0, y: 0)
        XCTAssertEqual(tour.nextSkylineTurn(), 0)
    }

    // MARK: - The station's camera

    /// The camera looks at the platform's middle from three quarters, low,
    /// far enough to show it, turned the least from where it faced.
    func testTheStationIsSeenFromThreeQuarters() {
        let east = Map3DPoint(1, 0, 0)
        let point = Map3DPoint(40, 6, -20)
        for heading: Float in [0, 1, 2.5, -2, -0.7] {
            let from = Map3DCamera(distance: 2_000, heading: heading)
            let camera = PhotoSpots.camera(stationAt: point, along: east, length: 200, from: from)
            XCTAssertEqual(camera.target, point)
            XCTAssertEqual(camera.pitch, PhotoSpots.stationTilt)
            XCTAssertEqual(camera.tilt, PhotoSpots.stationTilt)
            XCTAssertEqual(camera.distance, 220, accuracy: 0.01)
            // 35° off the way the platform runs (east or west).
            let off = abs(Map3DCamera.turnFromNorth(camera.heading - .pi / 2))
            let offEast = min(off, .pi - off)
            XCTAssertEqual(offEast, PhotoSpots.stationAngle, accuracy: 0.0001)
            XCTAssertLessThanOrEqual(abs(Map3DCamera.turnFromNorth(camera.heading - heading)), .pi / 2 - PhotoSpots.stationAngle + 0.0001,
                                     "never turned more than to the nearest of the four sides")
            XCTAssertGreaterThan(camera.eye.y, point.y + 40, "over the roofs")
        }
        XCTAssertEqual(PhotoSpots.camera(stationAt: .zero, along: east, length: 20, from: Map3DCamera()).distance, PhotoSpots.stationDistances.lowerBound)
        XCTAssertEqual(PhotoSpots.camera(stationAt: .zero, along: east, length: 900, from: Map3DCamera()).distance, PhotoSpots.stationDistances.upperBound)
        // A platform with no way (a point) is taken to run north.
        XCTAssertEqual(abs(PhotoSpots.camera(stationAt: .zero, along: .zero, length: 100, from: Map3DCamera()).heading), PhotoSpots.stationAngle, accuracy: 0.0001)
    }

    /// In the demo, every station's camera looks at its own platform, on
    /// the ground or above it.
    func testEveryStationOfTheDemoHasACamera() throws {
        let world = try playedDemo()
        let scene = Map3DScene(world: world)
        for place in PhotoSpots.stations(in: world, within: scene.region) {
            let camera = try XCTUnwrap(PhotoSpots.camera(station: place.id, in: world, scene: scene, from: Map3DCamera()))
            let at = scene.point(worldX: place.x, worldY: place.y, height: 0)
            XCTAssertLessThan(hypotf(camera.target.x - at.x, camera.target.z - at.z), 400, "at the station, not elsewhere")
            XCTAssertGreaterThanOrEqual(camera.target.y, scene.drawnGround.height(x: camera.target.x, z: camera.target.z, world: world) - 0.01)
            XCTAssertTrue(PhotoSpots.stationDistances.contains(camera.distance))
        }
        XCTAssertNil(PhotoSpots.camera(station: StationID(rawValue: 9_999), in: world, scene: scene, from: Map3DCamera()))
    }

    // MARK: - The skyline's camera

    /// Over flat ground the skyline is seen from as low as it goes, the
    /// horizon in the picture, looking at the same place.
    func testTheSkylineShowsTheHorizon() {
        let from = Map3DCamera(target: Map3DPoint(100, 0, -50), distance: 300, heading: 0.4)
        let camera = PhotoSpots.skylineCamera(from: from, turn: 0) { _, _ in 12 }
        XCTAssertEqual(camera.target, Map3DPoint(100, 12, -50), "on the ground there")
        XCTAssertEqual(camera.heading, 0.4, accuracy: 0.0001)
        XCTAssertEqual(camera.distance, PhotoSpots.skylineDistance)
        XCTAssertEqual(camera.pitch, PhotoSpots.skylineTilts[0])
        // The top of the picture looks above the level: the horizon shows.
        XCTAssertGreaterThan(camera.tilt + camera.fieldOfViewTall / 2, .pi / 2)
        XCTAssertGreaterThanOrEqual(camera.eye.y, 12 + PhotoSpots.skylineClearance)
        let turned = PhotoSpots.skylineCamera(from: camera, turn: .pi / 2) { _, _ in 12 }
        XCTAssertEqual(turned.heading, 0.4 + .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(turned.target, camera.target)
    }

    /// With a hill where the eye would stand, the camera stands higher.
    func testTheSkylineStandsOverAHill() {
        let from = Map3DCamera(target: .zero, distance: 300, heading: 0)
        // Facing north, the eye is to the south (z > 0): a hill 150 m high there.
        let hill: (Float, Float) -> Float = { _, z in z > 300 ? 150 : 0 }
        let camera = PhotoSpots.skylineCamera(from: from, turn: 0, ground: hill)
        XCTAssertEqual(camera.pitch, PhotoSpots.skylineTilts[1], "139 m is under the hill's 180: the next tilt's 194 m clears it")
        XCTAssertGreaterThanOrEqual(camera.eye.y, hill(camera.eye.x, camera.eye.z) + PhotoSpots.skylineClearance)
        // A mountain no tilt clears: the highest it tries.
        let buried = PhotoSpots.skylineCamera(from: from, turn: 0) { _, z in z > 10 ? 5_000 : 0 }
        XCTAssertEqual(buried.pitch, PhotoSpots.skylineTilts.last)
    }

    /// The tilts go from the lowest up, every one lower than the map's own.
    func testTheSkylineTiltsGoFromTheLowestUp() throws {
        XCTAssertEqual(PhotoSpots.skylineTilts, PhotoSpots.skylineTilts.sorted(by: >))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(PhotoSpots.skylineTilts.last), Map3DCamera.mostLean)
        XCTAssertGreaterThan(PhotoSpots.stationTilt, Map3DCamera.mostLean)
        XCTAssertLessThan(PhotoSpots.stationTilt + Map3DCamera.fieldOfView / 2, .pi / 2, "the station's picture ends under the horizon")
    }

    // MARK: - Leaving

    /// Leaving, the camera tilts by its distance again; one that already
    /// does stays as it is.
    func testLeavingGivesTheTiltBackToTheMap() throws {
        XCTAssertNil(PhotoSpots.cameraLeaving(Map3DCamera(distance: 300)))
        let spot = PhotoSpots.camera(stationAt: Map3DPoint(5, 0, 5), along: Map3DPoint(1, 0, 0), length: 150, from: Map3DCamera())
        let left = try XCTUnwrap(PhotoSpots.cameraLeaving(spot))
        XCTAssertNil(left.pitch)
        XCTAssertNil(left.lens)
        XCTAssertEqual(left.target, spot.target)
        XCTAssertEqual(left.heading, spot.heading)
        XCTAssertEqual(left.distance, spot.distance)
        XCTAssertEqual(left.tilt, Map3DCamera.tilt(atDistance: spot.distance))
    }

    // MARK: - Words

    /// Every spot has a name and a hint in both languages; the train and
    /// the station say when there is none.
    func testEverySpotHasItsWords() {
        for spot in PhotoSpot.allCases {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                XCTAssertFalse(spot.text(in: language).isEmpty)
                XCTAssertFalse(spot.hint(in: language).isEmpty)
            }
            XCTAssertNotEqual(spot.text(in: .english), spot.text(in: .traditionalChinese))
        }
        XCTAssertNotNil(PhotoSpot.train.none(in: .english))
        XCTAssertNotNil(PhotoSpot.station.none(in: .traditionalChinese))
        XCTAssertNil(PhotoSpot.skyline.none(in: .english))
    }
}
