@testable import GamePresentation
import GameCore
import XCTest

/// Decision 929: a small station in Finland is the studio's Finnish
/// country station.
final class Map3DFinlandStationTests: XCTestCase {
    private func station(_ profile: Map3DStationKit.Profile) -> Map3DStationKit.Station {
        Map3DStationKit.Station(id: "s", name: "s", system: "player", latitude: 0, longitude: 0, lines: [],
                                profile: profile, tier: 3, seed: 0, planned: false, isLandmark: false)
    }

    /// Both versions decode at the studio's size and triangle counts,
    /// stand on the ground and use only the palette's slots.
    func testTheModelDecodes() throws {
        let near = try XCTUnwrap(Map3DFinlandStation.model())
        let far = try XCTUnwrap(Map3DFinlandStation.model(far: true))
        XCTAssertEqual(near.triangleCount, 1906)
        XCTAssertEqual(far.triangleCount, 390)
        for model in [near, far] {
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.02)
            XCTAssertEqual(model.maximum.x - model.minimum.x, 17.8, accuracy: 0.1)
            XCTAssertEqual(model.maximum.y, 6.5, accuracy: 0.02, "the eave over the platform side")
            XCTAssertEqual(model.minimum.y, -5.4, accuracy: 0.02, "the porch")
            XCTAssertEqual(model.maximum.z, 8, accuracy: 0.05)
            XCTAssertTrue(model.vertices.allSatisfy { Map3DFinlandStation.meshPalette.contains($0.color) })
        }
        XCTAssertTrue(near.vertices.contains { $0.color == Map3DPalette.gold }, "its yellow boards")
        XCTAssertTrue(near.vertices.contains { $0.color == Map3DPalette.finnishSignBlue }, "its name board")
        XCTAssertTrue(near.vertices.contains { $0.color == Map3DPalette.redBrick }, "its chimney")
    }

    /// A regional station or a halt not yet expanded is the Finnish one,
    /// and only in Finland.
    func testWhichStationsAreFinnish() {
        XCTAssertTrue(Map3DFinlandStation.replaces(profile: .regional, expansion: nil))
        XCTAssertTrue(Map3DFinlandStation.replaces(profile: .halt, expansion: nil))
        XCTAssertFalse(Map3DFinlandStation.replaces(profile: .regional, expansion: .hall))
        XCTAssertFalse(Map3DFinlandStation.replaces(profile: .elevated, expansion: nil))
        let model = Map3DFinlandStation.model()!
        for profile in [Map3DStationKit.Profile.regional, .halt] {
            var finland = StationKitBuilder(), taiwan = StationKitBuilder()
            finland.finnish = true
            finland.genericHouse(station(profile), expansion: nil)
            taiwan.genericHouse(station(profile), expansion: nil)
            XCTAssertEqual(finland.mesh.triangleCount, model.triangleCount)
            XCTAssertNotEqual(taiwan.mesh.triangleCount, finland.mesh.triangleCount)
        }
        var expanded = StationKitBuilder(), plain = StationKitBuilder()
        expanded.finnish = true
        expanded.genericHouse(station(.regional), expansion: .hall)
        plain.genericHouse(station(.regional), expansion: .hall)
        XCTAssertEqual(expanded.mesh.triangleCount, plain.mesh.triangleCount, "an expanded one keeps its wings")
        var far = StationKitBuilder()
        far.finnish = true
        far.genericHouse(station(.regional), expansion: nil, far: true)
        XCTAssertEqual(far.mesh.triangleCount, Map3DFinlandStation.model(far: true)!.triangleCount)
    }

    /// Its platform-side wall on x 7, the line the generic station's back
    /// wall stands on, its eave half a metre over it; its long side along
    /// the platforms; its porch at the front.
    func testItFacesAwayFromItsPlatforms() throws {
        var kit = StationKitBuilder()
        kit.finnish = true
        kit.genericHouse(station(.regional), expansion: nil)
        let bounds = try XCTUnwrap(kit.mesh.bounds)
        XCTAssertEqual(bounds.min.x, 6.5, accuracy: 0.02)
        XCTAssertEqual(bounds.max.x, 18.4, accuracy: 0.02)
        XCTAssertGreaterThan(bounds.max.z - bounds.min.z, bounds.max.x - bounds.min.x)
        XCTAssertEqual(bounds.min.y, 0.25, accuracy: 0.02)
    }
}
