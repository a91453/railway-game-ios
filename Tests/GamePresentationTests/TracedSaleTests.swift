import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 468, later: a trace along a real line for sale says the line
/// can be bought as it is, for how much, and opens its purchase card.
@MainActor
final class TracedSaleTests: XCTestCase {
    private let reach: Int64 = 24 * WorldCoordinate.unitsPerMetre
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    // MARK: - Which trace runs along a line for sale

    private let line = RealBranchLine(network: "TEST", english: "Test Line", chinese: "測試線", stops: ["甲", "乙", "丙"])

    /// The line for sale, its way 2 km east from the origin, in metres.
    private var sale: SaleLineWay {
        SaleLineWay(line: line, pieces: [
            SaleLineWay.Piece(WorldPath([WorldVector(x: 0, y: 0), WorldVector(x: 1_000 * metre, y: 0)])),
            SaleLineWay.Piece(WorldPath([WorldVector(x: 1_000 * metre, y: 0), WorldVector(x: 2_000 * metre, y: 0)])),
        ])
    }

    private func way(_ points: [(Double, Double)]) -> WorldPath {
        WorldPath(points.map { WorldVector(x: $0.0 * metre, y: $0.1 * metre) })
    }

    func testATraceAlongTheLineRunsAlongIt() {
        // From one station's stretch into the next, 5 m off its centre.
        XCTAssertEqual(TracedSale.line(along: way([(600, 5), (1_400, 5)]), ways: [sale]), line)
        // A short trace, all along it.
        XCTAssertEqual(TracedSale.line(along: way([(100, 0), (250, 0)]), ways: [sale]), line)
    }

    func testATraceAcrossTheLineOrPastItsEndOrBesideItDoesNot() {
        // Across it.
        XCTAssertNil(TracedSale.line(along: way([(500, -1_000), (500, 1_000)]), ways: [sale]))
        // Along the main line it leaves, past its first station.
        XCTAssertNil(TracedSale.line(along: way([(-2_000, 0), (0, 0), (-80, 1_000)]), ways: [sale]))
        // Beside it, 40 m off: another line.
        XCTAssertNil(TracedSale.line(along: way([(200, 40), (1_800, 40)]), ways: [sale]))
        // Half along it, then away: too little of a long trace.
        XCTAssertNil(TracedSale.line(along: way([(1_850, 0), (2_000, 0), (2_000, 3_000)]), ways: [sale]))
    }

    func testOfTwoLinesTheOneItFollowsLongerIsTaken() {
        let other = RealBranchLine(network: "OTHER", english: "Other Line", chinese: "另一線", stops: ["丙", "丁"])
        let beside = SaleLineWay(line: other, pieces: [
            SaleLineWay.Piece(WorldPath([WorldVector(x: 1_500 * metre, y: 0), WorldVector(x: 4_000 * metre, y: 0)])),
        ])
        XCTAssertEqual(TracedSale.line(along: way([(1_700, 0), (3_500, 0)]), ways: [sale, beside]), other)
        XCTAssertEqual(TracedSale.line(along: way([(100, 0), (1_800, 0)]), ways: [beside, sale]), line)
    }

    // MARK: - What it says

    private func offer(total: Money?, problem: String? = nil) -> RealLineOffer {
        RealLineOffer(
            line: line, acquisition: nil,
            price: total.map { RealLineAcquisitionPrice(land: .zero, building: $0, trains: .zero, riders: .zero) },
            problem: problem
        )
    }

    func testTheHintGivesThePriceOnceKnownAndWhatTheCompanyLacks() throws {
        let price = Money(80_000_000)
        let waiting = try XCTUnwrap(TracedSale.hint(line, quote: nil, balance: .zero, in: .traditionalChinese))
        XCTAssertNil(waiting.price)
        XCTAssertNil(waiting.shortfall)
        XCTAssertEqual(waiting.text, "測試線可以直接收購，含列車與真實班表。")

        let rich = try XCTUnwrap(TracedSale.hint(line, quote: offer(total: price), balance: Money(100_000_000), in: .traditionalChinese))
        XCTAssertEqual(rich.price, price)
        XCTAssertEqual(rich.text, "測試線可以直接收購（\(price.moneyText)，含列車與真實班表）。")
        XCTAssertNil(rich.shortfall)

        let poor = try XCTUnwrap(TracedSale.hint(line, quote: offer(total: price), balance: Money(30_000_000), in: .english))
        XCTAssertEqual(poor.text, "You can buy the Test Line as it is (\(price.moneyText), with its trains and real timetable).")
        XCTAssertEqual(poor.shortfall, "\(Money(50_000_000).moneyText) short of the price.")
        XCTAssertEqual(
            TracedSale.hint(line, quote: offer(total: price), balance: .zero, in: .traditionalChinese)?.shortfall,
            "還差 \(price.moneyText)。"
        )

        // Where the line cannot be bought here, nothing is said.
        XCTAssertNil(TracedSale.hint(line, quote: offer(total: nil, problem: "軌道擋住了"), balance: .zero, in: .traditionalChinese))
    }

