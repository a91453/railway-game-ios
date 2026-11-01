import Foundation
@testable import GamePresentation
import XCTest

/// Decision 532: Taiwan Railway's every train of a week
/// (`tra-schedule.json`) on the real lines, as their real trains run, and
/// their next trains on a station card.
final class RealTRAScheduleTests: XCTestCase {
    private var operations: RealRailwayOperations {
        get throws { try XCTUnwrap(Map3DRealTrainsTests.railways?.operations) }
    }

    private var week: RealWeekTimetable {
        get throws { try XCTUnwrap(try operations.weekSchedule(forSystem: RealTrainTraffic.traSchedule)) }
    }

    /// The file: a real day of each weekday and a weekday holiday of TRA's
    /// timetable from 2026-10-16, every train with two or more stops whose
    /// times never run backwards, its stations all the game's TRA stations.
    func testTheFile() throws {
        let week = try week
        XCTAssertEqual(week.days, ["2026-10-18", "2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-16", "2026-10-17"])
        XCTAssertEqual(week.holiday, "2026-10-26")
        XCTAssertEqual(week.trains.count, 1_038)
        let stations = Set(try operations.lines(inSystem: "tra").flatMap(\.stations).map(\.name))
        for train in week.trains {
            XCTAssertGreaterThanOrEqual(train.stops.count, 2, train.number)
            XCTAssertNotEqual(train.dayBits, 0, train.number)
            var last = Int.min
            for stop in train.stops {
                XCTAssertTrue(stations.contains(stop.name), "\(train.number) \(stop.name)")
                XCTAssertGreaterThanOrEqual(stop.arrival, last, train.number)
                XCTAssertGreaterThanOrEqual(stop.departure, stop.arrival, train.number)
                last = stop.departure
            }
        }
        // Each day runs some 900 trains.
        for bit in 0..<8 {
            XCTAssertGreaterThan(week.trains.filter { $0.dayBits & (1 << bit) != 0 }.count, 850, "day \(bit)")
        }
    }

