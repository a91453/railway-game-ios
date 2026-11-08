import Foundation
@testable import GamePresentation
import XCTest

/// Review L14-9: the OpenStreetMap credit lists what the game takes from it,
/// and the 3D map's real station buildings (decision 625) are drawn from OSM
/// building outlines, so the list names them in both languages.
final class DataSourceCreditsOSMUseTests: XCTestCase {
    func testTheOSMCreditNamesTheRealStationBuildings() throws {
        let said: [(DisplayLanguage, String)] = [(.english, "real station buildings"), (.traditionalChinese, "真實車站站房")]
        for (language, phrase) in said {
            let credit = try XCTUnwrap(DataSourceCredits.sections(in: language).flatMap(\.credits).first { $0.id == "openStreetMap" })
            XCTAssertTrue(credit.detail.contains(phrase), "\(language): \(credit.detail)")
        }
    }
}
