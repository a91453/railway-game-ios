@testable import GamePresentation
import GameCore
import XCTest

/// Decision 933: a small station in Hong Kong is the studio's new-town
/// station of the East Rail line.
final class Map3DHongKongStationTests: XCTestCase {
    private func station(_ profile: Map3DStationKit.Profile, tier: Int = 3) -> Map3DStationKit.Station {
        Map3DStationKit.Station(id: "s", name: "s", system: "player", latitude: 0, longitude: 0, lines: [],
                                profile: profile, tier: tier, seed: 0, planned: false, isLandmark: false)
    }

    /// Each of the three, near and far, decodes at the studio's size and
    /// triangle counts, stands on the ground, has its platform-side wall
    /// where Taiwan's has its back and uses only the palette's slots.
    func testTheModelsDecode() throws {
        typealias Expected = (near: Int, far: Int, length: Float, front: Float, eave: Float, height: Float)
        let expected: [Map3DGenericStation.Model: Expected] = [
            .oneFloor: (666, 296, 24.85, -9, 6.7, 12),
            .twoFloor: (1232, 330, 30.45, -9, 6.45, 11.95),
            .halt: (1108, 236, 12.2, -5.5, 3.05, 9.5),
        ]
        XCTAssertEqual(Set(Map3DHongKongStation.models), Set(expected.keys))
        for (kind, want) in expected {
            let near = try XCTUnwrap(Map3DHongKongStation.model(kind), kind.rawValue)
            let far = try XCTUnwrap(Map3DHongKongStation.model(kind, far: true), kind.rawValue)
            XCTAssertEqual(near.triangleCount, want.near, kind.rawValue)
            XCTAssertEqual(far.triangleCount, want.far, kind.rawValue)
            for model in [near, far] {
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.02, kind.rawValue)
                XCTAssertEqual(model.maximum.z, want.height, accuracy: 0.02, kind.rawValue)
                XCTAssertEqual(model.maximum.x - model.minimum.x, want.length, accuracy: 0.02, kind.rawValue)
                XCTAssertEqual(model.minimum.y, want.front, accuracy: 0.02, "\(kind.rawValue): the walkway or canopy at the front")
                XCTAssertEqual(model.maximum.y, want.eave, accuracy: 0.02, "\(kind.rawValue): the eave over the platform side")
                XCTAssertTrue(model.vertices.allSatisfy { Map3DHongKongStation.meshPalette.contains($0.color) }, kind.rawValue)
            }
        }
        XCTAssertNil(Map3DHongKongStation.model(.wing1), "the wings are Taiwan's still")
        XCTAssertEqual(Map3DHongKongStation.meshPalette.count, 13)
    }

    /// What tells the three apart, and from Taiwan's: grey-green walls on
    /// the one-floor one, cream walls and brick-red panels on the
    /// two-floor one, a silver barrel roof and a green belt on the halt;
    /// none of Taiwan's green canopy on the bigger two or its blue band on
    /// any.
    func testTheirColours() throws {
        let green = Map3DHongKong.tenementWalls[8], cream = Map3DHongKong.civicWalls[1], grey = Map3DHongKong.civicWalls[3]
        func colours(_ kind: Map3DGenericStation.Model, far: Bool) throws -> Set<UInt32> {
            Set(try XCTUnwrap(Map3DHongKongStation.model(kind, far: far)).vertices.map(\.color))
        }
        for far in [false, true] {
            let one = try colours(.oneFloor, far: far), two = try colours(.twoFloor, far: far), halt = try colours(.halt, far: far)
            XCTAssertTrue(one.contains(green) && !one.contains(cream) && !one.contains(grey))
            XCTAssertTrue(two.contains(cream) && !two.contains(green) && !two.contains(grey))
            XCTAssertTrue(halt.contains(grey) && !halt.contains(green) && !halt.contains(cream))
            XCTAssertTrue(one.contains(Map3DPalette.brick) && two.contains(Map3DPalette.brick), "the walkway's red edge")
            XCTAssertTrue(one.contains(Map3DPalette.glazing) && two.contains(Map3DPalette.glazing), "the footbridge head's glass")
            XCTAssertTrue(halt.contains(Map3DPalette.mtrRoofSilver) && halt.contains(Map3DPalette.gymGreen), "the barrel roof and its belt")
            for set in [one, two] { XCTAssertFalse(set.contains(Map3DPalette.gymGreen)) }
            for set in [one, two, halt] { XCTAssertFalse(set.contains(Map3DPalette.canopy)) }
        }
    }

    /// A regional station or a halt not yet expanded is Hong Kong's, by
    /// the rule that picks Taiwan's (the halt, two floors for two
    /// platforms or more, one floor for the rest), and only in Hong Kong.
    func testWhichStationsAreHongKongs() throws {
        XCTAssertTrue(Map3DHongKongStation.replaces(profile: .regional, expansion: nil))
        XCTAssertTrue(Map3DHongKongStation.replaces(profile: .halt, expansion: nil))
        XCTAssertFalse(Map3DHongKongStation.replaces(profile: .regional, expansion: .hall))
        XCTAssertFalse(Map3DHongKongStation.replaces(profile: .elevated, expansion: nil))
        let cases: [(Map3DStationKit.Profile, Int, Map3DGenericStation.Model)] = [
            (.regional, 3, .oneFloor), (.regional, 2, .twoFloor), (.regional, 0, .twoFloor), (.halt, 3, .halt),
        ]
        for (profile, tier, kind) in cases {
            for far in [false, true] {
                var hongKong = StationKitBuilder(), taiwan = StationKitBuilder()
                hongKong.hongKong = true
                hongKong.genericHouse(station(profile, tier: tier), expansion: nil, far: far)
                taiwan.genericHouse(station(profile, tier: tier), expansion: nil, far: far)
                let model = try XCTUnwrap(Map3DHongKongStation.model(kind, far: far))
                XCTAssertEqual(hongKong.mesh.triangleCount, model.triangleCount, "\(profile) tier \(tier)")
                XCTAssertNotEqual(taiwan.mesh.triangleCount, hongKong.mesh.triangleCount, "\(profile) tier \(tier)")
                XCTAssertTrue(hongKong.mesh.vertices.allSatisfy { Map3DHongKongStation.meshPalette.contains($0.color) })
            }
        }
        var expanded = StationKitBuilder(), plain = StationKitBuilder()
        expanded.hongKong = true
        expanded.genericHouse(station(.regional), expansion: .hall)
        plain.genericHouse(station(.regional), expansion: .hall)
        XCTAssertEqual(expanded.mesh.triangleCount, plain.mesh.triangleCount, "an expanded one keeps Taiwan's building and wings")
    }

    /// Its platform-side wall on x 7, the line the generic station's back
    /// wall stands on, only its eave over it; its long side along the
    /// platforms; its covered walkway (the halt's canopy) at the front.
    func testItFacesAwayFromItsPlatforms() throws {
        let cases: [(Map3DStationKit.Profile, Int, Float, Float)] = [
            (.regional, 3, 6.3, 22), (.regional, 1, 6.55, 22), (.halt, 3, 6.95, 15.5),
        ]
        for (profile, tier, back, front) in cases {
            var kit = StationKitBuilder()
            kit.hongKong = true
            kit.genericHouse(station(profile, tier: tier), expansion: nil)
            let bounds = try XCTUnwrap(kit.mesh.bounds)
            XCTAssertEqual(bounds.min.x, back, accuracy: 0.02, "\(profile) tier \(tier)")
            XCTAssertEqual(bounds.max.x, front, accuracy: 0.02, "\(profile) tier \(tier)")
            XCTAssertGreaterThan(bounds.max.z - bounds.min.z, 12, "\(profile) tier \(tier)")
            XCTAssertEqual(bounds.min.y, 0.25, accuracy: 0.02, "\(profile) tier \(tier)")
            // Nothing below 2.8 m stands past the platform-side wall
            // (the brief's clearance line).
            let low = kit.mesh.vertices.filter { $0.y < 0.25 + 2.8 }.map(\.x).min() ?? 7
            XCTAssertGreaterThanOrEqual(low, 7 - 0.01, "\(profile) tier \(tier)")
        }
    }

    /// The footbridge head's opening is in the platform-side wall at the
    /// studio's place: a dark plug a tenth of a metre inside it, 2.4 m
    /// wide, its floor 6.5 m and its head 9 m above the model's ground.
    func testTheFootbridgeOpening() throws {
        let centres: [Map3DGenericStation.Model: Float] = [.oneFloor: -9.7, .twoFloor: 13.4, .halt: 0]
        for (kind, centre) in centres {
            let model = try XCTUnwrap(Map3DHongKongStation.model(kind))
            let wall: Float = kind == .halt ? 3 : 6
            let plug = model.vertices.filter {
                $0.color == Map3DPalette.dark && abs($0.y - (wall - 0.1)) < 0.005 && abs($0.x - centre) < 1.21 && $0.z > 6.4 && $0.z < 9.1
            }
            XCTAssertFalse(plug.isEmpty, kind.rawValue)
            XCTAssertEqual(plug.map(\.x).min() ?? 0, centre - 1.2, accuracy: 0.02, kind.rawValue)
            XCTAssertEqual(plug.map(\.x).max() ?? 0, centre + 1.2, accuracy: 0.02, kind.rawValue)
            XCTAssertEqual(plug.map(\.z).min() ?? 0, 6.5, accuracy: 0.02, kind.rawValue)
            XCTAssertEqual(plug.map(\.z).max() ?? 0, 9, accuracy: 0.02, kind.rawValue)
        }
    }
}
