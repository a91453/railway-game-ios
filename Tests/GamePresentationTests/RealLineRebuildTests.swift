import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 605 (third part): a Taoyuan Airport MRT bought as it was before
/// its expresses and Chang Gung's loops came is offered the rebuild from
/// its panel, and told what stops it where it cannot be done.
@MainActor
final class RealLineRebuildTests: XCTestCase {
    static let id = "tymc:A"

    /// The line bought from the timetable as it was before decision 605:
    /// every train stopping everywhere, two tracks at Chang Gung.
    static func boughtAsBefore() throws -> (session: GameSession, line: LineID) {
        let session = try RealLineAcquisitionTests.game(round: id, side: 1 << 22, heights: true)
        let current = try XCTUnwrap(session.railways)
        var before = current
        before.metroRuns[id] = try XCTUnwrap(current.metroRuns[id]).stoppingEverywhere()
        session.railways = before
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, "on sale")
        let offer = session.realLineOffer(for: line)
        XCTAssertTrue(session.acquireRealLine(offer), offer.problem ?? session.message?.text ?? "")
        session.railways = current
        let bought = try XCTUnwrap(session.world.acquisition(of: id)?.line)
        XCTAssertFalse(try XCTUnwrap(session.world.line(id: bought)).runs.contains { !$0.passes.isEmpty })
        return (session, bought)
    }

    /// Laid before decision 605, Chang Gung's track is level only along
    /// its platforms (112 m) and climbs at some 25 to 38‰ beyond them,
    /// steeper than a turnout may stand on (decision 233), up to the
    /// turn-back crossovers: the card names the station and what stops it,
    /// and the button changes nothing. Laying the station's stretch again
    /// level, as the purchase lays it, is decision 605's next step.
    func testALineBoughtBeforeSaysWhatStopsTheRebuild() throws {
        let (session, id) = try Self.boughtAsBefore()
        let station = try XCTUnwrap(session.world.line(id: id)?.stops.first { session.world.station(id: $0)?.name == "長庚醫院站" })
        XCTAssertEqual(session.world.network.platforms(of: station).count, 2)

        session.selectLine(id)
        XCTAssertTrue(session.rebuildsAsReal(id))
        let offer = try XCTUnwrap(session.selectedLineRealRebuildOffer)
        XCTAssertNil(offer.rebuild)
        let problem = try XCTUnwrap(offer.problem)
        XCTAssertTrue(problem.hasPrefix("長庚醫院站改建不了："), problem)
        XCTAssertTrue(problem.contains("坡度"), problem)
        XCTAssertEqual(offer.summaryText(in: session.language), problem)
        XCTAssertFalse(offer.canRebuild(balance: session.world.economy.balance))
        XCTAssertEqual(RealLineRebuildOffer.buttonTitle(in: .traditionalChinese), "照真實改建")

        let before = session.world
        XCTAssertFalse(session.rebuildRealLine(offer))
        XCTAssertEqual(session.message?.text, problem)
        XCTAssertEqual(session.world.economy.balance, before.economy.balance)
        XCTAssertEqual(session.world.network.platforms(of: station).count, 2)
    }

    /// While the line's trains run, the card says to wait for the last.
    func testItWaitsForTheLastTrain() throws {
        // Midnight: the day's last trains still out.
        let (session, id) = try Self.boughtAsBefore()
        session.selectLine(id)
        let offer = try XCTUnwrap(session.selectedLineRealRebuildOffer)
        XCTAssertTrue(offer.waitsForTheLastTrain)
        XCTAssertFalse(offer.canRebuild(balance: session.world.economy.balance))
        XCTAssertFalse(session.rebuildRealLine(offer))
    }

    /// A line bought now has its loops: nothing to rebuild.
    func testALineBoughtNowHasNothingToRebuild() throws {
        let session = try RealLineAcquisitionTests.game(round: Self.id, side: 1 << 22, heights: true)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id }, "on sale")
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        let id = try XCTUnwrap(session.world.acquisition(of: Self.id)?.line)
        XCTAssertNil(session.realRebuildOffer(for: id))
    }
}
