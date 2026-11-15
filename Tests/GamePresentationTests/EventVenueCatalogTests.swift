import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 768: the venues of Taiwan and Hong Kong, as the tool found them
/// on OpenStreetMap.
final class EventVenueCatalogTests: XCTestCase {
    func testTheCatalogIsTheToolsFile() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/event-venues/event_venues.json")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let rows = try XCTUnwrap(object["venues"] as? [[String: Any]])
        XCTAssertEqual(rows.count, EventVenueCatalog.venues.count)
        for (row, venue) in zip(rows, EventVenueCatalog.venues) {
            XCTAssertEqual(row["id"] as? String, venue.id)
            XCTAssertEqual(row["name"] as? String, venue.name, venue.id)
            XCTAssertEqual(row["englishName"] as? String, venue.englishName, venue.id)
            XCTAssertEqual(row["kind"] as? String, venue.kind.rawValue, venue.id)
            XCTAssertEqual((row["seats"] as? Int).map(Int64.init), venue.seats, venue.id)
            XCTAssertEqual(try XCTUnwrap(row["lat"] as? Double), venue.latitude, accuracy: 1e-9, venue.id)
            XCTAssertEqual(try XCTUnwrap(row["lon"] as? Double), venue.longitude, accuracy: 1e-9, venue.id)
        }
        XCTAssertEqual(Set(EventVenueCatalog.venues.map(\.id)).count, EventVenueCatalog.venues.count)
    }

    /// A map round Taipei Arena holds it and the Taipei Dome; one of
    /// Kaohsiung none of Taipei's.
    func testAMapHoldsTheVenuesInsideIt() throws {
        let bounds = GameWorld.newGameBounds
        func ids(_ latitude: Double, _ longitude: Double) throws -> Set<String> {
            let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude))
            return Set(EventVenueCatalog.venues(in: RealWorldFrame(anchor: anchor, bounds: bounds), bounds: bounds).map(\.id))
        }
        let taipei = try ids(25.0505, 121.5507)
        XCTAssertTrue(taipei.isSuperset(of: ["tw01", "tw02", "tw03"]), "\(taipei)")
        XCTAssertFalse(taipei.contains("tw19"))
        XCTAssertTrue(try ids(22.67, 120.30).contains("tw19"))
    }

    /// The station panel names the venue.
    func testTheEventNamesItsVenue() throws {
        XCTAssertEqual(EventVenueCatalog.venue("tw02")?.title(in: .traditionalChinese), "臺北小巨蛋")
        XCTAssertEqual(EventVenueCatalog.venue("hk03")?.title(in: .english), "Hong Kong Coliseum")
        XCTAssertNil(EventVenueCatalog.venue("nowhere"))
    }
}
