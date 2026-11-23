@testable import GamePresentation
import GameCore
import XCTest

/// Decision 929: Pingxi's and Rinan's stations are the studio's own models;
/// decision 932: Jingtong's and Checheng's too.
final class Map3DStudioStationsTests: XCTestCase {
    private func station(_ id: String) throws -> Map3DStationKit.Station {
        try XCTUnwrap(Map3DStationKit.stations.first { $0.id == id })
    }

    /// Each model decodes at the studio's triangle counts and bounds, on
    /// the ground, in its palette's colours only.
    func testTheModelsDecode() throws {
        let expected: [Map3DStudioStation: (near: Int, far: Int, length: Float, height: Float)] = [
            .pingxi: (3452, 592, 26, 7.4), .rinan: (2956, 864, 16.4, 6.66),
            .jingtong: (1612, 736, 19.02, 5.85), .checheng: (2980, 724, 25.68, 8.8),
        ]
        for own in Map3DStudioStation.allCases {
            let want = try XCTUnwrap(expected[own])
            let near = try XCTUnwrap(own.model()), far = try XCTUnwrap(own.model(far: true))
            XCTAssertEqual(near.triangleCount, want.near, own.name)
            XCTAssertEqual(far.triangleCount, want.far, own.name)
            for model in [near, far] {
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.02, own.name)
                XCTAssertEqual(model.maximum.x - model.minimum.x, want.length, accuracy: 0.05, own.name)
                XCTAssertEqual(model.maximum.z, want.height, accuracy: 0.05, own.name)
                XCTAssertTrue(model.vertices.allSatisfy { own.meshPalette.contains($0.color) }, own.name)
            }
        }
        // Pingxi's dark railings; Rinan's panes the dark ones, not Pingxi's.
        XCTAssertTrue(try XCTUnwrap(Map3DStudioStation.pingxi.model()).vertices.contains { $0.color == Map3DPingxiStation.railWood })
        let rinan = try XCTUnwrap(Map3DStudioStation.rinan.model())
        XCTAssertTrue(rinan.vertices.contains { $0.color == Map3DDepotFacilities.glass })
        XCTAssertFalse(rinan.vertices.contains { $0.color == Map3DPalette.glazing })
    }

    /// The catalog's two stations, and no other, draw their own model.
    func testOnlyTheirStationsDrawThem() throws {
        XCTAssertEqual(try station("station-tra_sched-a5dcd0a9").name, "平溪")
        XCTAssertEqual(try station("station-tra_sched-333125bf").name, "日南")
        XCTAssertEqual(try station("station-tra_sched-b2e8d7d9").name, "菁桐")
        XCTAssertEqual(try station("station-tra_sched-49f63912").name, "車埕")
        for own in Map3DStudioStation.allCases {
            var kit = StationKitBuilder()
            kit.house(try station(own.rawValue))
            XCTAssertEqual(kit.mesh.triangleCount, try XCTUnwrap(own.model()).triangleCount, own.name)
        }
        let others = Map3DStationKit.stations.filter { $0.profile == .heritage && Map3DStudioStation(rawValue: $0.id) == nil }
        let other = try XCTUnwrap(others.first)
        var kit = StationKitBuilder()
        kit.house(other)
        XCTAssertFalse(Map3DStudioStation.allCases.contains { $0.model()?.triangleCount == kit.mesh.triangleCount })
    }

    /// Decision 932: Jingtong and Checheng are no longer the Alishan
    /// line's `timber` recipe, which its other stations keep; Jingtong is
    /// the white house with the brick plinth and the dark panes, Checheng
    /// the dark boarded one under the red-brown roof, its monitor roof
    /// above Jingtong's ridge, in the far versions too.
    func testJingtongAndChechengAreNotTheTimberRecipe() throws {
        let timber = try XCTUnwrap(Map3DStationKit.stations.first { $0.profile == .timber && Map3DStudioStation(rawValue: $0.id) == nil })
        var recipe = StationKitBuilder()
        recipe.house(timber)
        let recipeBounds = try XCTUnwrap(recipe.mesh.bounds)
        for own in [Map3DStudioStation.jingtong, .checheng] {
            XCTAssertEqual(try station(own.rawValue).profile, .timber, own.name)
            var kit = StationKitBuilder()
            kit.house(try station(own.rawValue))
            XCTAssertNotEqual(kit.mesh.triangleCount, recipe.mesh.triangleCount, own.name)
            XCTAssertNotEqual(try XCTUnwrap(kit.mesh.bounds).max.y, recipeBounds.max.y, own.name)
        }
        for far in [false, true] {
            let jingtong = try XCTUnwrap(Map3DStudioStation.jingtong.model(far: far))
            let checheng = try XCTUnwrap(Map3DStudioStation.checheng.model(far: far))
            for colour in [Map3DPalette.tankWhite, Map3DPalette.arcade, Map3DContainerWagon.rust, Map3DDepotFacilities.glass] {
                XCTAssertTrue(jingtong.vertices.contains { $0.color == colour }, "far \(far)")
            }
            for colour in [Map3DPalette.timberSiding, Map3DPalette.cityRoofs[5].color, Map3DPalette.steel] {
                XCTAssertTrue(checheng.vertices.contains { $0.color == colour }, "far \(far)")
            }
            XCTAssertFalse(jingtong.vertices.contains { $0.color == Map3DPalette.cityRoofs[5].color })
            XCTAssertFalse(checheng.vertices.contains { $0.color == Map3DPalette.tankWhite })
            XCTAssertGreaterThan(checheng.maximum.z, jingtong.maximum.z + 2.5)
            // The highest of Checheng is its monitor roof, the tiles' colour
            // (but the bargeboards' few centimetres above it), over the
            // middle half of the house only.
            let top = checheng.vertices.filter { $0.z > 7.5 }
            XCTAssertTrue(top.contains { $0.color == Map3DPalette.cityRoofs[5].color })
            XCTAssertLessThan(top.map { abs($0.x) }.max() ?? 99, 8)
        }
    }

    /// The platform side's clear line on x 7, where the kit's buildings
    /// have their backs (only eaves and canopies reach up to a metre past
    /// it); the long side along the platforms.
    func testTheyStandBehindThePlatformLine() throws {
        for own in Map3DStudioStation.allCases {
            var kit = StationKitBuilder()
            kit.studioStation(own)
            let bounds = try XCTUnwrap(kit.mesh.bounds)
            XCTAssertGreaterThanOrEqual(bounds.min.x, 6 - 0.01, own.name)
            XCTAssertLessThan(bounds.min.x, 7 + 0.01, own.name)
            XCTAssertGreaterThan(bounds.max.z - bounds.min.z, bounds.max.x - bounds.min.x, own.name)
            XCTAssertEqual(bounds.min.y, 0.25, accuracy: 0.02, own.name)
            var far = StationKitBuilder()
            far.studioStation(own, far: true)
            let farBounds = try XCTUnwrap(far.mesh.bounds)
            XCTAssertEqual(farBounds.min.x, bounds.min.x, accuracy: 0.05, own.name)
            XCTAssertEqual(farBounds.max.z, bounds.max.z, accuracy: 0.05, own.name)
        }
    }
}
