import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// FUKUOKA-LANDMARKS (decision 854's later note): Fukuoka's landmarks on
/// its 3D map, registered landmarks since decision 895.
final class Map3DFukuokaLandmarksTests: XCTestCase {
    /// Fukuoka Tower stands at Momochihama, its mast as high as the real
    /// one's; Fukuoka Dome beside it and Hakata Station over the subway's
    /// Hakata station (in its tunnel, so the building is not left out),
    /// each as high as the real one, alone in a scene round it.
    func testOnFukuokasMap() throws {
        let world = GameWorld.newOverseasGame(try FukuokaRailwaysTests.ground())
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        for (landmark, reach, height) in [(Map3DFukuokaTower.registration, 800.0, Float(234)),
                                          (Map3DFukuokaDome.registration, 400, 84.85),
                                          (Map3DHakataStation.registration, 400, 63.05)] {
            let place = frame.worldPosition(latitude: landmark.latitude, longitude: landmark.longitude)
            let metre = Double(WorldCoordinate.unitsPerMetre), reach = reach * metre
            let region = WorldRegion(minX: place.x - reach, minY: place.y - reach, maxX: place.x + reach, maxY: place.y + reach)
            var builder = Map3DScene.Builder(originX: place.x, originY: place.y, region: region, world: world, heights: nil)
            XCTAssertEqual(builder.addHongKongLandmarks(frame: frame), [landmark.id])
            let top = builder.nearMeshes.values.flatMap(\.vertices).map(\.y).max() ?? 0
            XCTAssertEqual(top, height, accuracy: 1, landmark.id)
            XCTAssertTrue(builder.underLandmark(builder.point(x: place.x, y: place.y, height: 0)), landmark.id)
        }
    }

    /// The tower's walls are glass, lit at night, and its mast steel;
    /// Hakata Station's glass is its blue-grey glass alone.
    func testTheirGlass() {
        let tower = Map3DFukuokaTower.registration.model(full: true).vertices
        XCTAssertEqual(Set(tower.filter { $0.layer == Map3DVertex.curtainGlass }.map(\.color)), [Map3DPalette.officeWalls[2]])
        let station = Map3DHakataStation.registration.model(full: true).vertices
        XCTAssertEqual(Set(station.filter { $0.layer == Map3DVertex.curtainGlass }.map(\.color)), [Map3DPalette.cityOfficeWalls[5]])
        XCTAssertFalse(Map3DFukuokaDome.registration.model(full: true).vertices.contains { $0.layer == Map3DVertex.curtainGlass })
    }
}
