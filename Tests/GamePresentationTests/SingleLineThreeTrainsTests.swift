import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 628, TestFlight 115.1 ("three trains cannot run on the line";
/// the player had not played the tutorial). A new player draws one single
/// track from open ground and sets a platform for each station along it
/// with the platform tool, so every platform lies on the same edge. On
/// main "Add a Train" could not put in the passing loop the second train
/// needs (the edge's middle was a station's platform), so the player
/// bought trains and set them on the stations by hand: three trains, one
/// at each station of a single track with one platform each, each waiting
/// all day for the platform another stood on.
@MainActor
final class SingleLineThreeTrainsTests: XCTestCase {
    static let y: Int64 = 40_000
    static let west: Int64 = 20_000
    static let km: Int64 = 1_000 * WorldCoordinate.unitsPerMetre

    /// A new game by `rules` (traffic control on, as the app starts one)
    /// with an 8 km single track drawn from open ground, three stations on
    /// it 4 km apart set with the platform tool, and `lines` (stops by
    /// station, west to east) made from the line draft.
    func playerLine(rules: NewGameRules, lines: [[Int]] = [[0, 1, 2]]) throws -> GameSession {
        var world = GameWorld.newGame(rules: rules)
        world.setSpeed(.normal)
        let session = GameSession(world: world, language: .english)
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: Self.west, y: Self.y), reach: 16)
        session.tapNetwork(at: PlanPoint(x: Self.west + 8 * Self.km, y: Self.y), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.network.edges.count, 1)
        session.setNetworkMode(.platform)
        for x in [Self.west + 2_000, Self.west + 4 * Self.km, Self.west + 8 * Self.km - 2_000] {
            session.platformStationID = nil
            session.tapNetwork(at: PlanPoint(x: x, y: Self.y), reach: 64)
            session.addNetworkPlatform()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        }
        session.selectTool(.select)
        let stations = session.world.stations.sorted { $0.point.x < $1.point.x }.map(\.id)
        for stops in lines {
            for index in stops {
                session.selectStation(stations[index])
                session.addSelectedStationToLineDraft()
            }
            session.createLineFromDraft()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        }
        return session
    }

    /// Trains bought and set by hand, one at each station in turn, each
    /// assigned to a line in turn, until there are three; each line set to
    /// run the trains it has. The messages the assignments gave.
    func placeByHand(in session: GameSession) throws -> [String] {
        let stations = session.world.stations.sorted { $0.point.x < $1.point.x }.map(\.id)
        let lines = session.world.lines.map(\.id)
        var said: [String] = []
        for index in session.world.trains.count..<3 {
            session.purchaseTrain()
            let train = try XCTUnwrap(session.world.trains.last).id
            session.selectStation(stations[index % stations.count])
            session.selectTrain(train)
            session.placeSelectedTrain()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
            session.assignTrain(train, toLine: lines[index % lines.count])
            said.append(session.message?.text ?? "")
        }
        for line in lines {
            session.selectLine(line)
            let count = session.world.line(id: line)?.trains.count ?? 0
            for level in ServiceLevel.allCases { session.setSelectedLineTrains(count, at: level) }
        }
        return said
    }

    /// On main the loop was refused ("A platform must lie on a level
    /// stretch of a single track and not overlap another platform") and
    /// the line kept one train. Now Add a Train puts the loops in off the
    /// platforms, and three trains run all day.
    func testAddATrainOnTrackDrawnInOnePiece() throws {
        for rules in [NewGameRules.simple, .realistic] {
            let session = try playerLine(rules: rules)
            let line = try XCTUnwrap(session.world.lines.first).id
            session.selectLine(line)
            for _ in 0..<3 where session.world.trains.count < 3 {
                session.addTrainToSelectedLine()
                XCTAssertEqual(session.message?.kind, .success, "\(rules): \(session.message?.text ?? "")")
            }
            XCTAssertEqual(session.world.trains.count, 3, "\(rules)")
            XCTAssertTrue(session.world.stations.contains { $0.operationMode == .closed }, "\(rules): a loop went in")
            let day = try DoubleTrackDeadlockTests.runDay(session.world)
            XCTAssertEqual(day.deadlockMinutes, 0, "\(rules): \(day)")
            XCTAssertGreaterThanOrEqual(day.legs.filter { $0 > 100 }.count, 2, "\(rules): \(day)")
        }
    }

    /// Three trains set by hand on the single track stand still all day
    /// (on main too). The assignment says where a passing loop is needed,
    /// the station master warns of the line, its card has the button, and
    /// one tap puts in every loop needed: then the trains run all day.
    func testTrainsSetByHandAreWarnedOfAndOneTapLetsThemRun() throws {
        for rules in [NewGameRules.simple, .realistic] {
            let session = try playerLine(rules: rules)
            let line = try XCTUnwrap(session.world.lines.first).id
            let said = try placeByHand(in: session)
            XCTAssertTrue(said.last?.contains("no place for 3 trains to pass") == true, "\(rules): \(said)")
            let stuck = try DoubleTrackDeadlockTests.runDay(session.world)
            XCTAssertGreaterThan(stuck.deadlockMinutes, 1_000, "\(rules): the bug itself, \(stuck)")

            XCTAssertEqual(session.world.firstLineWithoutPlaceToPass()?.id, line, "\(rules)")
            XCTAssertEqual(StationMasterAdvice(world: session.world), .noPlaceToPass(line: line, name: "Line 1"), "\(rules)")
            session.selectLine(line)
            let shortfall = try XCTUnwrap(session.selectedLinePassingShortfall, "\(rules)")
            XCTAssertTrue(session.passingShortfallText(shortfall).contains("3 trains have no place to pass"), session.passingShortfallText(shortfall))

            session.addPassingLoopToSelectedLine()
            XCTAssertEqual(session.message?.kind, .success, "\(rules): \(session.message?.text ?? "")")
            XCTAssertNil(session.world.firstLineWithoutPlaceToPass(), "\(rules)")
            let day = try DoubleTrackDeadlockTests.runDay(session.world)
            XCTAssertEqual(day.deadlockMinutes, 0, "\(rules): \(day)")
            XCTAssertGreaterThanOrEqual(day.legs.filter { $0 > 100 }.count, 2, "\(rules): \(day)")
        }
    }

    /// The challenge's way (a station both lines stop at): two lines over
    /// the same single track, trains set by hand. The same tap fixes it.
    func testTwoLinesOverTheSingleTrackRunOnceTheLoopsAreIn() throws {
        let session = try playerLine(rules: .simple, lines: [[0, 1, 2], [0, 1]])
        _ = try placeByHand(in: session)
        let line = try XCTUnwrap(session.world.firstLineWithoutPlaceToPass()).id
        session.selectLine(line)
        session.addPassingLoopToSelectedLine()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let day = try DoubleTrackDeadlockTests.runDay(session.world)
        XCTAssertEqual(day.deadlockMinutes, 0, "\(day)")
        XCTAssertGreaterThanOrEqual(day.legs.filter { $0 > 100 }.count, 2, "\(day)")
    }

    /// Spares assigned but off the track stand in nobody's way: no warning.
    func testSparesOffTheTrackAreNoShortfall() throws {
        let session = try playerLine(rules: .realistic)
        let line = try XCTUnwrap(session.world.lines.first).id
        session.purchaseTrain()
        let station = try XCTUnwrap(session.world.stations.min { $0.point.x < $1.point.x }).id
        let first = try XCTUnwrap(session.world.trains.last).id
        session.selectStation(station)
        session.selectTrain(first)
        session.placeSelectedTrain()
        session.assignTrain(first, toLine: line)
        for _ in 0..<2 {
            session.purchaseTrain()
            session.assignTrain(try XCTUnwrap(session.world.trains.last).id, toLine: line)
        }
        XCTAssertEqual(session.world.line(id: line)?.assignedTrains.count, 3)
        XCTAssertNil(session.world.singleTrackShortfall(of: line))
        XCTAssertNil(session.world.firstLineWithoutPlaceToPass())
    }
}
