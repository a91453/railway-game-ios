import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 572, TestFlight 111.1, a save from before decision 571: "can
/// the track before and after a station get its crossovers by itself? I
/// have two trains now, but a third still will not go on." A double-track
/// station built before decision 571 has no crossover between its two
/// tracks; a line's third train found both ends' berths held and stayed
/// off the track.
@MainActor
final class OldStationCrossoverTests: XCTestCase {
    typealias Base = DoubleTrackDeadlockTests

    func newGame(rules: NewGameRules, language: DisplayLanguage) -> GameSession {
        var world = GameWorld.newGame(rules: rules)
        world.setSpeed(.normal)
        return GameSession(world: world, language: language)
    }

    /// A double track 3 km long from open ground with a platform on both
    /// tracks near each end, as the platform tool set them before decision
    /// 571: no crossovers.
    func oldStations(rules: NewGameRules, language: DisplayLanguage = .english, crossovers: Bool = false) throws -> GameSession {
        let session = newGame(rules: rules, language: language)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.tapNetwork(at: PlanPoint(x: Base.west, y: Base.y), reach: 16)
        session.tapNetwork(at: PlanPoint(x: Base.east, y: Base.y), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.setNetworkMode(.platform)
        for x in [Base.west + 2_000, Base.east - 2_000] {
            session.platformStationID = nil
            session.tapNetwork(at: PlanPoint(x: x, y: Base.y), reach: 64)
            let found = try session.networkPlatformDraft().get().addition
            XCTAssertNotNil(found.beside)
            XCTAssertFalse(found.crossovers.isEmpty, "decision 571 would lay them")
            let old = PlayerCommand.PlatformAddition(
                edge: found.edge, start: found.start, end: found.end, station: found.station, levelling: found.levelling, beside: found.beside,
                crossovers: crossovers ? found.crossovers : []
            )
            try session.performCommand(.addPlatform(old))
        }
        return session
    }

    /// A line through the stations in the order built.
    func line(_ session: GameSession) throws -> LineID {
        session.selectTool(.select)
        for station in session.world.stations {
            session.selectStation(station.id)
            session.addSelectedStationToLineDraft()
        }
        session.createLineFromDraft()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        return try XCTUnwrap(session.world.lines.first).id
    }

    /// ＋ on the line until it has `count` trains, or three taps.
    func plus(_ session: GameSession, _ line: LineID, to count: Int) -> String {
        session.selectLine(line)
        var said: [String] = []
        for _ in 0..<count where (session.world.line(id: line)?.trains.count ?? 0) < count {
            session.addTrainToSelectedLine()
            said.append(session.message?.text ?? "")
        }
        return said.joined(separator: " | ")
    }

    /// The player's case: before, ＋ three times left the line with fewer
    /// than three trains (one on main, two with the platform beside taking
    /// the second, never three). The station panel then offers each
    /// station's crossover; once laid, the two tracks count as double, ＋
    /// puts on the third, and all three run a day without a deadlock,
    /// under simple rules with traffic control and under realistic rules.
    func testOldStationsTakeAThirdTrainOnceTheirCrossoversAreLaid() throws {
        for rules in [NewGameRules.simple, .realistic] {
            let session = try oldStations(rules: rules)
            let (a, b) = (session.world.stations[0].id, session.world.stations[1].id)
            let id = try line(session)
            let probe = session.world
            _ = plus(session, id, to: 3)
            XCTAssertLessThan(session.world.line(id: id)?.trains.count ?? 0, 3, "\(rules): the player's report")

            // Laid from the panel, with the line's first train on the
            // track: it goes back to the start of its line.
            let fixed = GameSession(world: probe, language: .english)
            for station in [a, b] {
                let offer = try XCTUnwrap(fixed.stationCrossoverOffer(for: station), "\(rules)")
                XCTAssertEqual(offer.count, 1, "\(rules): a terminus gets one, on the line's side")
                XCTAssertNil(offer.problem)
                let balance = fixed.world.economy.balance
                fixed.addStationCrossovers(station)
                XCTAssertEqual(fixed.message?.kind, .success, fixed.message?.text ?? "")
                XCTAssertEqual(fixed.world.economy.balance, balance - offer.cost, "\(rules): what the button said")
                XCTAssertNil(fixed.stationCrossoverOffer(for: station), "\(rules): nothing more to lay")
            }
            XCTAssertEqual(fixed.world.parallelTracks(between: a, and: b), 2, "\(rules)")
            let said = plus(fixed, id, to: 3)
            XCTAssertEqual(fixed.world.line(id: id)?.trains.count, 3, "\(rules): \(said)")
            let day = try Base.runDay(fixed.world)
            XCTAssertEqual(day.deadlockMinutes, 0, "\(rules)")
            XCTAssertEqual(day.legs.filter { $0 > 100 }.count, 3, "\(rules): \(day.legs)")
        }
    }

    /// Decision 571's stations (the platform tool on a double track): the
    /// line now takes a third train, on the platform beside an end's, and
    /// all three run a day without a deadlock. Before, the third stayed
    /// off the track ("no room at the line's ends").
    func testThirdTrainStandsAtThePlatformBeside() throws {
        for rules in [NewGameRules.simple, .realistic] {
            let session = try oldStations(rules: rules, crossovers: true)
            for station in session.world.stations.map(\.id) {
                XCTAssertNil(session.stationCrossoverOffer(for: station), "\(rules): decision 571 laid them")
            }
            let id = try line(session)
            let said = plus(session, id, to: 3)
            XCTAssertEqual(session.world.line(id: id)?.trains.count, 3, "\(rules): \(said)")
            XCTAssertFalse(said.contains("no room"), said)
            let day = try Base.runDay(session.world)
            XCTAssertEqual(day.deadlockMinutes, 0, "\(rules)")
            XCTAssertEqual(day.legs.filter { $0 > 100 }.count, 3, "\(rules): \(day.legs)")
        }
    }

    /// Single track 4 km long with a station 500 m in from each end, made
    /// double with "Make double track": the run's crossovers go in near
    /// its ends, outside the platforms, so the stations get their own
    /// inside them in the same command.
    func upgradedStations(rules: NewGameRules, language: DisplayLanguage = .english, trains: Int = 0) throws -> GameSession {
        let session = newGame(rules: rules, language: language)
        let east = Base.west + 4_000 * 64
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: Base.west, y: Base.y), reach: 16)
        session.tapNetwork(at: PlanPoint(x: east, y: Base.y), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.setNetworkMode(.platform)
        for x in [Base.west + 500 * 64, east - 500 * 64] {
            session.platformStationID = nil
            session.tapNetwork(at: PlanPoint(x: x, y: Base.y), reach: 64)
            session.addNetworkPlatform()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        }
        if trains > 0 {
            let id = try line(session)
            let said = plus(session, id, to: trains)
            XCTAssertEqual(session.world.line(id: id)?.trains.count, trains, said)
        }
        session.selectTool(.select)
        // The middle, or beside it: a line's depot can stand there.
        for offset: Int64 in [0, 500 * 64, -500 * 64, 1_000 * 64] where !session.canDoubleSelectedTrack {
            session.tapMap(at: PlanPoint(x: (Base.west + east) / 2 + offset, y: Base.y), reach: 16)
        }
        XCTAssertTrue(session.canDoubleSelectedTrack)
        session.beginTrackUpgrade(.doubleTrack)
        return session
    }

