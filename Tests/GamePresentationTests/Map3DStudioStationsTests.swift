@testable import GamePresentation
import GameCore
import XCTest

/// Decision 929: Pingxi's and Rinan's stations are the studio's own models;
/// decision 932: Jingtong's and Checheng's too; decision 937: Shanjia's and
/// Shifen's too; decision 945: Hexing's and Neiwan's too.
final class Map3DStudioStationsTests: XCTestCase {
    private func station(_ id: String) throws -> Map3DStationKit.Station {
        try XCTUnwrap(Map3DStationKit.stations.first { $0.id == id })
    }

    /// The same station under another id, so drawn by its profile's
    /// recipe: since decision 937 every `heritage` station of the catalog
    /// has the studio's model.
    private func recipeTwin(of id: String) throws -> Map3DStationKit.Station {
        let s = try station(id)
        return Map3DStationKit.Station(id: s.id + "-recipe", name: s.name, system: s.system, latitude: s.latitude,
                                       longitude: s.longitude, lines: s.lines, profile: s.profile, tier: s.tier,
                                       seed: s.seed, planned: s.planned, isLandmark: s.isLandmark)
    }

    /// Each model decodes at the studio's triangle counts and bounds, on
    /// the ground, in its palette's colours only.
    func testTheModelsDecode() throws {
        let expected: [Map3DStudioStation: (near: Int, far: Int, length: Float, height: Float)] = [
            .pingxi: (3452, 592, 26, 7.4), .rinan: (2956, 864, 16.4, 6.66),
            .shanjia: (3140, 476, 41.75, 18.5), .shifen: (2132, 640, 45, 6.25),
            .jingtong: (1612, 736, 19.02, 5.85), .checheng: (2980, 724, 25.68, 8.8),
            .hexing: (1476, 648, 12.06, 5.26), .neiwan: (1864, 748, 24.36, 9.04),
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
        XCTAssertEqual(try station("station-tra_sched-6dd93a9d").name, "山佳")
        XCTAssertEqual(try station("station-tra_sched-683ebb50").name, "十分")
        XCTAssertEqual(try station("station-tra_sched-b2e8d7d9").name, "菁桐")
        XCTAssertEqual(try station("station-tra_sched-49f63912").name, "車埕")
        XCTAssertEqual(try station("station-tra_sched-23c52cff").name, "合興")
        XCTAssertEqual(try station("station-tra_sched-9d27c592").name, "內灣")
        for own in Map3DStudioStation.allCases {
            var kit = StationKitBuilder()
            kit.house(try station(own.rawValue))
            XCTAssertEqual(kit.mesh.triangleCount, try XCTUnwrap(own.model()).triangleCount, own.name)
        }
        for own in Map3DStudioStation.allCases {
            var kit = StationKitBuilder()
            kit.house(try recipeTwin(of: own.rawValue))
            XCTAssertFalse(Map3DStudioStation.allCases.contains { $0.model()?.triangleCount == kit.mesh.triangleCount }, own.name)
        }
    }

    /// Decision 937: Shanjia and Shifen are no longer the kit's brick
    /// `heritage` recipe, which its other stations keep. Shanjia has the
    /// green glass clock tower far above the rest, the ochre old house in
    /// front; Shifen is long and low, the red brick gateway, the red-edged
    /// canopy and the grey-pink stone house its own; in the far versions
    /// too.
    func testShanjiaAndShifenAreNotTheHeritageRecipe() throws {
        for own in [Map3DStudioStation.shanjia, .shifen] {
            var recipe = StationKitBuilder()
            recipe.house(try recipeTwin(of: own.rawValue))
            let recipeBounds = try XCTUnwrap(recipe.mesh.bounds)
            XCTAssertEqual(try station(own.rawValue).profile, .heritage, own.name)
            var kit = StationKitBuilder()
            kit.house(try station(own.rawValue))
            XCTAssertNotEqual(kit.mesh.triangleCount, recipe.mesh.triangleCount, own.name)
            XCTAssertNotEqual(try XCTUnwrap(kit.mesh.bounds).max.y, recipeBounds.max.y, own.name)
        }
        for far in [false, true] {
            let shanjia = try XCTUnwrap(Map3DStudioStation.shanjia.model(far: far))
            let shifen = try XCTUnwrap(Map3DStudioStation.shifen.model(far: far))
            for colour in [Map3DPalette.gymGreen, Map3DPalette.plaza, Map3DPalette.counters[1]] {
                XCTAssertTrue(shanjia.vertices.contains { $0.color == colour }, "far \(far)")
            }
            for colour in [Map3DPalette.templeRidge, Map3DScene.Builder.barrierRed, Map3DPalette.stonePink] {
                XCTAssertTrue(shifen.vertices.contains { $0.color == colour }, "far \(far)")
            }
            XCTAssertFalse(shanjia.vertices.contains { $0.color == Map3DPalette.stonePink })
            XCTAssertFalse(shifen.vertices.contains { $0.color == Map3DPalette.schoolWalls })
            XCTAssertGreaterThan(shanjia.maximum.z, shifen.maximum.z * 2.5)
            // The tower's green glass runs from the ground to the fourth
            // floor, far above the old house's ridge.
            let green = shanjia.vertices.filter { $0.color == Map3DPalette.gymGreen }
            XCTAssertGreaterThan(green.map(\.z).max() ?? 0, 14)
            let ochre = shanjia.vertices.filter { $0.color == Map3DPalette.plaza }
            XCTAssertLessThan(ochre.map(\.z).max() ?? 99, 7)
        }
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

    /// Decision 945: Hexing and Neiwan are no longer the kit's `halt`,
    /// which the Neiwan Line's other stations keep. Hexing is the white
    /// boarded house with the red frames, blue plinth and boards and the
    /// dark fascia on its front gable; Neiwan the pale green tiled house
    /// with the white tower far above Hexing's ridge; in the far versions
    /// too, which the map draws for them rather than the halt's.
    func testHexingAndNeiwanAreNotTheHaltRecipe() throws {
        for own in [Map3DStudioStation.hexing, .neiwan] {
            XCTAssertEqual(try station(own.rawValue).profile, .halt, own.name)
            var recipe = StationKitBuilder()
            recipe.house(try recipeTwin(of: own.rawValue))
            var kit = StationKitBuilder()
            kit.house(try station(own.rawValue))
            XCTAssertNotEqual(kit.mesh.triangleCount, recipe.mesh.triangleCount, own.name)
        }
        for far in [false, true] {
            let hexing = try XCTUnwrap(Map3DStudioStation.hexing.model(far: far))
            let neiwan = try XCTUnwrap(Map3DStudioStation.neiwan.model(far: far))
            for colour in [Map3DPalette.tankWhite, Map3DContainerWagon.rust, Map3DPalette.cityRoofs[2].color,
                           Map3DPalette.hallRoofs[0], Map3DPalette.arcade] {
                XCTAssertTrue(hexing.vertices.contains { $0.color == colour }, "far \(far)")
            }
            for colour in [Map3DPalette.park, Map3DPalette.tankWhite, Map3DPalette.glazing, Map3DPalette.steel] {
                XCTAssertTrue(neiwan.vertices.contains { $0.color == colour }, "far \(far)")
            }
            XCTAssertFalse(hexing.vertices.contains { $0.color == Map3DPalette.park })
            XCTAssertFalse(neiwan.vertices.contains { $0.color == Map3DContainerWagon.rust })
            XCTAssertGreaterThan(neiwan.maximum.z, hexing.maximum.z + 3)
            // Neiwan's tower is the highest of it, in front of the house.
            let top = neiwan.vertices.filter { $0.z > 8.9 }
            XCTAssertFalse(top.isEmpty)
            XCTAssertLessThan(top.map(\.y).max() ?? 99, 0)
        }
        // Neiwan's dark timber doors and green frames close up.
        let neiwan = try XCTUnwrap(Map3DStudioStation.neiwan.model())
        for colour in [Map3DPalette.timberSiding, CableParts.Paint.green] {
            XCTAssertTrue(neiwan.vertices.contains { $0.color == colour })
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
