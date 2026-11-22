@testable import GamePresentation
import GameCore
import XCTest

/// Decision 922: a small station in Japan is the earlier version's wooden
/// station.
final class Map3DJapanStationTests: XCTestCase {
    private func station(_ profile: Map3DStationKit.Profile) -> Map3DStationKit.Station {
        Map3DStationKit.Station(id: "s", name: "s", system: "player", latitude: 0, longitude: 0, lines: [],
                                profile: profile, tier: 3, seed: 0, planned: false, isLandmark: false)
    }

    /// Both versions decode, stand on the ground at about the size the old
    /// one had at half scale, and use only the palette's slots.
    func testTheModelDecodes() throws {
        let near = try XCTUnwrap(Map3DJapanStation.model())
        let far = try XCTUnwrap(Map3DJapanStation.model(far: true))
        XCTAssertLessThan(far.vertices.count, near.vertices.count, "the far one is lighter")
        for model in [near, far] {
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.05)
            XCTAssertEqual(model.maximum.x - model.minimum.x, 30.7, accuracy: 1)
            XCTAssertEqual(model.maximum.z, 9.3, accuracy: 0.5)
            XCTAssertTrue(model.vertices.allSatisfy { Map3DJapanStation.meshPalette.contains($0.color) })
        }
        XCTAssertTrue(near.vertices.contains { $0.color == Map3DPalette.glazing }, "its windows")
        XCTAssertTrue(near.vertices.contains { $0.color == Map3DPalette.tileWhite }, "its plaster panels")
        XCTAssertFalse(far.vertices.contains { $0.color == Map3DPalette.glazing }, "afar no panes")
    }

    /// Only a regional station not yet expanded is the wooden one, and only
    /// in Japan.
    func testWhichStationsAreWooden() {
        XCTAssertTrue(Map3DJapanStation.replaces(profile: .regional, expansion: nil))
        XCTAssertFalse(Map3DJapanStation.replaces(profile: .halt, expansion: nil))
        XCTAssertFalse(Map3DJapanStation.replaces(profile: .regional, expansion: .hall))
        var japan = StationKitBuilder(), taiwan = StationKitBuilder()
        japan.japanese = true
        japan.genericHouse(station(.regional), expansion: nil)
        taiwan.genericHouse(station(.regional), expansion: nil)
        XCTAssertEqual(japan.mesh.triangleCount, Map3DJapanStation.model()!.triangleCount)
        XCTAssertNotEqual(taiwan.mesh.triangleCount, japan.mesh.triangleCount)
        var halt = StationKitBuilder()
        halt.japanese = true
        halt.genericHouse(station(.halt), expansion: nil)
        XCTAssertEqual(halt.mesh.triangleCount, Map3DGenericStation.model(.halt)!.triangleCount, "a halt keeps its shelter")
    }

    /// Its back, the canopy's edge, at x 7 by the platforms; its long side
    /// along them; its porch at the front.
    func testItFacesAwayFromItsPlatforms() throws {
        var kit = StationKitBuilder()
        kit.japanese = true
        kit.genericHouse(station(.regional), expansion: nil)
        let bounds = try XCTUnwrap(kit.mesh.bounds)
        XCTAssertEqual(bounds.min.x, 7, accuracy: 0.05)
        XCTAssertGreaterThan(bounds.max.z - bounds.min.z, bounds.max.x - bounds.min.x)
    }
}
