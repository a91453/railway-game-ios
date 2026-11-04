import GameCore
@testable import GamePresentation
import XCTest

/// Taiwan's named festivals on the map and in the player's words (decision 576).
final class FestivalTextTests: XCTestCase {
    func testTheCatalogsPlacesAreSightsAndOnlyThoseOnTheMap() throws {
        let taipei = RealWorldPlace.standard.anchor
        let bounds = WorldBounds.standard
        let sites = FestivalCatalog.sites(in: RealWorldFrame(anchor: taipei, bounds: bounds), bounds: bounds)
        XCTAssertTrue(sites.contains { $0.kind == .newYearsEve })
        XCTAssertFalse(sites.contains { $0.kind == .mazuProcession }, "Dajia is 100 km from Taipei")
        let paris = try XCTUnwrap(RealWorldPlace.all.first { $0.id == "paris" }).anchor
        XCTAssertTrue(FestivalCatalog.sites(in: RealWorldFrame(anchor: paris, bounds: bounds), bounds: bounds).isEmpty)
    }

    func testEveryFestivalHasBothLanguagesAndTheHoursOnlyWhenNotAllDay() {
        for kind in FestivalKind.allCases {
            XCTAssertFalse(kind.title(in: .english).isEmpty)
            XCTAssertFalse(kind.title(in: .traditionalChinese).isEmpty)
            XCTAssertEqual(kind.hoursText(in: .english).isEmpty, kind.hours == 0..<24)
        }
        XCTAssertTrue(FestivalKind.newYearsEve.hoursText(in: .english).contains("20:00 to 24:00"))
    }
}
