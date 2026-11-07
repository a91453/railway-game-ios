import GameCore
import XCTest
@testable import GamePresentation

/// Decision 617: the glows round the 3D map's lights at night.
final class Map3DGlowTests: XCTestCase {
    private var pack: Map3DModelPack { .standard }

    private func model(_ name: String) throws -> Map3DModelPack.Model {
        pack.models[try XCTUnwrap(pack.index(of: name), name)]
    }

    func testAStreetLightGlowsOnceWarmAtItsHead() throws {
        let lamp = try model(Map3DProp.lamp.modelName)
        let spots = Map3DGlow.spots(of: lamp)
        XCTAssertEqual(spots.count, 1)
        let spot = try XCTUnwrap(spots.first)
        // The head 8.5 m up (model space: +z up), out over the road.
        XCTAssertEqual(spot.centre.z, 8.54, accuracy: 0.1)
        XCTAssertEqual(spot.radius, Map3DGlow.radius(across: 0.75), accuracy: 0.01)
        XCTAssertEqual(spot.red, 1)
        XCTAssertGreaterThan(spot.green, 0.7, "warm white, not orange")
        XCTAssertLessThan(spot.blue, spot.green)
    }

    func testTheSignalsGlowRedAmberAndGreenApart() throws {
        func glow(_ prop: Map3DProp) throws -> Map3DGlow.Spot {
            let spots = Map3DGlow.spots(of: try model(prop.modelName))
            XCTAssertEqual(spots.count, 1, prop.rawValue)
            return try XCTUnwrap(spots.first, prop.rawValue)
        }
        let red = try glow(.signalStop), amber = try glow(.signalAmber), green = try glow(.signalGo)
        XCTAssertEqual(red.red, 1)
        XCTAssertLessThan(red.green, 0.4)
        XCTAssertEqual(amber.red, 1)
        XCTAssertGreaterThan(amber.green, 0.6)
        XCTAssertLessThan(amber.green, 0.9)
        XCTAssertLessThan(amber.blue, 0.35)
        XCTAssertEqual(green.green, 1)
        XCTAssertLessThan(green.red, 0.4)
        // Each two at least 0.4 apart in some channel, glow on glow.
        for (a, b) in [(red, amber), (amber, green), (red, green)] {
            let apart = max(abs(a.red - b.red), abs(a.green - b.green), abs(a.blue - b.blue))
            XCTAssertGreaterThan(apart, 0.4)
        }
        // The lit light of each: red nearest the road's middle, green out.
        XCTAssertNotEqual(red.centre, green.centre)
        XCTAssertNotEqual(red.centre, amber.centre)
    }

    func testAScooterGlowsAtItsHeadlampAndTailLamp() throws {
        let spots = Map3DGlow.spots(of: try model(Map3DStreetModel.scooter.modelName))
        XCTAssertGreaterThanOrEqual(spots.count, 2)
        XCTAssertTrue(spots.contains { $0.centre.x > 0 && $0.blue > 0.5 }, "a white headlamp at the front")
        XCTAssertTrue(spots.contains { $0.centre.x < 0 && $0.green < 0.5 }, "a red tail lamp at the back")
    }

    func testATrainsWindowsAndLitGlassHaveNoGlow() {
        for model in pack.models where model.name.hasPrefix(Map3DTrainLights.prefix) {
            XCTAssertTrue(Map3DGlow.spots(of: model).isEmpty, model.name)
        }
        let glass = [Map3DVertex.trainGlassLit, Map3DVertex.transparentGlassLit].flatMap { layer in
            (0..<3).map { Map3DVertex(Map3DPoint(Float($0), 0, 0), normal: .up, color: 0xFFFF_FFFF, layer: layer) }
        }
        XCTAssertTrue(Map3DGlow.spots(of: Map3DModelPack.Model(name: "glass", vertices: glass, minimum: .zero, maximum: .zero)).isEmpty)
    }

