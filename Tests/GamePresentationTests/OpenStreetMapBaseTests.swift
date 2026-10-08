import Foundation
import GameCore
import GamePresentation
import XCTest

/// The OpenStreetMap base map of real-world maps (ARCHITECTURE decision 97):
/// where MapLibre looks, the style it loads and the labels it shows.
final class OpenStreetMapBaseTests: XCTestCase {
    func testTheStylesAreOpenFreeMapsPositronAndDark() {
        XCTAssertEqual(OpenStreetMapBase.styleURL(dark: false), "https://tiles.openfreemap.org/styles/positron")
        XCTAssertEqual(OpenStreetMapBase.styleURL(dark: true), "https://tiles.openfreemap.org/styles/dark")
    }

    /// One name in the player's language, falling back to the local one.
    func testLabelsAreInThePlayersLanguage() throws {
        func json(_ object: Any) throws -> String {
            try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: object), encoding: .utf8))
        }
        XCTAssertEqual(
            try json(OpenStreetMapBase.labelText(in: .traditionalChinese)),
            #"["coalesce",["get","name:zh-Hant"],["get","name:zh"],["get","name"]]"#
        )
        XCTAssertEqual(
            try json(OpenStreetMapBase.labelText(in: .english)),
            #"["coalesce",["get","name:en"],["get","name_en"],["get","name:latin"],["get","name"]]"#
        )
    }

    /// OpenFreeMap's place labels (Latin over local) are names; road
    /// numbers and house numbers are not.
    func testOnlyNameLabelsAreReplaced() throws {
        let openFreeMap = try JSONSerialization.jsonObject(with: Data(#"""
        ["case", ["has", "name:nonlatin"], ["concat", ["get", "name:latin"], "\n", ["get", "name:nonlatin"]], ["coalesce", ["get", "name_en"], ["get", "name"]]]
        """#.utf8))
        XCTAssertTrue(OpenStreetMapBase.showsName(openFreeMap))
        XCTAssertTrue(OpenStreetMapBase.showsName(["get", "name"]))
        XCTAssertTrue(OpenStreetMapBase.showsName("{name}") == false, "a token string is not a field")
        XCTAssertFalse(OpenStreetMapBase.showsName(["get", "ref"]))
        XCTAssertFalse(OpenStreetMapBase.showsName(["to-string", ["get", "housenumber"]]))
        XCTAssertFalse(OpenStreetMapBase.showsName(42))
    }

    /// MapLibre's camera draws the Earth as the game's camera does: the two
    /// corners of the view land the view's width and height apart in
    /// MapLibre's pixels (the Earth 512 · 2^z points wide), and the middle
    /// of the view is the place under the game's middle.
    func testTheCameraLinesUpWithTheGame() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.047882, longitudeDegrees: 121.517219))
        let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
        let size = (width: 402.0, height: 450.0)
        let cameras = [
            PlanCamera(bounds: GameWorld.newGameBounds, viewport: ScreenSize(width: size.width, height: 420)),
            PlanCamera(bounds: GameWorld.newGameBounds, viewport: ScreenSize(width: size.width, height: 420))
                .zoomedIn().zoomedIn().zoomedIn().panned(byX: 900, y: -300),
        ]
        for camera in cameras {
            let view = OpenStreetMapBase.camera(of: camera, in: frame, width: size.width, height: size.height)
            func pixel(_ latitude: Double, _ longitude: Double) -> (x: Double, y: Double) {
                let world = 512 * pow(2, view.zoom)
                let sine = sin(latitude * .pi / 180)
                return ((longitude + 180) / 360 * world, (0.5 - log((1 + sine) / (1 - sine)) / (4 * .pi)) * world)
            }
            let corners = [(0.0, 0.0), (size.width, size.height)].map { point in
                let world = camera.worldPosition(at: ScreenPoint(x: point.0, y: point.1))
                let place = frame.coordinate(worldX: world.x, worldY: world.y)
                return pixel(place.latitude, place.longitude)
            }
            XCTAssertEqual(corners[1].x - corners[0].x, size.width, accuracy: 0.01)
            XCTAssertEqual(corners[1].y - corners[0].y, size.height, accuracy: 0.01)
            let middle = camera.worldPosition(at: ScreenPoint(x: size.width / 2, y: size.height / 2))
            let place = frame.coordinate(worldX: middle.x, worldY: middle.y)
            XCTAssertEqual(view.latitude, place.latitude, accuracy: 1e-12)
            XCTAssertEqual(view.longitude, place.longitude, accuracy: 1e-12)
        }
    }
}
