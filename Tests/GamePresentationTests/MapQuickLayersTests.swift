import GameCore
@testable import GamePresentation
import XCTest

/// Decision 224: the map's quick layer strip (5B) and the station master's
/// title (6C).
final class MapQuickLayersTests: XCTestCase {
    func testEachButtonTurnsItsOwnLayerTheOtherWay() {
        let layers = MapLayerPreferences.default
        for layer in MapQuickLayer.allCases {
            let turned = layer.toggled(layers)
            XCTAssertNotEqual(layer.isOn(in: turned), layer.isOn(in: layers), "\(layer)")
            XCTAssertEqual(layer.toggled(turned), layers, "two taps leave \(layer) as it was")
        }
    }

    func testLoadAndPeopleAreShownOneAtATimeAsInTheLayerList() {
        var layers = MapQuickLayer.passengerLoad.toggled(.default)
        XCTAssertEqual(layers.popTravelMode, .sectionFlow)
        layers = MapQuickLayer.population.toggled(layers)
        XCTAssertEqual(layers.popTravelMode, .population)
        XCTAssertFalse(MapQuickLayer.passengerLoad.isOn(in: layers))
        layers = MapQuickLayer.population.toggled(layers)
        XCTAssertNil(layers.popTravelMode)
    }

    func testTheButtonsNames() {
        XCTAssertEqual(MapQuickLayer.allCases.map { $0.title(in: .traditionalChinese) }, ["站名", "候車", "載客量", "人口"])
    }

    func testTheTitleAndHowFarToTheNext() {
        let world = DemoWorld.make(in: .english)
        let rank = CompanyRank(world: world)
        let title = StationMasterTitle(rank: rank)
        XCTAssertEqual(title.title, rank.title)
        XCTAssertTrue((0...1).contains(title.progress))
        if let next = rank.title.next {
            let expected = Double(rank.score - rank.title.minimumScore) / Double(next.minimumScore - rank.title.minimumScore)
            XCTAssertEqual(title.progress, expected, accuracy: 1e-9)
        }
        XCTAssertTrue(StationMasterTitle.isShown(in: world) == (world.scenario == nil))
    }
}