    /// Each TRA line runs its week of trains, none by headway; a train is
    /// laid on a line only along a stretch of its stations, so none of the
    /// Mountain line's trains runs on the Coast line, whose two ends it
    /// shares.
    func testTheLinesRunTheirTrains() throws {
        let traffic = RealTrainTraffic(operations: try operations) { _ in true }
        let tra = traffic.lines.filter { $0.system == "tra" }
        XCTAssertFalse(tra.isEmpty)
        for line in tra {
            guard case .week = line.schedule else { return XCTFail("\(line.line.id) runs by headway") }
        }
        let coast = try XCTUnwrap(tra.first { $0.line.id == "海線" })
        guard case .week(let days) = coast.schedule else { return XCTFail() }
        let inner = Set(coast.line.stations.map(\.name).dropFirst().dropLast())
        let byNumber = Dictionary(try week.trains.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })
        for runs in days {
            for index in runs.runs.indices {
                let number = String(runs.key(index).split(separator: "#").last ?? "")
                let train = try XCTUnwrap(byNumber[number], number)
                XCTAssertTrue(train.stops.contains { inner.contains($0.name) }, "\(number) does not take the Coast line")
            }
        }
    }

    /// A train is where its timetable has it: standing at a station it
    /// calls at between its arrival and departure, keyed by its model and
    /// number; the day before's after midnight.
    func testATrainStandsAtItsStation() throws {
        let traffic = RealTrainTraffic(operations: try operations) { _ in true }
        let north = try XCTUnwrap(traffic.lines.first { $0.system == "tra" && $0.line.id == "縱貫線北段" })
        let wednesday = RealServiceDay(weekday: 3), tuesday = RealServiceDay(weekday: 2)
        let train = try XCTUnwrap(try week.trains.first { $0.runs(on: wednesday) && $0.stops.contains { $0.name == "臺北" && $0.stops && $0.departure > $0.arrival } && $0.stops.last?.name != "臺北" })
        let taipei = try XCTUnwrap(train.stops.first { $0.name == "臺北" })
        let km = try XCTUnwrap(north.line.stations.firstIndex { $0.name == "臺北" }.map { north.stationKm[$0] })
        let key = RealTrainTraffic.traKey(model: train.model, number: train.number)
        let second = Double(taipei.arrival + taipei.departure) / 2
        let place = try XCTUnwrap(traffic.places(of: north, at: second, on: wednesday, dayBefore: tuesday).first { $0.key == key })
        XCTAssertEqual(place.km, km, accuracy: 0.001)
        if taipei.departure < 86_400 {
            XCTAssertNil(traffic.places(of: north, at: second, on: RealServiceDay(weekday: 4), dayBefore: wednesday).first { $0.key == "-" + key })
        }
        XCTAssertEqual(RealTrainTraffic.traModel(ofPlace: key), train.model)
        XCTAssertEqual(RealTrainTraffic.traModel(ofPlace: "-" + key), train.model)
    }

    /// The station card lists TRA's real next trains, under one name for
    /// a station however many lines meet there: Taipei's on a Wednesday
    /// morning, each the timetable's.
    func testTheNextTrains() throws {
        let operations = try operations
        let wednesday = RealServiceDay(weekday: 3), tuesday = RealServiceDay(weekday: 2)
        let second = 8 * 3_600
        let services = operations.service(atStationNamed: "臺北", siteSystem: "tra_sched", after: second, on: wednesday, dayBefore: tuesday)
        XCTAssertEqual(services.count, 1)
        guard case .next(let trains) = try XCTUnwrap(services.first) else { return XCTFail("\(services)") }
        XCTAssertFalse(trains.isEmpty)
        let week = try week
        for train in trains {
            XCTAssertEqual(train.lineName, RealRailwayOperations.traName)
            XCTAssertGreaterThanOrEqual(train.second, second)
            XCTAssertTrue(week.trains.contains { real in
                real.runs(on: wednesday) && real.stops.last?.name == train.destination
                    && real.stops.dropLast().contains { $0.name == "臺北" && $0.stops && $0.departure == train.second }
            }, "\(train)")
        }
        // Both ways: south (Shulin and beyond) and north or east.
        XCTAssertGreaterThanOrEqual(Set(trains.map(\.destination)).count, 2)
    }

    /// Decision 532's formations by model (`formations.js`
    /// `baseFormation`); a local train as its line's.
    func testFormationsByModel() {
        XCTAssertEqual(Map3DRealTrains.traFormation(model: "自強(3000障)"), .init(key: "emu3000", cars: 12))
        XCTAssertEqual(Map3DRealTrains.traFormation(model: "110K"), .init(key: "emu3000", cars: 12))
        XCTAssertEqual(Map3DRealTrains.traFormation(model: "自強(太,障)"), .init(key: "taroko", cars: 8))
        XCTAssertEqual(Map3DRealTrains.traFormation(model: "自強(普,障)"), .init(key: "puyuma", cars: 8))
        XCTAssertEqual(Map3DRealTrains.traFormation(model: "自強(PP障12)"), .init(key: "pushPull", cars: 14))
        XCTAssertEqual(Map3DRealTrains.traFormation(model: "自強(D31)"), .init(key: "dieselExpress", cars: 3))
        XCTAssertEqual(Map3DRealTrains.traFormation(model: "莒光"), .init(key: "E200CK", cars: 9))
        XCTAssertNil(Map3DRealTrains.traFormation(model: "區間車"))
        XCTAssertNil(Map3DRealTrains.traFormation(model: "區間快"))
        let local = Map3DRealTrains.Formation(key: "emu800", cars: 8)
        XCTAssertEqual(Map3DRealTrains.formation(of: local, system: "tra", place: "區間車#1234"),
                       Map3DRealTrains.formation(of: local, system: "tra", number: 1234))
        XCTAssertEqual(Map3DRealTrains.formation(of: local, system: "tra", place: "自強(太,障)#408").key, "taroko")
        for model in Set(((try? week.trains) ?? []).map(\.model)) where Map3DRealTrains.traFormation(model: model) != nil {
            let formation = Map3DRealTrains.traFormation(model: model)!
            XCTAssertNotNil(Map3DTrainSet.set(forKey: Map3DRealTrains.variantKey(system: "tra", key: formation.key, number: 1), count: formation.cars), model)
        }
    }
}
