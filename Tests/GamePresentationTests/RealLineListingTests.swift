import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 649: the lines for sale nearest the land owned first, and
/// those the land does not reach greyed out with how far they are.
@MainActor
final class RealLineListingTests: XCTestCase {
    private func game(at latitude: Double, _ longitude: Double) throws -> GameSession {
        let data = RealWorldData.load(pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
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

    /// Review L14-5: with the panel open, the map expanded is checked again
    /// at once, not only when the panel is opened again; with it closed,
    /// nothing is worked out.
    func testTheListShowingIsCheckedAgainWhenTheLandGrows() async throws {
        let session = try game(at: 22.6273, 120.3014)
        session.showRealLineList(true)
        await session.realLineAvailabilityChecked()
        let checked = try XCTUnwrap(session.realLineAvailabilityKey)
        let owned = try XCTUnwrap(session.world.mapExpansion?.owned)
        let tile = try XCTUnwrap(session.world.mapTilesForSale().sorted().first)
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) -> String in
            world.setUnlimitedFunds(true)
            try world.buyMapTile(tile, passingMilestone: true)
            return ""
        })
        XCTAssertEqual(session.world.mapExpansion?.owned.count, owned.count + 1)
        XCTAssertNotEqual(session.realLineAvailabilityKey, checked, "checked again on the land bought")
        XCTAssertEqual(session.realLineCheckedLand, session.world.mapExpansion?.owned)
        await session.realLineAvailabilityChecked()
        XCTAssertNil(session.realLineAvailabilityTask)

        // Closed, a tile bought is checked only once the panel opens.
        session.showRealLineList(false)
        let closed = session.realLineAvailabilityKey
        let next = try XCTUnwrap(session.world.mapTilesForSale().sorted().first)
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) -> String in
            world.setUnlimitedFunds(true)
            try world.buyMapTile(next, passingMilestone: true)
            return ""
        })
        XCTAssertEqual(session.realLineAvailabilityKey, closed)
        session.showRealLineList(true)
        XCTAssertNotEqual(session.realLineAvailabilityKey, closed)
        await session.realLineAvailabilityChecked()
    }

    /// Review L14-4: the list's land check stops before the tiles the track
    /// reaches between its samples (32 m apart) are added; each of those
    /// touches a tile the check already has, so the purchase never refuses
    /// a line the list offers for its land. Every buyable line in the list
    /// round Kaohsiung and Taipei, bought in full.
    func testNoLineTheListOffersIsRefusedForItsLand() async throws {
        for (latitude, longitude) in [(22.6273, 120.3014), (25.047882, 121.517219)] {
            let session = try game(at: latitude, longitude)
            session.refreshRealLineAvailability()
            await session.realLineAvailabilityChecked()
            let buyable = session.realLineListings.filter(\.isBuyable)
            XCTAssertFalse(buyable.isEmpty)
            for listing in buyable {
                XCTAssertNotEqual(session.realLineOffer(for: listing.line).problem, GameSession.landProblem(in: .traditionalChinese), listing.line.id)
            }
        }
    }
}
