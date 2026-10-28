@testable import GameCore
@testable import GamePresentation
import Observation
import XCTest

/// Decision 471 (UI health check K): the follow bar, the economy panel's
/// trend charts and its ledger no longer work everything out again at every
/// tick, and show the same as before.
@MainActor
final class TickRecomputeTests: XCTestCase {
    // MARK: - 2-19 The follow bar

    /// What the follow bar read of the session before decision 471: the
    /// frame asked for the followed train and the bar read the world.
    static func followBarReadsBefore(_ session: GameSession) {
        guard let train = session.followedTrain else { return }
        _ = session.world.followBarInfo(of: train.id, in: session.language)
        _ = session.world.trainCard(of: train.id, in: session.language)
        _ = session.world.clock
    }

    /// What the frame and the bar read now, but for the progress bar.
    static func followBarReads(_ session: GameSession) {
        _ = session.followBar
        _ = session.isLayingDemoRealLines
    }

    func testAFollowedTrainNoLongerRebuildsTheBarAtEveryTick() throws {
        let session = try Self.followingATrain()
        let before = ScreenFactsTests.lookAgain(over: 100, session) { Self.followBarReadsBefore(session) }
        let now = ScreenFactsTests.lookAgain(over: 100, session) { Self.followBarReads(session) }
        let progress = ScreenFactsTests.lookAgain(over: 100, session) { _ = session.followProgress }
        print("[follow-bar] of 100 ticks at 600×, the bar looked again: before \(before), now \(now); its progress bar \(progress)")
        XCTAssertEqual(before, 100, "before decision 471 every tick rebuilt the bar")
        XCTAssertLessThan(now, 50, "only when its status or times change")
        // What changed, each time it looked again.
        var changed: [String: Int] = [:]
        for _ in 0..<100 {
            let old = try XCTUnwrap(session.followBar)
            session.advance(realElapsed: GameSession.tickInterval)
            let new = try XCTUnwrap(session.followBar)
            if old.detail != new.detail { changed["detail", default: 0] += 1 }
            if old.trip?.statusText != new.trip?.statusText { changed["status", default: 0] += 1 }
            if old.trip?.departure != new.trip?.departure || old.trip?.arrival != new.trip?.arrival { changed["times", default: 0] += 1 }
            if (old.trip == nil) != (new.trip == nil) { changed["trip shown", default: 0] += 1 }
        }
        print("[follow-bar] what changed over 100 more ticks: \(changed.sorted { $0.key < $1.key })")
        XCTAssertGreaterThan(progress, 0, "the progress bar still moves")
    }

    /// The frame, with a train followed, looks again no more often than
    /// the bar (decision 367's `frameReads`).
    func testTheFrameNoLongerReadsTheFollowedTrain() throws {
        let session = try Self.followingATrain()
        let frame = ScreenFactsTests.lookAgain(over: 100, session) { ScreenFactsTests.frameReads(session) }
        let bar = ScreenFactsTests.lookAgain(over: 100, session) { Self.followBarReads(session) }
        XCTAssertLessThanOrEqual(frame, bar)
    }

