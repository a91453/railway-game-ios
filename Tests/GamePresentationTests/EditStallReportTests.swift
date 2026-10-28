import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// What the main actor works out after an edit (decision 465; 91.1 and
/// 92.1: a player's 84 stations and 5 lines stopped 0.5–0.7 s after
/// linking a transfer, building a station, opening a line, buying a
/// train, changing the times): the edit itself, the station master's
/// corner, the map's alerts, the next steps and the first tick after it.
/// Run on request, in release:
///
///     EDIT_STALL_SAVE=<save> swift test -c release -Xswiftc -enable-testing --filter EditStallReportTests
///
/// `EDIT_STALL_SAVE` is a `.alongtheline` file or a `SavedGame`.
@MainActor
final class EditStallReportTests: XCTestCase {
    func testWhatTheMainActorWorksOutAfterAnEdit() async throws {
        guard let path = ProcessInfo.processInfo.environment["EDIT_STALL_SAVE"] else {
            throw XCTSkip("set EDIT_STALL_SAVE=<save> to time what follows an edit")
        }
        struct SharedFile: Decodable { let game: SavedGame }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let saved = try (try? JSONDecoder().decode(SharedFile.self, from: data).game) ?? JSONDecoder().decode(SavedGame.self, from: data)
        let session = GameSession(world: saved.world)
        session.setSpeed(.normal)
        print("stations \(session.world.stations.count), lines \(session.world.lines.count), trains \(session.world.trains.count)")
        let clock = ContinuousClock()
        func ms(_ duration: Duration) -> String {
            String(format: "%7.1f ms", Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
        }
        // Settles what a first look works out once for any game.
        _ = session.stationMasterAdvice
        _ = session.situationAlerts
        _ = session.nextSteps
        print("traffic control \(session.world.isTrafficControlEnabled)")
        for _ in 0..<3 { try await tick(session) }

        let world = session.world
        let stations = world.stations.map(\.id)
        let line = try XCTUnwrap(world.lines.first)
        let edits: [(String, PlayerCommand)] = [
            ("rename a station", .edit(.renameStation(stations[0], name: "Renamed"))),
            ("link a transfer", .edit(.linkTransfer(stations[0], stations[1]))),
            ("buy a train", .edit(.purchaseTrain(name: "Bought"))),
            ("open a line", .edit(.createLine(name: "New", stops: Array(line.stops.prefix(3)), targets: nil))),
            ("change the times", .edit(.setLineWindow(line.id, line.window == .allDay ? .standard : .allDay))),
        ] + (Self.newStation(in: world, session: session).map { [("build a station", $0)] } ?? [])
        for (name, command) in edits {
            var outcome: PlayerCommand.Outcome?
            let edit = clock.measure { outcome = session.perform(command) { _, _, _ in "" } }
            XCTAssertNotNil(outcome, name)
            let advice = clock.measure { _ = session.stationMasterAdvice }
            let alerts = clock.measure { _ = session.situationAlerts }
            let steps = clock.measure { _ = session.nextSteps }
            let rank = clock.measure { _ = CompanyRank(world: session.world) }
            let traffic = clock.measure { _ = session.trafficOverlay }
            var finish = Duration.zero
            let first = try await tick(session) { finish = $0 }
            print("\(name.padding(toLength: 18, withPad: " ", startingAt: 0)): edit \(ms(edit)), advice \(ms(advice)), "
                + "alerts \(ms(alerts)), next steps \(ms(steps)), rank \(ms(rank)), traffic \(ms(traffic)), "
                + "first tick off the main actor \(ms(first)), finishing it \(ms(finish))")
        }
    }

    /// One game loop tick; returns how long its work took off the main
    /// actor, and hands over how long finishing it took on it.
    @discardableResult
    private func tick(_ session: GameSession, finished: (Duration) -> Void = { _ in }) async throws -> Duration {
        let clock = ContinuousClock()
        let tick = try XCTUnwrap(session.beginLoopTick())
        let start = clock.now
        let outcome = await tick.work()
        let worked = clock.now - start
        finished(clock.measure { XCTAssertTrue(session.finish(tick, with: outcome)) })
        return worked
    }

    /// A new station's platform in the middle of the first track edge
    /// long enough that has none, as the station tool builds it.
    static func newStation(in world: GameWorld, session: GameSession) -> PlayerCommand? {
        let platform = 150 * WorldCoordinate.unitsPerMetre
        for edge in world.network.edges where edge.length > 4 * platform {
            let start = edge.length / 2 - platform / 2
            guard let from = world.network.node(edge.from)?.position, let to = world.network.node(edge.to)?.position else { continue }
            let point = PlanPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            let command = PlayerCommand.addPlatform(PlayerCommand.PlatformAddition(
                edge: edge.id, start: start, end: start + platform,
                station: .new(name: "Built", at: point, demand: StationDemand(kind: .residential, dailyTrips: 1_000))
            ))
            var copy = world
            if (try? session.apply(command, to: &copy)) != nil { return command }
        }
        return nil
    }
}
