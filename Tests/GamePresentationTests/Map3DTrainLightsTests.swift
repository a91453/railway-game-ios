import GameCore
import XCTest
@testable import GamePresentation

/// Decision 449: every train's headlamps at its front, its tail lamps at
/// its back and its windows lit at night, the same way on every set.
final class Map3DTrainLightsTests: XCTestCase {
    private let pack = Map3DModelPack.standard

    private func lit(_ keys: [String], lights: Float = 1) -> (rows: [Map3DShowcase.Row], before: Map3DTrains.Frame, after: Map3DTrains.Frame) {
        let rows = Map3DShowcase.layout(keys: keys)
        let before = Map3DShowcase.frame(rows, pack: pack)
        var after = before
        Map3DTrainLights.add(to: &after, pack: pack, lights: lights)
        return (rows, before, after)
    }

    func testEveryTrainIsWhiteAtItsFrontAndRedAtItsBack() {
        for entry in Map3DShowcase.catalog {
            let (rows, before, after) = lit([entry.key])
            let row = rows[0]
            let added = after.boxes.vertices.dropFirst(before.boxes.vertices.count)
            XCTAssertTrue(added.allSatisfy { $0.glows }, entry.key)
            let red = added.filter { Map3DTrainLights.isRed($0.color) }, white = added.filter { !Map3DTrainLights.isRed($0.color) }
            XCTAssertFalse(white.isEmpty, "\(entry.key): headlamps")
            XCTAssertFalse(red.isEmpty, "\(entry.key): tail lamps")
            let head = row.cars[0], last = row.cars[row.cars.count - 1]
            let headMiddle = (head.front.x + head.back.x) / 2, lastMiddle = (last.front.x + last.back.x) / 2
            for vertex in white { XCTAssertGreaterThan(vertex.x, headMiddle, "\(entry.key): a headlamp behind its first car's middle") }
            for vertex in red { XCTAssertLessThan(vertex.x, lastMiddle, "\(entry.key): a tail lamp ahead of its last car's middle") }
        }
    }

    func testPushPullSetsHaveAPowerCarTurnedAtTheBack() {
        for key in ["pushPull", "pushPullE1000"] {
            let row = Map3DShowcase.layout(keys: [key])[0]
            XCTAssertTrue(pack.isTurned(forType: key, carIndex: row.cars.count - 1, count: row.cars.count), key)
            let last = row.cars[row.cars.count - 1]
            XCTAssertLessThan(last.front.x, last.back.x, "\(key): its back power car faces backward")
            XCTAssertEqual(last.model, row.cars[0].model, "\(key): the same power car as at the front")
        }
    }

    func testACabTurnedRoundShowsRedWhereItsHeadlampsAre() throws {
        for name in ["commuter-cab", "set-emu800-head", "set-pushPull-head"] {
            let index = try XCTUnwrap(pack.index(of: name))
            let car = try XCTUnwrap(pack.lights[index], name)
            XCTAssertFalse(car.front.tail.isEmpty, name)
            XCTAssertTrue(car.front.tail.allSatisfy { Map3DTrainLights.isRed($0.color) && $0.glows }, name)
            XCTAssertTrue(car.front.head.allSatisfy { !Map3DTrainLights.isRed($0.color) && $0.glows }, name)
            XCTAssertTrue(car.front.head.allSatisfy { $0.x > 0 }, name)
        }
    }

    func testNothingIsAddedByDay() {
        let (_, before, after) = lit(Map3DShowcase.defaultKeys, lights: 0)
        XCTAssertEqual(after.instances.map(\.model), before.instances.map(\.model))
        XCTAssertEqual(after.boxes.vertices, before.boxes.vertices)
    }

    func testTheWindowsComeUpWithTheCitysLights() throws {
        let (_, before, after) = lit(Map3DShowcase.defaultKeys, lights: 0.5)
        let windows = after.instances.dropFirst(before.instances.count)
        XCTAssertFalse(windows.isEmpty)
        let saloon = Map3DTrainLights.saloon
        let half = (Float(saloon & 0xFF) / 255 * 0.5, Float((saloon >> 8) & 0xFF) / 255 * 0.5, Float((saloon >> 16) & 0xFF) / 255 * 0.5)
        for window in windows {
            XCTAssertTrue(pack.models[window.model].name.hasPrefix(Map3DTrainLights.prefix))
            XCTAssertEqual(window.stripe.0, half.0, accuracy: 1e-5)
            XCTAssertEqual(window.stripe.1, half.1, accuracy: 1e-5)
            XCTAssertEqual(window.stripe.2, half.2, accuracy: 1e-5)
            let car = try XCTUnwrap(before.instances.first { $0.transform == window.transform })
            XCTAssertEqual(pack.lights[car.model]?.windows, window.model)
        }
    }

    func testNoRunningCarLightsItselfAndEveryWindowIsLitGlass() {
        XCTAssertFalse(pack.lights.isEmpty)
        for (index, car) in pack.lights {
            let model = pack.models[index]
            XCTAssertTrue(Map3DTrainLights.isRunning(model.name), model.name)
            XCTAssertFalse(model.vertices.contains(where: \.glows), "\(model.name): lit only at its train's ends")
            guard let windows = car.windows else { continue }
            let panes = pack.models[windows]
            XCTAssertEqual(panes.name, Map3DTrainLights.prefix + model.name)
            XCTAssertEqual(panes.vertices.count % 3, 0)
            XCTAssertTrue(panes.vertices.allSatisfy { $0.glows && $0.color == 0 }, panes.name)
        }
        // The saloons the game runs most have windows.
        for name in ["commuter-car", "set-emu800-car", "set-emu3000-car", "set-puyuma-car", "set-E500CK-tail"] {
            XCTAssertNotNil(pack.index(of: name).flatMap { pack.lights[$0]?.windows }, name)
        }
    }

    /// Replacing the bus or the trucks (what the app does with its model
    /// files) leaves the trains' lamps and windows in the pack.
    func testReplacingAModelKeepsTheTrainLights() throws {
        XCTAssertFalse(pack.lights.isEmpty)
        let bus = try XCTUnwrap(pack.index(of: Map3DStreetModel.bus.modelName))
        let replaced = pack.replacing(pack.models[bus])
        XCTAssertEqual(replaced.lights.keys.sorted(), pack.lights.keys.sorted())
        XCTAssertEqual(replaced.locked, pack.locked)

        let withBus = Map3DCityBus.pack(file: Map3DCityBusTests.bundled)
        XCTAssertEqual(withBus.lights.keys.sorted(), pack.lights.keys.sorted())
        let models = Map3DCityBusTests.root.appendingPathComponent("RailwayGameApp/Resources/Models")
        var files: [Map3DStreetModel: URL] = [:]
        for (model, name) in Map3DGarbageTruck.fileNames {
            files[model] = models.appendingPathComponent(name + "." + Map3DGarbageTruck.fileExtension)
        }
        let both = Map3DGarbageTruck.pack(withBus, files: files)
        XCTAssertEqual(both.lights.keys.sorted(), pack.lights.keys.sorted())

        // The night lamps are still added to a train drawn from that pack.
        let rows = Map3DShowcase.layout(keys: [Map3DShowcase.catalog[0].key])
        let before = Map3DShowcase.frame(rows, pack: both)
        var after = before
        Map3DTrainLights.add(to: &after, pack: both, lights: 1)
        XCTAssertGreaterThan(after.boxes.vertices.count, before.boxes.vertices.count)
    }
}
