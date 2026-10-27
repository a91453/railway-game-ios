@testable import GamePresentation
import XCTest

/// Decision 434: the train showcase's catalog, rows and camera views.
final class Map3DShowcaseTests: XCTestCase {
    let pack = Map3DModelPack.standard

    // MARK: - The catalog

    func testEveryNearSetIsInTheCatalogOnce() {
        let keys = Map3DShowcase.catalog.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "a train listed twice")
        let near = Map3DTrainSet.all.map(\.key).filter { !$0.hasSuffix("Far") }
        XCTAssertEqual(Set(keys), Set(near))
    }

    func testEveryEntryHasBothNamesAndAHeadModel() {
        for entry in Map3DShowcase.catalog {
            XCTAssertFalse(entry.english.isEmpty, entry.key)
            XCTAssertFalse(entry.chinese.isEmpty, entry.key)
            XCTAssertNotEqual(entry.english, entry.key, "\(entry.key) shows its key")
            guard let set = Map3DTrainSet.byKey[entry.key] else { return XCTFail("no set \(entry.key)") }
            XCTAssertNotNil(pack.index(of: set.headName), entry.key)
            XCTAssertTrue((entry.fewestCars...entry.mostCars).contains(entry.defaultCars), entry.key)
        }
    }

    func testTheDefaultTrainsAreInTheCatalog() {
        XCTAssertEqual(Map3DShowcase.Selection().keys, Map3DShowcase.defaultKeys)
        XCTAssertLessThanOrEqual(Map3DShowcase.defaultKeys.count, Map3DShowcase.mostRows)
    }

    // MARK: - The rows

    func testTwoTrainsAreTwoParallelRowsTheirHeadsLevel() {
        let rows = Map3DShowcase.layout(keys: ["emu800", "metroC381"], cars: [:], far: false)
        XCTAssertEqual(rows.map(\.key), ["emu800", "metroC381"])
        XCTAssertEqual(rows[1].z - rows[0].z, Map3DShowcase.rowSpacing)
        for row in rows {
            // Every car along the row, on its rails.
            for car in row.cars {
                XCTAssertEqual(car.back.z, row.z)
                XCTAssertEqual(car.front.z, row.z)
                XCTAssertEqual(car.front.y, Map3DShowcase.railTop)
            }
            // The head's front at x 0, facing +x.
            let head = row.cars[0]
            XCTAssertEqual(max(head.front.x, head.back.x), 0, accuracy: 0.0001, row.key)
            XCTAssertGreaterThan(head.front.x, head.back.x, row.key)
        }
        // A train of 20 m cars: six of them, 20.5 m apart, the last its
        // set's own tail.
        XCTAssertEqual(rows[1].cars.count, 6)
        XCTAssertEqual(rows[1].cars[0].back.x - rows[1].cars[1].back.x, 20.5, accuracy: 0.0001)
        let last = rows[1].cars[5]
        XCTAssertEqual(pack.models[last.model].name, Map3DTrainSet.byKey["metroC381"]!.tailName)
        XCTAssertEqual(abs(last.front.x - last.back.x), 20, accuracy: 0.0001)
    }

    func testOwnLengthCarsAreTheirModelsLengths() {
        let rows = Map3DShowcase.layout(keys: ["highSpeed", "emu3000", "puyuma"], cars: ["highSpeed": 12], far: false)
        XCTAssertEqual(rows[0].cars.count, 12)
        for row in rows {
            XCTAssertTrue(Map3DTrainSet.byKey[row.key]!.ownLengths, row.key)
            for car in row.cars {
                XCTAssertEqual((car.front - car.back).length, pack.models[car.model].length, accuracy: 0.001, row.key)
            }
        }
    }

    func testFarUsesTheSetsFarModels() {
        let near = Map3DShowcase.layout(keys: ["emu800", "BLUE"], cars: [:], far: false)
        let far = Map3DShowcase.layout(keys: ["emu800", "BLUE"], cars: [:], far: true)
        XCTAssertTrue(near[0].cars.allSatisfy { pack.models[$0.model].name.hasPrefix("set-emu800-") || pack.models[$0.model].name.hasPrefix("emu800") })
        XCTAssertTrue(far[0].cars.allSatisfy { pack.models[$0.model].name.hasPrefix("set-emu800Far-") }, "\(far[0].cars.map { pack.models[$0.model].name })")
        XCTAssertEqual(far[0].key, "emu800")
        // A set with no far models drawn as near.
        XCTAssertEqual(near[1], far[1])
    }

    func testNoMoreThanTheMostRows() {
        let keys = Map3DShowcase.catalog.prefix(Map3DShowcase.mostRows + 1).map(\.key)
        XCTAssertEqual(Map3DShowcase.layout(keys: keys).count, Map3DShowcase.mostRows)
        var selection = Map3DShowcase.Selection(keys: Array(keys.prefix(Map3DShowcase.mostRows)))
        XCTAssertTrue(selection.isFull)
        XCTAssertFalse(selection.toggle(keys[Map3DShowcase.mostRows]))
        XCTAssertEqual(selection.keys.count, Map3DShowcase.mostRows)
        // Putting one back makes room again.
        XCTAssertTrue(selection.toggle(keys[0]))
        XCTAssertTrue(selection.toggle(keys[Map3DShowcase.mostRows]))
    }

    func testCarsStayWithinTheEntrysRange() {
        var selection = Map3DShowcase.Selection(keys: ["emu800", "puyuma"])
        selection.setCars(99, of: "emu800")
        XCTAssertEqual(selection.cars(of: "emu800"), Map3DShowcase.entry("emu800")!.mostCars)
        selection.setCars(0, of: "emu800")
        XCTAssertEqual(selection.cars(of: "emu800"), 1)
        selection.setCars(3, of: "puyuma")
        XCTAssertEqual(selection.cars(of: "puyuma"), 8)
    }

    func testEveryTrainLaysOutAtEachOfItsCounts() {
        for entry in Map3DShowcase.catalog {
            for count in [entry.fewestCars, entry.defaultCars, entry.mostCars] {
                for far in [false, true] {
                    let rows = Map3DShowcase.layout(keys: [entry.key], cars: [entry.key: count], far: far)
                    XCTAssertEqual(rows.count, 1)
                    XCTAssertFalse(rows[0].cars.isEmpty, "\(entry.key) \(count)")
                    XCTAssertGreaterThan(rows[0].length, 0)
                }
            }
        }
    }

    func testTheFrameHasACarAndAShadowForEveryCar() {
        let rows = Map3DShowcase.layout(keys: Map3DShowcase.defaultKeys)
        let frame = Map3DShowcase.frame(rows)
        XCTAssertEqual(frame.instances.count, rows.reduce(0) { $0 + $1.cars.count })
        XCTAssertFalse(frame.shadows.isEmpty)
        let ground = Map3DShowcase.ground(rows)
        XCTAssertFalse(ground.mesh.isEmpty)
        // The ground under every train.
        for row in rows {
            XCTAssertLessThan(ground.minimum.x, row.tailX)
            XCTAssertLessThan(ground.minimum.z, row.z)
            XCTAssertGreaterThan(ground.maximum.z, row.z)
        }
    }

    // MARK: - The camera

    func testEveryViewSeesTheFirstTrainsHead() {
        for viewport: (width: Float, height: Float) in [(390, 844), (844, 390), (1024, 1366)] {
            let rows = Map3DShowcase.layout(keys: Map3DShowcase.defaultKeys)
            for view in Map3DShowcase.View.allCases {
                let camera = Map3DShowcase.camera(view, rows: rows, viewport: viewport)
                let head = rows[0].head + Map3DPoint(-0.5, 1.5, 0)
                XCTAssertTrue(Map3DCamera.sees(minimum: head - Map3DPoint(0.3, 0.3, 0.3), maximum: head + Map3DPoint(0.3, 0.3, 0.3),
                                               through: camera.viewProjection), "\(view) \(viewport)")
                XCTAssertLessThan((camera.eye - head).length, Map3DShowcase.farthest)
            }
        }
        let close = Map3DShowcase.camera(.closeUp, rows: Map3DShowcase.layout(keys: ["emu800"]), viewport: (390, 844))
        XCTAssertEqual(close.distance, 18)
        XCTAssertEqual(close.heading, -120 * .pi / 180, accuracy: 0.0001)
    }

    func testTheCameraTurnsAndComesNearerThanTheMaps() {
        let camera = Map3DShowcase.camera(.closeUp, rows: Map3DShowcase.layout(keys: ["emu800"]), viewport: (390, 844))
        XCTAssertEqual(Map3DShowcase.zoomed(camera, by: 100).distance, Map3DShowcase.nearest)
        XCTAssertEqual(Map3DShowcase.zoomed(camera, by: 0.0001).distance, Map3DShowcase.farthest)
        let turned = Map3DShowcase.orbited(camera, dx: 100, dy: 10_000)
        XCTAssertNotEqual(turned.heading, camera.heading)
        XCTAssertEqual(turned.target, camera.target)
        XCTAssertLessThan(turned.pitch!, .pi / 2)
        let round = Map3DShowcase.turning(camera, seconds: Map3DShowcase.turnSeconds)
        XCTAssertEqual(cosf(round.heading), cosf(camera.heading), accuracy: 0.001)
        XCTAssertEqual(sinf(round.heading), sinf(camera.heading), accuracy: 0.001)
    }
}
