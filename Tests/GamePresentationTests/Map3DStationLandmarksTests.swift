import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1020: the station landmarks (``Map3DStationLandmark``), one
/// rule for each: they stand before and after their line is bought, with
/// nothing of them in the room the trains and the platforms need; a
/// station of the game under one draws no building, entrances or canopies
/// of its own, only its platforms; Duoliang's stands on the South Link
/// Line's rails, the line between its two platforms.
@MainActor
final class Map3DStationLandmarksTests: XCTestCase {
    private static let metre = Double(WorldCoordinate.unitsPerMetre)

    /// The four station landmarks (Mojiko's too) are registered as such, and Kumamoto's
    /// tower is not (no track runs through it).
    func testTheStationLandmarks() {
        let stations = Map3DLandmarkRegistry.landmarks.filter { $0.station != nil }.map(\.id)
        XCTAssertEqual(Set(stations), ["hakata-station", "kumamoto-station", "duoliang-station", "jp-mojiko-station"])
        XCTAssertNil(Map3DKumamotoStationTower.registration.station)
        XCTAssertEqual(Map3DDuoliangStation.registration.station?.railHeight, 2.5)
    }

    /// The builder round `landmark` on `world`, its track, platforms,
    /// viaducts, landmarks and stations laid as the scene lays them.
    static func built(round landmark: Map3DLandmarkRegistration, world: GameWorld, heights: HeightGrid?, railways: RealRailways? = nil,
                      reach: Double = 500) throws -> (builder: Map3DScene.Builder, built: Set<String>) {
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let place = frame.worldPosition(latitude: landmark.latitude, longitude: landmark.longitude)
        let reach = reach * metre
        let region = WorldRegion(minX: place.x - reach, minY: place.y - reach, maxX: place.x + reach, maxY: place.y + reach)
        var builder = Map3DScene.Builder(originX: place.x.rounded(), originY: place.y.rounded(), region: region, world: world, heights: heights)
        let snapshot = world.railwaySnapshot()
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        builder.addGround(water: true)
        _ = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        let realTrains = Map3DScene.realTrains(world: world, railways: railways, snapshot: snapshot, builder: &builder)
        builder.state.realTrains.realTrackLines = realTrains?.shownLanes ?? []
        builder.addViaducts()
        let built = builder.addHongKongLandmarks(frame: frame, snapshot: snapshot)
        _ = builder.addStations(snapshot, frame: frame, shops: false)
        return (builder, built)
    }