    /// The bar's facts are what the world says afresh, after every tick,
    /// in both languages, and `nil` once following stops.
    func testTheFactsAreWhatTheWorldSays() throws {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let session = try Self.followingATrain(language: language)
            func check(_ step: String, line: UInt = #line) throws {
                let train = try XCTUnwrap(session.followedTrain, step, line: line)
                let card = session.world.trainCard(of: train.id, in: language)
                let info = session.world.followBarInfo(of: train.id, in: language)
                let facts = try XCTUnwrap(session.followBar, step, line: line)
                XCTAssertEqual(facts, FollowBarFacts(train: train.id, in: session.world, card: card, language: language), step, line: line)
                // What the bar showed before, read from the world.
                XCTAssertEqual(facts.name, train.name, step, line: line)
                XCTAssertEqual(facts.line, info?.line, step, line: line)
                XCTAssertEqual(facts.detail, info?.detail(in: language, times: card == nil), step, line: line)
                XCTAssertEqual(facts.trip?.departure, card?.departure.clockText, step, line: line)
                XCTAssertEqual(facts.trip?.arrival, card?.arrival.clockText, step, line: line)
                XCTAssertEqual(facts.trip?.statusText, card?.statusText(in: language), step, line: line)
                XCTAssertEqual(facts.runningSpeed, session.world.clock.isPaused ? nil : session.world.clock.speed, step, line: line)
                XCTAssertEqual(session.followProgress, card.map { ($0.progress * 1000).rounded() / 1000 } ?? 0, step, line: line)
                XCTAssertEqual(session.followProgress, card?.progress ?? 0, accuracy: 0.0005, step, line: line)
            }
            try check("following")
            var sawTrip = false
            for tick in 0..<300 {
                if tick == 100 { session.setSpeed(.x10) }
                if tick == 150 { session.togglePause() }
                if tick == 160 { session.togglePause() }
                session.advance(realElapsed: GameSession.tickInterval)
                try check("tick \(tick)")
                sawTrip = sawTrip || session.followBar?.trip != nil
            }
            XCTAssertTrue(sawTrip, "the train ran a trip")
            session.stopFollowingTrain()
            XCTAssertNil(session.followBar)
            XCTAssertEqual(session.followProgress, 0)
        }
    }

    /// A line's train followed at the opening speed (600×).
    static func followingATrain(language: DisplayLanguage = .english) throws -> GameSession {
        let metre = WorldCoordinate.unitsPerMetre
        let world = try newGameLine(through: (0..<4).map { PlanPoint(x: (1_000 + $0 * 1_500) * metre, y: 4_000 * metre) })
        let session = GameSession(world: world, language: language)
        session.setSpeed(.normal)
        // Until a train stands on the track.
        for _ in 0..<600 where session.world.trains.allSatisfy({ $0.position == nil }) {
            session.advance(realElapsed: GameSession.tickInterval)
        }
        let train = try XCTUnwrap(session.world.trains.first { $0.position != nil })
        session.followTrain(train.id)
        XCTAssertNotNil(session.followBar)
        return session
    }

    // MARK: - 3-21 The ledger

    func testALedgerRowKeepsItsIDAsNewerRowsComeInAbove() throws {
        let session = try Self.followingATrain()
        var world = session.world
        world.setEconomyMode(.management)
        try world.advance(ticks: 61)
        let first = world.recentLedgerRows()
        XCTAssertFalse(first.isEmpty)
        try world.advance(ticks: 60)
        let then = world.recentLedgerRows()
        XCTAssertGreaterThan(then.count, first.count)
        XCTAssertEqual(Array(then.suffix(first.count)), first, "the older rows, their IDs and entries, as they were")
        XCTAssertEqual(then.map(\.entry), world.recentLedgerEntries(), "the same rows as before, newest first")
        XCTAssertEqual(Set(then.map(\.id)).count, then.count)
    }

    /// Rows of the same moment and kind (several demolitions at once) get
    /// IDs of their own, which stay as rows are added and the oldest let go.
    func testRowsOfOneMomentAndKindAreTold() {
        var world = GameWorld.newGame()
        let time = GameTime(seconds: 3_600)
        func row(_ kind: LedgerEntry.Kind, at time: GameTime) -> LedgerEntry {
            LedgerEntry(kind: kind, time: time, amount: Money(-100), breakdown: [])
        }
        world.accounts.record(row(.hourlyNet, at: GameTime(seconds: 0)), day: 0)
        world.accounts.record(row(.buildingDemolition, at: time), day: 0)
        world.accounts.record(row(.buildingDemolition, at: time), day: 0)
        let rows = world.recentLedgerRows()
        XCTAssertEqual(rows.map(\.id.ordinal), [1, 0, 0])
        XCTAssertEqual(Set(rows.map(\.id)).count, 3)
        for hour in 2..<Int64(CompanyAccounts.keptEntries) {
            world.accounts.record(row(.hourlyNet, at: GameTime(seconds: hour * 3_600)), day: 0)
        }
        XCTAssertEqual(world.accounts.entries.count, CompanyAccounts.keptEntries, "the first row let go")
        let demolitions = world.recentLedgerRows(CompanyAccounts.keptEntries).filter { $0.entry.kind == .buildingDemolition }
        XCTAssertEqual(demolitions.map(\.id), rows.prefix(2).map(\.id))
    }

    // MARK: - 3-22 The trend charts

    /// The charts' source stays as it is over ticks that write no ledger
    /// row, and the history it makes is the one made from the world.
    func testTheTrendSourceChangesOnlyWithTheBooks() throws {
        let session = try Self.followingATrain()
        var world = session.world
        world.setEconomyMode(.management)
        try world.advance(ticks: 61)
        for range in FinanceTrendRange.allCases {
            var source = FinanceHistory.Source(range, world: world)
            XCTAssertEqual(source.history(), FinanceHistory.make(range, world: world))
            var changes = 0
            var copy = world
            // Four game hours, a tick a minute.
            for _ in 0..<240 {
                let books = copy.accounts.days
                try copy.advance(ticks: 1)
                let next = FinanceHistory.Source(range, world: copy)
                XCTAssertEqual(next.history(), FinanceHistory.make(range, world: copy))
                if next != source {
                    changes += 1
                    XCTAssertNotEqual(copy.accounts.days, books, "\(range): only when the books change")
                }
                source = next
            }
            if range == .allYears {
                XCTAssertEqual(changes, 0, "no year closed")
            } else {
                XCTAssertTrue((1...4).contains(changes), "\(range): \(changes) changes, once an hour, not at every tick")
            }
        }
    }
}
