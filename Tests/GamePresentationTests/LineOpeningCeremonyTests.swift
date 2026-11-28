import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1044: a bought line's opening ceremony (``LineOpening``,
/// ``GameSession/noteLineOpenings()``).
@MainActor
final class LineOpeningCeremonyTests: XCTestCase {
    /// Advances `session` a few minutes at a time until its ceremony shows,
    /// for at most `days` game days; the minutes it took.
    private func advanceToOpening(_ session: GameSession, days: Int = 2) -> Int {
        var minutes = 0
        while session.lineOpening == nil, minutes < days * 24 * 60 {
            session.advance(ticks: 5)
            minutes += 5
        }
        return minutes
    }

    /// The Pingxi Line bought: nothing while its purchase card is open;
    /// once it is closed, its first train out holds the ceremony once: the
    /// banner, the bugle call, a line in the news log that goes to the
    /// line, the map over the line.
    func testABoughtLinesFirstTrainOutHoldsItsCeremonyOnce() throws {
        let session = try RealLineAcquisitionTests.game(round: "PINGXI")
        var heard: [SoundCue] = []
        session.playSound = { heard.append($0) }
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.network == "PINGXI" }, "on sale")
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        let id = try XCTUnwrap(session.lastLineAcquired?.line)

        session.advance(ticks: 24 * 60)
        XCTAssertNil(session.lineOpening, "it waits for the purchase card")
        XCTAssertFalse(heard.contains(.lineOpened))

        session.lastLineAcquired = nil
        session.dismissTrainArrival(all: true)
        _ = advanceToOpening(session)
        let opening = try XCTUnwrap(session.lineOpening, "its first train went out within two days")
        XCTAssertEqual(opening.line, id)
        XCTAssertEqual(opening.title(in: .traditionalChinese), "\(opening.name)通車")
        XCTAssertFalse(opening.from.isEmpty)
        XCTAssertFalse(opening.to.isEmpty)
        XCTAssertEqual(heard.filter { $0 == .lineOpened }.count, 1)
        let items = session.news.items.filter { $0.category == .opening }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.target, .line(id.rawValue))
        XCTAssertEqual(items.first?.text(in: .traditionalChinese), "\(opening.name)通車：首班車從\(opening.from)開往\(opening.to)。")
        XCTAssertNotNil(session.cameraRequest?.region, "the map looks over the line")

        session.dismissLineOpening()
        XCTAssertNil(session.lineOpening)
        session.advance(ticks: 24 * 60)
        XCTAssertNil(session.lineOpening, "once only")
        XCTAssertEqual(session.news.items.count { $0.category == .opening }, 1)
        XCTAssertEqual(heard.filter { $0 == .lineOpened }.count, 1)
    }

    /// "Go" on the banner selects the line and closes the banner.
    func testGoOnTheBannerSelectsTheLine() throws {
        let session = try RealLineAcquisitionTests.game(round: "PINGXI")
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.network == "PINGXI" }, "on sale")
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        let id = try XCTUnwrap(session.lastLineAcquired?.line)
        session.lastLineAcquired = nil
        session.dismissTrainArrival(all: true)
        _ = advanceToOpening(session)
        XCTAssertNotNil(session.lineOpening)
        session.goToLineOpening()
        XCTAssertNil(session.lineOpening)
        XCTAssertEqual(session.selectedLineID, id)
    }

    /// A line removed before its first train went out waits no more.
    func testALineRemovedBeforeItOpensHasNoCeremony() throws {
        let session = try RealLineAcquisitionTests.game(round: "PINGXI")
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.network == "PINGXI" }, "on sale")
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        let id = try XCTUnwrap(session.lastLineAcquired?.line)
        session.lastLineAcquired = nil
        session.dismissTrainArrival(all: true)
        session.selectLine(id)
        session.removeSelectedLine()
        XCTAssertNil(session.world.line(id: id))
        session.advance(ticks: 2 * 24 * 60)
        XCTAssertNil(session.lineOpening)
        XCTAssertTrue(session.awaitingOpenings.isEmpty)
        XCTAssertEqual(session.news.items.count { $0.category == .opening }, 0)
    }
}
