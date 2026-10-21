import Foundation
@testable import GamePresentation
import XCTest

/// The 3D map's city buses: the Meshy model the app bundles, fitted to a
/// real bus and lit at night, in the box-built bus's place; and where they
/// run.
final class Map3DCityBusTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let bundled = root.appendingPathComponent("RailwayGameApp/Resources/Models/city-bus.m3dmodel")

    /// The app's copy is the converted model of the art folder, byte for
    /// byte.
    func testTheAppBundlesTheConvertedBus() throws {
        let art = Self.root.appendingPathComponent("docs/art/meshy-city-bus-2026-10-18/city-bus.m3dmodel")
        XCTAssertEqual(try Data(contentsOf: Self.bundled), try Data(contentsOf: art))
    }

    /// Read from the file, the bus takes the box-built one's place, at its
    /// index: 12 × 2.5 × 3.3 m, its middle at the origin and its wheels on
    /// the ground, the generated model's 1,543 triangles and the lamps.
    func testTheBusFromItsFileIsFittedAndLit() throws {
        let pack = Map3DCityBus.pack(file: Self.bundled)
        let index = try XCTUnwrap(Map3DModelPack.standard.index(of: Map3DStreetModel.bus.modelName))
        XCTAssertEqual(pack.models.count, Map3DModelPack.standard.models.count)
        XCTAssertEqual(pack.index(of: Map3DStreetModel.bus.modelName), index)
        let bus = pack.models[index]
        XCTAssertEqual(bus.length, 12, accuracy: 0.11, "the lamps stand 0.05 m proud")
        XCTAssertEqual(bus.maximum.y - bus.minimum.y, 2.5, accuracy: 0.01)
        XCTAssertEqual(bus.maximum.z, 3.3, accuracy: 0.01)
        XCTAssertEqual(bus.minimum.z, 0, accuracy: 0.01)
        XCTAssertEqual(bus.minimum.x + bus.maximum.x, 0, accuracy: 0.01)
        let lamps = bus.vertices.filter(\.glows)
        XCTAssertEqual(lamps.count, 5 * 10 * 3, "two headlamps, two tail lamps and the board, a box with no bottom each")
        XCTAssertEqual(bus.triangleCount, 1_543 + lamps.count / 3)
        XCTAssertTrue(bus.vertices.contains { $0.color >> 24 == 0 }, "its paint takes the instance's colour")
        for vertex in bus.vertices {
            XCTAssertEqual(Map3DPoint(vertex.nx, vertex.ny, vertex.nz).length, 1, accuracy: 1e-3)
        }
        // Every other model is the standard pack's.
        for (other, standard) in zip(pack.models, Map3DModelPack.standard.models) where standard.name != bus.name {
            XCTAssertEqual(other.vertices, standard.vertices, other.name)
        }
    }

    /// With no file, or one that cannot be read, the box-built bus stays.
    func testWithoutItsFileTheBoxBuiltBusStays() throws {
        let index = try XCTUnwrap(Map3DModelPack.standard.index(of: Map3DStreetModel.bus.modelName))
        let box = Map3DModelPack.standard.models[index]
        XCTAssertLessThan(box.triangleCount, 200)
        XCTAssertTrue(box.vertices.contains(where: \.glows))
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-bus-\(UUID()).m3dmodel")
        try Data("M3DM".utf8).write(to: broken)
        defer { try? FileManager.default.removeItem(at: broken) }
        for url in [nil, broken, broken.appendingPathExtension("missing")] {
            XCTAssertEqual(Map3DCityBus.pack(file: url).models[index].vertices, box.vertices)
        }
    }

    /// On a road buses run on, about one vehicle in twenty is a bus, in a
    /// bus's paint, and none comes within a bus's length and a car's of the
    /// next; a road they do not run on has none.
    func testBusesRunOnMainRoadsKeepingApart() throws {
        let path = try XCTUnwrap(Map3DStreetLife.Path([Map3DPoint(0, 0, 0), Map3DPoint(2_000, 0, 0)]))
        let busIndex = try XCTUnwrap(Map3DStreetLife.models[.bus])
        var life = Map3DStreetLife()
        life.lanes = [Map3DStreetLife.Lane(path: path, half: 6, twoWay: true, speed: 11, perHundred: 5, scooters: true, seed: (3, 4), buses: true)]
        var buses = 0, vehicles = 0
        for time in stride(from: 0.0, to: 600, by: 60) {
            let frame = life.frame(target: Map3DPoint(1_000, 0, 0), distance: 1_200, time: time, detail: .full, activity: .init())
            XCTAssertEqual(frame.buses, frame.instances.filter { $0.model == busIndex }.count)
            XCTAssertLessThanOrEqual(frame.buses, Map3DStreetLife.mostBuses)
            buses += frame.buses
            vehicles += frame.vehicles
            for direction: Float in [1, -1] {
                let ahead = frame.instances.filter { $0.transform[0] * direction > 0.5 }.map { ($0.transform[12], $0.model == busIndex) }
                    .sorted { $0.0 < $1.0 }
                for (a, b) in zip(ahead, ahead.dropFirst()) where a.1 || b.1 {
                    XCTAssertGreaterThan(b.0 - a.0, 8.3, "a bus's half and a car's")
                }
            }
            for bus in frame.instances where bus.model == busIndex {
                let paint = (UInt32((bus.stripe.0 * 255).rounded()), UInt32((bus.stripe.1 * 255).rounded()), UInt32((bus.stripe.2 * 255).rounded()))
                XCTAssertTrue(Map3DStreetLife.busPaints.contains { ($0 & 0xFF, $0 >> 8 & 0xFF, $0 >> 16 & 0xFF) == paint })
            }
        }
        XCTAssertGreaterThan(buses, 0)
        XCTAssertEqual(Double(buses) / Double(vehicles), Double(Map3DStreetLife.busShare), accuracy: 0.03)

        life.lanes = [Map3DStreetLife.Lane(path: path, half: 6, twoWay: true, speed: 11, perHundred: 5, scooters: true, seed: (3, 4))]
        let none = life.frame(target: Map3DPoint(1_000, 0, 0), distance: 1_200, time: 0, detail: .full, activity: .init())
        XCTAssertGreaterThan(none.vehicles, 50)
        XCTAssertEqual(none.buses, 0)
    }

    /// Buses run on the trunk, primary and secondary roads.
    func testTheRoadsBusesRunOn() {
        XCTAssertEqual(Map3DScene.Builder.busRoutes, [.trunk, .primary, .secondary])
    }
}
