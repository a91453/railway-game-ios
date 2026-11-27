import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1020 (the owner, 2026-11-27): two stations the track tools
/// built, joined by track, lead from Build to their line; and Lines'
/// New Line… starts picking at once, which brings the form to the top.
@MainActor
final class LineFromBuiltTrackTests: XCTestCase {
    private static let reach: Int64 = 512

    /// A blank map, paused, with money to build.
    private func blankWorld() -> GameWorld {
        GameWorld(bounds: try! WorldBounds(width: 16_384, height: 8_192),
                  economy: GameEconomy(balance: Money(1_000_000), costs: testCosts), clock: GameClock(speed: .paused))
    }

    /// Track along y = 2048 from x 1024 to 15360 in two stretches, built
    /// with the tools.
    private func layTrack(in session: GameSession) {
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: 1_024, y: 2_048), reach: Self.reach)
        session.tapNetwork(at: PlanPoint(x: 8_192, y: 2_048), reach: Self.reach)
        session.buildNetworkTrack()
        session.tapNetwork(at: PlanPoint(x: 15_360, y: 2_048), reach: Self.reach)
        session.buildNetworkTrack()
        session.clearNetworkDraft()
    }

    /// A station with a platform at `x` on the track, built with the tools.
    @discardableResult
    private func addStation(_ name: String, at x: Int64, in session: GameSession) throws -> StationID {
        session.setNetworkMode(.platform)
        session.tapNetwork(at: PlanPoint(x: x, y: 2_048), reach: Self.reach)
        session.stationName = name
        // Short platforms, so three fit on the test's track.
        session.platformCars = 1
        let before = Set(session.world.stations.map(\.id))
        session.addNetworkPlatform()
        let built = Set(session.world.stations.map(\.id)).subtracting(before)
        return try XCTUnwrap(built.first, session.message?.text ?? "no station")
    }

    func testTwoStationsBuiltOnOneTrackOfferTheirLine() throws {
        let session = GameSession(world: blankWorld())
        layTrack(in: session)
        let west = try addStation("West", at: 3_072, in: session)
        XCTAssertNil(session.lineFromBuiltTrack, "one station: no line yet")
        let east = try addStation("East", at: 14_336, in: session)
        let offer = try XCTUnwrap(session.lineFromBuiltTrack)
        XCTAssertEqual(offer.from, west)
        XCTAssertEqual(offer.to, east)
        XCTAssertEqual(offer.stops, 2)
        XCTAssertEqual(offer.title(from: "West", to: "East", in: .traditionalChinese), "建立路線：West → East")
        XCTAssertEqual(LineFromBuiltTrack.buttonTitle(in: .traditionalChinese), "用這段軌道建路線")

        // A station between: the line still runs end to end, through it.
        try addStation("Middle", at: 11_264, in: session)
        let longer = try XCTUnwrap(session.lineFromBuiltTrack)
        XCTAssertEqual([longer.from, longer.to], [west, east])
        XCTAssertEqual(longer.stops, 3)

        // The button: a draft from end to end, picking on, the world as it was.
        let world = session.world
        session.selectTool(.select)
        session.startLineFromBuiltTrack()
        XCTAssertEqual(session.lineDraft, [west, east])
        XCTAssertEqual(session.lineDraftStops.count, 3)
        XCTAssertTrue(session.isPickingLineStops)
        XCTAssertFalse(session.linesPanelListsLinesFirst, "Lines opens on the new line's form")
        XCTAssertEqual(session.world, world)

        // Made: the offer is gone.
        session.createLineFromDraft()
        XCTAssertEqual(session.world.lines.count, 1)
        XCTAssertNil(session.lineFromBuiltTrack)
    }

    func testStationsNoTrackJoinsAreNotOffered() throws {
        let session = GameSession(world: blankWorld())
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: 1_024, y: 2_048), reach: Self.reach)
        session.tapNetwork(at: PlanPoint(x: 7_168, y: 2_048), reach: Self.reach)
        session.buildNetworkTrack()
        session.clearNetworkDraft()
        session.tapNetwork(at: PlanPoint(x: 9_216, y: 2_048), reach: Self.reach)
        session.tapNetwork(at: PlanPoint(x: 15_360, y: 2_048), reach: Self.reach)
        session.buildNetworkTrack()
        session.clearNetworkDraft()
        try addStation("West", at: 4_096, in: session)
        try addStation("East", at: 12_288, in: session)
        XCTAssertNil(session.lineFromBuiltTrack, "two tracks apart")

        // Track built between them joins them: offered now.
        session.setNetworkMode(.build)
        session.tapNetwork(at: PlanPoint(x: 7_168, y: 2_048), reach: Self.reach)
        session.tapNetwork(at: PlanPoint(x: 9_216, y: 2_048), reach: Self.reach)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertNotNil(session.lineFromBuiltTrack)
    }

    func testTheTutorialMakesItsOwnLine() throws {
        let session = GameSession(world: blankWorld())
        layTrack(in: session)
        try addStation("West", at: 3_072, in: session)
        try addStation("East", at: 13_312, in: session)
        XCTAssertNotNil(session.lineFromBuiltTrack)
        session.startTutorial()
        XCTAssertNil(session.lineFromBuiltTrack)
    }

    /// Lines' New Line…: picking starts, so the form leads the panel.
    func testNewLineStartsPickingAndPutsTheFormFirst() throws {
        let session = GameSession(world: blankWorld())
        layTrack(in: session)
        try addStation("West", at: 3_072, in: session)
        try addStation("East", at: 13_312, in: session)
        session.selectTool(.select)
        session.startLineFromBuiltTrack()
        session.createLineFromDraft()
        XCTAssertEqual(session.world.lines.count, 1)
        XCTAssertTrue(session.linesPanelListsLinesFirst)
        XCTAssertEqual(LinesListControls.pinned.parts, [.entries, .lines])
        session.startPickingLineStops()
        XCTAssertFalse(session.linesPanelListsLinesFirst)
    }
}