    func testMakingTrackDoubleLaysItsStationsCrossovers() throws {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let session = try upgradedStations(rules: .simple, language: language)
            let preview = try XCTUnwrap(session.trackUpgradePreview)
            XCTAssertNil(preview.problem, preview.problem ?? "")
            XCTAssertTrue(
                preview.note?.contains(language.text("2 crossovers go in beside its stations", "車站旁加 2 組渡線")) ?? false, preview.note ?? ""
            )
            XCTAssertEqual(preview.track.count, 5, "the second track, the run's two crossovers and the stations' two")
            let before = session.world.economy.balance
            session.buildTrackUpgrade()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
            XCTAssertEqual(session.world.economy.balance, before - (preview.cost ?? .zero), "what the preview said")
            for station in session.world.stations.map(\.id) {
                XCTAssertNil(session.stationCrossoverOffer(for: station), "laid with the second track")
            }
        }
        for rules in [NewGameRules.simple, .realistic] {
            let session = try upgradedStations(rules: rules)
            session.buildTrackUpgrade()
            let id = try line(session)
            let said = plus(session, id, to: 3)
            XCTAssertEqual(session.world.line(id: id)?.trains.count, 3, "\(rules): \(said)")
            let day = try Base.runDay(session.world)
            XCTAssertEqual(day.deadlockMinutes, 0, "\(rules)")
            XCTAssertEqual(day.legs.filter { $0 > 100 }.count, 3, "\(rules): \(day.legs)")
        }
    }

    /// REVIEW-L9 (decision 572, continued): with a train on the line, the
    /// preview said the upgrade could go ahead, but the stations'
    /// crossovers, planned with the trains taken off, were laid with them
    /// still on and GameCore refused ("A train's route runs over that
    /// track"); the train never leaves its platform, so the player could
    /// never make it double. They are laid as the station panel lays
    /// them: a train in the way goes back to the start of its line.
    func testMakingTrackDoubleUnderARunningLine() throws {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            for rules in [NewGameRules.simple, .realistic] {
                let session = try upgradedStations(rules: rules, language: language, trains: 1)
                let preview = try XCTUnwrap(session.trackUpgradePreview)
                XCTAssertNil(preview.problem, "\(rules): \(preview.problem ?? "")")
                XCTAssertNotNil(preview.cost, "\(rules): the preview says it can be built")
                XCTAssertTrue(
                    preview.note?.contains(language.text("beside", "車站旁加")) ?? false, "\(rules): \(preview.note ?? "")"
                )
                let before = session.world.economy.balance
                session.buildTrackUpgrade()
                XCTAssertEqual(session.message?.kind, .success, "\(rules): \(session.message?.text ?? "")")
                if rules == .realistic {
                    let text = session.message?.text ?? ""
                    XCTAssertTrue(text.contains(language.text("1 train was in the way", "有 1 列車擋在那段軌道上")), text)
                }
                XCTAssertEqual(session.world.economy.balance, before - (preview.cost ?? .zero), "\(rules): what the preview said")
                for station in session.world.stations.map(\.id) {
                    XCTAssertNil(session.stationCrossoverOffer(for: station), "\(rules): laid with the second track")
                }
                let id = try XCTUnwrap(session.world.lines.first).id
                XCTAssertEqual(session.world.line(id: id)?.trains.count, 1, "\(rules): the train is still on its line")
                XCTAssertTrue(session.world.trains.allSatisfy { $0.position != nil }, "\(rules): and on the track")
            }
        }
    }

    /// The panel's button and message in both languages; one undo takes
    /// the crossover away, and the command reads back from the log.
    func testCrossoverButtonSaysWhatItLaysAndUndoes() throws {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let session = try oldStations(rules: .simple, language: language)
            let station = session.world.stations[0].id
            let offer = try XCTUnwrap(session.stationCrossoverOffer(for: station))
            let button = session.stationCrossoverButtonText(offer)
            XCTAssertTrue(button.contains(language.text("Add a crossover between the two tracks", "在兩條軌道之間加一組渡線")), button)
            XCTAssertTrue(button.contains(offer.cost.moneyText), button)
            let edges = session.world.network.edges.count
            session.addStationCrossovers(station)
            let text = session.message?.text ?? ""
            XCTAssertTrue(text.contains(language.text("Trains can now pass each other at this station.", "列車可以在這站交會了。")), text)
            guard case .command(let command)? = session.commandLog.entries.last?.action,
                  case .buildStationCrossovers(let laidAt, let crossovers) = command else {
                return XCTFail("\(String(describing: session.commandLog.entries.last?.action))")
            }
            XCTAssertEqual(laidAt, station)
            XCTAssertEqual(crossovers.count, 1)
            XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: JSONEncoder().encode(command)), command)
            XCTAssertGreaterThan(session.world.network.edges.count, edges)
            session.undo()
            XCTAssertEqual(session.world.network.edges.count, edges)
            XCTAssertNotNil(session.stationCrossoverOffer(for: station), "offered again")
        }
    }

    /// Nothing to offer at a station on one track, and none while the
    /// double track is not taught yet (a lesson before lesson 5).
    func testNoOfferOnSingleTrack() throws {
        let session = newGame(rules: .simple, language: .english)
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: Base.west, y: Base.y), reach: 16)
        session.tapNetwork(at: PlanPoint(x: Base.east, y: Base.y), reach: 16)
        session.buildNetworkTrack()
        session.setNetworkMode(.platform)
        session.platformStationID = nil
        session.tapNetwork(at: PlanPoint(x: Base.west + 2_000, y: Base.y), reach: 64)
        session.addNetworkPlatform()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertNil(session.stationCrossoverOffer(for: session.world.stations[0].id))
    }
}

