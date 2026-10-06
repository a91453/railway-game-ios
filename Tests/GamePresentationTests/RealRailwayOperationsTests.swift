import Foundation
import GameCore
import GamePresentation
import XCTest

final class RealRailwayOperationsTests: XCTestCase {
    private static func bundledFile(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)"))
    }

    private static func makeOperations() throws -> RealRailwayOperations {
        let systemNames = ["tra", "trtc", "krtc", "tymc", "afr", "tmrt", "ntdlrt", "ntalrt", "sanying"]
        var systems: [String: Data] = [:]
        for s in systemNames {
            systems[s] = try bundledFile("\(s).json")
        }

        let timetableNames = ["trtc_times", "krtc_times", "tymc_times", "ntdlrt_times", "ntalrt_times", "sanying_times", "tmrt_times"]
        var timetables: [String: Data] = [:]
        for t in timetableNames {
            timetables[t] = try bundledFile("\(t).json")
        }

        return try RealRailwayOperations(systems: systems, timetables: timetables)
    }

    func testOperationsLoadAllSystems() throws {
        let ops = try Self.makeOperations()
        XCTAssertEqual(ops.systems.count, 9, "All 9 railway systems loaded")

        // TRA
        let tra = try XCTUnwrap(ops.system(id: "tra"))
        XCTAssertEqual(tra.lines.count, 16)
        let traNorth = try XCTUnwrap(tra.lines.first { $0.id == "縱貫線北段" })
        XCTAssertEqual(traNorth.peakHeadwaySec, 600)
        XCTAssertEqual(traNorth.offpeakHeadwaySec, 1200)
        XCTAssertEqual(traNorth.stations.count, 37)

        // TRTC
        let trtc = try XCTUnwrap(ops.system(id: "trtc"))
        XCTAssertEqual(trtc.lines.count, 9)
        let wenhu = try XCTUnwrap(trtc.lines.first { $0.id == "BR" })
        XCTAssertEqual(wenhu.peakHeadwaySec, 120)
        XCTAssertEqual(wenhu.offpeakHeadwaySec, 420)
        XCTAssertEqual(wenhu.stations.count, 24)
        XCTAssertEqual(wenhu.dwellSec?.first, 0)

        // KRTC
        let krtc = try XCTUnwrap(ops.system(id: "krtc"))
        XCTAssertEqual(krtc.lines.count, 3)
        let red = try XCTUnwrap(krtc.lines.first { $0.id == "KR" })
        XCTAssertEqual(red.peakHeadwaySec, 240)
        XCTAssertEqual(red.offpeakHeadwaySec, 420)

        // TYMC
        let tymc = try XCTUnwrap(ops.system(id: "tymc"))
        XCTAssertEqual(tymc.lines.count, 1)
        let airport = try XCTUnwrap(tymc.lines.first { $0.id == "A" })
        XCTAssertEqual(airport.peakHeadwaySec, 900)

        // TMRT
        let tmrt = try XCTUnwrap(ops.system(id: "tmrt"))
        XCTAssertEqual(tmrt.lines.count, 1)
        let green = try XCTUnwrap(tmrt.lines.first { $0.id == "TG" })
        XCTAssertEqual(green.peakHeadwaySec, 360)
        XCTAssertEqual(green.offpeakHeadwaySec, 540)

        // NTDLRT
        let ntdlrt = try XCTUnwrap(ops.system(id: "ntdlrt"))
        XCTAssertEqual(ntdlrt.lines.count, 2)

        // NTALRT
        let ntalrt = try XCTUnwrap(ops.system(id: "ntalrt"))
        XCTAssertEqual(ntalrt.lines.count, 1)

        // SANYING
        let sanying = try XCTUnwrap(ops.system(id: "sanying"))
        XCTAssertEqual(sanying.lines.count, 1)
        let lb = try XCTUnwrap(sanying.lines.first { $0.id == "LB" })
        XCTAssertEqual(lb.peakHeadwaySec, 360)
        XCTAssertEqual(lb.offpeakHeadwaySec, 480)

        // AFR
        let afr = try XCTUnwrap(ops.system(id: "afr"))
        XCTAssertEqual(afr.lines.count, 12)

        // Timetable data dictionary
        XCTAssertEqual(ops.timetableData.count, 7, "All 7 timetable datasets loaded")
    }

    func testHeadwayQueries() throws {
        let ops = try Self.makeOperations()
        XCTAssertEqual(ops.headway(forLine: "BR", inSystem: "trtc", peak: true), 120)
        XCTAssertEqual(ops.headway(forLine: "BR", inSystem: "trtc", peak: false), 420)
        XCTAssertEqual(ops.headway(forLine: "KR", inSystem: "krtc", peak: true), 240)
        XCTAssertNil(ops.headway(forLine: "nonexistent", inSystem: "trtc", peak: true))
    }
}
