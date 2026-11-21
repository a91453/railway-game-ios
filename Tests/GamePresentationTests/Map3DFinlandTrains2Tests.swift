import XCTest
@testable import GamePresentation

/// FINLAND-TRAINS-2: the local studio's Sr3 locomotive, intercity control
/// car and double-deck sleeping car, and Rovaniemi's trains each drawn by
/// its name in the timetable.
final class Map3DFinlandTrains2Tests: XCTestCase {
    func testAllThreeDecodeNearAndFarInTheSameFrame() throws {
        let cars: [(String, Map3DModelPack.Model?, Map3DModelPack.Model?, Float, Float)] = [
            ("sr3", Map3DFinlandSr3.model(), Map3DFinlandSr3.model(far: true), 19.04, 3.02),
            ("control", Map3DFinlandControlCar.model(), Map3DFinlandControlCar.model(far: true), 27.40, 3.2),
            ("sleeper", Map3DFinlandSleeper.model(), Map3DFinlandSleeper.model(far: true), 26.40, 3.2),
            // Decision 914.
            ("car carrier", Map3DFinlandCarCarrier.model(), Map3DFinlandCarCarrier.model(far: true), 26.70, 2.9),
            // Decision 916.
            ("open car carrier", Map3DFinlandCarCarrierGfot.model(), Map3DFinlandCarCarrierGfot.model(far: true), 26.40, 2.6),
        ]
        for (label, near, far, length, width) in cars {
            let near = try XCTUnwrap(near, label), far = try XCTUnwrap(far, label)
            XCTAssertEqual(near.length, length, accuracy: 0.02, label)
            XCTAssertEqual(far.length, near.length, accuracy: 0.01, label)
            XCTAssertEqual(near.maximum.y - near.minimum.y, width, accuracy: 0.03, label)
            XCTAssertEqual(near.minimum.z, 0, accuracy: 0.04, "\(label) stands on the rail")
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount + 400, "\(label): the far model about half")
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), label)
        }
    }

    /// As the Sr2's: the Sr3's cab windows mirror the sky and none lights
    /// at night; its pantographs' lower arms are the palette's train red.
    func testTheSr3HasNoLitWindowsAndRedPantographArms() throws {
        let sr3 = try XCTUnwrap(Map3DFinlandSr3.model())
        let glass = sr3.vertices.filter { $0.layer == Map3DVertex.trainGlass }
        XCTAssertFalse(glass.isEmpty, "the windscreens mirror")
        XCTAssertTrue(glass.allSatisfy { abs($0.x) > Map3DFinlandSr3.cabWindows - 0.3 }, "only the cabs' windows")
        XCTAssertNil(Map3DTrainLights.windowModel(of: sr3), "no window lights at night")
        XCTAssertTrue(sr3.vertices.contains { $0.color == Map3DPalette.trainRed && $0.z > 4 }, "the pantographs' lower arms")
        let lamps = sr3.vertices.filter { $0.color == Map3DTrainStyle.headlamp }.map(\.x)
        XCTAssertGreaterThan(lamps.max() ?? 0, 8.5)
        XCTAssertLessThan(lamps.min() ?? 0, -8.5)
    }

    /// The control car's headlamps are at its cab end only (+x), and its
    /// passenger windows light at night as the coach's.
    func testTheControlCarHasItsCabAtOneEnd() throws {
        let control = try XCTUnwrap(Map3DFinlandControlCar.model())
        let lamps = control.vertices.filter { $0.color == Map3DTrainStyle.headlamp }.map(\.x)
        XCTAssertGreaterThan(lamps.min() ?? 0, 12, "the headlamps at the cab")
        XCTAssertNotNil(Map3DTrainLights.windowModel(of: control))
        XCTAssertNotNil(Map3DTrainLights.windowModel(of: try XCTUnwrap(Map3DFinlandSleeper.model())))
    }

    /// The intercity: the locomotive, five coaches, the control car at the
    /// back with its cab turned back; the night train: the locomotive, four
    /// sleeping cars and (decisions 914 and 916) two car carriers, the
    /// open one and then the closed one, its tail lamps lit at the back.
    func testTheSetsAreLaidAsTheRealTrains() throws {
        let pack = Map3DModelPack.standard
        let count = Map3DFinlandSr2.cars
        func names(_ key: String) throws -> [String] {
            try (0..<count).map { car in
                pack.models[try XCTUnwrap(pack.modelIndex(forType: key, carIndex: car, count: count), key)].name
            }
        }
        for key in [Map3DFinlandSr2.key, Map3DFinlandSr3.key] {
            let coaches: [String] = Array(repeating: "set-\(key)-car", count: 5)
            let expected: [String] = ["set-\(key)-head"] + coaches + ["set-\(key)-tail"]
            XCTAssertEqual(try names(key), expected, key)
        }
        for key in [Map3DFinlandSleeper.key, Map3DFinlandSleeper.sr3Key] {
            let sleepers: [String] = Array(repeating: "set-\(key)-car", count: 4)
            let expected: [String] = ["set-\(key)-head"] + sleepers + ["set-\(key)-centre", "set-\(key)-tail"]
            XCTAssertEqual(try names(key), expected, key)
        }
        let sr3 = try XCTUnwrap(pack.layout(forType: Map3DFinlandSr3.key, count: count))
        XCTAssertEqual(sr3.map(\.length).reduce(0, +), 19.04 + 26.40 * 5 + 27.40, accuracy: 0.15)
        let night = try XCTUnwrap(pack.layout(forType: Map3DFinlandSleeper.key, count: count))
        let nightLength: Float = 19.02 + 26.40 * 5 + 26.70
        XCTAssertEqual(night.map(\.length).reduce(0, +), nightLength, accuracy: 0.15)
        // The car carrier's tail lamps lit at the train's back, the other's not.
        let nightCars = Map3DTrainSet.finlandNight(sr3: false).build()
        let carrierTail = try XCTUnwrap(nightCars.tail), carrier = try XCTUnwrap(nightCars.centre)
        XCTAssertEqual(carrierTail.length, 26.70, accuracy: 0.02)
        let lit = carrierTail.vertices.filter { $0.layer == Map3DVertex.glowing }.map(\.x)
        XCTAssertFalse(lit.isEmpty)
        XCTAssertLessThan(lit.max() ?? 0, carrierTail.minimum.x + 1, "the lamps at its back end")
        XCTAssertFalse(carrier.vertices.contains { $0.layer == Map3DVertex.glowing })
        XCTAssertEqual(carrier.length, 26.40, accuracy: 0.02, "the open car carrier before it")
        XCTAssertEqual(carrier.maximum.z, 4.535, accuracy: 0.03)
        // The control car's cab (its headlamps) at the train's back.
        let tail = try XCTUnwrap(pack.models.first { $0.name == "set-\(Map3DFinlandSr2.key)-tail" })
        let lamps = tail.vertices.filter { $0.color == Map3DTrainStyle.headlamp }.map(\.x)
        XCTAssertLessThan(lamps.max() ?? 0, tail.minimum.x + 2, "its cab faces back")
    }

    /// Each train by its name: `PYO` a night train, any other an
    /// intercity; three numbers in eight behind the Sr3, the Kemijärvi line's night
    /// trains behind the Sr2.
    func testRovaniemisTrainsByTheirNames() {
        func key(_ train: String) -> String { Map3DRealTrains.finland(train: train).key }
        XCTAssertEqual(key("PYO 265"), Map3DFinlandSleeper.key, "the Kemijärvi line's night trains behind the Sr2")
        XCTAssertEqual(key("PYO 274"), Map3DFinlandSleeper.key)
        XCTAssertEqual(key("PYO 273"), Map3DFinlandSleeper.key)
        XCTAssertEqual(key("PYO 267"), Map3DFinlandSleeper.sr3Key)
        XCTAssertEqual(key("IC 27"), Map3DFinlandSr3.key)
        XCTAssertEqual(key("IC 24"), Map3DFinlandSr2.key)
        XCTAssertEqual(key("S 28"), Map3DFinlandSr2.key)
        XCTAssertEqual(key("MUS 1974"), Map3DFinlandSr3.key)
        let line = Map3DRealTrains.Formation(key: Map3DFinlandSr2.key, cars: 7)
        XCTAssertEqual(Map3DRealTrains.formation(of: line, system: "vr", place: "x#0", train: "PYO 265").key, Map3DFinlandSleeper.key)
        XCTAssertEqual(Map3DRealTrains.formation(of: line, system: "vr", place: "x#0"), line, "no name: the line's")
    }

    /// The timetable file names Rovaniemi's trains, and the traffic finds
    /// each running train's name from its place.
    func testTheTimetableNamesEachTrip() throws {
        let data = """
        {"system": "VR", "lines": {"KJA": {"days": ["a"], "sets": {"a": [[0, 100, 1, 200], [1, 300, 0, 400]]},
         "kinds": {"a": "11"}, "trains": {"a": ["PYO 265", "IC 24"]}}}}
        """.data(using: .utf8)!
        let timetable = try RealSystemTimetable(data: data)
        XCTAssertEqual(timetable.lines["KJA"]?.sets["a"]?.map(\.name), ["PYO 265", "IC 24"])
    }
}
