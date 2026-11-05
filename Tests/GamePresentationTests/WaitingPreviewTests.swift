import GameCore
@testable import GamePresentation
import XCTest

/// Decision 590: in the app, the new line's price and its card's preview,
/// which try the command on copies of the world, are worked out on the
/// main actor's next turn, not inside the view update that asks for them
/// (TestFlight 112.1 ran out of main-thread stack there).
@MainActor
final class WaitingPreviewTests: XCTestCase {
    private static let middle = Int64(524_288)
    private static let metre = WorldCoordinate.unitsPerMetre

    /// Two stations 2.5 km apart on one straight track, under simple rules.
    private func session(waits: Bool) throws -> GameSession {
        var world = GameWorld.newGame(rules: .simple)
        world.setTourism(nil)
        let platform = 4 * world.platformCarLength
        func point(_ east: Int64) -> WorldCoordinate {
            WorldCoordinate(x: Self.middle + east * Self.metre, y: Self.middle)
        }
        let west = try world.buildTrackNode(at: point(-2_000))
        let east = try world.buildTrackNode(at: point(2_000))
        let main = try world.buildTrackEdge(from: west, to: east)
        var stations: [StationID] = []
        for (name, east) in [("West", Int64(-1_250)), ("East", 1_250)] {
            let id = try world.buildStation(named: name, at: PlanPoint(x: Self.middle + east * Self.metre, y: Self.middle - 64 * Self.metre)).id
            let from = (east + 2_000) * Self.metre - platform / 2
            try world.addTrackPlatform(id, on: main, from: from, to: from + platform)
            stations.append(id)
        }
        let session = GameSession(world: world, language: .english)
        session.worksOutPreviewsOnTheNextTurn = waits
        session.startPickingLineStops(announces: false)
        for station in stations {
            session.selectStation(station)
            session.addSelectedStationToLineDraft()
        }
        return session
    }

    /// The map's ✓ reads no price while the screen asks; the next turn
    /// brings it, and then the same caption as a session that works it out
    /// at once.
    func testTheLinePriceComesOnTheNextTurn() async throws {
        let now = try session(waits: false)
        let expected = try XCTUnwrap(now.mapLineDraft)
        XCTAssertNotNil(expected.opening)

        let app = try session(waits: true)
        let asked = app.previewsWorkedOutLater
        let first = try XCTUnwrap(app.mapLineDraft)
        XCTAssertNil(first.opening, "not worked out inside the view update")
        XCTAssertNil(app.lineOpeningMemo)
        XCTAssertTrue(app.isWaiting(for: .lineOpening))
        _ = app.lineDraftSummary
        XCTAssertNil(app.lineDraftSummaryMemo, "a summary without its price is not kept")

        await app.waitingPreviewsSettled()
        XCTAssertEqual(app.previewsWorkedOutLater, asked + 1, "worked out once, however often it was asked for")
        XCTAssertEqual(app.mapLineDraft, expected)
        XCTAssertEqual(app.lineDraftSummary, now.lineDraftSummary)
        XCTAssertFalse(app.isWaiting(for: .lineOpening))
    }

    /// The card's preview waits likewise, but Confirm works it out at once
    /// and opens the line.
    func testTheCardPreviewWaitsButConfirmDoesNot() async throws {
        let now = try session(waits: false)
        now.confirmLineDraft()
        let expected = try XCTUnwrap(now.lineConfirmationPreview)

        let app = try session(waits: true)
        app.confirmLineDraft()
        XCTAssertNotNil(app.lineConfirmation)
        XCTAssertNil(app.lineConfirmationPreview)
        await app.waitingPreviewsSettled()
        XCTAssertEqual(app.lineConfirmationPreview, expected)

        let confirming = try session(waits: true)
        confirming.confirmLineDraft()
        confirming.confirmLine()
        XCTAssertEqual(confirming.world.lines.count, 1, "Confirm does not wait")
        XCTAssertNil(confirming.lineConfirmation)
    }

