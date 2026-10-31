import Foundation
@testable import GamePresentation
import XCTest

/// Decision 511: the DR3100 diesel express drawn on the DR1000's shape, and
/// its real trains on the real lines.
final class Map3DDR3100Tests: XCTestCase {
    private var operations: RealRailwayOperations {
        get throws { try XCTUnwrap(Map3DRealTrainsTests.railways?.operations) }
    }

    /// One or two cars are a DR1000, three or more the DR3100, near and
    /// far; each DR3100 car is the DR1000's shape in its own paint.
    func testTheDieselExpressIsTheDR1000sShape() throws {
        let pack = Map3DModelPack.standard
        func names(_ count: Int) -> [String] {
            (0..<count).compactMap { car in pack.modelIndex(forType: "dieselExpress", carIndex: car, count: count).map { pack.models[$0].name } }
        }
        XCTAssertEqual(Map3DTrainSet.set(forKey: "dieselExpress", count: 1)?.key, "dieselRailcar")
        XCTAssertEqual(Map3DTrainSet.set(forKey: "dieselExpress", count: 2)?.key, "dieselRailcar")
        for count in [3, 6, 9] { XCTAssertEqual(Map3DTrainSet.set(forKey: "dieselExpress", count: count)?.key, "dieselExpress", "\(count)") }
        XCTAssertEqual(names(3), ["set-dieselExpress-head", "set-dieselExpress-car", "set-dieselExpress-tail"])
        XCTAssertEqual(Map3DTrainSet.named("dieselExpress")?.far, "dieselExpressFar")
        XCTAssertNotNil(pack.models(forType: "dieselExpressFar"))

        for far in [false, true] {
            let dr1000 = Map3D45DR1000.model(far: far), dr3100 = Map3D45DR1000.model(far: far, livery: .dr3100)
            XCTAssertEqual(dr3100.name, far ? "dr3100-on-45dr1000-far" : "dr3100-on-45dr1000")
            XCTAssertEqual(dr3100.vertices.map { [$0.x, $0.y, $0.z] }, dr1000.vertices.map { [$0.x, $0.y, $0.z] }, "the same shape")
            XCTAssertNotEqual(dr3100.vertices.map(\.color), dr1000.vertices.map(\.color), "its own paint")
            let colours = Set(dr3100.vertices.map(\.color))
            XCTAssertTrue(colours.contains(Map3DColor.rgb(0xAEB0AD)) && colours.contains(Map3DColor.rgb(0xE0653F)) && colours.contains(Map3DColor.rgb(0xE6B324)))
            XCTAssertFalse(colours.contains(Map3D45DR1000.orange), "none of the DR1000's orange")
        }
    }

    /// The trains the DR3100 runs: 209, 221, 238 and 246, Shulin to
    /// Hualien, every day of the TRA's timetable from 2026-10-16.
    func testItsTrains() throws {
        let day = try XCTUnwrap(try operations.schedule(forSystem: RealTrainTraffic.dr3100Schedule))
        XCTAssertEqual(day.date, "20261016")
        XCTAssertEqual(day.trains.map(\.number).sorted(), ["209", "221", "238", "246"])
        for train in day.trains {
            XCTAssertEqual(train.model, "自強(D31)")
            XCTAssertEqual(Set([train.stops.first?.name, train.stops.last?.name]), ["樹林", "花蓮"], train.number)
        }
    }

    /// They run on the three lines they take, every one of them, beside
    /// those lines' own trains, drawn as the DR3100's three cars; the
    /// other trains as before.
    func testTheyRunOnTheRealLines() throws {
        let operations = try operations
        let traffic = RealTrainTraffic(operations: operations) { _ in true }
        let withDR3100 = traffic.lines.filter { $0.dr3100 != nil }
        XCTAssertEqual(Set(withDR3100.map(\.line.id)), ["縱貫線北段", "宜蘭線", "北迴線"])
        for line in withDR3100 { XCTAssertEqual(line.dr3100?.runs.count, 4, line.line.id) }
        XCTAssertTrue(traffic.lines.filter { $0.system != "tra" }.allSatisfy { $0.dr3100 == nil })

        // 209 halfway between Hualien and Su'aoxin: on the North-link line.
        let day = try XCTUnwrap(operations.schedule(forSystem: RealTrainTraffic.dr3100Schedule))
        let train = try XCTUnwrap(day.trains.first { $0.number == "209" })
        let hualien = try XCTUnwrap(train.stops.first { $0.name == "花蓮" }), suaoxin = try XCTUnwrap(train.stops.first { $0.name == "蘇澳新" })
        let second = Double(hualien.departureSecond + suaoxin.arrivalSecond) / 2
        let northLink = try XCTUnwrap(traffic.lines.first { $0.line.id == "北迴線" })
        let places = traffic.places(of: northLink, at: second, on: RealServiceDay(weekday: 3), dayBefore: RealServiceDay(weekday: 2))
        let dr3100 = places.filter { $0.key.hasPrefix(RealTrainTraffic.dr3100Prefix) }
        XCTAssertEqual(dr3100.count, 1)

        let local = Map3DRealTrains.formation(system: "tra", line: northLink.line)
        for place in places {
            let formation = Map3DRealTrains.formation(of: local, system: "tra", place: place.key)
            if place.key.hasPrefix(RealTrainTraffic.dr3100Prefix) {
                XCTAssertEqual(formation, .init(key: "dieselExpress", cars: 3))
                XCTAssertEqual(Map3DTrainSet.set(forKey: formation.key, count: formation.cars)?.key, "dieselExpress")
            } else {
                XCTAssertEqual(formation, Map3DRealTrains.formation(of: local, system: "tra", number: Map3DTrainSet.number(ofRealTrain: place.key)))
            }
        }
        XCTAssertEqual(Map3DRealTrains.formation(of: local, system: "tra", place: "-dr3100#2"), .init(key: "dieselExpress", cars: 3),
                       "one from the day before")
    }
}
