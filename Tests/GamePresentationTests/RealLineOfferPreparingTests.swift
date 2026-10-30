@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 497: a real line's purchase card opens at once, saying it is
/// being prepared, while the offer is laid out off the main actor; an
/// offer laid out on a world a command has changed since is laid out again.
@MainActor
final class RealLineOfferPreparingTests: XCTestCase {
    private func pingxi(in session: GameSession) throws -> RealBranchLine {
        try XCTUnwrap(session.buyableRealLines.first { $0.network == "PINGXI" }, "the Pingxi Line on sale")
    }

    /// The tap opens the card at once, the offer not yet laid out (some
    /// 0.4 s for the Pingxi Line from Taipei, up to 2 s on a real map of 64
    /// stations, all of it on the main actor before); the offer that then
    /// shows is the one laid out on the main actor.
    func testTheCardOpensAtOnceAndShowsTheOfferLaidOutOffTheMainActor() async throws {
        let session = try RealLineAcquisitionTests.game(round: "PINGXI")
        let line = try pingxi(in: session)

        session.offerRealLine(line)
        XCTAssertNil(session.shownRealLineOffer, "not laid out on the main actor")
        XCTAssertEqual(session.preparingRealLine, line)

        await session.realLineOfferPrepared()
        let offer = try XCTUnwrap(session.shownRealLineOffer)
        XCTAssertNil(session.preparingRealLine)
        let onTheMainActor = session.realLineOffer(for: line)
        XCTAssertNil(offer.problem, offer.problem ?? "")
        XCTAssertEqual(offer.acquisition, onTheMainActor.acquisition)
        XCTAssertEqual(offer.price, onTheMainActor.price)
    }

    /// A command while the offer is laid out (here a station named Shifen
    /// beside the real one, which the line then joins): the offer laid out
    /// before it is dropped and the line laid out again on the world as it
    /// is now.
    func testAnOfferLaidOutBeforeACommandIsLaidOutAgain() async throws {
        let session = try RealLineAcquisitionTests.game(round: "PINGXI")
        let line = try pingxi(in: session)
        let before = try XCTUnwrap(session.realLineOffer(for: line).acquisition)
        XCTAssertEqual(before.stops.compactMap(\.existing), [], "no station of the company's along the line yet")

        session.offerRealLine(line)
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        let shifen = try BundledRealData.station("十分", in: "tra_sched").coordinate
        let at = frame.worldPosition(latitude: shifen.latitude, longitude: shifen.longitude)
        let built = try session.performEdit { try $0.buildStation(named: "十分", at: PlanPoint(x: Int64(at.x), y: Int64(at.y))).id }

        await session.realLineOfferPrepared()
        let offer = try XCTUnwrap(session.shownRealLineOffer?.acquisition, session.shownRealLineOffer?.problem ?? "")
        XCTAssertEqual(offer.stops.compactMap(\.existing), [built], "laid out on the world with the new station")
        XCTAssertEqual(offer, session.realLineOffer(for: line).acquisition)
    }

    /// Closing the card while the offer is laid out drops it.
    func testClosingTheCardDropsTheOfferBeingLaidOut() async throws {
        let session = try RealLineAcquisitionTests.game(round: "PINGXI")
        let line = try pingxi(in: session)
        session.offerRealLine(line)
        let task = try XCTUnwrap(session.realLineOfferTask)
        session.closeRealLineOffer()
        XCTAssertNil(session.preparingRealLine)
        await task.value
        XCTAssertNil(session.shownRealLineOffer)
        XCTAssertNil(session.preparingRealLine)
    }
}