extension OldStationCrossoverTests {
    /// Decision 571's "mixed" row: the platform tool tapped on one track at
    /// the first station and on the other at the second. Its crossovers'
    /// near turnouts lay on different tracks, and under simple rules with
    /// traffic control three trains stood deadlocked all day (1,074
    /// minutes). The second station's crossover is now laid from the
    /// platform beside, so the near turnouts share a track, and all three
    /// run under either rules.
    func testPlatformToolOnTheOtherTrackAtTheFarEnd() throws {
        for rules in [NewGameRules.simple, .realistic] {
            let session = newGame(rules: rules, language: .english)
            session.selectTool(.network)
            session.networkBuildsDouble = true
            session.tapNetwork(at: PlanPoint(x: Base.west, y: Base.y), reach: 16)
            session.tapNetwork(at: PlanPoint(x: Base.east, y: Base.y), reach: 16)
            session.buildNetworkTrack()
            session.setNetworkMode(.platform)
            var tapped: [TrackEdgeID] = []
            for (x, y) in [(Base.west + 2_000, Base.y), (Base.east - 2_000, Base.y - DoubleTrack.spacing)] {
                session.platformStationID = nil
                session.tapNetwork(at: PlanPoint(x: x, y: y), reach: 64)
                tapped.append(try XCTUnwrap(session.networkPlatformStretch).edge)
                session.addNetworkPlatform()
                XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
            }
            XCTAssertNotEqual(tapped[0], tapped[1], "one track, then the other")
            let id = try line(session)
            let said = plus(session, id, to: 3)
            XCTAssertEqual(session.world.line(id: id)?.trains.count, 3, "\(rules): \(said)")
            let day = try Base.runDay(session.world)
            XCTAssertEqual(day.deadlockMinutes, 0, "\(rules)")
            XCTAssertEqual(day.legs.filter { $0 > 100 }.count, 3, "\(rules): \(day.legs)")
        }
    }
}
