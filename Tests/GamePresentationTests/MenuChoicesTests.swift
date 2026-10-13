import GameCore
@testable import GamePresentation
import XCTest

/// The native menus' entries (the train picker, the station menus of a
/// line, the transfer links) stay the same while the game runs, so a tick
/// does not rebuild a menu the player has open (TestFlight 54.1: the train
/// menu could not be scrolled and showed two layers of text).
final class MenuChoicesTests: XCTestCase {
    func testTicksThatMoveTrainsLeaveTheMenusEntriesAlone() async throws {
        let world = DemoWorld.make(in: .english)
        await MainActor.run {
            let session = GameSession(world: world)
            session.setSpeed(.normal)
            guard let station = session.world.stations.first?.id else { return XCTFail("the demo has stations") }
            let trains = session.trainMenuChoices
            let stations = session.stationMenuChoices
            let transfers = session.transferMenuChoices(for: station)
            XCTAssertFalse(trains.isEmpty)
            XCTAssertFalse(stations.isEmpty)
            XCTAssertFalse(transfers.isEmpty)
            let before = session.world

            for _ in 0..<20 {
                session.advance(realElapsed: GameSession.tickInterval)
            }

            XCTAssertNotEqual(session.world, before, "the ticks changed the world")
            XCTAssertNotEqual(session.world.trains, before.trains, "the trains moved")
            XCTAssertEqual(session.trainMenuChoices, trains)
            XCTAssertEqual(session.stationMenuChoices, stations)
            XCTAssertEqual(session.transferMenuChoices(for: station), transfers)
        }
    }

    func testTheEntriesFollowTheWorld() async throws {
        let world = DemoWorld.make(in: .english)
        await MainActor.run {
            let session = GameSession(world: world)
            XCTAssertEqual(session.trainMenuChoices.map(\.id), session.world.trains.map(\.id))
            XCTAssertEqual(session.trainMenuChoices.map(\.title), session.world.trains.map(\.name))
            XCTAssertEqual(session.stationMenuChoices.map(\.title), session.world.stations.map(\.name))
            let trains = session.trainMenuChoices
            session.purchaseTrain()
            XCTAssertEqual(session.trainMenuChoices.count, trains.count + 1, "a bought train joins the menu")
            XCTAssertNotEqual(session.trainMenuChoices, trains)
        }
    }

    /// Decision 184, later: the other menus' entries (the train's types,
    /// the types a line buys, the platform tracks, a line's routes) stay the
    /// same while the game runs; the author could not scroll the type menu.
    func testTicksLeaveTheOtherMenusEntriesAlone() async throws {
        let world = DemoWorld.make(in: .english)
        await MainActor.run {
            let session = GameSession(world: world)
            session.setSpeed(.normal)
            guard let train = session.world.trains.first?.id,
                  let line = session.world.lines.first,
                  let platform = session.world.stations.flatMap({ session.world.trackPlatforms(of: $0.id) }).first
            else { return XCTFail("the demo has trains, lines and platforms") }
            @MainActor func routes() -> [[LineRoutePreference]] {
                zip(line.stops.indices, line.stops.indices.dropFirst()).map { session.world.lineRouteChoices(line.id, from: $0, to: $1, pattern: nil) }
            }
            let types = session.trainTypeMenuChoices(for: train)
            let cards = session.trainTypeCardChoices
            let tracks = session.platformTrackMenuChoices(beside: platform)
            let lineRoutes = routes()
            XCTAssertFalse(types.isEmpty)
            XCTAssertFalse(cards.isEmpty)
            XCTAssertEqual(tracks.count, PlatformTrackLayout.allCases.count * PlatformTrackSide.allCases.count)
            let before = session.world

            for _ in 0..<20 {
                session.advance(realElapsed: GameSession.tickInterval)
            }

            XCTAssertNotEqual(session.world.trains, before.trains, "the trains moved")
            XCTAssertEqual(session.trainTypeMenuChoices(for: train), types)
            XCTAssertEqual(session.trainTypeCardChoices, cards)
            XCTAssertEqual(session.platformTrackMenuChoices(beside: platform), tracks)
            XCTAssertEqual(routes(), lineRoutes)
        }
    }

    /// TestFlight 59.1: each platform track entry shows its cost, or why
    /// it cannot be built, from the session's dry run.
    func testThePlatformTrackEntriesShowTheirCost() async throws {
        let world = DemoWorld.make(in: .english)
        await MainActor.run {
            let session = GameSession(world: world)
            guard let platform = session.world.stations.flatMap({ session.world.trackPlatforms(of: $0.id) }).first
            else { return XCTFail("the demo has platforms") }
            for choice in session.platformTrackMenuChoices(beside: platform) {
                let preview = session.platformTrackPreview(beside: platform, layout: choice.id.layout, side: choice.id.side)
                let expected = preview.cost.map { "Costs \($0.moneyText)" } ?? preview.problem
                XCTAssertNotNil(expected)
                XCTAssertEqual(choice.detail, expected)
            }
        }
    }

    func testTheTypeEntriesFollowTheWorld() async throws {
        let world = DemoWorld.make(in: .english)
        await MainActor.run {
            let session = GameSession(world: world)
            guard let train = session.world.trains.first?.id else { return XCTFail("the demo has trains") }
            let types = session.trainTypeMenuChoices(for: train)
            XCTAssertEqual(types.map(\.id), (session.world.offersStandardCar ? [nil] : []) + session.world.offeredTrainTypes.map { $0 })
            XCTAssertEqual(types.map(\.title), types.map { Train.typeText($0.id, in: .english) })
            XCTAssertEqual(types.map(\.detail), types.map { session.world.trainTypeMenuText($0.id, for: train, in: .english) })
            XCTAssertEqual(session.trainTypeCardChoices.map(\.id), session.world.offeredTrainTypes)
        }
    }
}