    /// Hakata's and Kumamoto's stand with the Kyushu Shinkansen bought,
    /// its viaduct and platforms in the room their models leave (nothing
    /// of either in the trains' room), and stand for the line's Hakata
    /// and Kumamoto: neither draws a building, entrances or canopies of
    /// its own, and no footprint of the game's own building is under
    /// either. Before the line is bought both stand as scenery.
    func testTheyStandOverTheBoughtShinkansen() throws {
        let session = try FukuokaRailwaysTests.fukuoka()
        for landmark in [Map3DHakataStation.registration, Map3DKumamotoStation.registration, Map3DKumamotoStationTower.registration] {
            let (_, built) = try Self.built(round: landmark, world: session.world, heights: session.heights)
            XCTAssertTrue(built.contains(landmark.id), "\(landmark.id) before the line is bought")
        }
        let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == KyushuShinkansenTests.id })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: real)), session.message?.text ?? "")
        let world = session.world
        let line = try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: KyushuShinkansenTests.id)?.line)))
        for (landmark, name) in [(Map3DHakataStation.registration, "博多"), (Map3DKumamotoStation.registration, "熊本")] {
            let stop = try XCTUnwrap(line.stops.first { world.station(id: $0)?.name == name })
            let (builder, built) = try Self.built(round: landmark, world: world, heights: session.heights)
            let frame = try XCTUnwrap(RealWorldFrame(world: world))
            var probe = builder
            let place = probe.stationLandmarkPlace(landmark, snapshot: world.railwaySnapshot(), frame: frame)
            XCTAssertLessThanOrEqual(place.share, Map3DScene.Builder.stationCutShare, "\(landmark.id): \(place.intrusion) m² in the trains' room")
            XCTAssertTrue(built.contains(landmark.id), "\(landmark.id) with the Shinkansen bought")
            // Its rails on the viaduct's, and nothing of it left in the
            // trains' room once cut.
            XCTAssertNotNil(place.rails, "\(landmark.id): its rails on the viaduct's")
            XCTAssertLessThan(place.room.intrusion(of: place.mesh(landmark.model(full: true))), 0.01, "\(landmark.id) cut clear")
            XCTAssertTrue(builder.state.stations.underStationLandmarks.contains(stop), "\(name) stands under \(landmark.id)")
            XCTAssertTrue(builder.state.stations.shellRoofed.contains(stop), "\(name): no kit canopy")
            XCTAssertFalse(builder.state.platforms.laidPlatforms.filter { $0.station == stop }.isEmpty, "\(name)'s platforms stay")
            for footprint in builder.state.stations.houseFootprints {
                let middle = footprint.reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * (1 / Float(footprint.count))
                XCTAssertFalse(place.plan.covers(middle), "\(name): a building of the game's own under \(landmark.id)")
            }
            // Its rails as high in the model's room as the game lays them:
            // the viaduct's rails over the model's foot.
            let rails = world.network.platforms(of: stop).compactMap { platform -> Double? in
                guard let geometry = world.trackGeometry(of: platform.edge) else { return nil }
                return Double(geometry.location(at: (platform.start + platform.end) / 2).position.z) / Self.metre
            }
            print("STATION-LANDMARK \(landmark.id): ground \(place.ground) m, rails \(rails) m, model's \(String(describing: place.rails)), moved \(place.centre), \(place.intrusion) m² (\(place.share * 100) %) cut")
        }
    }

    /// Duoliang's stands on the South Link Line's drawn track (the real
    /// line's, not the player's), its rails (2.5 m over its foot) on the
    /// drawn rails' height, the line running between its two platforms
    /// with nothing of the model in a car's room; and the line there is
    /// as many tracks as the gap between the platforms takes.
    func testDuoliangStandsOnTheSouthLinkLine() throws {
        let (session, _) = try DemoRealLinesTrackReportTests.game(at: "金崙", in: "tra_sched", half: 4_000)
        let landmark = Map3DDuoliangStation.registration
        let (builder, built) = try Self.built(round: landmark, world: session.world, heights: session.heights, railways: session.railways)
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        var probe = builder
        let place = probe.stationLandmarkPlace(landmark, snapshot: session.world.railwaySnapshot(), frame: frame)
        XCTAssertTrue(built.contains(landmark.id), "Duoliang over the South Link Line")
        XCTAssertLessThanOrEqual(place.share, Map3DScene.Builder.stationCutShare, "\(place.intrusion) m² of the model in a car's room")
        // The drawn lanes through the model's middle: their rails at the
        // model's (its foot 2.5 m under them).
        let centre = place.centre
        let lanes = builder.state.realTrains.realTrackLines.compactMap { lane -> (distance: Float, rails: Float)? in
            var best: (distance: Float, rails: Float)?
            for (a, b) in zip(lane, lane.dropFirst()) {
                let ab = Map3DPoint(b.x - a.x, 0, b.z - a.z), ap = Map3DPoint(centre.x - a.x, 0, centre.z - a.z)
                let share = min(max(ab.dot(ap) / max(ab.dot(ab), 1e-6), 0), 1)
                let distance = (ap - ab * share).length
                if distance < best?.distance ?? .greatestFiniteMagnitude { best = (distance, a.y + (b.y - a.y) * share) }
            }
            return best.flatMap { $0.distance < 12 ? $0 : nil }
        }
        print("STATION-LANDMARK duoliang-station: ground \(place.ground) m, lanes \(lanes), model's \(String(describing: place.rails)), moved \(place.centre), \(place.intrusion) m² (\(place.share * 100) %) cut")
        XCTAssertFalse(lanes.isEmpty, "the line runs through it")
        let nearest = try XCTUnwrap(lanes.min { $0.distance < $1.distance })
        XCTAssertEqual(place.ground + (place.rails?.drawn ?? 2.5), nearest.rails, accuracy: 0.05, "its rails on the drawn rails")
        let cut = place.room.intrusion(of: place.mesh(landmark.model(full: true)))
        XCTAssertLessThan(cut, 0.01, "nothing of it left in the room once cut")
    }
}
