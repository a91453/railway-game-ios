import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 649: the lines for sale nearest the land owned first, and
/// those the land does not reach greyed out with how far they are.
@MainActor
final class RealLineListingTests: XCTestCase {
    private func game(at latitude: Double, _ longitude: Double) throws -> GameSession {
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude))
        let world = GameLauncher.newWorld(at: anchor, options: NewGameOptions(), data: GameLauncher.NewWorldData(
            population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights
        ))
        XCTAssertNotNil(world.mapExpansion, "bought tile by tile")
        let session = GameSession(world: world, language: .traditionalChinese)
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.heights = data.heights
        session.coverage = data.coverage
        session.railways = data.railways
        return session
    }

    func testKaohsiungListsItsLightRailFirstAndBuyable() async throws {
        let session = try game(at: 22.6273, 120.3014)
        let listings = session.realLineListings
        XCTAssertGreaterThan(listings.count, 3)
        XCTAssertEqual(listings.map(\.metres), listings.map(\.metres).sorted(), "nearest first")
        let first = try XCTUnwrap(listings.first)
        XCTAssertEqual(first.line.network, "C", "the Circular Light Rail, \(listings.prefix(3).map(\.line.id))")
        XCTAssertTrue(listings.contains { $0.line.system == "tra_sched" })
        session.refreshRealLineAvailability()
        await session.realLineAvailabilityChecked()
        let after = session.realLineListings
        XCTAssertNil(after.first?.note, "buyable from the land owned")
        let far = try XCTUnwrap(after.last)
        XCTAssertNotNil(far.note, far.line.id)
        XCTAssertTrue(far.note?.text(in: .traditionalChinese).contains("公里") ?? false)
        XCTAssertTrue(far.note?.text(in: .english).contains("km") ?? false)
    }

    func testTaipeiGreysOutTheLinesItsLandDoesNotReach() async throws {
        let session = try game(at: 25.047882, 121.517219)
        let sorted = session.realLineListings
        XCTAssertEqual(sorted.map(\.metres), sorted.map(\.metres).sorted())
        session.refreshRealLineAvailability()
        await session.realLineAvailabilityChecked()
        let listings = session.realLineListings
        let jiji = try XCTUnwrap(listings.first { $0.line.network == "JIJI" })
        XCTAssertFalse(jiji.isBuyable)
        // The same answer as the purchase card's.
        XCTAssertEqual(session.realLineOffer(for: jiji.line).problem, GameSession.landProblem(in: .traditionalChinese))
        for listing in listings.filter(\.isBuyable).prefix(1) {
            XCTAssertNotEqual(session.realLineOffer(for: listing.line).problem, GameSession.landProblem(in: .traditionalChinese), listing.line.id)
        }
        XCTAssertLessThan(try XCTUnwrap(listings.firstIndex { $0.isBuyable } ?? 0), try XCTUnwrap(listings.firstIndex { !$0.isBuyable }),
                          "the buyable ones come first here")
    }
}
