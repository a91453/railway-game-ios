import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 318: the trains that were drawn as boxes, with models built
/// from the scene kit's train recipes, one per car.
final class Map3DTrainSetTests: XCTestCase {
    private let pack = Map3DModelPack.standard

    /// Every set's cars are in the pack: a car's length and width, on the
    /// rail, up to a lowered pantograph's height, in their own colours (none
    /// takes the line's but the metro's band), lit at the right end.
    func testEverySetsCarsAreInThePack() throws {
        let lineColoured: Set = ["metroC381", "wenhu"]
        for set in Map3DTrainSet.all {
            var names = [set.headName]
            for name in [set.middleName, set.tailName, set.singleName, set.pantographName, set.tenderName, set.middleBackName, set.pantographBackName] where pack.index(of: name) != nil { names.append(name) }
            for name in names {
                let model = pack.models[try XCTUnwrap(pack.index(of: name), name)]
                // Decision 331: a tram car is two of its sections.
                let triangles = set.key == "greenTram" ? 2_500...3_200
                    : ["greenCommuter", "threeCarUrban", "fiveSectionLRT", "sevenSectionLRT"].contains(set.key) ? 2_000...6_000
                    // Decision 399: a steam locomotive, eight to ten thousand.
                    : name == set.headName && ["SUMMER", "STEAM"].contains(set.key) ? 8_000...10_500
                    // Decision 408: #1201's 700T, eight to nine thousand a
                    // cab and five to six a middle car, so drawn near only;
                    // its E200, five to six thousand; the N700S-G, the
                    // author's mesh with fewer triangles on the 700T's bogies,
                    // seven thousand a cab and six a middle car.
                    // EMU3000 dedicated near detail (<500m), measured geometry budget;
                    // far models keep the generic ceiling, tested separately at 500m.
                    : name == set.headName && ["E500CK", "MINGRI", "STAR"].contains(set.key) ? 4_000...10_000
                    : set.key == "emu3000" ? ([set.headName,set.tailName].contains(name) ? 6_000...9_200:4_000...6_100)
                    : set.key == "highSpeed" ? ([set.headName, set.tailName].contains(name) ? 8_000...9_500 : 5_000...6_000)
                    : set.key == "n700sG" ? ([set.headName, set.tailName].contains(name) ? 6_700...7_300 : 5_700...6_300)
                    : name == set.headName && set.key == "E200CK" ? 5_000...6_000 : 100...4_100
                XCTAssertTrue(triangles.contains(model.triangleCount), "\(name): \(model.triangleCount) triangles")
                // #900's 700T is 24 m, its Wenhu car 12.6 m, #988's urban
                // EMU 15 m; drawn at the train's car length.
                // Decision 338, later: an articulated LRT's car from cut to cut.
                // Decision 399: the steam locomotives 14.8 and 15.4 m, their
                // tenders 9 and 9.5 m, the four-car metro's cars 12.3 m and
                // the seven-section car's 7.6 to 8.3 m, as they are.
                // Decision 408: the 700T's cars 25.2 to 25.5 m, the N700S-G's
                // and its far set's 25 and 25.3 m,
                // #900's light 700T (now the far set) 24 m.
                let length: ClosedRange<Float> = set.key == "highSpeed" ? 25...25.6 : ["n700sG", "n700sGFar"].contains(set.key) ? 24.9...25.4
                    : set.key == "highSpeedFar" ? 23...25 : ["taroko", "tarokoFar"].contains(set.key) ? 23...24.5 : set.key == "wenhu" ? 12...13.5
                    : set.key == "threeCarUrban" ? 15...16 : set.key == "sevenSectionLRT" ? 14...16
                    : name == set.headName && ["SUMMER", "STEAM"].contains(set.key) ? 14.5...15.5
                    : name == set.tenderName ? 8.9...9.6 : set.key == "fourCarMetro" ? 12.3...12.8
                    : set.key == "blueSeven" ? 7.5...8.4 : 17...22.5
                XCTAssertTrue(length.contains(model.length), "\(name): \(model.length) m long")
                XCTAssertTrue((2.6...3.5).contains(model.maximum.y - model.minimum.y), "\(name): \(model.maximum.y - model.minimum.y) m wide")
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.1, "\(name) stands on the rail")
                // The low-floor tram is lower than a train.
                let height: ClosedRange<Float> = name == set.headName && ["E500CK", "MINGRI", "STAR", "E500CKFar", "MINGRIFar", "STARFar"].contains(set.key) ? 5.2...5.5
                    : ["greenTram", "fiveSectionLRT", "sevenSectionLRT"].contains(set.key) ? 3.2...4.6
                    : set.key == "STEAM" ? 3.4...4.7
                    // Decision 408: #1201's E200 and the 700T's pantographs.
                    : ["E200CK", "highSpeed", "n700sG", "emu3000", "emu3000Far"].contains(set.key) ? 3.4...4.9 : 3.4...4.6
                XCTAssertTrue(height.contains(model.maximum.z), "\(name): \(model.maximum.z) m tall")
                if lineColoured.contains(set.key) {
                    XCTAssertTrue(model.vertices.contains { $0.color >> 24 == 0 }, "\(name): the band is the line's colour")
                } else {
                    XCTAssertTrue(model.vertices.allSatisfy { $0.color >> 24 == 0xFF }, "\(name) keeps its own colours")
                }
                XCTAssertTrue(model.vertices.allSatisfy { abs(Map3DPoint($0.nx, $0.ny, $0.nz).length - 1) < 1e-3 }, name)
            }
            let middle = (pack.models[try XCTUnwrap(pack.index(of: set.headName))].minimum.x
                + pack.models[try XCTUnwrap(pack.index(of: set.headName))].maximum.x) / 2
            let head = pack.models[try XCTUnwrap(pack.index(of: set.headName))]
            XCTAssertTrue(head.vertices.contains { $0.glows && $0.x > middle + 4 }, "\(set.key): the head's lamps at the front")
            XCTAssertFalse(head.vertices.contains { $0.glows && $0.x < middle - 4 }, "\(set.key): none at its back")
            if let tail = pack.index(of: set.tailName).map({ pack.models[$0] }) {
                XCTAssertTrue(tail.vertices.contains { $0.glows && $0.x < -4 }, "\(set.key): the tail's lamps at the back")
                XCTAssertFalse(tail.vertices.contains { $0.glows && $0.x > 4 }, "\(set.key): none at its front")
            }
            if let single = pack.index(of: set.singleName).map({ pack.models[$0] }) {
                XCTAssertTrue(single.vertices.contains { $0.glows && $0.x > 4 } && single.vertices.contains { $0.glows && $0.x < -4 },
                              "\(set.key): a railcar alone has a cab at each end")
            }
        }
    }

    /// The types that were boxes now have their models; maglev, skyrail,
    /// monorail still have none.
    func testTheTypesThatWereBoxes() {
        // Decision 399: and the steam train.
        for code in ["E200CK", "E500CK", "R100CK", "R200CK", "BLUE", "MINGRI", "STAR", "SUMMER", "STEAM"] {
            XCTAssertNotNil(pack.models(forType: code), code)
        }
        for code in ["MAGLEV", "SKYRAIL", "MONORAIL"] {
            XCTAssertNil(pack.models(forType: code), code)
        }
    }

    /// Decision 399: the sets drawn at their own lengths. The Midsummer
    /// Formosa and the steam train: the locomotive, its tender against it
    /// and the coaches 0.6 m apart, the last one lit; the linear-motor
    /// metro's cars 12.3 m apart; four light metro cars the seven-section
    /// car, seven units whatever its count. The rest stay 20 m a car.
    func testTheSetsDrawnAtTheirOwnLengths() throws {
        func layout(_ key: String, _ count: Int) throws -> [(String, Float, Float)] {
            try XCTUnwrap(pack.layout(forType: key, count: count), key).map { (pack.models[$0.model].name, $0.length, $0.gap) }
        }
        let summer = try layout("SUMMER", 4)
        XCTAssertEqual(summer.map(\.0), ["set-SUMMER-head", "set-SUMMER-tender", "set-SUMMER-car", "set-SUMMER-car", "set-SUMMER-tail"])
        for (car, (length, gap)) in zip(summer, zip([14.77, 9, 19.4, 19.4, 19.59] as [Float], [0, 0.6, 0.6, 0.6, 0] as [Float])) {
            XCTAssertEqual(car.1, length, accuracy: 0.01, car.0)
            XCTAssertEqual(car.2, gap, accuracy: 1e-6, car.0)
        }
        XCTAssertEqual(try layout("STEAM", 1).map(\.0), ["set-STEAM-head", "set-STEAM-tender"], "a locomotive alone keeps its tender")
        XCTAssertEqual(try layout("STEAM", 2).map(\.0), ["set-STEAM-head", "set-STEAM-tender", "set-STEAM-tail"])
        let four = try layout("L", 4)
        XCTAssertEqual(four.map(\.0), ["set-fourCarMetro-head", "set-fourCarMetro-car", "set-fourCarMetro-car", "set-fourCarMetro-tail"])
        // #1081's 12.3 m pitch: the middle cars' bounds are their pitch,
        // the cab cars' reach on to their couplers.
        XCTAssertEqual(four[1].1, 12.32, accuracy: 0.01)
        XCTAssertTrue(four.allSatisfy { $0.2 == 0 })
        let seven = try layout("C", 4)
        XCTAssertEqual(seven.map(\.0), ["set-blueSeven-head"] + Array(repeating: "set-blueSeven-car", count: 5) + ["set-blueSeven-tail"])
        XCTAssertEqual(seven.reduce(0) { $0 + $1.1 }, Map3DSevenCarBlue.formation().length, accuracy: 0.01, "as long as #1094's whole car")
        let steam = try layout("STEAM", 3)
        XCTAssertEqual(steam[0].1 + steam[0].2 + steam[1].1, Map3DDuplexSteam.formation().length, accuracy: 0.01,
                       "the locomotive and tender as #1118 couples them")
        for key in ["R100CK", "", "C", "A", "emu800"] { XCTAssertNil(pack.layout(forType: key, count: 3), key) }
        // Only half as far as other cars: the steam locomotives are eight
        // to ten thousand triangles.
        XCTAssertEqual(Map3DTrainSet.reach(of: "SUMMER"), Map3DTrainSet.tramReach)
        XCTAssertEqual(Map3DTrainSet.reach(of: "STEAM"), Map3DTrainSet.tramReach)
        XCTAssertEqual(Map3DTrainSet.reach(of: "L"), Map3DTrains.modelReach)
        // The locomotive's headlamp lit at its smokebox's lens.
        let head = pack.models[try XCTUnwrap(pack.index(of: "set-SUMMER-head"))]
        let lamp = head.vertices.filter(\.glows)
        XCTAssertFalse(lamp.isEmpty)
        XCTAssertTrue(lamp.allSatisfy { abs($0.x - 5.67) < 0.02 && abs($0.z - 2.83) < 0.14 && abs($0.y) < 0.14 })
    }

    /// A train's key: its type's when the type has a style or a set, else
    /// its performance's set (the Chu-Kuang presets are their types'), else
    /// its type's.
    func testATrainsKey() {
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .tiltingPuyuma), "puyuma")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .tiltingTaroko), "taroko")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .dieselRailcar), "dieselExpress", "the same curves")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .r100ChuKuang), "R100CK")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .standard), "")
        XCTAssertEqual(Map3DTrainSet.key(type: .emu3000, performance: .tiltingPuyuma), "EMU3000", "the type's style first")
        XCTAssertEqual(Map3DTrainSet.key(type: .blueTrain, performance: .r100ChuKuang), "BLUE")
        XCTAssertEqual(Map3DTrainSet.key(type: .mingRi, performance: .mingRi), "MINGRI")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .mingRi), "MINGRI", "the performance's set")
        XCTAssertEqual(Map3DTrainSet.key(type: .formosaStar, performance: .formosaStar), "STAR")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .formosaStar), "STAR", "the performance's set")
        XCTAssertEqual(Map3DTrainSet.key(type: .midsummerFormosa, performance: .midsummerFormosa), "SUMMER")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .midsummerFormosa), "SUMMER", "the performance's set")
        XCTAssertEqual(Map3DTrainSet.key(type: .steam, performance: .steam), "STEAM")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .metroC381), "metroC381")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .metro), "metroC381", "a metro is a C381")
    }

    /// Which model each car is: a hauled set's locomotive, coaches and lit
    /// last coach; the push-pull set's power car at both ends; a railcar
    /// alone, or its two cab cars; the others' last car their head turned.
    func testEachCarsModel() throws {
        func names(_ key: String, _ count: Int) -> [String] {
            (0..<count).map { car in
                guard let index = pack.modelIndex(forType: key, carIndex: car, count: count) else { return "-" }
                return pack.models[index].name + (pack.isTurned(forType: key, carIndex: car, count: count) ? " turned" : "")
            }
        }
        XCTAssertEqual(names("R100CK", 4), ["set-R100CK-head", "set-R100CK-car", "set-R100CK-car", "set-R100CK-tail"])
        XCTAssertEqual(names("pushPull", 3), ["set-pushPull-head", "set-pushPull-car", "set-pushPull-head turned"])
        XCTAssertEqual(names("dieselExpress", 1), ["set-dieselRailcar-single"], "a DR1000 alone")
        XCTAssertEqual(names("dieselExpress", 2), ["set-dieselRailcar-head", "set-dieselRailcar-tail"])
        XCTAssertEqual(names("dieselExpress", 3), ["set-dieselExpress-head", "set-dieselExpress-car", "set-dieselExpress-tail"], "a DR3100 set")
        XCTAssertEqual(names("puyuma", 3), ["set-puyuma-head", "set-puyuma-car", "set-puyuma-tail"])
        // Decision 331, later: two cars of it are the green two-car EMU;
        // one car, or a typed flat-fronted EMU, stays the commuter.
        XCTAssertEqual(names("", 2), ["set-greenCommuter-head", "set-greenCommuter-tail"])
        XCTAssertEqual(names("", 1), ["commuter-cab"])
        // Decision 331, fourth: three cars of it are the three-car urban
        // EMU; four or more stay the commuter.
        XCTAssertEqual(names("", 3), ["set-threeCarUrban-head", "set-threeCarUrban-car", "set-threeCarUrban-tail"])
        XCTAssertEqual(names("", 4), ["commuter-cab", "commuter-car", "commuter-car", "commuter-cab turned"])
        XCTAssertEqual(names("EMU100", 2), ["commuter-cab", "commuter-cab turned"])
        // As #900 has them (the author, 2026-10-21): the 700T with its two
        // pantograph cars, the EMU3000, every metro size a C381.
        XCTAssertEqual(names("HSR", 1), ["set-highSpeed-head"])
        XCTAssertEqual(names("HSR", 12), ["set-highSpeed-head", "set-highSpeed-car", "set-highSpeed-car", "set-highSpeed-panto"]
            + Array(repeating: "set-highSpeed-car", count: 4) + ["set-highSpeed-panto", "set-highSpeed-car", "set-highSpeed-car", "set-highSpeed-tail"])
        XCTAssertEqual(names("EMU3000", 3), ["set-emu3000-head", "set-emu3000-car", "set-emu3000-tail"])
        for code in ["A", "B", "D"] {
            XCTAssertEqual(names(code, 2), ["set-metroC381-head", "set-metroC381-tail"], code)
        }
        // Decision 399: the linear-motor metro is the four-car metro.
        XCTAssertEqual(names("L", 2), ["set-fourCarMetro-head", "set-fourCarMetro-tail"])
        // Decision 331: the light metro is the green tram (decision 338,
        // later: but two or three cars of it an articulated LRT; decision
        // 399: four the seven-section car).
        XCTAssertEqual(names("C", 1), ["set-greenTram-single"])
        XCTAssertEqual(names("C", 5), ["set-greenTram-head", "set-greenTram-car", "set-greenTram-car", "set-greenTram-car", "set-greenTram-tail"])
        XCTAssertEqual(names("APM", 2), ["set-wenhu-head", "set-wenhu-tail"])
    }

    /// Decision 331: a tram car is two of the tram's sections, as long as
    /// the light metro's car once stretched to it; the cabs only at the
    /// train's two ends, the pantograph on the last car.
    func testTheLightMetroIsTheGreenTram() throws {
        func model(_ name: String) throws -> Map3DModelPack.Model { pack.models[try XCTUnwrap(pack.index(of: name), name)] }
        let section = Map3DGreenTram.model(.middle).triangleCount
        XCTAssertEqual(try model("set-greenTram-car").triangleCount, 2 * section)
        let head = try model("set-greenTram-head"), tail = try model("set-greenTram-tail")
        XCTAssertEqual(head.length, 2 * Map3DGreenTram.sectionLength + Map3DGreenTram.gap + 0.11, accuracy: 0.2)
        let carLength = Float(TrainType.c.spec.carLength) / Float(WorldCoordinate.unitsPerMetre) - Map3DTrains.carGap
        XCTAssertTrue((0.8...0.9).contains(carLength / head.length), "drawn \(carLength / head.length) times its length")
        XCTAssertLessThan(head.maximum.z, 3.4, "no pantograph on the head car")
        XCTAssertGreaterThan(tail.maximum.z, 4, "the pantograph on the last")
        XCTAssertFalse(try model("set-greenTram-car").vertices.contains(where: \.glows), "no lamps between")
        // Ten times a metro car's triangles, so drawn half as far.
        XCTAssertEqual(Map3DTrainSet.reach(of: "EMU3000"),Map3DTrainSet.tramReach)
        XCTAssertEqual(Map3DTrainSet.reach(of: "C"), 500)
        XCTAssertEqual(Map3DTrainSet.reach(of: "greenTram"), 500)
        for key in ["B", "", "puyuma"] { XCTAssertEqual(Map3DTrainSet.reach(of: key), Map3DTrains.modelReach, key) }
    }

    /// Decision 331, later: the green two-car EMU's cars are #961's two
    /// units as they are, the trailing unit's cab at its back, so no car
    /// is turned; drawn as far as the other trains.
    func testTwoCommuterCarsAreTheGreenEMU() throws {
        func model(_ name: String) throws -> Map3DModelPack.Model { pack.models[try XCTUnwrap(pack.index(of: name), name)] }
        let head = try model("set-greenCommuter-head"), tail = try model("set-greenCommuter-tail")
        // The units as they are, and two lamps (twelve triangles each).
        XCTAssertEqual(head.triangleCount, Map3DGreenCommuter.model(.leading).triangleCount + 24)
        XCTAssertEqual(tail.triangleCount, Map3DGreenCommuter.model(.trailing).triangleCount + 24)
        XCTAssertEqual(head.length, Map3DGreenCommuter.model(.leading).length, accuracy: 0.05)
        XCTAssertFalse(pack.isTurned(forType: "", carIndex: 1, count: 2))
        XCTAssertTrue(pack.isTurned(forType: "", carIndex: 3, count: 4), "four cars: the commuter's cab turned")
        XCTAssertEqual(Map3DTrainSet.reach(of: "greenCommuter"), Map3DTrains.modelReach)
        XCTAssertTrue((2_000...6_000).contains(head.triangleCount), "\(head.triangleCount) triangles")
    }

    /// Decision 331, fourth: the three-car urban EMU's cars are #988's three
    /// units as they are, the cabs only at the train's two ends, so no car
    /// is turned; drawn as far as the other trains.
    func testThreeCommuterCarsAreTheUrbanEMU() throws {
        func model(_ name: String) throws -> Map3DModelPack.Model { pack.models[try XCTUnwrap(pack.index(of: name), name)] }
        let head = try model("set-threeCarUrban-head"), middle = try model("set-threeCarUrban-car")
        let tail = try model("set-threeCarUrban-tail")
        // The units as they are, and two lamps (twelve triangles each) at
        // each cab, none on the middle car.
        XCTAssertEqual(head.triangleCount, Map3DThreeCarUrban.model(.leading).triangleCount + 24)
        XCTAssertEqual(middle.triangleCount, Map3DThreeCarUrban.model(.middle).triangleCount)
        XCTAssertEqual(tail.triangleCount, Map3DThreeCarUrban.model(.trailing).triangleCount + 24)
        XCTAssertFalse(middle.vertices.contains(where: \.glows), "no lamps between")
        XCTAssertEqual(head.length, Map3DThreeCarUrban.model(.leading).length, accuracy: 0.05)
        // The lamps stand clear of the raked cab face, over its lamp blocks.
        let lamps = head.vertices.filter(\.glows)
        XCTAssertGreaterThan(lamps.map(\.x).min() ?? 0, 7.48)
        XCTAssertEqual(Set(lamps.map { $0.y > 0 }).count, 2, "a lamp each side")
        XCTAssertFalse(pack.isTurned(forType: "", carIndex: 2, count: 3))
        XCTAssertEqual(Map3DTrainSet.reach(of: "threeCarUrban"), Map3DTrains.modelReach)
    }

    /// Decision 338, later: a two-car light metro is #992's five-section
    /// LRT, a three-car one its seven-section LRT, each whole train cut
    /// into its cars on plain body; one car, or four and more, stay the
    /// green tram. The cars are as long as the cuts are apart, so stretched
    /// to the light metro's car the sections keep their proportions; the
    /// body at a cut is drawn on into the gap and closed.
    func testTwoOrThreeLightMetroCarsAreAnArticulatedLRT() throws {
        func names(_ key: String, _ count: Int) -> [String] {
            (0..<count).map { car in
                guard let index = pack.modelIndex(forType: key, carIndex: car, count: count) else { return "-" }
                return pack.models[index].name + (pack.isTurned(forType: key, carIndex: car, count: count) ? " turned" : "")
            }
        }
        func model(_ name: String) throws -> Map3DModelPack.Model { pack.models[try XCTUnwrap(pack.index(of: name), name)] }
        XCTAssertEqual(names("C", 2), ["set-fiveSectionLRT-head", "set-fiveSectionLRT-tail"])
        XCTAssertEqual(names("C", 3), ["set-sevenSectionLRT-head", "set-sevenSectionLRT-car", "set-sevenSectionLRT-tail"])
        XCTAssertEqual(names("C", 1), ["set-greenTram-single"])
        XCTAssertEqual(names("C", 5), ["set-greenTram-head", "set-greenTram-car", "set-greenTram-car", "set-greenTram-car", "set-greenTram-tail"])
        XCTAssertEqual(names("L", 2), ["set-fourCarMetro-head", "set-fourCarMetro-tail"], "the linear-motor metro is no LRT")
        XCTAssertNil(pack.index(of: "set-fiveSectionLRT-car"), "only ever two cars")

        let carLength = Float(TrainType.c.spec.carLength) / Float(WorldCoordinate.unitsPerMetre) - Map3DTrains.carGap
        // Each car: its length (cut to cut, or to its nose), the stretch
        // to the light metro's car, and whether it is cut in front, behind.
        let five = Map3DFiveSectionLRT.formation(), seven = Map3DSevenSectionLRT.formation()
        let cars: [(String, Float, ClosedRange<Float>, Bool, Bool)] = [
            ("set-fiveSectionLRT-head", five.maximum.x, 1.07...1.09, false, true),
            ("set-fiveSectionLRT-tail", -five.minimum.x, 1.07...1.09, true, false),
            ("set-sevenSectionLRT-head", seven.maximum.x - 7.08, 1.16...1.19, false, true),
            ("set-sevenSectionLRT-car", 2 * 7.08, 1.28...1.31, true, true),
            ("set-sevenSectionLRT-tail", -seven.minimum.x - 7.08, 1.16...1.19, true, false),
        ]
        for (name, length, stretch, cutInFront, cutBehind) in cars {
            let car = try model(name)
            XCTAssertEqual(car.length, length, accuracy: 0.01, name)
            XCTAssertTrue(stretch.contains(carLength / car.length), "\(name): drawn \(carLength / car.length) times its length")
            // Past a cut, half the gap once stretched; nothing past a nose.
            let reach = Map3DTrains.carGap / 2 * car.length / carLength
            let front = car.vertices.map(\.x).max() ?? 0, back = car.vertices.map(\.x).min() ?? 0
            XCTAssertEqual(front - car.maximum.x, cutInFront ? reach : 0, accuracy: 0.01, name)
            XCTAssertEqual(car.minimum.x - back, cutBehind ? reach : 0, accuracy: 0.01, name)
            // Closed where it ends in the gap, across its whole body.
            for (end, facing, cut) in [(front, Float(1), cutInFront), (back, Float(-1), cutBehind)] where cut {
                let cap = car.vertices.filter { abs($0.x - end) < 1e-3 && $0.nx * facing > 0.99 }
                XCTAssertGreaterThan((cap.map(\.y).max() ?? 0) - (cap.map(\.y).min() ?? 0), 2.6, "\(name): closed across its width")
                XCTAssertGreaterThan(cap.map(\.z).max() ?? 0, 3.2, "\(name): closed up to its roof")
            }
        }
        // The lamps: white at the head's nose, red at the tail's, none
        // between; the pantograph only on the last car.
        for key in ["fiveSectionLRT", "sevenSectionLRT"] {
            let head = try model("set-\(key)-head"), tail = try model("set-\(key)-tail")
            let front = head.vertices.filter(\.glows), back = tail.vertices.filter(\.glows)
            XCTAssertTrue(front.contains { $0.color == Map3DTrainStyle.headlamp }, "\(key): white at the head")
            XCTAssertFalse(front.contains { $0.color == Map3DPalette.lantern }, key)
            XCTAssertTrue(back.contains { $0.color == Map3DPalette.lantern }, "\(key): red at the tail")
            XCTAssertFalse(back.contains { $0.color == Map3DTrainStyle.headlamp }, key)
            XCTAssertGreaterThan(front.map(\.x).min() ?? 0, head.maximum.x - 0.1, "\(key): at the nose, clear of its face")
            XCTAssertLessThan(back.map(\.x).max() ?? 0, tail.minimum.x + 0.1, key)
            XCTAssertEqual(Set(front.map { $0.y > 0 }).count, 2, "\(key): a lamp each side")
            XCTAssertEqual(front.count, 2 * 36, "\(key): two lamps of twelve triangles")
            XCTAssertLessThan(head.maximum.z, 3.5, "\(key): no pantograph on the head")
            XCTAssertGreaterThan(tail.maximum.z, 4.3, "\(key): the pantograph on the last car")
        }
        XCTAssertFalse(try model("set-sevenSectionLRT-car").vertices.contains(where: \.glows), "no lamps between")
        XCTAssertFalse(pack.isTurned(forType: "C", carIndex: 1, count: 2))
        XCTAssertFalse(pack.isTurned(forType: "C", carIndex: 2, count: 3))
        // Fewer triangles than the green tram's cars, so drawn as far.
        XCTAssertEqual(try model("set-fiveSectionLRT-head").triangleCount, 2_628)
        XCTAssertEqual(try model("set-fiveSectionLRT-tail").triangleCount, 2_756)
        XCTAssertEqual(try model("set-sevenSectionLRT-head").triangleCount, 2_444)
        XCTAssertEqual(try model("set-sevenSectionLRT-car").triangleCount, 2_720)
        XCTAssertEqual(try model("set-sevenSectionLRT-tail").triangleCount, 2_572)
        XCTAssertEqual(Map3DTrainSet.reach(of: "C"), Map3DTrainSet.tramReach)
    }

    /// Decision 338, later: a cut leaves the rest of the model as it was,
    /// and closes every piece it cuts through.
    func testACutKeepsTheModelAndClosesIt() {
        var builder = StationKitBuilder()
        builder.box(0, 0, 0, 4, 2, 2, 0xFF0000FF)
        let box = Map3DModelPack.Model.flat(named: "box", from: builder.mesh)
        let cut = box.cut(from: -1, to: 1, reach: (0.5, 0))
        XCTAssertEqual(cut.minimum.x, -1.5, accuracy: 1e-5)
        XCTAssertEqual(cut.maximum.x, 1, accuracy: 1e-5)
        // Every edge is two triangles': the cut box is closed.
        var edges: [String: Int] = [:]
        for start in stride(from: 0, to: cut.vertices.count, by: 3) {
            for i in 0..<3 {
                let a = cut.vertices[start + i].position, b = cut.vertices[start + (i + 1) % 3].position
                func key(_ p: Map3DPoint) -> String { String(format: "%.4f,%.4f,%.4f", p.x, p.y, p.z) }
                edges[key(a) + "-" + key(b), default: 0] += 1
                edges[key(b) + "-" + key(a), default: 0] -= 1
            }
        }
        XCTAssertGreaterThan(cut.vertices.filter { abs($0.x + 1.5) < 1e-5 && $0.nx < -0.99 }.count, 0, "closed behind")
        XCTAssertGreaterThan(cut.vertices.filter { abs($0.x - 1) < 1e-5 && $0.nx > 0.99 }.count, 0, "closed before")
        XCTAssertEqual(box.cut(from: -5, to: 5, reach: (0, 0)).vertices.count, box.vertices.count, "nothing to cut")
        // Every normal faces out.
        for start in stride(from: 0, to: cut.vertices.count, by: 3) {
            let t = cut.vertices[start..<start + 3].map(\.position)
            let centre = (t[0] + t[1] + t[2]) * (1.0 / 3)
            let n = Map3DPoint(cut.vertices[start].nx, cut.vertices[start].ny, cut.vertices[start].nz)
            XCTAssertGreaterThan(n.dot(centre - Map3DPoint(-0.25, 0, 1)), 0)
            XCTAssertGreaterThan(n.dot((t[1] - t[0]).cross(t[2] - t[0])), 0, "wound as it faces")
        }
    }

    /// The 3D map asks each train of the world for its key.
    func testTheMapAsksForTheKey() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let heights = Map3DTrains.Heights(world: world)
        XCTAssertFalse(world.trains.isEmpty)
        for train in world.trains where train.position != nil {
            XCTAssertEqual(heights.type(of: train.id), Map3DTrainSet.key(type: train.type, performance: train.performance))
        }
    }

    /// The models are the same every time they are made.
    func testTheSetsAreTheSameEveryTime() {
        for set in Map3DTrainSet.all {
            XCTAssertEqual(set.models().map(\.vertices), set.models().map(\.vertices), set.key)
        }
    }
}
