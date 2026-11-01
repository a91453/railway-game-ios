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
    /// Hualien, every day of the TRA's week (decision 532's
    /// `tra-schedule.json`, which took over decision 511's own file).
    func testItsTrains() throws {
        let week = try XCTUnwrap(try operations.weekSchedule(forSystem: RealTrainTraffic.traSchedule))
        let trains = week.trains.filter { $0.model == "自強(D31)" }
        XCTAssertEqual(trains.map(\.number).sorted(), ["209", "221", "238", "246"])
        for train in trains {
            XCTAssertEqual(train.dayBits, 0xFF, train.number)
            XCTAssertEqual(Set([train.stops.first?.name, train.stops.last?.name]), ["樹林", "花蓮"], train.number)
        }
    }

    /// They run on the three lines they take, each day, among those lines'
    /// own trains, drawn as the DR3100's three cars; the other trains as
    /// their own models.
    func testTheyRunOnTheRealLines() throws {
        let operations = try operations
        let traffic = RealTrainTraffic(operations: operations) { _ in true }
        let wednesday = RealServiceDay(weekday: 3), tuesday = RealServiceDay(weekday: 2)
        func dr3100(on line: RealTrainTraffic.Line) -> Set<String> {
            guard case .week(let days) = line.schedule else { return [] }
            let runs = days[RealWeekTimetable.bit(of: wednesday)]
            return Set(runs.runs.indices.map(runs.key).filter { $0.hasPrefix("自強(D31)#") })
        }
        let withDR3100 = traffic.lines.filter { !dr3100(on: $0).isEmpty }
        XCTAssertEqual(Set(withDR3100.map(\.line.id)), ["縱貫線北段", "宜蘭線", "北迴線"])
        for line in withDR3100 { XCTAssertEqual(dr3100(on: line).count, 4, line.line.id) }

        // 209 halfway between Hualien and Su'aoxin: on the North-link line.
        let week = try XCTUnwrap(operations.weekSchedule(forSystem: RealTrainTraffic.traSchedule))
        let train = try XCTUnwrap(week.trains.first { $0.number == "209" })
        let hualien = try XCTUnwrap(train.stops.first { $0.name == "花蓮" }), suaoxin = try XCTUnwrap(train.stops.first { $0.name == "蘇澳新" })
        let second = Double(hualien.departure + suaoxin.arrival) / 2
        let northLink = try XCTUnwrap(traffic.lines.first { $0.line.id == "北迴線" })
        let places = traffic.places(of: northLink, at: second, on: wednesday, dayBefore: tuesday)
        XCTAssertEqual(places.filter { $0.key == "自強(D31)#209" }.count, 1)

        let local = Map3DRealTrains.formation(system: "tra", line: northLink.line)
        for place in places {
            let formation = Map3DRealTrains.formation(of: local, system: "tra", place: place.key)
            if place.key.hasPrefix("自強(D31)#") {
                XCTAssertEqual(formation, .init(key: "dieselExpress", cars: 3))
                XCTAssertEqual(Map3DTrainSet.set(forKey: formation.key, count: formation.cars)?.key, "dieselExpress")
            }
        }
        XCTAssertEqual(Map3DRealTrains.formation(of: local, system: "tra", place: "-自強(D31)#221"), .init(key: "dieselExpress", cars: 3),
                       "one from the day before")
    }
}
