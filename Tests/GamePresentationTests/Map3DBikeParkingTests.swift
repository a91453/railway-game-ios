import XCTest
import GameCore
@testable import GamePresentation

/// Decision 949: the kits' bicycle rack and shed on the 3D map, and the
/// bicycles in them.
final class Map3DBikeParkingTests: XCTestCase {
    private typealias Unit = Map3DBikeParking.Unit

    /// Both kit parts are in the pack, as small as the kits make them.
    func testTheModelsAreInThePack() throws {
        XCTAssertEqual(Map3DBikeParking.drawn.map(\.name), Unit.allCases.map(\.rawValue))
        XCTAssertEqual(Set(Map3DScene.Builder.bikeParkingModels.keys), Set(Unit.allCases))
        let rack = Map3DBikeParking.model(.rack), shed = Map3DBikeParking.model(.shed)
        XCTAssertLessThan(rack.triangleCount, 200)
        XCTAssertLessThan(shed.triangleCount, 200)
        XCTAssertLessThan(rack.maximum.z, 1)
        XCTAssertLessThan(shed.maximum.z, 2.7)
    }

    /// One bicycle beside each hoop, three at most, their 0.62 m
    /// handlebars clear of each other and within the rack's length.
    func testTheRackHoldsThree() {
        XCTAssertEqual(Map3DBikeParking.inRack(5).count, 3)
        XCTAssertEqual(Map3DBikeParking.inRack(0), [])
        let three = Map3DBikeParking.inRack(3)
        for (a, b) in zip(three, three.dropFirst()) { XCTAssertGreaterThan(b - a, 0.62) }
        let rack = Map3DBikeParking.model(.rack)
        XCTAssertTrue(three.allSatisfy { abs($0) <= Double(rack.maximum.y) + 0.31 })
    }

    /// Most of Taiwan's exits, few of Hong Kong's; public bicycles only in
    /// Taiwan; the rack and its bicycles clear of the exit's side.
    func testByTheExits() throws {
        XCTAssertGreaterThan(Map3DStreetRegion.taiwan.exitRackShare, 0.5)
        XCTAssertLessThan(Map3DStreetRegion.hongKong.exitRackShare, 0.2)
        XCTAssertLessThan(Map3DStreetRegion.hongKong.stopRackShare, Map3DStreetRegion.taiwan.stopRackShare)
        XCTAssertNil(Map3DBikeParking.exitRack(width: 3.5, length: 5, region: .hongKong, random: (0.3, 0, 0)))
        let docked = try XCTUnwrap(Map3DBikeParking.exitRack(width: 3.5, length: 5, region: .taiwan, random: (0.3, 0.1, 0)))
        XCTAssertEqual(docked.bicycles, [.publicBike, .publicBike, .publicBike])
        let hongKong = try XCTUnwrap(Map3DBikeParking.exitRack(width: 3.5, length: 5, region: .hongKong, random: (0.1, 0.1, 0)))
        XCTAssertEqual(hongKong.bicycles, [.bicycle, .bicycle])
        // A bicycle's 0.9 m half length past the exit's side, with room.
        XCTAssertGreaterThanOrEqual(docked.aside - 0.9 - 3.5 / 2, 0.3)
    }

    /// The shed's bicycles stand under its roof, each in a wheel stop,
    /// facing back; the company's schools and night markets have a shed
    /// or a rack with bicycles in it.
    func testTheShedsBicycles() throws {
        let shed = Map3DBikeParking.shed(x: 0, right: 0), model = Map3DBikeParking.model(.shed)
        XCTAssertEqual(shed.bicycles.count, Map3DBikeParking.shedSlots.count)
        for bicycle in shed.bicycles {
            XCTAssertTrue(bicycle.backward)
            XCTAssertLessThanOrEqual(abs(bicycle.x) + 0.9, model.maximum.x)
            XCTAssertLessThanOrEqual(abs(bicycle.right) + 0.31, model.maximum.y)
        }
        for kind in [PlacedBuildingKind.school, .nightMarket] {
            for layout in try XCTUnwrap(Map3DScene.Builder.placedKitLayouts[kind]) {
                XCTAssertFalse(layout.bicycles.isEmpty, "\(kind)")
                let half = Float(Double(kind.side) / Map3DScene.Builder.metre) / 2
                XCTAssertTrue(layout.bicycles.allSatisfy { abs($0.x) + 0.9 <= half && abs($0.right) + 0.31 <= half }, "\(kind) inside its square")
            }
        }
    }
}

/// Decision 949: the racks stand beside a viaduct station's stair
/// entrances, each with its bicycles beside it, more in Taiwan than in
/// Hong Kong.
final class Map3DBikeParkingSceneTests: XCTestCase {
    /// The props of a viaduct station with one 120 m platform along x,
    /// `shift` metres along, on `region`'s streets.
    private func props(shift: Float, region: Map3DStreetRegion) -> [Map3DInstance] {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                                         world: .newGame())
        builder.streetLife.region = region
        let line = stride(from: Float(-60), through: 60, by: 2).map { Map3DPoint($0 + shift, Map3DScene.railLift, 0) }
        builder.laidPlatforms = [Map3DScene.Builder.LaidPlatform(station: StationID(rawValue: 7), line: line, offset: 3.5, width: 3.2,
                                                                 structure: .elevated)]
        builder.trackLines = [(line, TrackSectionKind.surface)]
        _ = builder.addStations(GameWorld.newGame().railwaySnapshot(), frame: nil)
        return builder.props.values.flatMap { $0 }
    }

    func testBesideTheStairEntrances() throws {
        let rack = try XCTUnwrap(Map3DScene.Builder.bikeParkingModels[.rack])
        let bicycles = Set(Map3DScene.Builder.bicycleModels.values)
        var counts: [Map3DStreetRegion: Int] = [:]
        for region in [Map3DStreetRegion.taiwan, .hongKong] {
            for shift in stride(from: Float(0), to: 120, by: 10) {
                let props = props(shift: shift, region: region)
                let racks = props.filter { $0.model == rack }
                counts[region, default: 0] += racks.count
                for instance in racks {
                    let near = props.filter { bicycles.contains($0.model) }.filter {
                        let dx = $0.transform[12] - instance.transform[12], dz = $0.transform[14] - instance.transform[14]
                        return dx * dx + dz * dz < 2.5 * 2.5
                    }
                    XCTAssertTrue((2...3).contains(near.count), "\(near.count) by a rack")
                    // Away from the viaduct, past the stairs' side.
                    XCTAssertGreaterThan(abs(instance.transform[14]), 3.5 + 1.6 + 3 + 1.75 + 1.2)
                }
            }
        }
        XCTAssertGreaterThan(counts[.taiwan] ?? 0, 8, "most of 24 entrances")
        XCTAssertLessThan(counts[.hongKong] ?? 0, counts[.taiwan] ?? 0)
    }
}
