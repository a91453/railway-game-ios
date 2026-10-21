import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 312: the start area the real-world picker draws (where its
/// frame lies, its area, that it stays on the map) and the recent places
/// it lists.
///
/// Expected values are worked out from the rules, never taken from a
/// previous run.
final class RealWorldStartAreaTests: XCTestCase {
    private func anchor(_ latitude: Double, _ longitude: Double) throws -> GeoAnchor {
        try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude))
    }

    /// The middle of the corners, as degrees.
    private func centre(_ corners: [(latitude: Double, longitude: Double)]) -> (latitude: Double, longitude: Double) {
        (corners.map(\.latitude).reduce(0, +) / 4, corners.map(\.longitude).reduce(0, +) / 4)
    }

    /// A place of Taiwan starts with one tile that can grow; Tokyo with
    /// the 16 km square, its whole map, 16,384 m a side on the ground at
    /// its middle, 268 km². Taiwan's tile is 16,384 metres at the map's
    /// anchor, so at Taipei, north of it, a little less on the ground:
    /// scaled by the cosines of the two latitudes.
    func testTheAreaAndWhetherItGrows() throws {
        let tokyo = RealWorldStartArea(middle: try anchor(35.681, 139.767))
        XCTAssertNil(tokyo.expansion)
        XCTAssertFalse(tokyo.buysMoreLand)
        XCTAssertEqual(tokyo.groundMetres.width, 16_384, accuracy: 0.01)
        XCTAssertEqual(tokyo.groundMetres.height, 16_384, accuracy: 2)
        XCTAssertEqual(tokyo.squareKilometres, 16.384 * 16.384, accuracy: 0.05)
        XCTAssertEqual(tokyo.areaText(in: .english), "268 km² (16.4 × 16.4 km)")
        XCTAssertEqual(tokyo.areaText(in: .traditionalChinese), "268 平方公里（16.4 × 16.4 公里）")
        XCTAssertEqual(tokyo.summary(in: .english), "Your map is 268 km² (16.4 × 16.4 km). It stays this size.")
        XCTAssertEqual(tokyo.summary(in: .traditionalChinese), "地圖約 268 平方公里（16.4 × 16.4 公里），之後不會再擴大。")

        let taipei = RealWorldStartArea(middle: RealWorldPlace.standard.anchor)
        let expansion = try XCTUnwrap(taipei.expansion)
        XCTAssertTrue(taipei.buysMoreLand)
        let scale = cos(RealWorldPlace.standard.anchor.latitudeDegrees * .pi / 180) / cos(expansion.anchor.latitudeDegrees * .pi / 180)
        XCTAssertLessThan(scale, 1, "Taipei is north of the map's anchor")
        XCTAssertEqual(taipei.groundMetres.width, 16_384 * scale, accuracy: 1)
        XCTAssertEqual(taipei.groundMetres.height, 16_384 * scale, accuracy: 3)
        XCTAssertEqual(taipei.squareKilometres, 16.384 * 16.384 * scale * scale, accuracy: 0.1)
        let area = Int((16.384 * 16.384 * scale * scale).rounded()), side = (163.84 * scale).rounded() / 10
        XCTAssertEqual(taipei.summary(in: .english), "You start with \(area) km² (\(side) × \(side) km) of land. You can buy land later to grow it.")
        XCTAssertEqual(taipei.summary(in: .traditionalChinese), "一開始的土地約 \(area) 平方公里（\(side) × \(side) 公里），之後可以買地擴大。")
    }

    /// The frame is a square round the middle: north-west, north-east,
    /// south-east, south-west, about 16.4 km a side on the ground.
    func testTheFrameIsTheSquareRoundTheMiddle() throws {
        for middle in [RealWorldPlace.standard.anchor, try anchor(35.681, 139.767), try anchor(-33.87, 151.21)] {
            let area = RealWorldStartArea(middle: middle)
            let corners = area.corners
            XCTAssertEqual(corners.count, 4)
            let (north, south) = (corners[0].latitude, corners[3].latitude)
            let (west, east) = (corners[0].longitude, corners[1].longitude)
            XCTAssertEqual(corners[1].latitude, north, accuracy: 1e-9)
            XCTAssertEqual(corners[2].latitude, south, accuracy: 1e-9)
            XCTAssertEqual(corners[2].longitude, east, accuracy: 1e-9)
            XCTAssertEqual(corners[3].longitude, west, accuracy: 1e-9)
            XCTAssertGreaterThan(north, middle.latitudeDegrees)
            XCTAssertLessThan(south, middle.latitudeDegrees)
            XCTAssertLessThan(west, middle.longitudeDegrees)
            XCTAssertGreaterThan(east, middle.longitudeDegrees)
            // The middle is the middle, to a metre or so.
            let centre = centre(corners)
            XCTAssertEqual(centre.longitude, middle.longitudeDegrees, accuracy: 1e-5)
            XCTAssertEqual(centre.latitude, middle.latitudeDegrees, accuracy: 1e-3, "Mercator stretches north of the middle a little")
            // Square on the ground, to a few metres.
            XCTAssertEqual(area.groundMetres.width, area.groundMetres.height, accuracy: 3)
        }
    }

    /// For a place of Taiwan the frame is the tile the game would own:
    /// the expansion's start tile, as decision 167 lays it.
    func testTaiwansFrameIsTheStartTile() throws {
        let area = RealWorldStartArea(middle: RealWorldPlace.standard.anchor)
        let expansion = try XCTUnwrap(area.expansion)
        let frame = expansion.frame
        let length = Double(MapExpansion.tileLength)
        let northWest = frame.coordinate(worldX: Double(expansion.start.column) * length, worldY: Double(expansion.start.row) * length)
        XCTAssertEqual(area.corners[0].latitude, northWest.latitude, accuracy: 1e-12)
        XCTAssertEqual(area.corners[0].longitude, northWest.longitude, accuracy: 1e-12)
    }

    /// A tap moves the frame to the point; one near a pole moves it as far
    /// as it can go with the land still on the map; the longitude comes
    /// round the Earth.
    func testATapKeepsTheFrameOnTheMap() throws {
        let tapped = try XCTUnwrap(RealWorldStartArea(latitude: 24.9, longitude: 121.3))
        XCTAssertEqual(tapped.middle, try anchor(24.9, 121.3))
        XCTAssertNotNil(tapped.expansion)

        let limit = RealWorldStartArea.maximumLatitude
        XCTAssertGreaterThan(limit, 84.9)
        XCTAssertLessThan(limit, 85.0511)
        let north = try XCTUnwrap(RealWorldStartArea(latitude: 89, longitude: 10))
        XCTAssertEqual(north.middle.latitudeDegrees, limit, accuracy: 1e-7)
        let south = try XCTUnwrap(RealWorldStartArea(latitude: -89, longitude: 10))
        XCTAssertEqual(south.middle.latitudeDegrees, -limit, accuracy: 1e-7)
        // At the limit the frame's north edge is within the map's top
        // (85.0511°), and only just.
        let top = north.corners[0].latitude
        XCTAssertLessThanOrEqual(top, 85.051_129)
        XCTAssertGreaterThan(top, 85.05)

        let round = try XCTUnwrap(RealWorldStartArea(latitude: 0, longitude: 190))
        XCTAssertEqual(round.middle.longitudeDegrees, -170, accuracy: 1e-7)
        XCTAssertNil(RealWorldStartArea(latitude: .nan, longitude: 0))
        XCTAssertNil(RealWorldStartArea(latitude: 0, longitude: .infinity))
    }

    // MARK: - Recent places

    func testRecentPlacesAreNewestFirstWithoutRepeats() throws {
        let taipei = try anchor(25.0478, 121.5170), tokyo = try anchor(35.681, 139.767)
        var recent = RecentStartPlaces().adding(taipei).adding(tokyo)
        XCTAssertEqual(recent.places, [tokyo, taipei])
        // Taipei again, 500 m away: the same place, moved to the front.
        let nearTaipei = try anchor(25.0478, 121.5220)
        recent = recent.adding(nearTaipei)
        XCTAssertEqual(recent.places, [nearTaipei, tokyo])
        // At most five.
        for step in 1...6 {
            recent = recent.adding(try anchor(Double(step), 0))
        }
        XCTAssertEqual(recent.places.count, RecentStartPlaces.limit)
        XCTAssertEqual(recent.places.first, try anchor(6, 0))
        XCTAssertEqual(recent.places.last, try anchor(2, 0))
    }

    func testRecentPlacesAreKeptAsText() throws {
        let recent = RecentStartPlaces().adding(try anchor(25.0478, 121.5170)).adding(try anchor(-33.87, -70.65))
        XCTAssertEqual(recent.stored, "-338700000,-706500000;250478000,1215170000")
        XCTAssertEqual(RecentStartPlaces(stored: recent.stored), recent)
        // What does not read is left out.
        XCTAssertEqual(RecentStartPlaces(stored: "x;250478000,1215170000;1,2,3;999999999,0").places, [try anchor(25.0478, 121.5170)])
        XCTAssertEqual(RecentStartPlaces(stored: "").places, [])
    }

    /// Without the app's place names, a recent place near one of the
    /// list's is called by it; one far from all by where it is.
    func testRecentPlacesNames() throws {
        let nearTaipei = try anchor(25.05, 121.52)
        XCTAssertEqual(RecentStartPlaces.name(of: nearTaipei, names: nil, language: .english), "Taipei")
        XCTAssertEqual(RecentStartPlaces.name(of: nearTaipei, names: nil, language: .traditionalChinese), "臺北")
        XCTAssertEqual(RecentStartPlaces.name(of: try anchor(-40.5, -120.25), names: nil, language: .english), "40.50°S 120.25°W")
        XCTAssertEqual(RecentStartPlaces.metres(from: try anchor(0, 0), to: try anchor(0, 1)), 111_195, accuracy: 1)
    }
}
