import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 507: a station's layout picked before it is built, and built
/// with ✓ as one command: for each layout, how many tracks run through
/// the station, how many platforms each has, and that every track it laid
/// joins the line at both ends.
@MainActor
final class StationLayoutTests: XCTestCase {
    /// A track 500 m long west to east along y = 10,240 from open ground,
    /// with a second 5 m north where `double`; the platform mode on.
    private func line(double: Bool, balance: Money = 100_000_000) throws -> GameSession {
        let world = try makeWorld(width: 40_960, height: 20_480, balance: balance, speed: .paused)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.networkBuildsDouble = double
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 34_816, y: 10_240), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.network.edges.count, double ? 2 : 1)
        session.setNetworkMode(.platform)
        session.platformCars = 4
        return session
    }

    /// Picks the middle of the main track for `layout` and builds it.
    private func build(_ layout: StationLayout, on session: GameSession) throws -> StationID {
        session.stationLayout = layout
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 10_240), reach: 64)
        session.stationName = "Middle"
        XCTAssertEqual(session.networkStationLayout, layout)
        if layout.isLaidByLayout {
            let preview = try XCTUnwrap(session.networkStationLayoutPreview)
            XCTAssertNil(preview.problem)
            XCTAssertNotNil(preview.cost)
        }
        session.addNetworkPlatform()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        return try XCTUnwrap(session.world.stations.first { $0.name == "Middle" }?.id)
    }

    /// The tracks crossing the line x = 18,432, by how far north or south
    /// of the main track they run there.
    private func tracksThroughTheMiddle(of world: GameWorld) -> [Int64] {
        world.network.edges.compactMap { edge -> Int64? in
            guard let geometry = world.trackGeometry(of: edge.id) else { return nil }
            let points = (0...64).map { geometry.location(at: geometry.length * Int64($0) / 64).position }
            guard let west = points.min(by: { $0.x < $1.x }), let east = points.max(by: { $0.x < $1.x }),
                  west.x < 18_432, east.x > 18_432,
                  let near = points.min(by: { abs($0.x - 18_432) < abs($1.x - 18_432) }) else { return nil }
            return near.y - 10_240
        }.sorted()
    }

    /// Every node where track meets lets a train run on through it, and
    /// the line has as many ends as before.
    private func assertJoined(_ world: GameWorld, ends: Int, file: StaticString = #filePath, line: UInt = #line) {
        for node in world.network.nodes where node.ends.count > 1 {
            XCTAssertTrue(node.ends.allSatisfy { !$0.exits.isEmpty }, "node \(node.id) has track meeting with nothing beyond", file: file, line: line)
        }
        XCTAssertEqual(world.network.nodes.filter { $0.ends.count == 1 }.count, ends, "the line's ends only", file: file, line: line)
    }

    func testEachLayoutLaysItsTracksAndPlatforms() throws {
        // Layout, double track, the tracks' places across the middle (in
        // 64ths of a metre, south positive), the platforms on track.
        let cases: [(StationLayout, Bool, [Int64], Int)] = [
            (.singleSide, false, [0], 1),
            (.singleIsland, false, [-704, 0], 2),
            (.doubleSide, true, [-320, 0], 2),
            (.doubleIsland, true, [-704, 0], 2),
            (.doubleTwoIslands, true, [-1_024, -320, 0, 704], 4),
        ]
        for (layout, double, places, platforms) in cases {
            let session = try line(double: double)
            let station = try build(layout, on: session)
            let world = session.world
            XCTAssertEqual(tracksThroughTheMiddle(of: world), places, "\(layout)")
            XCTAssertEqual(places.count, layout.tracks, "\(layout)")
            XCTAssertEqual(world.trackPlatforms(of: station).count, platforms, "\(layout)")
            assertJoined(world, ends: double ? 4 : 2)
            XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world, "\(layout)")
        }
    }

    /// A layout for the other kind of track is not offered there: ✓
    /// builds the plain one for the track tapped, as the tool always did.
    func testALayoutThatDoesNotFitTheTrackFallsBackToThePlainOne() throws {
        let single = try line(double: false)
        single.stationLayout = .doubleIsland
        single.tapNetwork(at: PlanPoint(x: 18_432, y: 10_240), reach: 64)
        XCTAssertFalse(single.fits(.doubleIsland))
        XCTAssertEqual(single.stationLayoutUnfitText(.doubleIsland), "Needs double track")
        XCTAssertNil(single.stationLayoutUnfitText(.singleIsland))
        XCTAssertEqual(single.networkStationLayout, .singleSide)
        XCTAssertEqual(single.stationLayoutChoices.map(\.title), [
            "Single, one side", "Single, island", "Double, two sides (Needs double track)", "Double, island (Needs double track)",
            "Double, two islands (Needs double track)",
        ])
        XCTAssertEqual(single.stationLayoutChoices.map(\.fits), [true, true, false, false, false])

        let double = try line(double: true)
        double.stationLayout = .singleIsland
        double.tapNetwork(at: PlanPoint(x: 18_432, y: 10_240), reach: 64)
        XCTAssertEqual(double.stationLayoutUnfitText(.singleIsland), "This track is double")
        XCTAssertEqual(double.networkStationLayout, .doubleSide)
        double.stationName = "Middle"
        double.addNetworkPlatform()
        XCTAssertEqual(tracksThroughTheMiddle(of: double.world), [-320, 0])
    }

    /// Trains still run through the station whose track beside was swung
    /// out round the island: a line from end to end finds its way.
    func testALineRunsThroughADoubleTrackIsland() throws {
        let session = try line(double: true)
        let middle = try build(.doubleIsland, on: session)
        for (x, name) in [(Int64(4_096), "West"), (32_768, "East")] {
            session.stationLayout = .doubleSide
            session.tapNetwork(at: PlanPoint(x: x, y: 10_240), reach: 64)
            session.stationName = name
            session.addNetworkPlatform()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        }
        let west = try XCTUnwrap(session.world.stations.first { $0.name == "West" }?.id)
        let east = try XCTUnwrap(session.world.stations.first { $0.name == "East" }?.id)
        session.selectTool(.select)
        for id in [west, middle, east] {
            session.selectStation(id)
            session.addSelectedStationToLineDraft()
        }
        XCTAssertNil(session.lineDraftGap)
        session.createLineFromDraft()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
    }

    /// The command log keeps the layout as one command, and reads it back.
    func testTheLogKeepsALayoutAsOneCommand() throws {
        let session = try line(double: true)
        session.stationLayout = .doubleTwoIslands
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 10_240), reach: 64)
        session.stationName = "Middle"
        guard case .success(let draft) = session.networkPlatformDraft(),
              case .success(let plan) = session.stationLayoutPlan(.doubleTwoIslands, platform: draft.addition) else {
            return XCTFail("no plan")
        }
        XCTAssertEqual(plan.tracks.count, 2)
        XCTAssertTrue(plan.removed.isEmpty)
        let command = PlayerCommand.buildStationLayout(plan)
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: JSONEncoder().encode(command)), command)
        XCTAssertEqual(command.name, "buildStationLayout")
    }

    /// Too little money: nothing is built, and the preview said so.
    func testALayoutTheCashDoesNotCoverChangesNothing() throws {
        func picked(_ session: GameSession) {
            session.stationLayout = .singleIsland
            session.tapNetwork(at: PlanPoint(x: 18_432, y: 10_240), reach: 64)
            session.stationName = "Middle"
        }
        let rich = try line(double: false)
        let track = Money(100_000_000 - rich.world.economy.balance.amount)
        picked(rich)
        let cost = try XCTUnwrap(rich.networkStationLayoutPreview?.cost)
        let session = try line(double: false, balance: Money(track.amount + cost.amount - 1))
        picked(session)
        XCTAssertNotNil(session.networkStationLayoutPreview?.problem)
        let before = session.world
        session.addNetworkPlatform()
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, before)
    }
    /// The 3D map draws each island as one: the two platforms either side
    /// of it each lay half its width, toward each other. With two islands
    /// the platform beside across the double track (5 m off, too near for
    /// an island) once won, and the main track's half was drawn as a side
    /// platform, a gap short of the loop's half. Nothing stands over a
    /// track.
    func testThe3DMapDrawsEachIslandWhole() throws {
        let island = Double(PlatformTrackLayout.island.spacing) / Double(WorldCoordinate.unitsPerMetre)
        let half = Float(island / 2) - Map3DScene.Builder.platformEdge
        let cases: [(StationLayout, Bool, Int)] = [(.singleIsland, false, 2), (.doubleIsland, true, 2), (.doubleTwoIslands, true, 4)]
        for (layout, double, halves) in cases {
            let session = try line(double: double)
            let station = try build(layout, on: session)
            let frame = Map3DScene.frame(world: session.world, focus: (x: 18_432, y: 10_240))
            var builder = Map3DScene.Builder(originX: frame.originX, originY: frame.originY, region: frame.region, world: session.world)
            let snapshot = session.world.railwaySnapshot()
            _ = builder.addTrack(snapshot)
            builder.addPlatforms(snapshot)
            let laid = builder.laidPlatforms.filter { $0.station == station }
            XCTAssertEqual(laid.count, halves, "\(layout)")
            for platform in laid {
                XCTAssertEqual(platform.width, half, accuracy: 0.05, "\(layout): half an island")
            }
            XCTAssertEqual(Map3DPlatformClearanceTests.intrusions(world: session.world, focus: (x: 18_432, y: 10_240)).found.map(\.description), [],
                           "\(layout)")
        }
    }
}