    func testTouchingTrianglesAreOneLightAndAPanelIsNone() {
        func square(_ x: Float, _ size: Float, colour: UInt32 = Map3DColor.rgb(0xFFFFFF)) -> [Map3DVertex] {
            let corners = [Map3DPoint(x, 0, 0), Map3DPoint(x + size, 0, 0), Map3DPoint(x + size, 0, size), Map3DPoint(x, 0, size)]
            return [0, 1, 2, 0, 2, 3].map { Map3DVertex(corners[$0], normal: Map3DPoint(0, -1, 0), color: colour, layer: Map3DVertex.glowing) }
        }
        // Two lamps 1.5 m apart, each two triangles, and one 0.1 m beside
        // the second (one light with it).
        let two = Map3DGlow.spots(in: square(0, 0.2) + square(1.5, 0.2) + square(1.8, 0.2)) { $0.glows }
        XCTAssertEqual(two.count, 2)
        XCTAssertEqual(two[0].centre.x, 0.1, accuracy: 1e-4)
        XCTAssertEqual(two[1].centre.x, 1.75, accuracy: 1e-4)
        // A lit band 4 m long is a panel.
        XCTAssertTrue(Map3DGlow.spots(in: square(0, 4)) { $0.glows }.isEmpty)
        // A dim colour glows at full brightness, its hue kept.
        let dim = Map3DGlow.spots(in: square(0, 0.2, colour: Map3DColor.rgb(0x402010))) { $0.glows }
        XCTAssertEqual(dim.first?.red, 1)
        XCTAssertEqual(dim.first?.green ?? 0, 0.5, accuracy: 0.01)
        XCTAssertEqual(dim.first?.blue ?? 0, 0.25, accuracy: 0.01)
        // A light grown into one before it takes it in.
        let bridged = Map3DGlow.spots(in: square(0, 0.2) + square(0.6, 0.2) + square(0.25, 0.3)) { $0.glows }
        XCTAssertEqual(bridged.count, 1)
    }

    func testEveryModelHasFewSpotsAndTheTableFindsThem() {
        let table = Map3DGlow.Table(models: pack.models)
        XCTAssertEqual(table.first.count, pack.models.count)
        XCTAssertEqual(table.floats.count, table.spots * Map3DGlow.floatsASpot)
        var next = 0
        for index in pack.models.indices {
            XCTAssertEqual(table.first[index], next)
            XCTAssertLessThanOrEqual(table.count[index], Map3DGlow.mostAModel, pack.models[index].name)
            next += table.count[index]
        }
        XCTAssertEqual(next, table.spots)
        XCTAssertEqual(table.spots(of: pack.models.count), 0)
        // The running cars light no lamp of their own (decision 449): their
        // glows are placed each frame.
        for (index, _) in pack.lights { XCTAssertEqual(table.count[index], 0, pack.models[index].name) }
        // The budget, for decision 617: some 1–2 thousand floats in all.
        XCTAssertLessThan(table.floats.count, 40_000)
    }

    func testEveryTrainGlowsWhiteAtItsFrontAndRedAtItsBack() {
        for entry in Map3DShowcase.catalog {
            let rows = Map3DShowcase.layout(keys: [entry.key])
            let frame = Map3DShowcase.frame(rows, pack: pack)
            let spots = Map3DGlow.trainSpots(of: frame, pack: pack)
            let row = rows[0], head = row.cars[0], last = row.cars[row.cars.count - 1]
            let headMiddle = (head.front.x + head.back.x) / 2, lastMiddle = (last.front.x + last.back.x) / 2
            let white = spots.filter { $0.blue > 0.5 }, red = spots.filter { $0.green < 0.5 && $0.blue < 0.5 }
            XCTAssertFalse(white.isEmpty, "\(entry.key): headlamps")
            XCTAssertFalse(red.isEmpty, "\(entry.key): tail lamps")
            for spot in white { XCTAssertGreaterThan(spot.centre.x, headMiddle, entry.key) }
            for spot in red {
                XCTAssertLessThan(spot.centre.x, lastMiddle, entry.key)
                XCTAssertEqual(spot.strength, Map3DGlow.tailStrength)
            }
            XCTAssertLessThanOrEqual(spots.count, Map3DGlow.mostTrainSpots)
        }
        // A frame of every train, still within the most.
        let frame = Map3DShowcase.frame(Map3DShowcase.layout(keys: Map3DShowcase.catalog.map(\.key)), pack: pack)
        XCTAssertLessThanOrEqual(Map3DGlow.trainSpots(of: frame, pack: pack).count, Map3DGlow.mostTrainSpots)
    }

