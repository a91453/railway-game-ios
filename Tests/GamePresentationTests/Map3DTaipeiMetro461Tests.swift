import XCTest
@testable import GamePresentation

/// Decision 461: #1323's C371, C381 and Circular line 610 studies run as
/// sets of their own, near and far: the player's metros three ways, the
/// Taipei Metro's lines by their own fleets, the Circular line the 610;
/// Kaohsiung's, Taoyuan's and Taichung's metros stay the generic car.
final class Map3DTaipeiMetro461Tests: XCTestCase {
    private let pack = Map3DModelPack.standard

    private func cars(_ key: String, _ count: Int) throws -> [Map3DModelPack.Model] {
        try XCTUnwrap(pack.layout(forType: key, count: count), key).map { pack.models[$0.model] }
    }

    private func names(_ key: String, _ count: Int) throws -> [String] {
        try cars(key, count).map(\.name)
    }

    /// The same triangles in the same places (the lit lenses are recoloured).
    private func sameShape(_ car: Map3DModelPack.Model, _ unit: Map3DModelPack.Model) -> Bool {
        car.vertices.count == unit.vertices.count
            && zip(car.vertices, unit.vertices).allSatisfy { $0.x == $1.x && $0.y == $1.y && $0.z == $1.z }
    }

    // MARK: The sets

    func testTheFormations() throws {
        for key in ["metroC371", "metroC381"] {
            XCTAssertEqual(try names(key, 6), ["head", "car", "centre", "centre", "car", "tail"].map { "set-\(key)-\($0)" })
            XCTAssertEqual(try names(key, 3), ["head", "car", "tail"].map { "set-\(key)-\($0)" }, "the branches' DM T DM")
        }
        XCTAssertEqual(try names("circular610", 4), ["head", "car", "carBack", "tail"].map { "set-circular610-\($0)" })
        // The cars touch, each at its own length: six 23.5 m C371s (141 m), the
        // C381's cabs 23.71 m; the 610's four 68.4 m with its gangways.
        let c371 = try XCTUnwrap(pack.layout(forType: "metroC371", count: 6))
        XCTAssertTrue(c371.allSatisfy { $0.gap == 0 })
        XCTAssertEqual(c371.reduce(0) { $0 + $1.length }, 141.7, accuracy: 0.6)
        let c381 = try XCTUnwrap(pack.layout(forType: "metroC381", count: 6))
        XCTAssertGreaterThan(c381[0].length, c381[1].length)
        let ring = try XCTUnwrap(pack.layout(forType: "circular610", count: 4))
        XCTAssertEqual(ring.reduce(0) { $0 + $1.length }, 68.4, accuracy: 1.0)
    }

    func testTheCarsAreTheStudiesUnits() throws {
        let c371 = try cars("metroC371", 6), c381 = try cars("metroC381", 6)
        for (index, unit) in Map3DC371.arrangement.enumerated() {
            XCTAssertTrue(sameShape(c371[index], Map3DC371.model(unit)), "C371 \(index)")
        }
        for (index, unit) in Map3DC381.arrangement.enumerated() {
            XCTAssertTrue(sameShape(c381[index], Map3DC381.model(unit)), "C381 \(index)")
        }
        let ring = try cars("circular610", 4)
        for (index, role) in Map3DTaipei610.sequence.enumerated() {
            XCTAssertTrue(sameShape(ring[index], Map3DTaipei610.model(role)), "610 \(role)")
        }
        let light = try cars("circular610Far", 4)
        for (index, role) in Map3DTaipei610.sequence.enumerated() {
            XCTAssertTrue(sameShape(light[index], Map3DTaipei610.model(role, light: true)), "610 light \(role)")
        }
    }

    /// The near units are the studies as they were (`hashes.lock.json`
    /// pins them too); the far flag only leaves parts out.
    func testTheNearStudiesAreAsTheyWere() {
        let triangles = Dictionary(uniqueKeysWithValues: (Map3DC371.Unit.allCases.map { Map3DC371.model($0) }
            + Map3DC381.Unit.allCases.map { Map3DC381.model($0) }).map { ($0.name, $0.triangleCount) })
        XCTAssertEqual(triangles, ["c371-dm": 5_358, "c371-t": 2_188, "c371-m": 2_200, "c371-rear": 5_358,
                                   "c381-dm": 6_976, "c381-t": 1_804, "c381-m": 1_816, "c381-rear": 6_976])
        for unit in Map3DC371.Unit.allCases { XCTAssertEqual(Map3DC371.model(unit).vertices, Map3DC371.model(unit, far: false).vertices) }
    }

