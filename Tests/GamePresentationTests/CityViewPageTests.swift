import Foundation
@testable import GamePresentation
import XCTest

/// The 3D city view on the game's website (decision 163): each area's page,
/// and which links stay in the web view.
final class CityViewPageTests: XCTestCase {
    func testEachAreaOpensTheWebsitesPageOnTheLightView() {
        XCTAssertEqual(CityViewArea.allCases, [.kaohsiung, .taichung])
        for area in CityViewArea.allCases {
            XCTAssertEqual(
                area.pageAddress,
                "https://www.alongthelinegame.com/city/?area=\(area.rawValue)&radius=400&clouds=0&birds=0&traffic=0"
            )
            let url = URL(string: area.pageAddress)
            XCTAssertNotNil(url)
            XCTAssertTrue(url.map(CityViewPage.opensInView) ?? false, area.rawValue)
        }
    }

    func testTheCityViewsOwnPagesStayInTheView() {
        for address in [
            "https://www.alongthelinegame.com/city/",
            "https://www.alongthelinegame.com/city",
            "https://www.alongthelinegame.com/city/index.html?area=taichung",
            "about:blank",
        ] {
            XCTAssertTrue(CityViewPage.opensInView(URL(string: address)!), address)
        }
    }

    func testEveryOtherLinkGoesToTheBrowser() {
        for address in [
            "https://www.alongthelinegame.com",
            "https://www.alongthelinegame.com/",
            "https://www.alongthelinegame.com/credits",
            "https://www.alongthelinegame.com/cityscape",
            "http://www.alongthelinegame.com/city/",
            "https://alongthelinegame.com/city/",
            "https://www.alongthelinegame.com.example.net/city/",
            "https://www.openstreetmap.org/copyright",
        ] {
            XCTAssertFalse(CityViewPage.opensInView(URL(string: address)!), address)
        }
    }
}
