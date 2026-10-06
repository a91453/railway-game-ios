import Foundation
import GameCore
import GamePresentation
import XCTest

final class RealTimetableTests: XCTestCase {
    private static func timetable(_ system: String) throws -> RealSystemTimetable {
        try RealSystemTimetable(data: BundledRealData.file("\(system)_times", "json"))
    }

    func testEveryBundledTimetableParses() throws {
        for system in RealRailways.bundledTimetables {
            let timetable = try Self.timetable(system)
            XCTAssertFalse(timetable.lines.isEmpty, system)
            for (id, line) in timetable.lines {
                XCTAssertEqual(line.days.count, 7, "\(system) \(id)")
                XCTAssertFalse(line.sets.isEmpty, "\(system) \(id)")
            }
        }
    }

    func testATripIsItsStationsAndSeconds() throws {
        let red = try XCTUnwrap(Self.timetable("trtc").lines["R"])
        let first = try XCTUnwrap(red.sets["平日"]?.first)
        XCTAssertEqual(first.calls.first, RealTimetableTrip.Call(stationIndex: 0, second: 21_600))
        XCTAssertEqual(first.calls[1], RealTimetableTrip.Call(stationIndex: 1, second: 21_780))
        XCTAssertEqual(first.calls.last?.stationIndex, 27)
        XCTAssertNil(first.kind)
        XCTAssertEqual(red.sets["平日"]?.count, 545)
    }

    func testTheSetOfAServiceDayIsTheSites() throws {
        let red = try XCTUnwrap(Self.timetable("trtc").lines["R"])
        XCTAssertEqual(RealTimetables.weekday(of: "2026-10-06"), 2, "A Tuesday")
        XCTAssertEqual(RealTimetables.weekday(of: "2026-10-04"), 0, "A Sunday")
        XCTAssertEqual(RealTimetables.weekday(of: "1970-01-01"), 4)
        XCTAssertNil(RealTimetables.weekday(of: "not a day"))
        XCTAssertEqual(red.setName(forServiceDay: "2026-10-06"), "平日")
        XCTAssertEqual(red.setName(forServiceDay: "2026-10-03"), "週六")
        XCTAssertEqual(red.setName(forServiceDay: "2026-10-04"), "週日")
        // National Day, a Saturday, runs the holiday set.
        XCTAssertEqual(red.setName(forServiceDay: "2026-10-10"), "週日")
        XCTAssertEqual(red.trips(forServiceDay: "2026-10-06").count, 545)

        // A day the file names runs its own set, with its trips' kinds.
        let airport = try XCTUnwrap(Self.timetable("tymc").lines["A"])
        XCTAssertEqual(airport.setName(forServiceDay: "2026-10-02"), "設計展週五")
        XCTAssertEqual(airport.trips(forServiceDay: "2026-10-02").first?.kind, "2")
        XCTAssertEqual(airport.trips(forServiceDay: "2026-10-02")[1].kind, "1")
    }

    func testEstimatedTimetablesAreMarked() throws {
        XCTAssertTrue(try Self.timetable("sanying").isEstimated)
        XCTAssertTrue(try XCTUnwrap(Self.timetable("tmrt").lines["TG"]).isEstimated)
        XCTAssertFalse(try XCTUnwrap(Self.timetable("krtc").lines["KR"]).isEstimated)
    }

    func testATripsClockRunsPastMidnight() {
        // The site's freqTrainTime.
        let late = RealTimetableTrip(calls: [.init(stationIndex: 0, second: 86_000), .init(stationIndex: 1, second: 87_000)])
        XCTAssertEqual(late.time(at: 86_100), 86_100)
        XCTAssertEqual(late.time(at: 300), 86_700)
        XCTAssertNil(late.time(at: 1_000))
        XCTAssertNil(late.time(at: 80_000))
    }

    func testAMalformedTripIsRefused() {
        let data = Data(#"{"system":"X","lines":{"L":{"days":[],"sets":{"平日":[[0, 100, 1]]}}}}"#.utf8)
        XCTAssertThrowsError(try RealSystemTimetable(data: data)) { error in
            XCTAssertEqual(error as? RealTimetables.FormatError, .malformedTrip(line: "L", set: "平日", index: 0))
        }
    }

    func testThePeakIsTheSites() {
        XCTAssertTrue(RealTimetables.isPeak(hour: 7))
        XCTAssertFalse(RealTimetables.isPeak(hour: 9))
        XCTAssertTrue(RealTimetables.isPeak(hour: 19.25))
        XCTAssertFalse(RealTimetables.isPeak(hour: 19.5))
        let line = RealOperationLine(id: "L", name: "L", peakHeadwaySec: 300, offpeakHeadwaySec: 600)
        XCTAssertEqual(RealTimetables.headway(of: line, atHour: 8), 300)
        XCTAssertEqual(RealTimetables.headway(of: line, atHour: 12), 600)
    }

    func testTheHighSpeedRailScheduleParses() throws {
        let schedule = try RealDailySchedule(data: BundledRealData.file("thsr-schedule", "json"))
        XCTAssertEqual(schedule.trains.count, 169)
        XCTAssertEqual(schedule.date, "20260929")
        let first = try XCTUnwrap(schedule.trains.first)
        XCTAssertEqual(first.number, "0108")
        XCTAssertEqual(first.stops.first?.name, "左營")
        XCTAssertEqual(first.stops.first?.departureSecond, 28_500)
    }
}