    func testTheLampsAreLitAtTheTrainsEnds() throws {
        func lit(_ car: Map3DModelPack.Model) -> [Map3DVertex] { car.vertices.filter { $0.layer == Map3DVertex.glowing } }
        let unbaked = Map3DModelPack.unbaked
        for (key, count) in [("metroC371", 6), ("metroC371Far", 6), ("metroC381", 6), ("metroC381Far", 6), ("circular610", 4), ("circular610Far", 4)] {
            let laid = try XCTUnwrap(unbaked.layout(forType: key, count: count), key).map { unbaked.models[$0.model] }
            let head = lit(laid[0]), tail = lit(laid[count - 1])
            XCTAssertFalse(head.isEmpty, key)
            XCTAssertTrue(head.allSatisfy { $0.x > 4 && $0.color == Map3DTrainStyle.headlamp }, "\(key) head")
            XCTAssertFalse(tail.isEmpty, key)
            XCTAssertTrue(tail.allSatisfy { $0.x < -4 && $0.color == Map3DPalette.lantern }, "\(key) tail")
            for index in 1..<(count - 1) { XCTAssertTrue(lit(laid[index]).isEmpty, "\(key) car \(index + 1)") }
        }
    }

    // MARK: Near, far and a box

    func testNearThenFarThenABox() throws {
        for (key, units) in [("metroC371", ["head", "car", "centre", "tail"]), ("metroC381", ["head", "car", "centre", "tail"]),
                             ("circular610", ["head", "car", "carBack", "tail"])] {
            XCTAssertEqual(Map3DTrainSet.reach(of: key), Map3DTrainSet.tramReach, key)
            for unit in units {
                let near = try XCTUnwrap(pack.index(of: "set-\(key)-\(unit)"), "\(key) \(unit)")
                XCTAssertEqual(pack.model(near, forType: key, count: 6, at: 100), near)
                XCTAssertEqual(pack.model(near, forType: key, count: 6, at: 700), pack.index(of: "set-\(key)Far-\(unit)"), "\(key) \(unit)")
                XCTAssertNil(pack.model(near, forType: key, count: 6, at: 1_000))
            }
        }
    }

    /// A far car fits its near car's box and has under half its triangles
    /// (decisions 417, 420); the far cab still has its lamp lenses.
    func testTheFarCarsAreTheSameCarsLighter() {
        for unit in Map3DC371.Unit.allCases {
            check(Map3DC371.model(unit), Map3DC371.model(unit, far: true))
        }
        for unit in Map3DC381.Unit.allCases {
            check(Map3DC381.model(unit), Map3DC381.model(unit, far: true))
        }
        for role in Map3DTaipei610.Role.allCases {
            check(Map3DTaipei610.model(role), Map3DTaipei610.model(role, light: true), sameColours: false)
        }
        XCTAssertTrue(Map3DC371.model(.dm, far: true).vertices.contains { $0.color == Map3DPalette.tunnelLamp })
        XCTAssertTrue(Map3DC381.model(.dm, far: true).vertices.contains { $0.color == Map3DPalette.tunnelLamp })
    }

    private func check(_ near: Map3DModelPack.Model, _ far: Map3DModelPack.Model, sameColours: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(Double(far.triangleCount), Double(near.triangleCount) * 0.5, near.name, file: file, line: line)
        XCTAssertEqual(far.minimum.x, near.minimum.x, accuracy: 0.1, near.name, file: file, line: line)
        XCTAssertEqual(far.maximum.x, near.maximum.x, accuracy: 0.1, near.name, file: file, line: line)
        XCTAssertEqual(far.maximum.z, near.maximum.z, accuracy: 0.05, near.name, file: file, line: line)
        XCTAssertEqual(far.minimum.z, near.minimum.z, accuracy: 0.1, near.name, file: file, line: line)
        // The 610's `light` cab (its study, unchanged) has a coarser nose,
        // so its flat-shaded faces take shades the near cab does not have.
        guard sameColours else { return }
        let colours = Set(near.vertices.map(\.color))
        XCTAssertTrue(far.vertices.allSatisfy { colours.contains($0.color) }, "\(near.name): the far car's colours are the near car's", file: file, line: line)
    }

    // MARK: Which trains