    // MARK: - Decision 590, 114.1: the network tool's and the track card's previews

    /// A session on a 256 × 128 m map with 1,000,000 to spend and the
    /// network tool chosen, working previews out on the next turn where
    /// `waits`.
    private func networkSession(waits: Bool) throws -> GameSession {
        let session = GameSession(world: try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000), language: .english)
        session.worksOutPreviewsOnTheNextTurn = waits
        session.selectTool(.network)
        return session
    }

    /// The stretch drawn waits for the next turn, in the map's overlay as
    /// well, and then is the stretch a session working it out at once has;
    /// ✓ builds it without waiting.
    func testTheTrackDrawnComesOnTheNextTurn() async throws {
        let now = try networkSession(waits: false)
        let app = try networkSession(waits: true)
        for session in [now, app] {
            session.tapNetwork(at: PlanPoint(x: 2_048, y: 2_048), reach: 512)
            session.tapNetwork(at: PlanPoint(x: 14_336, y: 2_048), reach: 512)
        }
        let expected = try XCTUnwrap(now.networkPreview)
        XCTAssertNil(expected.problem, expected.problem ?? "")

        XCTAssertNil(app.networkPreview, "not worked out inside the view update")
        XCTAssertTrue(app.isWaiting(for: .networkDraft))
        XCTAssertEqual(app.networkOverlay?.preview, [], "nothing drawn yet")
        XCTAssertEqual(app.buildPreviewsWorkedOut, 0)
        await app.waitingPreviewsSettled()
        XCTAssertEqual(app.networkPreview, expected)
        XCTAssertEqual(app.networkOverlay, now.networkOverlay)
        XCTAssertEqual(app.buildPreviewsWorkedOut, 1, "worked out once, however often it was asked for")

        let building = try networkSession(waits: true)
        building.tapNetwork(at: PlanPoint(x: 2_048, y: 2_048), reach: 512)
        building.tapNetwork(at: PlanPoint(x: 14_336, y: 2_048), reach: 512)
        building.buildNetworkTrack()
        XCTAssertEqual(building.message?.kind, .success, building.message?.text ?? "")
        XCTAssertEqual(building.world.network.edges.count, 1, "✓ does not wait")
    }

    /// The tutorial's track step in the app: while the stretch drawn
    /// waits, the step keeps the answer it had (neither done early nor
    /// undone for a turn); then it is done as at once. Next, and the step
    /// moving on by itself, work it out at once, so a stretch redrawn too
    /// short does not move the step on.
    func testTheTutorialTrackStepWaitsWithoutChangingItsAnswer() async throws {
        func atTheTrackStep(waits: Bool) throws -> GameSession {
            let session = try networkSession(waits: waits)
            session.startTutorial()
            session.selectTool(.network)
            session.showNextTutorialStep()
            session.mapDidMove()
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.goal, .drawTrack)
            XCTAssertFalse(session.isTutorialStepDone)
            session.tapNetwork(at: PlanPoint(x: 2_048, y: 6_144), reach: 512)
            session.tapNetwork(at: PlanPoint(x: 14_336, y: 6_144), reach: 512)
            return session
        }
        let now = try atTheTrackStep(waits: false)
        XCTAssertTrue(now.isTutorialStepDone)
        XCTAssertTrue(now.tutorialAdvancesByItself)

        let app = try atTheTrackStep(waits: true)
        XCTAssertFalse(app.isTutorialStepDone, "as it was before the stretch was drawn")
        XCTAssertTrue(app.isWaiting(for: .networkDraft))
        XCTAssertFalse(app.tutorialAdvancesByItself)
        await app.waitingPreviewsSettled()
        XCTAssertTrue(app.isTutorialStepDone)
        XCTAssertTrue(app.tutorialAdvancesByItself)
        XCTAssertEqual(app.tutorialHint, now.tutorialHint)

        // Redrawn too short: done still while it waits, then not; moving
        // on by itself meanwhile works it out and stays.
        app.tapNetwork(at: PlanPoint(x: 3_072, y: 6_144), reach: 512)
        XCTAssertTrue(app.isTutorialStepDone, "kept for the turn the preview waits")
        XCTAssertTrue(app.isWaiting(for: .networkDraft))
        let index = try XCTUnwrap(app.tutorial?.index)
        app.showNextTutorialStep(from: index)
        XCTAssertEqual(app.tutorial?.index, index, "not moved on by a stretch too short")
        await app.waitingPreviewsSettled()
        XCTAssertFalse(app.isTutorialStepDone)

        // Next works the stretch out at once.
        let next = try atTheTrackStep(waits: true)
        XCTAssertNil(next.networkPreview)
        next.showNextTutorialStep()
        XCTAssertEqual(next.tutorial?.step.goal, .buildTrack, "Next does not wait")
    }

    /// The track card's double track waits, then is the one worked out at
    /// once; ✓ builds it without waiting.
    func testTheTrackCardWaitsButItsCheckDoesNot() async throws {
        func picked(waits: Bool) throws -> GameSession {
            var world = try makeWorld(width: 65_536, height: 16_384, balance: 100_000_000)
            let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
            let east = try world.buildTrackNode(at: WorldCoordinate(x: 33_024, y: 8_192))
            let edge = try world.buildTrackEdge(from: west, to: east)
            let session = GameSession(world: world, language: .english)
            session.worksOutPreviewsOnTheNextTurn = waits
            session.selectTool(.select)
            session.tapMap(at: PlanPoint(x: 17_024, y: 8_192), reach: 16)
            XCTAssertEqual(session.selectedTrackEdge, edge)
            session.beginTrackUpgrade(.doubleTrack)
            return session
        }
        let now = try picked(waits: false)
        let expected = try XCTUnwrap(now.trackUpgradePreview)
        XCTAssertNil(expected.problem, expected.problem ?? "")

        let app = try picked(waits: true)
        XCTAssertNil(app.trackUpgradePreview)
        XCTAssertTrue(app.isWaiting(for: .trackUpgrade))
        await app.waitingPreviewsSettled()
        XCTAssertEqual(app.trackUpgradePreview, expected)

        let building = try picked(waits: true)
        let edges = building.world.network.edges.count
        building.buildTrackUpgrade()
        XCTAssertEqual(building.message?.kind, .success, building.message?.text ?? "")
        XCTAssertGreaterThan(building.world.network.edges.count, edges, "✓ does not wait")
    }

    /// The platform tool's station layout and the crossovers of a platform
    /// on both tracks wait, then are those worked out at once.
    func testThePlatformPreviewsComeOnTheNextTurn() async throws {
        func platforms(double: Bool, layout: StationLayout, waits: Bool) throws -> GameSession {
            let session = GameSession(world: try makeWorld(width: 40_960, height: 20_480, balance: 100_000_000), language: .english)
            session.selectTool(.network)
            session.networkBuildsDouble = double
            session.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
            session.tapNetwork(at: PlanPoint(x: 34_816, y: 10_240), reach: 16)
            session.buildNetworkTrack()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
            session.setNetworkMode(.platform)
            session.platformCars = 4
            session.worksOutPreviewsOnTheNextTurn = waits
            session.stationLayout = layout
            session.tapNetwork(at: PlanPoint(x: 18_432, y: 10_240), reach: 64)
            return session
        }
        let laidNow = try platforms(double: false, layout: .singleIsland, waits: false)
        let layout = try XCTUnwrap(laidNow.networkStationLayoutPreview)
        let laid = try platforms(double: false, layout: .singleIsland, waits: true)
        XCTAssertNil(laid.networkStationLayoutPreview)
        XCTAssertTrue(laid.isWaiting(for: .stationLayout))
        await laid.waitingPreviewsSettled()
        XCTAssertEqual(laid.networkStationLayoutPreview, layout)

        let besideNow = try platforms(double: true, layout: StationLayout.allCases.first { !$0.isLaidByLayout }!, waits: false)
        let crossovers = besideNow.networkPlatformCrossovers
        XCTAssertNotNil(besideNow.networkPlatformBeside)
        let beside = try platforms(double: true, layout: StationLayout.allCases.first { !$0.isLaidByLayout }!, waits: true)
        XCTAssertEqual(beside.networkPlatformCrossovers, [])
        XCTAssertEqual(beside.isWaiting(for: .platformCrossovers), besideNow.networkPlatformBeside != nil)
        await beside.waitingPreviewsSettled()
        XCTAssertEqual(beside.networkPlatformCrossovers, crossovers)
        XCTAssertEqual(beside.networkOverlay, besideNow.networkOverlay)
    }

    #if os(Linux)
    /// The main-thread stack the map's ✓ takes while the screen asks for
    /// it: the line's price tried at once took about 140 KB of an
    /// optimised build's stack, on top of SwiftUI's view update; here,
    /// unoptimised, about 270 KB at once and 32 KB waiting (16 KB of it
    /// the probe's own margin).
    func testTheMapCheckTakesLittleStackWhileTheScreenAsks() throws {
        let now = try session(waits: false)
        let atOnce = StackProbe.deepest { _ = now.mapLineDraft }
        let app = try session(waits: true)
        let waiting = StackProbe.deepest { _ = app.mapLineDraft }
        print("[WaitingPreviewTests] map check stack: at once \(atOnce / 1_024) KB, waiting \(waiting / 1_024) KB")
        XCTAssertGreaterThan(atOnce, 128 * 1_024, "the probe sees the work tried at once")
        XCTAssertLessThan(waiting, 48 * 1_024)
    }

    /// Decision 590, 114.1: the stack the map's overlay of the network
    /// tool takes while the screen asks for it, a stretch drawn, a
    /// station layout picked and the track card's double track.
    func testTheNetworkPreviewsTakeLittleStackWhileTheScreenAsks() throws {
        func drawn(waits: Bool) throws -> GameSession {
            let session = try networkSession(waits: waits)
            session.tapNetwork(at: PlanPoint(x: 2_048, y: 2_048), reach: 512)
            session.tapNetwork(at: PlanPoint(x: 14_336, y: 2_048), reach: 512)
            return session
        }
        let now = try drawn(waits: false)
        let atOnce = StackProbe.deepest { _ = now.networkOverlay }
        let app = try drawn(waits: true)
        let waiting = StackProbe.deepest { _ = app.networkOverlay }
        print("[WaitingPreviewTests] network overlay stack: at once \(atOnce / 1_024) KB, waiting \(waiting / 1_024) KB")
        // Since the world keeps its state on the heap (decision 590,
        // step 2) the overlay tried at once takes about 86 KB here, no
        // longer over 128 KB: the probe is checked against the waiting
        // call, as the map's check is.
        XCTAssertGreaterThan(atOnce, waiting + 32 * 1_024, "the probe sees the work tried at once")
        XCTAssertLessThan(waiting, 48 * 1_024)
    }
    #endif
}

#if os(Linux)
/// How deep a call goes into this thread's stack: the stack below the
/// caller is filled with a pattern first, and the lowest word the call
/// changed is its deepest point. Linux's main thread grows its stack on
/// demand up to its limit (8 MB), well past what is filled here.
enum StackProbe {
    private static let pattern: UInt64 = 0x5EED_F00D_CAFE_D00D
    private static let filled = 2 << 20
    /// Left alone right below the caller, for the filling itself.
    private static let margin = 16 << 10

    @inline(never)
    static func deepest(_ call: () -> Void) -> Int {
        var anchor = 0
        let top = withUnsafeMutablePointer(to: &anchor) { UInt(bitPattern: $0) } & ~UInt(7)
        let low = top - UInt(filled)
        let words = (filled - margin) / 8
        let start = UnsafeMutablePointer<UInt64>(bitPattern: low)!
        start.initialize(repeating: pattern, count: words)
        call()
        var index = 0
        while index < words, start[index] == pattern { index += 1 }
        return filled - index * 8
    }
}
#endif
