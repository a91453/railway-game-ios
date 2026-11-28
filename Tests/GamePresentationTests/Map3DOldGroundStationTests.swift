@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1042: a ground station in Japan from the earlier version's
/// general ground station, restyled as the game's.
final class Map3DOldGroundStationTests: XCTestCase {
    private typealias Old = Map3DOldGroundStation
    private typealias Builder = Map3DScene.Builder

    private func station(_ profile: Map3DStationKit.Profile, tier: Int) -> Map3DStationKit.Station {
        Map3DStationKit.Station(id: "s", name: "s", system: "player", latitude: 0, longitude: 0, lines: [],
                                profile: profile, tier: tier, seed: 0, planned: false, isLandmark: false)
    }

    /// Every model decodes in the palette's slots, the buildings at the
    /// studio's sizes (half the old ones) on the ground, each far one
    /// lighter; the restyle is there: the small one's green roof, each
    /// one's blue board, the middle one's green entrance canopy.
    func testTheModelsDecodeRestyled() throws {
        let lengths: [Old.Building: Float] = [.s: 18.22, .m: 39.44, .l: 58.86]
        for building in Old.Building.allCases {
            let near = try XCTUnwrap(Old.model(building.rawValue)), far = try XCTUnwrap(Old.model(building.rawValue, far: true))
            XCTAssertLessThan(far.triangleCount, near.triangleCount, building.rawValue)
            for model in [near, far] {
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.05)
                XCTAssertEqual(model.maximum.x - model.minimum.x, lengths[building]!, accuracy: 0.1)
                XCTAssertTrue(model.vertices.allSatisfy { Old.meshPalette.contains($0.color) })
            }
            XCTAssertTrue(near.vertices.contains { $0.color == Map3DPalette.canopy && $0.z > 4 }, "\(building) name board")
        }
        let small = try XCTUnwrap(Old.model("s"))
        XCTAssertTrue(small.vertices.contains { $0.color == Map3DPalette.gymGreen && $0.z > 5 }, "the green roof")
        XCTAssertFalse(small.vertices.contains { $0.color == Map3DPalette.timberSiding && $0.z > 4.5 }, "no brown roof")
        let middle = try XCTUnwrap(Old.model("m"))
        XCTAssertTrue(middle.vertices.contains { $0.color == Map3DPalette.gymGreen && $0.z > 3 && $0.y < -9 }, "the entrance canopy")
        for name in ["canopy-side", "canopy-island", "end-side"] { XCTAssertNotNil(Old.model(name), name) }
        XCTAssertTrue(Old.railing.allSatisfy { $0.color == Map3DPalette.platformEdge })
    }

    /// One platform keeps the wooden station, two the small one, three
    /// or more or a bigger concourse the middle one, a big station the big
    /// one; a halt its shelter.
    func testWhichBuilding() {
        XCTAssertNil(Old.building(profile: .regional, tier: 3, expansion: nil))
        XCTAssertEqual(Old.building(profile: .regional, tier: 2, expansion: nil), .s)
        XCTAssertEqual(Old.building(profile: .regional, tier: 1, expansion: nil), .m)
        XCTAssertEqual(Old.building(profile: .regional, tier: 0, expansion: nil), .m)
        XCTAssertEqual(Old.building(profile: .regional, tier: 3, expansion: .concourse), .m)
        XCTAssertEqual(Old.building(profile: .regional, tier: 2, expansion: .hall), .l)
        XCTAssertNil(Old.building(profile: .halt, tier: 3, expansion: nil))
    }

    /// In Japan the kit draws the building alone (no Taiwan wings), its
    /// back at x 7 by the platforms; in Taiwan nothing changes.
    func testTheKitDrawsItInJapanOnly() throws {
        for (tier, expansion, building) in [(2, nil, Old.Building.s), (1, nil, .m), (2, StationExpansion.hall, .l)] {
            var japan = StationKitBuilder(), taiwan = StationKitBuilder()
            japan.japanese = true
            japan.genericHouse(station(.regional, tier: tier), expansion: expansion)
            taiwan.genericHouse(station(.regional, tier: tier), expansion: expansion)
            XCTAssertEqual(japan.mesh.triangleCount, Old.model(building.rawValue)!.triangleCount)
            XCTAssertNotEqual(taiwan.mesh.triangleCount, japan.mesh.triangleCount)
            XCTAssertEqual(try XCTUnwrap(japan.mesh.bounds).min.x, 7, accuracy: 0.05)
            var far = StationKitBuilder()
            far.japanese = true
            far.genericHouse(station(.regional, tier: tier), expansion: expansion, far: true)
            XCTAssertEqual(far.mesh.triangleCount, Old.model(building.rawValue, far: true)!.triangleCount)
        }
        var wooden = StationKitBuilder()
        wooden.japanese = true
        wooden.genericHouse(station(.regional, tier: 3), expansion: nil)
        XCTAssertEqual(wooden.mesh.triangleCount, Map3DJapanStation.model()!.triangleCount, "one platform: the wooden one")
    }

    /// 200 m with the middle three fifths roofed: six units of 20 m (a
    /// little longer, to meet on a curve), a post at each one's start and
    /// the last one's closing post.
    func testTheCanopysPosts() {
        let units = Old.units(length: 200, share: 0.6)
        XCTAssertEqual(units.count, 6)
        XCTAssertEqual(units.step, 20, accuracy: 0.001)
        let posts = Old.posts(length: 200, share: 0.6)
        XCTAssertEqual(posts.count, 7)
        XCTAssertEqual(posts.first ?? 0, 40 + 10 - 9.6 * units.stretch, accuracy: 0.001)
        XCTAssertEqual(posts.last ?? 0, 160 - 10 + 9.6 * units.stretch, accuracy: 0.001)
    }

    private func japan() throws -> GameWorld {
        GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 33.5897, longitudeDegrees: 130.4207)))
    }

    private func builder(_ world: GameWorld, platforms: [Builder.LaidPlatform]) -> Builder {
        var builder = Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                              world: world)
        builder.state.platforms.laidPlatforms = platforms
        builder.state.stations.stationSystems[StationID(rawValue: 1)] = "tra_sched"
        return builder
    }

    private func line(z: Float) -> [Map3DPoint] {
        stride(from: Float(-100), through: 100, by: 20).map { Map3DPoint($0, Map3DScene.railLift, z) }
    }

    /// A side platform 200 m long in Japan: the old canopy over its
    /// middle, its roof 3.96 to 4.40 m over the platform and over it
    /// (not the track), a post at each unit's start and the end's; the
    /// lamps under that roof; the railing across each end.
    func testASidePlatformTakesTheOldCanopyAndRailings() throws {
        let side = Builder.LaidPlatform(station: StationID(rawValue: 1), line: line(z: 0), offset: 3.2, width: 3.2, structure: .surface)
        var b = builder(try japan(), platforms: [side])
        XCTAssertTrue(b.oldCanopy(side))
        b.addOldCanopy(on: 0, of: [side])
        let top = Map3DScene.railLift + Builder.platformHeight
        let near = b.nearMeshes.values.flatMap(\.vertices)
        let roof = near.filter { $0.color == Map3DPalette.canopy }
        XCTAssertFalse(roof.isEmpty)
        XCTAssertTrue(roof.allSatisfy { $0.y >= top + 3.95 && $0.y <= top + 4.41 && $0.x >= -60.5 && $0.x <= 60.5 })
        // Across: the model's y −1.54 to 1.34, its track side (+y) by the track at z 1.6.
        XCTAssertEqual(roof.map(\.z).min() ?? 0, 3.2 - 1.34, accuracy: 0.01)
        XCTAssertEqual(roof.map(\.z).max() ?? 0, 3.2 + 1.54, accuracy: 0.01)
        let feet = near.filter { $0.color == Map3DPalette.roofSlate && $0.y < top + 0.01 }.map(\.x).sorted()
        XCTAssertEqual(zip(feet, feet.dropFirst()).filter { $1 - $0 > 1 }.count + 1, 7, "six posts and the closing one")
        // Taiwan's kit canopy keeps its own lamps; Japan's hang under the old roof.
        b.addPlatformProps()
        let lamps = b.closeMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.tunnelLamp }
        XCTAssertFalse(lamps.isEmpty)
        XCTAssertTrue(lamps.allSatisfy { $0.y >= top + Old.lampHeight - 0.01 && $0.y < top + 3.96 })
        // (The hung signs' yellow is in the middle; the ends are the railing's.)
        let railing = b.closeMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.platformEdge && abs($0.x) > 95 }
        XCTAssertFalse(railing.isEmpty)
        XCTAssertTrue(railing.allSatisfy { abs(abs($0.x) - 99.7) < 0.06 && $0.y <= top + 1.11 && $0.z > 1.6 && $0.z < 4.8 })
        XCTAssertTrue(railing.contains { $0.x < 0 } && railing.contains { $0.x > 0 }, "at both ends")
        var taiwan = builder(.newGame(), platforms: [side])
        XCTAssertFalse(taiwan.oldCanopy(side))
        taiwan.addPlatformProps()
        XCTAssertTrue(taiwan.closeMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.tunnelLamp }
            .allSatisfy { $0.y < top + 3.2 })
    }

    /// An island's two halves take one island canopy, from the half laid
    /// first, as wide as the island and over its middle; the other half
    /// draws none.
    func testAnIslandTakesOneIslandCanopy() throws {
        let a = Builder.LaidPlatform(station: StationID(rawValue: 1), line: line(z: -5.5), offset: 3.55, width: 3.9, structure: .surface,
                                     island: true)
        let b = Builder.LaidPlatform(station: StationID(rawValue: 1), line: line(z: 5.5), offset: -3.55, width: 3.9, structure: .surface,
                                     island: true)
        var first = builder(try japan(), platforms: [a, b])
        first.addOldCanopy(on: 0, of: [a, b])
        let roof = first.nearMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.canopy }
        XCTAssertEqual(roof.map(\.z).min() ?? 0, -3, accuracy: 0.01)
        XCTAssertEqual(roof.map(\.z).max() ?? 0, 3, accuracy: 0.01)
        var second = builder(try japan(), platforms: [a, b])
        second.addOldCanopy(on: 1, of: [a, b])
        XCTAssertTrue(second.nearMeshes.values.allSatisfy { $0.vertices.isEmpty })
    }
}
