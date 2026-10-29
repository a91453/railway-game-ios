import GameCore
import GamePresentation
import XCTest

/// Decision 477: the map's floating labels keep off the stations' names
/// and each other.
final class MapLabelPlacementTests: XCTestCase {
    private typealias Box = MapLabelPlacement.Box
    private static let radius = 8.0
    /// Decision 210's lift at full detail: over the waiting count's pill.
    private static let lift = radius + 30

    private func overlaps(_ a: Box, _ b: Box) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }

    /// The freight scene of the website's screenshots (freight-materials,
    /// run 40805756457): a cross of stations 79 points apart, the middle
    /// row and the south station short of materials.
    private let cross = [
        MapLabelPlacement.Station(x: 400, y: 121, name: "北站"),
        MapLabelPlacement.Station(x: 321, y: 200, name: "西站"),
        MapLabelPlacement.Station(x: 400, y: 200, name: "中央"),
        MapLabelPlacement.Station(x: 479, y: 200, name: "東站"),
        MapLabelPlacement.Station(x: 400, y: 279, name: "南站"),
    ]

    private func bubbleBox(_ bubble: MapLabelPlacement.Bubble, at point: ScreenPoint) -> Box {
        Box(x: point.x - bubble.width / 2, y: point.y - bubble.height, width: bubble.width, height: bubble.height)
    }

    func testTheOldPlaceOverTheStationCoveredTheNameAbove() {
        // The bubble straight over the middle station, where main drew
        // it, lies on the north station's name.
        let bubble = MapLabelPlacement.Bubble(x: 400, y: 200, text: "缺建材", hasReason: false)
        let old = MapLabelPlacement.bubbleCandidates(x: 400, y: 200, lift: Self.lift, radius: Self.radius,
                                                     width: bubble.width, height: bubble.height)[0]
        XCTAssertTrue(overlaps(old, MapLabelPlacement.nameBox(of: cross[0], radius: Self.radius)))
    }

    func testShortOfMaterialsBubblesLeaveEveryNameUncovered() {
        let bubbles = cross.dropFirst().map { MapLabelPlacement.Bubble(x: $0.x, y: $0.y, text: "缺建材", hasReason: false) }
        let points = MapLabelPlacement.placeBubbles(bubbles, stations: cross, lift: Self.lift, radius: Self.radius)
        let boxes = zip(bubbles, points).map { bubbleBox($0, at: $1) }
        for box in boxes {
            for station in cross {
                XCTAssertFalse(overlaps(box, MapLabelPlacement.nameBox(of: station, radius: Self.radius)),
                               "A bubble at \(box) covers \(station.name)'s name")
            }
        }
        for (i, a) in boxes.enumerated() {
            for b in boxes[(i + 1)...] {
                XCTAssertFalse(overlaps(a, b), "Two bubbles lie on each other")
            }
        }
    }

    func testABubbleWithRoomStaysOverItsStation() {
        let alone = [MapLabelPlacement.Station(x: 200, y: 200, name: "臺北")]
        let bubble = MapLabelPlacement.Bubble(x: 200, y: 200, text: "Crowded", hasReason: false)
        let point = MapLabelPlacement.placeBubbles([bubble], stations: alone, lift: Self.lift, radius: Self.radius)[0]
        XCTAssertEqual(point, ScreenPoint(x: 200, y: 200 - Self.lift), "Over the station, as before")
    }

    func testTwoBubblesOfOneStationKeepTheirTouchAreasApart() {
        let alone = [MapLabelPlacement.Station(x: 200, y: 300, name: "臺北")]
        let bubbles = [
            MapLabelPlacement.Bubble(x: 200, y: 300, text: "Crowded", hasReason: false),
            MapLabelPlacement.Bubble(x: 200, y: 300, text: "Short of materials", hasReason: false),
        ]
        let points = MapLabelPlacement.placeBubbles(bubbles, stations: alone, lift: Self.lift, radius: Self.radius)
        let touch = zip(bubbles, points).map { bubble, point in
            let box = bubbleBox(bubble, at: point)
            return Box(x: box.minX, y: (box.minY + box.maxY) / 2 - 22, width: box.maxX - box.minX, height: 44)
        }
        XCTAssertFalse(overlaps(touch[0], touch[1]))
    }

    /// real-world-demo-day: a fare at Qidu, Badu's name up and to its right.
    func testAFareKeepsOffTheNameBesideIt() {
        let stations = [
            MapLabelPlacement.Station(x: 284, y: 167, name: "七堵"),
            MapLabelPlacement.Station(x: 321, y: 124, name: "八堵"),
        ]
        let old = Box(x: 284 - 30, y: 167 - 32, width: 60, height: 20)
        XCTAssertTrue(overlaps(old, MapLabelPlacement.nameBox(of: stations[1], radius: Self.radius)), "Where main drew it")
        let point = MapLabelPlacement.placeFares([(x: 284, y: 167, text: "+$1.5k")], stations: stations, radius: Self.radius)[0]
        let width = MapLabelPlacement.textWidth("+$1.5k", size: 12) + 12
        let box = Box(x: point.x - width / 2, y: point.y - 10, width: width, height: 20)
        for station in stations {
            XCTAssertFalse(overlaps(box, MapLabelPlacement.nameBox(of: station, radius: Self.radius)), "The fare covers \(station.name)")
        }
    }

    func testAFareWithRoomStaysOverItsStation() {
        let point = MapLabelPlacement.placeFares([(x: 100, y: 100, text: "+$12")], stations: [.init(x: 100, y: 100, name: "A")],
                                                 radius: Self.radius)[0]
        XCTAssertEqual(point, ScreenPoint(x: 100, y: 78))
    }

    // MARK: - Tiles for sale

    func testATilesPriceMovesOutFromUnderTheTopBar() {
        let clear = Box(x: 0, y: 120, width: 874, height: 282)
        // A tile whose middle (y 100) is under the bar: its price goes to
        // the middle of the part below it.
        let tile = Box(x: 300, y: 0, width: 200, height: 200)
        let width = MapLabelPlacement.priceWidth("$5,000,000", locked: true)
        let label = MapLabelPlacement.tileLabel(tile: tile, clear: clear, width: width, height: 18)
        XCTAssertNotNil(label)
        if let label {
            XCTAssertGreaterThanOrEqual(label.minY, 120)
            XCTAssertEqual((label.minX + label.maxX) / 2, 400, accuracy: 0.001)
        }
        XCTAssertNil(MapLabelPlacement.tileLabel(tile: Box(x: 300, y: 0, width: 200, height: 125), clear: clear, width: width, height: 18),
                     "Not a sliver's worth showing")
    }

    func testASightsMarkOnAPriceIsLeftOut() {
        let price = Box(x: 340, y: 191, width: 120, height: 18)
        XCTAssertTrue(MapLabelPlacement.coversPrice(x: 400, y: 205, stars: "4★", prices: [price]))
        XCTAssertFalse(MapLabelPlacement.coversPrice(x: 400, y: 260, stars: "4★", prices: [price]))
    }

    // MARK: - The base map's place names

    func testTheCoveredBandsAreTheMapsInsets() {
        let bands = MapLabelPlacement.coveredBands(width: 874, height: 402, top: 70, leading: 140, bottom: 0, trailing: 0)
        XCTAssertEqual(bands.count, 2, "Top and leading only")
        XCTAssertEqual(bands[0].maxY, 70)
        XCTAssertEqual(bands[1].maxX, 140)
        XCTAssertEqual(bands[1].minY, 70)
        XCTAssertEqual(bands[1].maxY, 402)
    }

    func testWidthsCountChineseWide() {
        XCTAssertEqual(MapLabelPlacement.textWidth("臺北", size: 10), 20)
        XCTAssertEqual(MapLabelPlacement.textWidth("ab", size: 10), 12)
    }
}
