import GameCore
import XCTest
@testable import GamePresentation

/// Decision 430: the Chu-Kuang sets (E200CK, E500CK, R100CK, R200CK and the
/// Midsummer Formosa) run #1306's automatic-door coach, near and far.
final class Map3DChuKuangIntegrationTests: XCTestCase {
    private let pack = Map3DModelPack.unbaked  // the recipes before decision 439's shade
    private let keys = ["E200CK", "E500CK", "R100CK", "R200CK", "SUMMER"]

    private func model(_ name: String) throws -> Map3DModelPack.Model {
        pack.models[try XCTUnwrap(pack.index(of: name), name)]
    }

    private func set(_ key: String, far: Bool) throws -> Map3DTrainSet {
        try XCTUnwrap(Map3DTrainSet.named(far ? key + "Far" : key), key)
    }

    /// Every vertex field, so a moved vertex, normal, colour or material shows.
    private func payload(_ model: Map3DModelPack.Model) -> [UInt32] {
        model.vertices.flatMap { v in
            [v.x.bitPattern, v.y.bitPattern, v.z.bitPattern, v.nx.bitPattern, v.ny.bitPattern, v.nz.bitPattern,
             v.color, v.u.bitPattern, v.v.bitPattern, v.layer.bitPattern]
        }
    }

