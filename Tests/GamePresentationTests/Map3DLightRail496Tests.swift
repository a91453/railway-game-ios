import Foundation
@testable import GamePresentation
import XCTest

/// Decision 496: the real light rails drawn as their own five-module
/// trains (#1533's Danhai and Ankeng, #1506's Kaohsiung CAF and Citadis),
/// each cut into the light metro's two cars, from 500 m out their light
/// versions.
final class Map3DLightRail496Tests: XCTestCase {
    var pack: Map3DModelPack { .standard }
    static let keys = ["danhaiLRT", "ankengLRT", "klrtCAF", "klrtCitadis"]
    /// The whole train's length from nose to nose, metres (the READMEs'
    /// assembly tables).
    static let lengths: [String: Float] = ["danhaiLRT": 34.45, "ankengLRT": 34.45, "klrtCAF": 34.166, "klrtCitadis": 33.4]

    func model(_ name: String) throws -> Map3DModelPack.Model {
        pack.models[try XCTUnwrap(pack.index(of: name), name)]
    }

    func testEachLineIsDrawnAsItsOwnTrain() {
        // The Kaohsiung light rail's trains split by their number.
        for number in [0, 1, 2, 3, 7, 8, 1_107, -5] {
            XCTAssertEqual(Map3DRealTrains.variantKey(system: "krtc", key: "klrtCitadis", number: number),
                           Map3DTrainSet.kaohsiungLightRail(number: number), "\(number)")
        }
        // The New Taipei light rails are one fleet each.
        for number in [1, 2, 3] {
            XCTAssertEqual(Map3DRealTrains.variantKey(system: "ntdlrt", key: "danhaiLRT", number: number), "danhaiLRT")
            XCTAssertEqual(Map3DRealTrains.variantKey(system: "ntalrt", key: "ankengLRT", number: number), "ankengLRT")
        }
        // The player's light metro stays the green tram.
        XCTAssertEqual(Map3DTrainSet.named("C")?.key, "greenTram")
        XCTAssertEqual(Map3DTrainSet.variant(of: "C", number: 3), "C")
    }

    func testTheKaohsiungFleetsShareItsTrainsAsTheirNumbers() {
        // CAF 9, Alstom 15 of 24: 3 of every 8.
        let drawn = (0..<24).map(Map3DTrainSet.kaohsiungLightRail(number:))
        XCTAssertEqual(drawn.filter { $0 == "klrtCAF" }.count, 9)
        XCTAssertEqual(drawn.filter { $0 == "klrtCitadis" }.count, 15)
        // Never three in a row of the CAF, never four of the Citadis.
        for start in 0..<(drawn.count - 3) {
            XCTAssertFalse(drawn[start..<start + 2].allSatisfy { $0 == "klrtCAF" }, "\(start)")
            XCTAssertFalse(drawn[start..<start + 4].allSatisfy { $0 == "klrtCitadis" }, "\(start)")
        }
    }

    func testTwoCarsAsLongAsTheWholeTrain() throws {
        for key in Self.keys {
            for set in [key, key + "Far"] {
                let head = try model("set-\(set)-head"), tail = try model("set-\(set)-tail")
                XCTAssertNil(pack.index(of: "set-\(set)-car"), set)
                XCTAssertEqual(head.minimum.x, 0, accuracy: 0.001, set)
                XCTAssertEqual(tail.maximum.x, 0, accuracy: 0.001, set)
                XCTAssertEqual(head.length + tail.length, try XCTUnwrap(Self.lengths[key]), accuracy: 0.05, set)
                XCTAssertEqual(head.minimum.z, 0, accuracy: 0.001, set)
            }
            // A train of the line's two cars, front to back.
            XCTAssertEqual(pack.modelIndex(forType: key, carIndex: 0, count: 2), pack.index(of: "set-\(key)-head"))
            XCTAssertEqual(pack.modelIndex(forType: key, carIndex: 1, count: 2), pack.index(of: "set-\(key)-tail"))
            XCTAssertFalse(pack.isTurned(forType: key, carIndex: 1, count: 2), key)
        }
    }

    func testFromFiveHundredMetresTheirLightVersions() throws {
        for key in Self.keys {
            XCTAssertEqual(Map3DTrainSet.reach(of: key), 500, key)
            XCTAssertEqual(Map3DTrainSet.byKey[key]?.far, key + "Far")
            for car in ["head", "tail"] {
                let near = try XCTUnwrap(pack.index(of: "set-\(key)-\(car)"))
                let far = try XCTUnwrap(pack.index(of: "set-\(key)Far-\(car)"))
                XCTAssertEqual(pack.farModel(of: near, forType: key, count: 2), far, "\(key) \(car)")
                // Decision 420: under half the triangles, in the same box.
                let n = pack.models[near], f = pack.models[far]
                XCTAssertLessThan(f.triangleCount * 2, n.triangleCount, "\(key) \(car)")
                XCTAssertEqual(f.minimum.x, n.minimum.x, accuracy: 0.1)
                XCTAssertEqual(f.maximum.x, n.maximum.x, accuracy: 0.1)
                XCTAssertEqual(f.maximum.z, n.maximum.z, accuracy: 0.05)
            }
        }
    }

    /// Decision 449 finds each cab's lamps from its lit lenses: head and
    /// tail lamps at the head car's front and at the last car's back.
    func testTheEndsHaveLamps() throws {
        for key in Self.keys {
            for set in [key, key + "Far"] {
                let head = try XCTUnwrap(pack.lights[try XCTUnwrap(pack.index(of: "set-\(set)-head"))], set)
                XCTAssertFalse(head.front.head.isEmpty, "\(set) head lamps")
                XCTAssertFalse(head.front.tail.isEmpty, "\(set) head car's tail lamps")
                let tail = try XCTUnwrap(pack.lights[try XCTUnwrap(pack.index(of: "set-\(set)-tail"))], set)
                XCTAssertFalse(tail.back.head.isEmpty, "\(set) last car's lamps at the back")
                XCTAssertFalse(tail.back.tail.isEmpty, "\(set) last car's tail lamps at the back")
            }
        }
    }

    func testTheCost() throws {
        var lines: [String] = []
        for key in Self.keys {
            for set in [key, key + "Far"] {
                let head = try model("set-\(set)-head"), tail = try model("set-\(set)-tail")
                lines.append("\(set): head \(head.triangleCount), tail \(tail.triangleCount), train \(head.triangleCount + tail.triangleCount)")
                // Decision 496: a train only ever two cars, a car within
                // `tools/train-models/budgets.json`'s `twoCarSets`, 30,000,
                // the whole train within a quarter of a 12-car train's 240,000;
                // a far car under half its near car (the test above).
                XCTAssertLessThanOrEqual(max(head.triangleCount, tail.triangleCount), 30_000, set)
                XCTAssertLessThanOrEqual(head.triangleCount + tail.triangleCount, 60_000, set)
            }
        }
        if ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] == "1" {
            FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        }
    }
}
