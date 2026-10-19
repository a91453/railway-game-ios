import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 285, TestFlight 70.1: the platform tool on one track of a
/// double line no track joins to the other gives the same station a
/// platform on both, so stations whose platforms were tapped on different
/// tracks are still joined and a line between them runs.
@MainActor
final class DoubleTrackPlatformTests: XCTestCase {
    /// A double track 500 m long drawn from open ground: the main track
    /// along y = 10,240, the second 5 m north, no crossover between them.
    private func doubleTrack(language: DisplayLanguage = .english, balance: Money = 100_000_000) throws -> GameSession {
        let world = try makeWorld(width: 40_960, height: 20_480, balance: balance, speed: .normal)
        let session = GameSession(world: world, language: language)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 34_816, y: 10_240), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.network.edges.count, 2, "two tracks, no crossover")
        session.setNetworkMode(.platform)
        return session
    }

    private func tap(_ session: GameSession, x: Int64, north: Bool) {
        session.tapNetwork(at: PlanPoint(x: x, y: north ? 10_240 - 320 : 10_240), reach: 64)
    }

    private func addPlatform(_ session: GameSession, x: Int64, north: Bool) {
        tap(session, x: x, north: north)
        session.addNetworkPlatform()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
    }

    /// The report: a station on each track, tapped on different ones. On
    /// `main` the draft found no route and the line's train never left.
    func testStationsTappedOnDifferentTracksOfADoubleLineAreJoinedAndTheLineRuns() throws {
        let session = try doubleTrack()
        addPlatform(session, x: 6_144, north: false)
        addPlatform(session, x: 30_720, north: true)
        let ids = session.world.stations.map(\.id)
        XCTAssertEqual(ids.count, 2)
        for id in ids {
            XCTAssertEqual(session.world.network.platforms(of: id).count, 2, "a platform on each track")
            XCTAssertEqual(Set(session.world.network.platforms(of: id).map(\.edge)).count, 2)
        }
        session.selectTool(.select)
        for id in ids {
            session.selectStation(id)
            session.addSelectedStationToLineDraft()
        }
        XCTAssertEqual(session.lineDraftRoute, ids)
        XCTAssertNil(session.lineDraftGap)
        session.createLineFromDraft()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let line = try XCTUnwrap(session.world.lines.first)
        XCTAssertEqual(line.stops, ids)

        // A train on it runs to the far station and back.
        var world = session.world
        try world.setLineServiceWindow(line.id, to: .allDay)
        let train = try world.purchaseTrain(named: "T").id
        let running = GameSession(world: world)
        running.selectStation(ids[0])
        running.selectTrain(train)
        running.placeSelectedTrain()
        XCTAssertNotNil(running.world.train(id: train)?.position, running.message?.text ?? "")
        running.assignTrain(train, toLine: line.id)
        world = running.world
        XCTAssertNil(world.lineDispatchHold(of: train))
        var stopped: [StationID] = []
        for _ in 0..<3_600 where stopped.count < 3 {
            try world.advance(ticks: 1)
            for id in world.stationsStoppedAt(by: train) where stopped.last != id { stopped.append(id) }
        }
        XCTAssertNil(world.lineDispatchHold(of: train))
        // Off from the first station: the far one, back, and out again.
        XCTAssertEqual(stopped, [ids[1], ids[0], ids[1]], "to the far station and back")
    }

    func testThePreviewTheMapAndTheMessageSayBothTracks() throws {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let session = try doubleTrack(language: language)
            tap(session, x: 6_144, north: false)
            XCTAssertNotNil(session.networkPlatformBeside)
            let overlay = try XCTUnwrap(session.networkOverlay)
            XCTAssertGreaterThan(overlay.highlight.count, 1)
            XCTAssertGreaterThan(overlay.besideHighlight.count, 1)
            XCTAssertTrue(overlay.besideHighlight.allSatisfy { $0.y < 10_240 - 256 }, "drawn on the north track")
            let summary = session.networkDraftText()
            XCTAssertTrue(
                summary.hasPrefix(language.text("64 m platform here, on both tracks", "在這裡設 64 公尺 的月台（兩條軌道）")), summary
            )
            session.addNetworkPlatform()
            let text = session.message?.text ?? ""
            XCTAssertEqual(session.message?.kind, .success, text)
            XCTAssertTrue(text.contains(language.text(
                "The track beside it gets a platform too, so trains on either track call here.",
                "旁邊的軌道也設了月台，兩條軌道的列車都能停這一站。"
            )), text)
        }
    }

    func testOneUndoTakesBothBackAndTheLogReplaysIt() throws {
        let session = try doubleTrack()
        let before = session.world
        let logged = session.commandLog.entries.count
        addPlatform(session, x: 6_144, north: false)
        XCTAssertEqual(session.world.network.platforms.count, 2)
        XCTAssertEqual(session.commandLog.entries.count, logged + 1, "one command for both platforms")
        let entry = try XCTUnwrap(session.commandLog.entries.last)
        XCTAssertEqual(try JSONDecoder().decode(type(of: entry), from: JSONEncoder().encode(entry)), entry)
        guard case .command(.addPlatform(let addition)) = entry.action else { return XCTFail("\(entry.action)") }
        XCTAssertNotNil(addition.beside)
        session.undo()
        XCTAssertEqual(session.world, before)
    }

    func testAPlatformAlreadyOnTheTrackBesideLeavesTheTappedOneAsBefore() throws {
        // The north track has a platform opposite already, put there as
        // decision 285 would not: GameCore will not overlap it, so the
        // tap on the south track builds that one only, as before.
        let session = try doubleTrack()
        tap(session, x: 6_144, north: false)
        let opposite = try XCTUnwrap(session.networkPlatformBeside)
        var world = session.world
        let station = try world.buildStation(named: "West", at: PlanPoint(x: 6_144, y: 10_080)).id
        try world.addTrackPlatform(station, on: opposite.edge, from: opposite.start, to: opposite.end)
        let blocked = GameSession(world: world)
        blocked.selectTool(.network)
        blocked.setNetworkMode(.platform)
        blocked.platformStationID = station
        tap(blocked, x: 6_144, north: false)
        XCTAssertNil(blocked.networkPlatformBeside, "the preview says one track")
        addPlatform(blocked, x: 6_144, north: false)
        XCTAssertEqual(blocked.world.network.platforms(of: station).count, 2, "the one tapped, beside the one there")
        XCTAssertFalse(blocked.message?.text.contains("beside") ?? true, blocked.message?.text ?? "")
    }

    func testTracksAlreadyJoinedGetThePlatformOnTheTrackTappedOnly() throws {
        // A single track, then a double track on from its east end: the
        // second track has a crossover to it, so the two meet.
        var world = try makeWorld(width: 40_960, height: 16_384, balance: 100_000_000, speed: .paused)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 5_120, y: 8_192))
        try world.buildTrackEdge(from: west, to: east)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.networkDoubleSide = .left
        session.tapNetwork(at: PlanPoint(x: 5_120, y: 8_192), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 30_720, y: 8_192), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.setNetworkMode(.platform)
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 8_192 - 320), reach: 64)
        XCTAssertNil(session.networkPlatformBeside, "joined by the crossover")
        session.addNetworkPlatform()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.network.platforms.count, 1)
    }
}