    /// FNV-1a over `payload`, to pin a model as it was before this decision.
    private func hash(_ model: Map3DModelPack.Model) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for word in payload(model) {
            for shift in stride(from: 0, to: 32, by: 8) { h = (h ^ UInt64((word >> UInt32(shift)) & 0xFF)) &* 0x100000001b3 }
        }
        return String(h, radix: 16)
    }

    func testTheMiddleCarsAreTheStandardCoachNearAndFar() throws {
        for key in keys {
            for far in [false, true] {
                let set = try set(key, far: far)
                XCTAssertEqual(payload(try model(set.middleName)), payload(Map3DChuKuangPassenger.model(.standard, far: far)), set.key)
                XCTAssertNotEqual(payload(try model(set.middleName)), payload(Map3DChuKuangPassenger.model(.conductorStudy, far: far)), set.key)
            }
        }
    }

    /// The coach's navy and cream are in the model; the line's colour is
    /// not painted over them.
    func testTheCoachKeepsItsOwnPaint() throws {
        for key in keys {
            let colours = Set(try model(try set(key, far: false).middleName).vertices.map(\.color))
            XCTAssertTrue(colours.contains(Map3DChuKuangPassenger.bodyColor), key)
            XCTAssertTrue(colours.contains(Map3DColor.rgb(0xECE2BC)), key)
            XCTAssertFalse(colours.contains(Map3DColor.rgb(UInt32(TrainLivery.chuKuangCoach))), "\(key): no orange")
        }
    }

    func testTheLastCoachIsTheStandardCoachWithTwoLitRedLamps() throws {
        for key in keys {
            for far in [false, true] {
                let set = try set(key, far: far)
                let standard = Map3DChuKuangPassenger.model(.standard, far: far)
                XCTAssertFalse(standard.vertices.contains(where: \.glows))
                let tail = try model(set.tailName)
                let lit = tail.vertices.filter(\.glows)
                XCTAssertFalse(lit.isEmpty, set.key)
                // The lantern's red, each face of the box shaded as boxes are.
                func isRed(_ colour: UInt32) -> Bool {
                    let red = colour & 0xFF, green = colour >> 8 & 0xFF, blue = colour >> 16 & 0xFF
                    return red >= 0x90 && green * 3 < red && blue * 3 < red
                }
                XCTAssertTrue(lit.allSatisfy { isRed($0.color) }, "\(set.key): red")
                XCTAssertTrue(lit.contains { $0.color == Map3DPalette.lantern }, set.key)
                // Nothing else is lit, and the coach itself is as it is.
                XCTAssertEqual(Array(payload(tail).prefix(payload(standard).count)), payload(standard), set.key)
                XCTAssertEqual(tail.vertices.count - standard.vertices.count, lit.count, set.key)
                XCTAssertEqual(tail.minimum, standard.minimum, "\(set.key): the lamps do not lengthen the coach")
                XCTAssertEqual(tail.maximum, standard.maximum)
                // The middle cars have none, and the head's lamps are at its front.
                XCTAssertFalse(try model(set.middleName).vertices.contains(where: \.glows), set.key)
            }
        }
    }

    /// Two lamps at the −x end, one each side of the gangway, their backs on
    /// the end wall and clear of the body behind them.
    func testTheLampsStandOnTheEndWall() throws {
        let wall = -Map3DChuKuangPassenger.bodyHalfLength
        for far in [false, true] {
            let standard = Map3DChuKuangPassenger.model(.standard, far: far)
            let tail = try model(try set("E500CK", far: far).tailName)
            let lit = tail.vertices.filter(\.glows)
            // The end wall: the body's own face at x = −9.65, the whole
            // width of the coach.
            let face = standard.vertices.filter { abs($0.x - wall) < 1e-4 }
            XCTAssertFalse(face.isEmpty)
            let wallWidth = face.map(\.y).min()!...face.map(\.y).max()!
            let wallHeight = face.map(\.z).min()!...face.map(\.z).max()!
            XCTAssertEqual(wallWidth.upperBound, 1.44, accuracy: 0.01)
            // Back on the wall, front proud of it.
            XCTAssertEqual(lit.map(\.x).max()!, wall, accuracy: 0.011, "touching the wall")
            XCTAssertLessThan(lit.map(\.x).min()!, wall - 0.05, "standing out of it")
            XCTAssertGreaterThan(lit.map(\.x).min()!, wall - 0.3, "not in the gangway's reach")
            // Two lamps, one each side, the same height, outside the gangway
            // (±0.6 m) and on the wall's face.
            let left = lit.filter { $0.y > 0 }, right = lit.filter { $0.y < 0 }
            XCTAssertEqual(left.count, right.count)
            XCTAssertFalse(left.isEmpty)
            XCTAssertEqual(left.map(\.y).min()!, -right.map(\.y).max()!, accuracy: 0.001, "symmetric")
            XCTAssertGreaterThan(left.map(\.y).min()!, 0.62)
            XCTAssertLessThan(left.map(\.y).max()!, wallWidth.upperBound - 0.05)
            XCTAssertEqual(left.map(\.z).min()!, right.map(\.z).min()!, accuracy: 0.001)
            XCTAssertGreaterThan(lit.map(\.z).min()!, wallHeight.lowerBound + 0.1)
            XCTAssertLessThan(lit.map(\.z).max()!, wallHeight.upperBound - 0.1)
            // Not in the body: none of the coach's triangles passes through a lamp.
            for lamp in [left, right] {
                let low = Map3DPoint(lamp.map(\.x).min()!, lamp.map(\.y).min()!, lamp.map(\.z).min()!)
                let high = Map3DPoint(lamp.map(\.x).max()!, lamp.map(\.y).max()!, lamp.map(\.z).max()!)
                let eps: Float = 0.004
                for start in stride(from: 0, to: standard.vertices.count, by: 3) {
                    let t = standard.vertices[start..<start + 3]
                    let inside = t.map(\.x).max()! > low.x + eps && t.map(\.x).min()! < high.x - eps
                        && t.map(\.y).max()! > low.y + eps && t.map(\.y).min()! < high.y - eps
                        && t.map(\.z).max()! > low.z + eps && t.map(\.z).min()! < high.z - eps
                    XCTAssertFalse(inside, "a triangle of the coach is in a lamp")
                    if inside { return }
                }
            }
        }
    }

    /// 3, 6 and 12 cars: the locomotive, the coaches and the lit last coach,
    /// as many cars as before.
    func testEveryCarCountIsLaidAsBefore() throws {
        for key in keys {
            for count in [3, 6, 12] {
                let names = (0..<count).map { car in
                    pack.modelIndex(forType: key, carIndex: car, count: count).map { pack.models[$0].name }
                }
                XCTAssertEqual(names, ["set-\(key)-head"] + Array(repeating: "set-\(key)-car", count: count - 2) + ["set-\(key)-tail"], key)
                XCTAssertFalse(pack.isTurned(forType: key, carIndex: count - 1, count: count), "\(key): the tail is its own model")
            }
        }
        // E500CK and SUMMER were drawn at their models' lengths, as they still are (a coach 20 m, the locomotive's tender between).
        for count in [3, 6, 12] {
            let e500 = try XCTUnwrap(pack.layout(forType: "E500CK", count: count))
            XCTAssertEqual(e500.count, count)
            XCTAssertEqual(e500.dropFirst().map(\.length), Array(repeating: 20.0, count: count - 1))
            XCTAssertTrue(e500.allSatisfy { $0.gap == 0 })
            let summer = try XCTUnwrap(pack.layout(forType: "SUMMER", count: count))
            XCTAssertEqual(summer.count, count + 1, "the locomotive, its tender and the coaches")
            XCTAssertEqual(summer.dropFirst(2).map(\.length), Array(repeating: 20.0, count: count - 1))
        }
    }

    /// The sets stretched to a car's length have no layout of their own, as
    /// before: the 20 m coach is drawn the length it was.
    func testTheStretchedSetsStillHaveNoLayout() throws {
        for key in ["R100CK", "E200CK", "R200CK"] {
            for count in [3, 6, 12] { XCTAssertNil(pack.layout(forType: key, count: count), key) }
            XCTAssertFalse(try set(key, far: false).ownLengths)
            XCTAssertFalse(try set(key, far: true).ownLengths)
            XCTAssertNil(try set(key, far: false).fixedCars)
        }
        XCTAssertEqual(Map3DChuKuangPassenger.model(.standard).length, 20.0, accuracy: 0.001)
    }

    /// From 500 m out the light coach, as decisions 420 and 422 do the others.
    func testEachSetSwitchesToItsFarSetAt500Metres() throws {
        for key in keys {
            let near = try set(key, far: false), far = try set(key, far: true)
            XCTAssertEqual(near.far, key + "Far", key)
            XCTAssertNil(far.far, key)
            XCTAssertEqual(Map3DTrainSet.reach(of: key), Map3DTrainSet.tramReach, key)
            XCTAssertEqual(Map3DTrainSet.reach(of: key + "Far"), Map3DTrains.modelReach, key)
            for unit in ["head", "car", "tail"] {
                let index = try XCTUnwrap(pack.index(of: "set-\(key)-\(unit)"))
                let farIndex = try XCTUnwrap(pack.index(of: "set-\(key)Far-\(unit)"))
                XCTAssertEqual(pack.model(index, forType: key, count: 12, at: 499), index, "\(key) \(unit)")
                XCTAssertEqual(pack.model(index, forType: key, count: 12, at: 500), farIndex, "\(key) \(unit)")
                XCTAssertEqual(pack.model(index, forType: key, count: 12, at: 899), farIndex, "\(key) \(unit)")
                XCTAssertNil(pack.model(index, forType: key, count: 12, at: 900), "\(key) \(unit)")
                // The same size, to the light roof's centimetre.
                let a = pack.models[index], b = pack.models[farIndex]
                XCTAssertEqual(a.length, b.length, accuracy: 0.05, "\(key) \(unit)")
                XCTAssertEqual(a.minimum.y, b.minimum.y, accuracy: 0.05, "\(key) \(unit)")
                XCTAssertEqual(a.maximum.z, b.maximum.z, accuracy: 0.05, "\(key) \(unit)")
            }
            XCTAssertLessThan(try model(far.middleName).triangleCount, try model(near.middleName).triangleCount, key)
            XCTAssertLessThan(try model(far.tailName).triangleCount, try model(near.tailName).triangleCount, key)
        }
    }

    /// The locomotives stay as they were: the far set has the near one's
    /// where it has no light model of its own, the E500's light model where
    /// it has.
    func testTheLocomotivesAreUnchanged() throws {
        let heads: [String: String] = [
            "E200CK": "8627afbfece96e5e", "R100CK": "e39e7101afd08de4", "R200CK": "d9d90477d06f35a4",
            "SUMMER": "bfdb194e7eb7d9ea", "E500CK": "9847c0f5eb19364",
        ]
        for (key, expected) in heads {
            XCTAssertEqual(hash(try model(try set(key, far: false).headName)), expected, key)
        }
        for key in ["E200CK", "R100CK", "R200CK", "SUMMER"] {
            XCTAssertEqual(payload(try model(try set(key, far: true).headName)), payload(try model(try set(key, far: false).headName)), key)
        }
        XCTAssertEqual(hash(try model("set-E500CKFar-head")), "8dbdf8cee771ebe4")
        XCTAssertEqual(payload(try model("set-E500CKFar-head")), payload(Map3DE500.model(far: true)))
        XCTAssertEqual(hash(try model("set-SUMMER-tender")), "dab705df760e2507")
        XCTAssertEqual(payload(try model("set-SUMMERFar-tender")), payload(try model("set-SUMMER-tender")))
        // The E200's and the E500's lamps are lit at the front, as before.
        for key in ["E200CK", "E500CK", "SUMMER"] {
            XCTAssertTrue(try model(try set(key, far: false).headName).vertices.contains { $0.glows && $0.x > 4 }, key)
        }
    }

    /// The Blue Train, the Ming-Ri, the Formosa Star and the steam train are
    /// not Chu-Kuang coaches: every model of them as it was on main before
    /// this decision.
    func testTheOtherHauledSetsAreAsTheyWere() throws {
        let before: [String: String] = [
            "set-BLUE-head": "84d4a14820279a14", "set-BLUE-car": "1ef18359c168b9f5", "set-BLUE-tail": "267f145e46bbcd85",
            "set-MINGRI-head": "9847c0f5eb19364", "set-MINGRI-car": "19a87a349f7ae095", "set-MINGRI-tail": "9206cbf2686803a5",
            "set-MINGRIFar-head": "8dbdf8cee771ebe4", "set-MINGRIFar-car": "19a87a349f7ae095", "set-MINGRIFar-tail": "9206cbf2686803a5",
            "set-STAR-head": "9847c0f5eb19364", "set-STAR-car": "ad7930168200a9e5", "set-STAR-tail": "17bd7d1f746dd0b5",
            "set-STARFar-head": "8dbdf8cee771ebe4", "set-STARFar-car": "ad7930168200a9e5", "set-STARFar-tail": "17bd7d1f746dd0b5",
            "set-STEAM-head": "b043cf673bc3f74a", "set-STEAM-car": "1ef18359c168b9f5", "set-STEAM-tail": "267f145e46bbcd85",
            "set-STEAM-tender": "3f3c9943404f058f",
        ]
        for (name, expected) in before { XCTAssertEqual(hash(try model(name)), expected, name) }
        XCTAssertNil(Map3DTrainSet.named("BLUEFar"))
        XCTAssertNil(Map3DTrainSet.named("STEAMFar"))
    }

    /// The conductor study is a display model, not a coach in service.
    func testTheConductorStudyIsNotInService() throws {
        let study = payload(Map3DChuKuangPassenger.model(.conductorStudy))
        for set in Map3DTrainSet.all {
            for name in [set.middleName, set.tailName] {
                guard let index = pack.index(of: name) else { continue }
                XCTAssertNotEqual(payload(pack.models[index]), study, name)
            }
        }
    }
}
