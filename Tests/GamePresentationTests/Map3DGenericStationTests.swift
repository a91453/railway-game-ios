@testable import GamePresentation
import GameCore
import XCTest

/// Decision 899: the local studio's generic stations.
final class Map3DGenericStationTests: XCTestCase {
    func testEveryModelDecodesWithItsFarVersion() {
        for model in Map3DGenericStation.Model.allCases {
            XCTAssertNotNil(Map3DGenericStation.model(model), model.rawValue)
            if model.hasFar {
                let near = Map3DGenericStation.model(model)!, far = Map3DGenericStation.model(model, far: true)!
                XCTAssertLessThan(far.vertices.count, near.vertices.count, "\(model.rawValue): the far one is lighter")
            }
        }
    }

    func testTheBuildingIsChosenByProfileAndTier() {
        XCTAssertEqual(Map3DGenericStation.building(profile: .halt, tier: 1), .halt)
        XCTAssertEqual(Map3DGenericStation.building(profile: .regional, tier: 1), .twoFloor)
        XCTAssertEqual(Map3DGenericStation.building(profile: .regional, tier: 2), .twoFloor)
        XCTAssertEqual(Map3DGenericStation.building(profile: .regional, tier: 3), .oneFloor)
        XCTAssertEqual(Map3DGenericStation.building(profile: .regional, tier: 4), .oneFloor)
    }

    /// The back towards the platforms (−x in the kit), the green canopy
    /// and the forecourt's steps at the front (+x), the long side along z.
    func testTheStationFacesAwayFromItsPlatforms() {
        for tier in [1, 4] {
            let station = Map3DStationKit.Station(id: "s", name: "s", system: "player", latitude: 0, longitude: 0, lines: [],
                                                  profile: .regional, tier: tier, seed: 0, planned: false, isLandmark: false)
            var kit = StationKitBuilder()
            kit.genericHouse(station, expansion: nil)
            guard let bounds = kit.mesh.bounds else { return XCTFail("nothing drawn") }
            // The body is 12 m deep from x 7; only the back canopy's
            // metre reaches behind it.
            XCTAssertEqual(bounds.min.x, 6, accuracy: 0.3, "tier \(tier): its back by the platforms")
            XCTAssertGreaterThan(bounds.max.z - bounds.min.z, bounds.max.x - bounds.min.x, "tier \(tier): long along the platforms")
            let middle = (bounds.min.x + bounds.max.x) / 2
            let front = kit.mesh.vertices.filter { $0.x > middle }.count
            let back = kit.mesh.vertices.filter { $0.x < middle }.count
            XCTAssertGreaterThan(front, back, "tier \(tier): the canopy, steps and boards at the front")
        }
    }

    /// The kit's stair head still climbs towards +x; the underground exit
    /// still goes down from +x.
    func testTheStairsGoTheKitsWay() {
        var stair = StationKitBuilder()
        stair.part(.stairHead)
        var exit = StationKitBuilder()
        exit.part(.undergroundExit)
        func meanX(_ mesh: Map3DMesh, _ test: (Float) -> Bool) -> Float {
            let xs = mesh.vertices.filter { test($0.y) }.map(\.x)
            return xs.reduce(0, +) / Float(max(xs.count, 1))
        }
        XCTAssertLessThan(exit.mesh.bounds!.min.y, -2, "the exit goes below the ground")
        XCTAssertLessThan(meanX(exit.mesh) { $0 < -1.5 }, 0, "its lowest steps towards −x")
    }
}
