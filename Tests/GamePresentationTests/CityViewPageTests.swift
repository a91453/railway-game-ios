import Foundation
@testable import GamePresentation
import XCTest

/// The 3D city view on the game's website (decision 163): each area's page,
/// and which links stay in the web view. The website is the brand's
/// (GameBrand); these tests use one of their own, and a neutral build has
/// none.
final class CityViewPageTests: XCTestCase {
    private let brand = GameBrand(english: "Test", chinese: "測試", saveExtension: "test", website: "www.railway.example")

    func testEachAreaOpensTheWebsitesPageOnTheLightView() {
        XCTAssertEqual(CityViewArea.allCases, [.kaohsiung, .taichung])
        for area in CityViewArea.allCases {
            XCTAssertEqual(
                area.pageAddress(of: brand),
                "https://www.railway.example/city/?area=\(area.rawValue)&radius=400&clouds=0&birds=0&traffic=0&app=1"
            )
            let url = area.pageAddress(of: brand).flatMap(URL.init(string:))
            XCTAssertNotNil(url)
            XCTAssertTrue(url.map { CityViewPage.opensInView($0, brand: brand) } ?? false, area.rawValue)
        }
    }

    func testTheWebsiteIsItsHomePage() {
        XCTAssertEqual(brand.home, "https://www.railway.example/")
        XCTAssertFalse(CityViewPage.opensInView(URL(string: brand.home!)!, brand: brand))
    }

    func testANeutralBuildHasNoWebsiteNorCityView() {
        XCTAssertNil(GameBrand.neutral.home)
        XCTAssertNil(CityViewPage.root(of: .neutral))
        for area in CityViewArea.allCases {
            XCTAssertNil(area.pageAddress(of: .neutral))
        }
        XCTAssertFalse(CityViewPage.opensInView(URL(string: "https://www.railway.example/city/")!, brand: .neutral))
        XCTAssertTrue(CityViewPage.opensInView(URL(string: "about:blank")!, brand: .neutral))
    }

    func testTheCityViewsOwnPagesStayInTheView() {
        for address in [
            "https://www.railway.example/city/",
            "https://www.railway.example/city",
            "https://www.railway.example/city/index.html?area=taichung",
            "about:blank",
        ] {
            XCTAssertTrue(CityViewPage.opensInView(URL(string: address)!, brand: brand), address)
        }
    }

    func testEveryOtherLinkGoesToTheBrowser() {
        for address in [
            "https://www.railway.example",
            "https://www.railway.example/",
            "https://www.railway.example/credits",
            "https://www.railway.example/cityscape",
            "http://www.railway.example/city/",
            "https://railway.example/city/",
            "https://www.railway.example.example.net/city/",
            "https://www.openstreetmap.org/copyright",
        ] {
            XCTAssertFalse(CityViewPage.opensInView(URL(string: address)!, brand: brand), address)
        }
    }
}
