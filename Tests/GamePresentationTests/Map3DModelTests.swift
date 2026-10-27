import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 230: the trains of the native 3D map, made in code.
final class Map3DModelTests: XCTestCase {
    private let pack = Map3DModelPack.standard

    func testEveryStyleHasACabAndAMiddleCarOfTheRightSize() {
        // Decision 244: and the street furniture after the trains;
        // decision 259: then the people and vehicles; decision 318: then the
        // sets'; decision 400, 10i-6: then the route bus; finally the
        // independent PP passenger-car display roles, near and far.
        let pantoStyles = Map3DTrainStyle.all.filter { !$0.pantographCars.isEmpty }.count
        let sets = Map3DTrainSet.all.map { $0.models().count }.reduce(0, +)
        let temu1000Models = Map3DTEMU1000.Unit.allCases.count + 1
        let baseModels = Map3DTrainStyle.all.count * 2 + pantoStyles + Map3DProp.allCases.count + Map3DStreetModel.allCases.count + sets
        let temu2000Models = Map3DTEMU2000.Unit.allCases.count + 1
        let shortSets = Map3DGreenTram.Section.allCases.count + 1 + Map3DGreenCommuter.Unit.allCases.count + 1 + temu1000Models + temu2000Models
        let longSets = Map3DThreeCarUrban.Unit.allCases.count + 1 + Map3DFiveSectionLRT.Unit.allCases.count + 1 + Map3DSevenSectionLRT.Unit.allCases.count + 1
        let rest = Map3DFourCarMetro.Unit.allCases.count + 1 + Map3DSevenCarBlue.Unit.allCases.count + 1 + Map3DDuplexSteam.Unit.allCases.count + 1 + Map3DSteamTender.Unit.allCases.count + 1 + Map3DTrainShapeRefresh.ids.count + 1
        let ppDisplayModels = Map3DPPPassenger.roles.count * 2 + 2 // E1000 near/far
        XCTAssertEqual(pack.models.count, baseModels + shortSets + longSets + rest + ppDisplayModels + Map3DEMU800.Role.allCases.count * 4)
        for style in Map3DTrainStyle.all {
            var names = [style.name + "-cab", style.name + "-car"]
            if !style.pantographCars.isEmpty { names.append(style.name + "-panto") }
            for name in names {
                guard let index = pack.index(of: name) else { return XCTFail(name) }
                let model = pack.models[index]
                XCTAssertEqual(model.vertices.count % 3, 0)
                // Decision 410: a cab within 4,000 triangles, a middle car 2,000.
                XCTAssertTrue((100...(name.hasSuffix("-cab") ? 4_000 : 2_000)).contains(model.triangleCount), "\(name): \(model.triangleCount) triangles")
                XCTAssertEqual(model.length, style.length, accuracy: 0.5, name)
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.01, "\(name) stands on the rail")
                // The roof and its boxes (decision 410: a high-speed car's
                // low cable shrouds; its pantograph stands higher, below).
                if !name.hasSuffix("-panto") {
                    XCTAssertTrue((style.roof...style.roof + 0.33).contains(model.maximum.z), "\(name): the roof and its boxes, \(model.maximum.z)")
                }
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
        let panto = pack.models[try XCTUnwrap(pack.index(of: "highSpeed-panto"))]
        // The nose drops: the front end is lower than the roof.
        let tip = cab.vertices.filter { $0.x > cab.maximum.x - 0.5 }
        XCTAssertLessThan(try XCTUnwrap(tip.map(\.z).max()), 2.5)
        XCTAssertGreaterThan(car.vertices.filter { $0.x > car.maximum.x - 0.5 }.map(\.z).max() ?? 0, 3.5)
        // Some vertices take the line's colour (alpha 0), some are glass.
        XCTAssertTrue(car.vertices.contains { $0.color >> 24 == 0 })
        XCTAssertTrue(car.vertices.contains { $0.color == Map3DTrainStyle.glass })
        // On the N700ST cab, the line-coloured stripe and navy band sweep
        // forward onto the nose, the shoulder headlamps glow low on the
        // shoulder ridge, and the windscreen stops at the cockpit canopy.
        XCTAssertTrue(cab.vertices.contains { $0.x > 4 && $0.color >> 24 == 0 })
        XCTAssertTrue(cab.vertices.contains { $0.x > 4 && $0.color == Map3DTrainStyle.navyLine })
        let lamps = cab.vertices.filter { $0.x > 4 && $0.glows }
        XCTAssertFalse(lamps.isEmpty)
        XCTAssertLessThan(try XCTUnwrap(lamps.map(\.z).max()), 2.3, "headlamps sit low on the shoulder ridge")
        XCTAssertFalse(cab.vertices.contains { $0.x > 6.5 && $0.color == Map3DTrainStyle.glass })
        let noseCrown = cab.vertices.filter { $0.x > 7.5 && $0.x < 9.2 && abs($0.y) < 0.25 && $0.z > 1.5 }
        XCTAssertFalse(noseCrown.isEmpty)
        XCTAssertTrue(noseCrown.allSatisfy { $0.nz > 0 }, "the dropping nose crown faces upward, not inward")
        // Pantograph fairing sits only on Car 4 and Car 9 (indices 3 and 8) of a 12-car HSR set.
        XCTAssertGreaterThan(panto.maximum.z, car.maximum.z)
        // (Decision 318: the HSR type is #900's 700T now, its pantograph
        // cars the same, Map3DTrainSetTests.)
    }

    func testTheModelsAreTheSameEveryTime() {
        let again = Map3DModelPack(styles: Map3DTrainStyle.all)
        XCTAssertEqual(pack.models.map(\.vertices), again.models.map(\.vertices))
    }

    func testEveryTypeWithAStyleHasItsModels() {
        for type in TrainTypeCatalog.builtIn {
            // Decision 318: the Chu-Kuang sets and the Blue Train have their
            // locomotives now (decision 399: and the steam train); the rest
            // have no model.
            let expected = !["MAGLEV", "SKYRAIL", "MONORAIL"].contains(type.code)
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
        // Decision 227: the cars stand their own length apart.
        let cars = motion.runs.reduce(0) { $0 + TrainCars.count(length: $1.length, carPitch: $1.carPitch) }
        XCTAssertEqual(cars, 4)
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

    /// After #752: the top of each cab's nose stays the roof's grey, as it
    /// was before #752 (the #764 check found the EMU3000's nose top turned
    /// white); only a diving high-speed nose sweeps its body colour over
    /// the top to the tip.
    func testTheNoseTopIsTheRoofsColourButOnAHighSpeedNose() throws {
        for style in Map3DTrainStyle.all where style.nose > 0 {
            let model = pack.models[try XCTUnwrap(pack.index(of: style.name + "-cab"))]
            let top = style.floor + 0.9 * (style.roof - style.floor)
            // The shell's top over the nose (not the roof boxes above it).
            let noseTop = model.vertices.filter { $0.x > style.length / 2 - style.nose + 0.01 && $0.z > top + 0.01 && $0.z <= style.roof + 0.01 }
            XCTAssertFalse(noseTop.isEmpty, style.name)
            let body = noseTop.filter { $0.color == style.body }.count
            if style.dive > 0 {
                XCTAssertGreaterThan(body, 0, "\(style.name): the body colour sweeps over the nose")
            } else {
                // Glass where the windscreen reaches up (a flat front), the
                // roof's grey over the rest (the EMU3000's long nose).
                // (Decision 410: and the windscreen's dark frame.)
                let frame = Map3DColor.shaded(Map3DTrainStyle.glass, 0.7)
                XCTAssertTrue(noseTop.allSatisfy { [Map3DTrainStyle.roofColour, Map3DTrainStyle.glass, frame].contains($0.color) },
                              "\(style.name): the nose top is the roof's grey or the windscreen")
            }
        }
        // The EMU3000's long nose has the roof's grey on top.
        let express = pack.models[try XCTUnwrap(pack.index(of: "express-cab"))]
        let style = try XCTUnwrap(Map3DTrainStyle.all.first { $0.name == "express" })
        XCTAssertTrue(express.vertices.contains { $0.x > style.length / 2 - style.nose + 0.01 && $0.color == Map3DTrainStyle.roofColour })
    }
}
