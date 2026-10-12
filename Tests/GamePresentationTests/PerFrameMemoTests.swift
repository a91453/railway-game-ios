import GameCore
@testable import GamePresentation
import XCTest

/// What the map and the inspector read several times a frame while the
/// game runs is not worked out again at every tick (the third bug hunt,
/// after #399): the track inspector's line map is built once a command,
/// the situation bubbles' deadlock search once a command or ten game
/// minutes. On the real-world demo (debug build) the line map took some
/// 24 ms and the bubbles some 81 ms, each read twice a frame.
@MainActor
final class PerFrameMemoTests: XCTestCase {
    private func tick(_ session: GameSession) throws {
        let tick = try XCTUnwrap(session.beginLoopTick())
        XCTAssertTrue(session.finish(tick, with: .success(try GameSession.advanced(tick.world, by: 1, listening: false))))
    }

    func testAStepOfGameTimeIsNotACommand() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let session = GameSession(world: try newGameLine(through: [towns[0], towns[1]]))
        session.setSpeed(.normal)
        let commands = session.commandRevision, revision = session.worldRevision
        try tick(session)
        XCTAssertNotEqual(session.worldRevision, revision)
        XCTAssertEqual(session.commandRevision, commands, "game time moved on, no command")
        session.togglePause()
        XCTAssertNotEqual(session.commandRevision, commands, "a pause is the player's")
    }

    func testTheTrackInspectorKeepsItsLineMapUntilACommand() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let session = GameSession(world: try newGameLine(through: [towns[0], towns[1]]))
        let line = try XCTUnwrap(session.world.lines.first)
        let edge = try XCTUnwrap(session.world.network.edges.first).id
        XCTAssertEqual(session.trackInspection(of: edge), session.world.trackInspection(of: edge))
        let built = try XCTUnwrap(session.inspectionLineMap)

        session.setSpeed(.normal)
        let commands = session.commandRevision
        for _ in 0..<30 {
            try tick(session)
            // The same as worked out afresh, at every tick: the signal as it is now.
            XCTAssertEqual(session.trackInspection(of: edge), session.world.trackInspection(of: edge))
            XCTAssertEqual(session.trackInspectionText(of: edge), session.world.trackInspectionText(of: edge, in: session.language))
        }
        XCTAssertEqual(session.inspectionLineMap?.revision, commands, "the line map kept through the ticks")
        XCTAssertEqual(session.inspectionLineMap?.map, built.map)

        // A second line along the same track: the inspector says so at once.
        try session.performEdit { world throws(GameError) in
            try world.createLine(named: "Back", stops: Array(line.stops.reversed()))
        }
        XCTAssertEqual(session.trackInspection(of: edge)?.lines.count, 2)
        XCTAssertEqual(session.trackInspection(of: edge), session.world.trackInspection(of: edge))
        XCTAssertEqual(session.trackInspectionText(of: edge), session.world.trackInspectionText(of: edge, in: session.language))
        XCTAssertNil(session.trackInspection(of: TrackEdgeID.edge(9_999)))
    }

    func testTheSituationBubblesAreWorkedOutAgainAfterACommandOrTenGameMinutes() throws {
        var world = try makeWorld(width: 40_960, height: 8_192, balance: 100_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        world.setTourism([
            Attraction(id: AttractionID(rawValue: 1), name: "遠方古蹟", englishName: "Far Sight",
                       point: PlanPoint(x: 36_000, y: 4_096), kind: .town, baseStars: 450),
        ])
        let session = GameSession(world: world)
        XCTAssertEqual(session.situationAlerts, [])
        try session.performEdit { world throws(GameError) in
            try world.createLine(named: "Main", stops: [StationID(rawValue: 1), StationID(rawValue: 2)])
        }
        XCTAssertEqual(session.situationAlerts.map(\.kind), [.sightWithoutStation(AttractionID(rawValue: 1))], "a command: at once")
        XCTAssertEqual(session.situationAlerts, session.world.situationAlerts())

        session.setSpeed(.normal)
        _ = session.situationAlerts
        let memo = try XCTUnwrap(session.situationAlertsMemo)
        try tick(session)
        _ = session.situationAlerts
        XCTAssertEqual(session.situationAlertsMemo?.revision, memo.revision, "a game minute: kept")
        XCTAssertEqual(session.situationAlertsMemo?.period, memo.period)
        for _ in 0..<10 { try tick(session) }
        _ = session.situationAlerts
        XCTAssertNotEqual(session.situationAlertsMemo?.period, memo.period, "ten game minutes: worked out again")
        // Whenever they are worked out again, they are what the world says afresh.
        for _ in 0..<30 {
            let period = session.situationAlertsMemo?.period
            try tick(session)
            let alerts = session.situationAlerts
            if session.situationAlertsMemo?.period != period {
                XCTAssertEqual(alerts, session.world.situationAlerts())
            }
        }
    }
}
