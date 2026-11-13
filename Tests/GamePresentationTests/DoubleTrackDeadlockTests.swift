import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 571, TestFlight 110.1: "a double track, but the trains are
/// always deadlocked and never pass each other". A new player draws a
/// double track from open ground, sets a platform at each end and opens a
/// line between them. Before decision 571 the two tracks never met between
/// the stations: the line could use one of them only, planned a single
/// train, and two trains set off from opposite ends met head on.
@MainActor
final class DoubleTrackDeadlockTests: XCTestCase {
    static let y: Int64 = 40_000
    static let west: Int64 = 20_000
    static let east: Int64 = west + 3_000 * 64

    /// A new game by `rules` (traffic control on, as the app starts one;
    /// off when `controlled` is false) with a double track 3 km long drawn
    /// from open ground and a platform set near each end with the platform
    /// tool, each a station of its own.
    func playerStations(rules: NewGameRules, controlled: Bool = true, language: DisplayLanguage = .english) throws -> GameSession {
        var world = GameWorld.newGame(rules: rules)
        if !controlled { try world.setTrafficControl(false) }
        world.setSpeed(.normal)
        let session = GameSession(world: world, language: language)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.tapNetwork(at: PlanPoint(x: Self.west, y: Self.y), reach: 16)
        session.tapNetwork(at: PlanPoint(x: Self.east, y: Self.y), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.setNetworkMode(.platform)
        for x in [Self.west + 2_000, Self.east - 2_000] {
            session.platformStationID = nil
            session.tapNetwork(at: PlanPoint(x: x, y: Self.y), reach: 64)
            session.addNetworkPlatform()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        }
        return session
    }

    /// ``playerStations(rules:controlled:language:)`` with a line from the
    /// first station to the second.
    func playerLine(rules: NewGameRules, controlled: Bool = true) throws -> (GameSession, LineID) {
        let session = try playerStations(rules: rules, controlled: controlled)
        session.selectTool(.select)
        for station in session.world.stations {
            session.selectStation(station.id)
            session.addSelectedStationToLineDraft()
        }
        session.createLineFromDraft()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        return (session, try XCTUnwrap(session.world.lines.first).id)
    }

    /// `start` run a day a minute at a time: the legs each train ran (a
    /// leg ends where it sets off for its next stop) and the minutes some
    /// train was in a deadlock.
    static func runDay(_ start: GameWorld) throws -> (legs: [Int], deadlockMinutes: Int) {
        var world = start
        world.setSpeed(.normal)
        var legs: [TrainID: Int] = [:]
        var last: [TrainID: Int] = [:]
        var deadlockMinutes = 0
        for _ in 0..<GameTime.minutesPerDay {
            try world.advance(ticks: 1)
            if !world.deadlockedTrains().isEmpty { deadlockMinutes += 1 }
            for train in world.trains {
                let stop: Int? = switch train.execution {
                case .waitingAtStop(let stop, _)?, .travellingToStop(let stop, _)?: stop
                default: nil
                }
                guard let stop, last[train.id] != stop else { continue }
                if last[train.id] != nil { legs[train.id, default: 0] += 1 }
                last[train.id] = stop
            }
        }
        return (world.trains.map { legs[$0.id, default: 0] }, deadlockMinutes)
    }

    /// The player's way: ＋ on the line until it has two trains (the
    /// simple game's first train is on it already). The line takes them,
    /// and they run all day on the double track, never stuck.
    func testTwoLineTrainsPassOnTheDoubleTrack() throws {
        for rules in [NewGameRules.simple, .realistic] {
            let (session, line) = try playerLine(rules: rules)
            session.selectLine(line)
            for _ in 0..<2 where (session.world.line(id: line)?.trains.count ?? 0) < 2 { session.addTrainToSelectedLine() }
            XCTAssertEqual(session.world.line(id: line)?.trains.count, 2, "\(rules): \(session.message?.text ?? "")")
            let day = try Self.runDay(session.world)
            XCTAssertEqual(day.deadlockMinutes, 0, "\(rules)")
            // A leg takes a few minutes: each train runs all day.
            XCTAssertEqual(day.legs.filter { $0 > 100 }.count, 2, "\(rules): \(day.legs)")
        }
    }

    /// Trains bought and set at opposite ends by hand under realistic
    /// rules, which run as many as are set: on main both stood on the same
    /// track and were deadlocked all day.
    func testHandPlacedTrainsAtOppositeEndsPass() throws {
        for count in [2, 3] {
            let (session, line) = try playerLine(rules: .realistic)
            let stations = session.world.stations.map(\.id)
            for index in 0..<count {
                session.purchaseTrain()
                let train = try XCTUnwrap(session.world.trains.last).id
                session.selectStation(stations[index % 2])
                session.selectTrain(train)
                session.placeSelectedTrain()
                session.assignTrain(train, toLine: line)
            }
            session.selectLine(line)
            for level in ServiceLevel.allCases { session.setSelectedLineTrains(count, at: level) }
            let day = try Self.runDay(session.world)
            XCTAssertEqual(day.deadlockMinutes, 0, "\(count) trains")
            for legs in day.legs { XCTAssertGreaterThan(legs, 100, "\(count) trains: \(day.legs)") }
        }
    }

    /// `start` run a day a minute at a time: the legs each train ran, and
    /// the longest run of minutes some train was in a deadlock.
    func longestDeadlock(_ start: GameWorld) throws -> (legs: [Int], longest: Int) {
        var world = start
        world.setSpeed(.normal)
        var legs: [TrainID: Int] = [:]
        var last: [TrainID: Int] = [:]
        var run = 0
        var longest = 0
        for _ in 0..<GameTime.minutesPerDay {
            try world.advance(ticks: 1)
            run = world.deadlockedTrains().isEmpty ? 0 : run + 1
            longest = max(longest, run)
            for train in world.trains {
                let stop: Int? = switch train.execution {
                case .waitingAtStop(let stop, _)?, .travellingToStop(let stop, _)?: stop
                default: nil
                }
                guard let stop, last[train.id] != stop else { continue }
                if last[train.id] != nil { legs[train.id, default: 0] += 1 }
                last[train.id] = stop
            }
        }
        return (world.trains.map { legs[$0.id, default: 0] }, longest)
    }

    /// Decision 571, continued: the player tapped one track at one end and
    /// the other at the other. The line's two ways cross over at the end
    /// each sets off from, so each way reaches one berth at each end, and
    /// under simple rules with traffic control (a new game's) the two
    /// trains each waited all day for the berth the other stood on (1,065
    /// minutes). Now the dispatcher sends one to the free berth along the
    /// other main track. Continued again: the train takes it as it is due
    /// to leave, so no minute shows a deadlock (each trip showed one).
    func testTwoTrainsOnTracksTappedAtEitherEndRunAllDay() throws {
        var world = GameWorld.newGame(rules: .simple)
        world.setSpeed(.normal)
        let session = GameSession(world: world, language: .english)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.tapNetwork(at: PlanPoint(x: Self.west, y: Self.y), reach: 16)
        session.tapNetwork(at: PlanPoint(x: Self.east, y: Self.y), reach: 16)
        session.buildNetworkTrack()
        let other = try XCTUnwrap(session.world.network.nodes.map(\.position.y).first { $0 != Self.y })
        session.setNetworkMode(.platform)
        for (x, y) in [(Self.west + 2_000, Self.y), (Self.east - 2_000, other)] {
            session.platformStationID = nil
            session.tapNetwork(at: PlanPoint(x: x, y: y), reach: 64)
            session.addNetworkPlatform()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        }
        session.selectTool(.select)
        for station in session.world.stations {
            session.selectStation(station.id)
            session.addSelectedStationToLineDraft()
        }
        session.createLineFromDraft()
        let line = try XCTUnwrap(session.world.lines.first).id
        session.selectLine(line)
        for _ in 0..<2 where (session.world.line(id: line)?.trains.count ?? 0) < 2 { session.addTrainToSelectedLine() }
        XCTAssertEqual(session.world.line(id: line)?.trains.count, 2)
        let day = try longestDeadlock(session.world)
        XCTAssertEqual(day.longest, 0, "\(day)")
        for legs in day.legs { XCTAssertGreaterThan(legs, 100, "\(day)") }
    }

    /// Decision 571, continued: under simple rules with traffic control
    /// the line runs one train (its round trip is its headway); trains
    /// bought and set at either end by hand are its spares, standing on a
    /// berth. The train it runs waited all day for the berth a spare stood
    /// on (1,074 minutes, no leg run). Now it takes the free one, as it is
    /// due to leave (continued again), so no minute shows a deadlock.
    func testTheRunningTrainPassesSparesSetAtEitherEnd() throws {
        for count in [2, 3] {
            let (session, line) = try playerLine(rules: .simple)
            let stations = session.world.stations.map(\.id)
            for index in 0..<count {
                session.purchaseTrain()
                let train = try XCTUnwrap(session.world.trains.last).id
                session.selectStation(stations[index % 2])
                session.selectTrain(train)
                session.placeSelectedTrain()
                session.assignTrain(train, toLine: line)
            }
            session.selectLine(line)
            for level in ServiceLevel.allCases { session.setSelectedLineTrains(count, at: level) }
            let day = try longestDeadlock(session.world)
            XCTAssertEqual(day.longest, 0, "\(count) trains: \(day)")
            XCTAssertGreaterThan(day.legs.max() ?? 0, 200, "\(count) trains: \(day)")
        }
    }

    /// The platform tool on a double track whose tracks never meet says,
    /// before the tap on ✓, that a crossover comes with the platforms, and
    /// draws it; after, that one was laid, and the two tracks then count
    /// as double track between the stations.
    func testPlatformToolLaysACrossoverAndSaysSo() throws {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let session = try playerStations(rules: .simple, language: language)
            XCTAssertEqual(session.world.stations.count, 2)
            let built = session.message?.text ?? ""
            XCTAssertTrue(built.contains(language.text("A crossover joins the two tracks", "旁邊加了一組渡線")), built)
            let (a, b) = (session.world.stations[0].id, session.world.stations[1].id)
            XCTAssertEqual(session.world.parallelTracks(between: a, and: b), 2)

            // A third platform midway, 1.5 km from the turnouts at the
            // ends: a crossover at each end of it.
            session.platformStationID = nil
            session.tapNetwork(at: PlanPoint(x: (Self.west + Self.east) / 2, y: Self.y), reach: 64)
            XCTAssertEqual(session.networkPlatformCrossoverCount, 2)
            let preview = session.networkDraftText()
            XCTAssertTrue(preview.contains(language.text("a crossover at each end", "兩端各加一組渡線")), preview)
            XCTAssertEqual(session.networkOverlay?.crossovers.count, 2)
            XCTAssertEqual(session.networkOverlay?.previewIsBuildable, true)
        }
    }

    /// The crossovers are part of the platform's command: one undo takes
    /// them away with the platforms, and the command reads back from the
    /// command log as it was.
    func testCrossoversUndoAndRecordWithThePlatform() throws {
        let session = try playerStations(rules: .simple)
        guard case .command(.addPlatform(let addition))? = session.commandLog.entries.last?.action else {
            return XCTFail("\(String(describing: session.commandLog.entries.last?.action))")
        }
        XCTAssertEqual(addition.crossovers.count, 1)
        let command = PlayerCommand.addPlatform(addition)
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: JSONEncoder().encode(command)), command)

        let edges = session.world.network.edges.count
        session.undo()
        XCTAssertEqual(session.world.stations.count, 1)
        // The crossover's edge and the two it split are gone with it.
        XCTAssertLessThan(session.world.network.edges.count, edges)
        let a = session.world.stations[0].id
        XCTAssertEqual(session.world.network.platforms.filter { $0.station == a }.count, 2)
    }
}