    // MARK: - On a real-world map

    /// A real-world game at Zhuzhong, where the Liujia Line is for sale, tracing single track.
    private func zhuzhong(unlimited: Bool = false) throws -> GameSession {
        let junction = try BundledRealData.station("竹中", in: "tra_sched")
        // 1,000,000 in hand: less than a line costs.
        var world = GameWorld.newGame(anchor: try XCTUnwrap(junction.anchor), balance: Money(1_000_000))
        world.setUnlimitedFunds(unlimited)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        session.networkBuildsDouble = false
        session.networkDoubleChosen = true
        return session
    }

    private func point(_ name: String, in session: GameSession) throws -> PlanPoint {
        try BundledRealData.point(try BundledRealData.station(name, in: "tra_sched").coordinate, in: session.world)
    }

    func testATraceAlongALineForSaleOffersItAtItsPrice() async throws {
        let session = try zhuzhong()
        let liujia = try XCTUnwrap(session.buyableRealLines.first { $0.network == "LIUJIA" }, "\(session.buyableRealLines.map(\.network))")
        // From its junction, Zhuzhong, to Liujia.
        XCTAssertEqual(liujia.stops, ["竹中", "六家"])
        session.tapNetwork(at: try point("竹中", in: session), reach: reach)
        session.tapNetwork(at: try point("六家", in: session), reach: reach)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertEqual(preview.forSale, liujia)

        // At once, without its price; then with it.
        let waiting = try XCTUnwrap(session.tracedSaleHint)
        XCTAssertNil(waiting.price)
        await session.tracedSaleQuoted()
        let hint = try XCTUnwrap(session.tracedSaleHint)
        let expected = try XCTUnwrap(session.realLineOffer(for: liujia).price?.total)
        XCTAssertEqual(hint.price, expected)
        XCTAssertTrue(hint.text.contains(expected.moneyText), hint.text)

        // Short of cash, it says by how much.
        XCTAssertEqual(session.tracedSaleHint?.shortfall, "還差 \(Money(expected.amount - 1_000_000).moneyText)。")

        // The button opens the purchase card at once, with that offer; the
        // trace stays drawn.
        session.offerTracedSaleLine()
        XCTAssertEqual(session.shownRealLineOffer?.line, liujia)
        XCTAssertEqual(session.shownRealLineOffer?.price?.total, expected)
        XCTAssertNil(session.preparingRealLine)
        XCTAssertNotNil(session.networkPreview)
    }

    /// L2-5 (#1576's review): a price laid out for a world a command then
    /// changed is laid out again, so a paused game's hint gets one.
    func testAPriceLaidOutForAWorldThatChangedIsLaidOutAgain() async throws {
        let session = try zhuzhong()
        session.tapNetwork(at: try point("竹中", in: session), reach: reach)
        session.tapNetwork(at: try point("六家", in: session), reach: reach)
        XCTAssertNil(try XCTUnwrap(session.tracedSaleHint).price)
        // A command while the price is laid out: nothing the hint shows
        // changes, so nothing would ask for it again.
        session.setSpeed(.fast)
        XCTAssertNotNil(session.networkPreview?.forSale)
        await session.tracedSaleQuoted()
        let quote = try XCTUnwrap(session.tracedSaleQuote, "laid out again for the world as it is now")
        XCTAssertEqual(quote.revision, session.commandRevision)
        XCTAssertNotNil(session.tracedSaleHint?.price)
    }

    func testNoHintWithoutTracingOrOnceTheLineIsBought() async throws {
        let session = try zhuzhong(unlimited: true)
        let liujia = try XCTUnwrap(session.buyableRealLines.first { $0.network == "LIUJIA" })
        session.networkTracesRealRailway = false
        session.tapNetwork(at: try point("竹中", in: session), reach: reach)
        session.tapNetwork(at: try point("六家", in: session), reach: reach)
        XCTAssertNil(session.networkPreview?.forSale)
        XCTAssertNil(session.tracedSaleHint)

        session.clearNetworkDraft()
        session.networkTracesRealRailway = true
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: liujia)), session.message?.text ?? "")
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.tapNetwork(at: try point("竹中", in: session), reach: reach)
        session.tapNetwork(at: try point("六家", in: session), reach: reach)
        XCTAssertNil(session.networkPreview?.forSale)
    }
}
