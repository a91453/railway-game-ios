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