    func testAGlowNarrowsToAPointAfarAndFadesNearAndPastItsReach() {
        let radius: Float = 0.9
        XCTAssertEqual(Map3DGlow.drawnRadius(radius, distance: 50), radius)
        XCTAssertEqual(Map3DGlow.drawnRadius(radius, distance: 1_000), 2.5, accuracy: 1e-4)
        XCTAssertEqual(Map3DGlow.strength(radius: radius, distance: 0.5), 0, "the eye in its own light")
        XCTAssertEqual(Map3DGlow.strength(radius: radius, distance: 50), 1)
        XCTAssertEqual(Map3DGlow.strength(radius: radius, distance: Map3DGlow.reach), 0)
        var last: Float = 2
        for distance in stride(from: Float(400), through: Map3DGlow.reach, by: 100) {
            let strength = Map3DGlow.strength(radius: radius, distance: distance)
            XCTAssertLessThanOrEqual(strength, last, "dimmer the farther, \(distance) m")
            last = strength
        }
        XCTAssertGreaterThan(Map3DGlow.strength(radius: radius, distance: 1_200), 0.2, "a light 1.2 km off still shows")
    }

    func testTheGlowIsASoftBellWithNothingAtItsEdge() {
        XCTAssertGreaterThan(Map3DGlow.falloff(0), 1)
        XCTAssertGreaterThan(Map3DGlow.falloff(0.3), Map3DGlow.falloff(0.6))
        XCTAssertEqual(Map3DGlow.falloff(1), 0, accuracy: 1e-5)
        XCTAssertEqual(Map3DGlow.falloff(2), 0, accuracy: 1e-5)
    }

    func testGlowsAreOffWhenSavingPowerOrOnTheLowestTierButNotForReduceMotion() {
        XCTAssertTrue(Map3DGlow.draws(quality: .automatic, lowPower: false, heat: .nominal, tier: .standard))
        XCTAssertTrue(Map3DGlow.draws(quality: .high, lowPower: false, heat: .nominal, tier: .higher))
        XCTAssertFalse(Map3DGlow.draws(quality: .automatic, lowPower: true, heat: .nominal, tier: .standard), "Low Power Mode")
        XCTAssertFalse(Map3DGlow.draws(quality: .saving, lowPower: false, heat: .nominal, tier: .higher), "Battery Saver")
        XCTAssertFalse(Map3DGlow.draws(quality: .automatic, lowPower: false, heat: .serious, tier: .standard), "a hot phone")
        XCTAssertFalse(Map3DGlow.draws(quality: .automatic, lowPower: false, heat: .nominal, tier: .lower), "the lowest tier")
        XCTAssertFalse(Map3DGlow.draws(quality: .automatic, lowPower: false, heat: .nominal, tier: nil))
        XCTAssertFalse(Map3DGlow.draws(quality: .high, lowPower: false, heat: .nominal, tier: .higher, overBudget: true), "frames over budget")
        XCTAssertFalse(Map3DGlow.shows(lights: 0), "none by day")
        XCTAssertTrue(Map3DGlow.shows(lights: 1))
    }

    func testTheSquaresFaceTheEye() {
        let floats = Map3DGlow.axes(eye: Map3DPoint(0, 100, 200), target: .zero, lights: 0.5)
        XCTAssertEqual(floats.count, 8)
        let right = Map3DPoint(floats[0], floats[1], floats[2]), up = Map3DPoint(floats[4], floats[5], floats[6])
        let toward = Map3DPoint(0, -100, -200).normalized!
        XCTAssertEqual(right.length, 1, accuracy: 1e-4)
        XCTAssertEqual(up.length, 1, accuracy: 1e-4)
        XCTAssertEqual(right.dot(up), 0, accuracy: 1e-4)
        XCTAssertEqual(right.dot(toward), 0, accuracy: 1e-4)
        XCTAssertEqual(up.dot(toward), 0, accuracy: 1e-4)
        XCTAssertGreaterThan(up.y, 0)
        XCTAssertEqual(floats[3], Map3DGlow.peak * 0.5)
        // Straight down: still a right and an up.
        let down = Map3DGlow.axes(eye: Map3DPoint(0, 100, 0), target: .zero, lights: 1)
        XCTAssertEqual(Map3DPoint(down[0], down[1], down[2]).length, 1, accuracy: 1e-4)
    }
}
