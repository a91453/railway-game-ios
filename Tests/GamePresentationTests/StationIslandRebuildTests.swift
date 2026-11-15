import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 761: a station of two side platforms rebuilt as an island
/// from its panel: one track swung out to 11 m, its old stretch and
/// platform taken up, the crossovers laid again, a line's chosen platform
/// moved to the new one.
@MainActor
final class StationIslandRebuildTests: XCTestCase {
    /// A double track 500 m long west to east along y = 10,240, the second
    /// 5 m north, with a station "Middle" of `layout` in the middle.
    private func station(_ layout: StationLayout = .doubleSide, balance: Money = 100_000_000) throws -> (GameSession, StationID) {
        let world = try makeWorld(width: 40_960, height: 20_480, balance: balance, speed: .paused)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 34_816, y: 10_240), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.setNetworkMode(.platform)
        session.platformCars = 4
        session.stationLayout = layout
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 10_240), reach: 64)
        session.stationName = "Middle"
        session.addNetworkPlatform()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let id = try XCTUnwrap(session.world.stations.first { $0.name == "Middle" }?.id)
        return (session, id)
    }

    /// The tracks crossing the line x = 18,432, by how far north or south
    /// of the main track they run there (as `StationLayoutTests`).
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

    /// How many nodes join three edges or more.
    private func turnouts(_ world: GameWorld) -> Int {
        world.network.nodes.filter { $0.ends.count >= 3 }.count
    }

    func testTwoSidePlatformsBecomeAnIsland() throws {
        let (session, id) = try station()
        XCTAssertEqual(tracksThroughTheMiddle(of: session.world), [-320, 0])
        let crossovers = turnouts(session.world)
        XCTAssertGreaterThan(crossovers, 0, "the platform tool laid the station's crossovers")
        let offer = try XCTUnwrap(session.stationIslandOffer(for: id))
        XCTAssertNil(offer.problem)
        let cost = try XCTUnwrap(offer.cost)
        XCTAssertGreaterThan(cost.amount, 0)
        XCTAssertEqual(session.stationIslandButtonText(offer), "Make it an island platform (\(cost.moneyText))")
        let before = session.world.economy.balance
        session.rebuildStationAsIsland(id)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let world = session.world
        XCTAssertEqual(tracksThroughTheMiddle(of: world), [-704, 0])
        XCTAssertEqual(world.trackPlatforms(of: id).count, 2)
        XCTAssertEqual(Money(before.amount - world.economy.balance.amount), cost)
        // The crossovers again, moved out beyond the swung track: its old
        // stretch is gone, so where it leaves and rejoins are plain joints.
        XCTAssertEqual(turnouts(world), crossovers)
        for node in world.network.nodes where node.ends.count > 1 {
            XCTAssertTrue(node.ends.allSatisfy { !$0.exits.isEmpty }, "node \(node.id) has track meeting with nothing beyond")
        }
        XCTAssertEqual(world.network.nodes.filter { $0.ends.count == 1 }.count, 4, "the line's ends only")
        // An island now: nothing more to offer.
        XCTAssertNil(session.stationIslandOffer(for: id))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    /// The 3D map draws one island between the two tracks: each
    /// platform lays half its width, toward the other.
    func testThe3DMapDrawsTheIsland() throws {
        let (session, id) = try station()
        session.rebuildStationAsIsland(id)
        let half = Float(Double(PlatformTrackLayout.island.spacing) / Double(WorldCoordinate.unitsPerMetre) / 2) - Map3DScene.Builder.platformEdge
        let frame = Map3DScene.frame(world: session.world, focus: (x: 18_432, y: 10_240))
        var builder = Map3DScene.Builder(originX: frame.originX, originY: frame.originY, region: frame.region, world: session.world)
        let snapshot = session.world.railwaySnapshot()
        _ = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        let laid = builder.laidPlatforms.filter { $0.station == id }
        XCTAssertEqual(laid.count, 2)
        for platform in laid {
            XCTAssertEqual(platform.width, half, accuracy: 0.05)
        }
    }

    /// Only a station of two side platforms is offered it.
    func testOnlySidePlatformsAreOffered() throws {
        for layout in [StationLayout.doubleIsland, .doubleTwoIslands] {
            let (session, id) = try station(layout)
            XCTAssertNil(session.stationIslandOffer(for: id), "\(layout)")
        }
    }

    /// A line's chosen platform on the track moved goes to the new one,
    /// and a line runs through the island.
    func testALineKeepsItsChosenPlatform() throws {
        let (session, middle) = try station()
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
        session.createLineFromDraft()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let line = try XCTUnwrap(session.world.lines.first)
        session.selectLine(line.id)
        // The north track's platform at Middle, chosen for the leg there.
        let north = try XCTUnwrap(session.world.trackPlatforms(of: middle).first { platform in
            session.world.trackGeometry(of: platform.edge).map { $0.location(at: (platform.start + platform.end) / 2).position.y < 10_240 } ?? false
        })
        session.setSelectedLineRoute(from: 0, to: 1, preference: LineRoutePreference(from: 0, to: 1, platform: north))
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")

        session.rebuildStationAsIsland(middle)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let world = session.world
        let chosen = try XCTUnwrap(world.line(id: line.id)?.routePreferences.first { $0.from == 0 && $0.to == 1 }?.platform)
        XCTAssertTrue(world.trackPlatforms(of: middle).contains(chosen))
        let y = try XCTUnwrap(world.trackGeometry(of: chosen.edge)).location(at: (chosen.start + chosen.end) / 2).position.y
        XCTAssertEqual(y - 10_240, -704, accuracy: 2)
        XCTAssertNotNil(world.lineJourney(line.id), "the line still finds its way")
    }

    /// The log keeps it as one command and reads it back.
    func testTheLogKeepsItAsOneCommand() throws {
        let (session, id) = try station()
        guard case .success(let rebuild)? = session.stationIslandPlan(for: id) else { return XCTFail("no plan") }
        XCTAssertFalse(rebuild.unjoined.isEmpty)
        XCTAssertFalse(rebuild.removed.isEmpty)
        XCTAssertEqual(rebuild.crossovers.count, 2)
        let command = PlayerCommand.rebuildStationAsIsland(rebuild)
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: JSONEncoder().encode(command)), command)
        XCTAssertEqual(command.name, "rebuildStationAsIsland")
    }

    /// Too little money: nothing changes, and the offer said so.
    func testTooLittleMoneyChangesNothing() throws {
        let (rich, id) = try station()
        let cost = try XCTUnwrap(rich.stationIslandOffer(for: id)?.cost)
        let spent = Money(100_000_000 - rich.world.economy.balance.amount)
        let (session, poor) = try station(balance: Money(spent.amount + cost.amount - 1))
        XCTAssertNotNil(session.stationIslandOffer(for: poor)?.problem)
        let before = session.world
        session.rebuildStationAsIsland(poor)
        XCTAssertEqual(session.world, before)
    }
}
