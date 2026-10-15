import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 230: the trains of the native 3D map, made in code.
final class Map3DModelTests: XCTestCase {
    private let pack = Map3DModelPack.standard

    func testEveryStyleHasACabAndAMiddleCarOfTheRightSize() {
        XCTAssertEqual(pack.models.count, Map3DTrainStyle.all.count * 2)
        for style in Map3DTrainStyle.all {
            for name in [style.name + "-cab", style.name + "-car"] {
                guard let index = pack.index(of: name) else { return XCTFail(name) }
                let model = pack.models[index]
                XCTAssertEqual(model.vertices.count % 3, 0)
                XCTAssertTrue((100...3_000).contains(model.triangleCount), "\(name): \(model.triangleCount) triangles")
                XCTAssertEqual(model.length, style.length, accuracy: 0.5, name)
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.01, "\(name) stands on the rail")
                XCTAssertEqual(model.maximum.z, style.roof + 0.28, accuracy: 0.05, "\(name): the roof and its boxes")
                // About a car's width, the proud panels and all.
                XCTAssertEqual(model.maximum.y - model.minimum.y, style.halfWidth * 2, accuracy: 0.12, name)
                XCTAssertTrue(model.vertices.allSatisfy { abs(Map3DPoint($0.nx, $0.ny, $0.nz).length - 1) < 1e-3 })
            }
        }
    }

    func testTheShellFacesOutward() throws {
        let model = pack.models[try XCTUnwrap(pack.index(of: "commuter-car"))]
        // Every triangle of the body's sides faces away from the car's middle.
        var checked = 0
        for start in stride(from: 0, to: model.vertices.count, by: 3) {
            let a = model.vertices[start]
            guard abs(a.ny) > 0.9, abs(a.y) > 1.2 else { continue }
            XCTAssertGreaterThan(a.ny * a.y, 0)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 10)
    }

    func testTheCabHasANoseAndTheLineColourIsMarked() throws {
        let cab = pack.models[try XCTUnwrap(pack.index(of: "highSpeed-cab"))]
        let car = pack.models[try XCTUnwrap(pack.index(of: "highSpeed-car"))]
        // The nose drops: the front end is lower than the roof.
        let tip = cab.vertices.filter { $0.x > cab.maximum.x - 0.5 }
        XCTAssertLessThan(try XCTUnwrap(tip.map(\.z).max()), 2.5)
        XCTAssertGreaterThan(car.vertices.filter { $0.x > car.maximum.x - 0.5 }.map(\.z).max() ?? 0, 3.5)
        // Some vertices take the line's colour (alpha 0), some are glass.
        XCTAssertTrue(car.vertices.contains { $0.color >> 24 == 0 })
        XCTAssertTrue(car.vertices.contains { $0.color == Map3DTrainStyle.glass })
    }

    func testTheModelsAreTheSameEveryTime() {
        let again = Map3DModelPack(styles: Map3DTrainStyle.all)
        XCTAssertEqual(pack.models.map(\.vertices), again.models.map(\.vertices))
    }

    func testEveryTypeWithAStyleHasItsModels() {
        for type in TrainTypeCatalog.builtIn {
            let expected = !["MAGLEV", "SKYRAIL", "MONORAIL", "STEAM"].contains(type.code)
            XCTAssertEqual(pack.models(forType: type.code) != nil, expected, type.code)
        }
        XCTAssertNotNil(pack.models(forType: ""), "a train with no type is a commuter EMU")
    }

    func testACarsModelStandsBetweenItsEndsFacingForward() throws {
        let model = pack.models[0]
        let back = Map3DPoint(10, 2, 0), front = Map3DPoint(10, 2, -20) // facing north, 20 m
        let instance = Map3DTrains.instance(of: model, index: 0, from: back, to: front, stripe: Map3DColor.rgb(0xFF0000))
        let matrix = Map3DMatrix(columns: instance.transform)
        let nose = try XCTUnwrap(matrix.project(Map3DPoint(model.maximum.x, 0, 0)))
        XCTAssertEqual(nose.x, front.x, accuracy: 1e-3)
        XCTAssertEqual(nose.z, front.z, accuracy: 1e-3)
        XCTAssertEqual(nose.y, 2, accuracy: 1e-3, "on the rail")
        let tail = try XCTUnwrap(matrix.project(Map3DPoint(model.minimum.x, 0, 0)))
        XCTAssertEqual(tail.z, back.z, accuracy: 1e-3)
        // The model's left (+y) is the west when it faces north; its top is up.
        let left = try XCTUnwrap(matrix.project(Map3DPoint((model.minimum.x + model.maximum.x) / 2, 1, 0)))
        XCTAssertLessThan(left.x, 10)
        let roof = try XCTUnwrap(matrix.project(Map3DPoint((model.minimum.x + model.maximum.x) / 2, 0, 3)))
        XCTAssertEqual(roof.y, 5, accuracy: 1e-3)
        XCTAssertEqual(instance.stripe.0, 1)
        XCTAssertEqual(instance.floats.count, 20)
    }

    func testNearCarsAreModelsAndFarOnesBoxes() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        try world.advance(ticks: 30)
        let scene = Map3DScene(world: world)
        let motion = TrainMotion(world: world, time: 0)
        let heights = Map3DTrains.Heights(world: world)
        let cars = motion.runs.reduce(0) { $0 + TrainCars.count(length: $1.length) }
        // The eye over the first car.
        let all = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: nil, eye: nil)
        let first = try XCTUnwrap(all.boxes.vertices.first?.position)
        let near = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: pack, eye: first + Map3DPoint(0, 100, 0))
        XCTAssertEqual(near.instances.count, cars, "a four-car train within reach")
        XCTAssertTrue(near.boxes.isEmpty)
        let headModel = try XCTUnwrap(pack.models(forType: "")).head
        XCTAssertEqual(near.instances.first?.model, headModel)
        XCTAssertEqual(near.instances.last?.model, headModel, "the last car is a cab car turned round")
        let far = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: pack, eye: first + Map3DPoint(0, 5_000, 0))
        XCTAssertTrue(far.instances.isEmpty)
        XCTAssertEqual(far.boxes.triangleCount, all.boxes.triangleCount)
    }
}