    /// The player's metro: 8, 6 and 6 in 20 consecutive numbers.
    func testThePlayersMetrosAreThreeFleets() {
        var count: [String: Int] = [:]
        for number in 1...20 { count[Map3DTrainSet.taipeiMetro(number: number), default: 0] += 1 }
        XCTAssertEqual(count, ["metroC371": 8, "metroC381": 6, "metroC341": 6])
        XCTAssertEqual(Map3DTrainSet.taipeiMetro(number: -3), Map3DTrainSet.taipeiMetro(number: 17))
    }

    /// The real Songshan-Xindian line's odd-numbered trains are the C371,
    /// the even the C381; every other line one fleet.
    func testTheSongshanXindianLineIsTwoFleets() {
        let green = Map3DRealTrains.Formation(key: "metroC381", cars: 6, alternate: "metroC371")
        XCTAssertEqual(Map3DRealTrains.formation(of: green, system: "trtc", number: 1_107).key, "metroC371")
        XCTAssertEqual(Map3DRealTrains.formation(of: green, system: "trtc", number: 1_108).key, "metroC381")
        XCTAssertEqual(Map3DRealTrains.formation(of: green, system: "trtc", number: 1_108).cars, 6)
        for key in ["metroC341", "metroC371", "circular610", "wenhu"] {
            let line = Map3DRealTrains.Formation(key: key, cars: 6)
            for number in [1, 2] { XCTAssertEqual(Map3DRealTrains.formation(of: line, system: "trtc", number: number), line) }
        }
    }

    /// Kaohsiung's, Taoyuan's and Taichung's metros: the generic car that
    /// key `metroC381` drew before, line-coloured, bit for bit.
    func testTheOtherCitiesKeepTheGenericCar() throws {
        let old = Map3DTrainSet.multipleUnit("metroC381", asset: "02_HSR_MRT_3x2-02", lineColoured: true).build()
        let generic = try XCTUnwrap(Map3DTrainSet.byKey["metroGeneric"]).build()
        XCTAssertEqual(generic.head.vertices, old.head.vertices)
        XCTAssertEqual(generic.middle?.vertices, old.middle?.vertices)
        XCTAssertEqual(generic.tail?.vertices, old.tail?.vertices)
        XCTAssertNil(pack.layout(forType: "metroGeneric", count: 3), "20 m a car, as before")
        XCTAssertEqual(Map3DTrainSet.reach(of: "metroGeneric"), Map3DTrains.modelReach)
        for system in ["krtc", "tymc", "tmrt"] {
            for number in [1, 2, 7] {
                XCTAssertEqual(Map3DRealTrains.variantKey(system: system, key: "metroGeneric", number: number), "metroGeneric")
            }
        }
    }

    /// The unlocked train pack's linear-motor metro is drawn as far as
    /// before, though its type's set while locked (the C381) has a far set.
    func testTheFourCarMetroIsAsFarAsBefore() throws {
        var unlocked = Map3DModelPack.standard
        unlocked.locked = []
        let near = try XCTUnwrap(unlocked.modelIndex(forType: "L", carIndex: 0, count: 4))
        XCTAssertEqual(unlocked.models[near].name, "set-fourCarMetro-head")
        XCTAssertEqual(unlocked.model(near, forType: "L", count: 4, at: 700), near)
        var locked = Map3DModelPack.standard
        locked.locked = TrainPack.locked(unlocked: false)
        let c381 = try XCTUnwrap(locked.modelIndex(forType: "L", carIndex: 0, count: 4))
        XCTAssertEqual(locked.models[c381].name, "set-metroC381-head")
        XCTAssertEqual(locked.model(c381, forType: "L", count: 4, at: 700), locked.index(of: "set-metroC381Far-head"))
    }

    /// Only on request: the numbers decision 461 gives. `MAP3D_FRAME_REPORT=1`.
    func testTheCost() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        for (key, count) in [("metroGeneric", 6), ("metroC341", 6), ("metroC341Far", 6), ("metroC371", 6), ("metroC371Far", 6),
                             ("metroC381", 6), ("metroC381Far", 6), ("circular610", 4), ("circular610Far", 4), ("wenhu", 4)] {
            let laid = try XCTUnwrap(pack.layout(forType: key, count: count).map { $0.map { pack.models[$0.model] } }
                ?? (0..<count).map { pack.modelIndex(forType: key, carIndex: $0, count: count) }.map { $0.map { pack.models[$0] } } as? [Map3DModelPack.Model])
            print("\(key): cars \(laid.map(\.triangleCount)) total \(laid.reduce(0) { $0 + $1.triangleCount })")
        }
    }
}
