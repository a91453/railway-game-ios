import GameCore
import XCTest

/// The references' dwell rules (G1b, ARCHITECTURE decision 35), ported as
/// pure functions for W2. Every expected value here is what the
/// reference's own JavaScript returned for the same case: the functions
/// were taken verbatim from the prettier copies of `Ci/`'s
/// `app__q_c234188b7c397f91.js` and `bootstrap-lazy__q_1d19ebbdad3f59c3.js`
/// and `Railway/`'s `index.html` and run in Node (with only the helpers
/// they call for unrelated things, such as distances, stubbed); the PR
/// lists the cases. The references work in seconds; these are tenths.
final class StationDwellTests: XCTestCase {
    private let tenths = StationDwell.tenthsPerSecond

    // MARK: - Ci metro game

    func testMetroDwellIsThirtySixSecondsAndFortyTwoAtATerminal() {
        XCTAssertEqual(StationDwell.metroDwell(isServed: true, isRing: false, isTerminal: false), 360)
        XCTAssertEqual(StationDwell.metroDwell(isServed: true, isRing: false, isTerminal: true), 420)
        XCTAssertEqual(StationDwell.metroDwell(isServed: true, isRing: true, isTerminal: true), 360, "a ring line has no terminal")
        XCTAssertEqual(StationDwell.metroDwell(isServed: false, isRing: false, isTerminal: true), 0, "a closed station is run through")
    }

    func testDwellRunsDownAndNeverBelowZero() {
        XCTAssertEqual(StationDwell.remainingDwell(360, after: 100), 260)
        XCTAssertEqual(StationDwell.remainingDwell(50, after: 100), 0)
        XCTAssertEqual(StationDwell.remainingDwell(0, after: 100), 0)
        XCTAssertEqual(StationDwell.remainingDwell(360, after: 0), 360)
    }

    /// `metroHeadwayRoundTripMinutes` with its running time stubbed to the
    /// distance, times 60 (the reference returns minutes).
    func testTheRoundTripIsTheReferencesInSeconds() {
        let cases: [(travel: Int64, stops: Int, ring: Bool, reference: Int64)] = [
            (250, 3, false, 6560), (600, 4, false, 14280), (90, 2, false, 2640), (650, 4, true, 7940), (300, 3, true, 4080),
        ]
        for c in cases {
            XCTAssertEqual(StationDwell.metroRoundTrip(travel: c.travel * tenths, stops: c.stops, isRing: c.ring), c.reference, "\(c)")
        }
        XCTAssertNil(StationDwell.metroRoundTrip(travel: 100, stops: 1, isRing: false))
    }

    /// `Bt` and `Ta` of `bootstrap-lazy`.
    func testDoorPhasesAreTheReferences() {
        let metro: [(total: Int64, remaining: Int64, phase: StationDwell.DoorPhase)] = [
            (360, 360, .opening), (360, 281, .opening), (360, 280, .boarding), (360, 200, .boarding), (360, 84, .boarding),
            (360, 83, .closing), (360, 0, .closing), (420, 341, .opening), (420, 500, .opening), (420, -10, .closing), (5, 2, .opening),
        ]
        for c in metro {
            let phase = StationDwell.doorPhase(
                total: c.total, remaining: c.remaining, opening: StationDwell.metroDoorOpening, closing: StationDwell.metroDoorClosing
            )
            XCTAssertEqual(phase, c.phase, "metro \(c)")
        }
        let highSpeed: [(total: Int64, remaining: Int64, phase: StationDwell.DoorPhase)] = [
            (1200, 1200, .opening), (1200, 1131, .opening), (1200, 1130, .boarding), (1200, 600, .boarding), (1200, 91, .boarding),
            (1200, 90, .closing), (600, 0, .closing), (1200, 1300, .opening),
        ]
        for c in highSpeed {
            let phase = StationDwell.doorPhase(
                total: c.total, remaining: c.remaining, opening: StationDwell.highSpeedDoorOpening, closing: StationDwell.highSpeedDoorClosing
            )
            XCTAssertEqual(phase, c.phase, "high-speed \(c)")
        }
        XCTAssertEqual(StationDwell.metroDoorCloseWarning(speed: 1), 102)
        XCTAssertEqual(StationDwell.metroDoorCloseWarning(speed: 0), 102)
        XCTAssertEqual(StationDwell.metroDoorCloseWarning(speed: 4), 408)
    }

    /// The dead constants keep the reference's values.
    func testTheReferencesUnusedConstantsAreKept() {
        XCTAssertEqual(StationDwell.referenceBoardingRate, 2)
        XCTAssertEqual(StationDwell.referenceTrainDwellTime, 440)
    }

    // MARK: - Ci high-speed timetables

    func testStopMinutesAreTheReferences() {
        let detail: [(arrival: Int64, departure: Int64, minutes: Int64)] = [
            (600, 602, 2), (600, 600, 0), (1439, 1, 2), (600, 599, 1439), (0, 1439, 1439), (100, -3000, 1220),
        ]
        for c in detail {
            XCTAssertEqual(StationDwell.stopMinutes(arrival: c.arrival, departure: c.departure), c.minutes, "\(c)")
        }
        let imported: [(arrival: Int64, departure: Int64, endpoint: Bool, minutes: Int64)] = [
            (600, 602, false, 2), (600, 602, true, 0), (1439, 1, false, 2), (1, 1439, false, 1438), (100, -3000, false, 0),
        ]
        for c in imported {
            XCTAssertEqual(StationDwell.importedStopMinutes(arrival: c.arrival, departure: c.departure, isEndpoint: c.endpoint), c.minutes, "\(c)")
        }
        let estimated: [(duration: Int64, departure: Int64, next: Int64, minutes: Int64?)] = [
            (40, 600, 638, 2), (40, 600, 640, nil), (40, 600, 641, nil), (100, 600, 639, nil), (30, 1430, 10, 10), (90, 600, 620, nil),
        ]
        for c in estimated {
            XCTAssertEqual(StationDwell.estimatedStopMinutes(listedDuration: c.duration, departure: c.departure, nextArrival: c.next), c.minutes, "\(c)")
        }
        XCTAssertEqual(StationDwell.insertedStopMinutes, 2)
    }

    // MARK: - Railway live map

    func testAStationsDwellIsItsOwnThenTheLinesThenTwentyFiveSeconds() {
        let cases: [(own: Int64?, line: Int64?, reference: Int64)] = [(40, 30, 40), (nil, 30, 30), (nil, nil, 25), (0, 0, 25), (0, 35, 35), (-5, nil, 25)]
        for c in cases {
            XCTAssertEqual(StationDwell.stationDwell(own: c.own.map { $0 * tenths }, line: c.line.map { $0 * tenths }), c.reference * tenths, "\(c)")
        }
    }

    func testTheCoastCycleIsTheReferences() {
        let cases: [(given: Int64?, gap: Int64?, run: Int64, cycle: Int64, dwell: Int64, travel: Int64)] = [
            (120, nil, 90, 120, 30, 90), (nil, 150, 100, 150, 50, 100), (nil, nil, 90, 115, 25, 90), (100, nil, 95, 100, 15, 85),
            (40, nil, 10, 40, 20, 20), (nil, -3, 70, 95, 25, 70), (0, 131, 120, 131, 15, 116),
        ]
        for c in cases {
            let result = StationDwell.coastCycle(given: c.given.map { $0 * tenths }, lastArrivalGap: c.gap.map { $0 * tenths }, run: c.run * tenths)
            XCTAssertEqual([result.cycle, result.dwell, result.travel], [c.cycle, c.dwell, c.travel].map { $0 * tenths }, "\(c)")
        }
    }

    func testThePeriodicTimetableIsTheReferences() {
        let cases: [(dwells: [Int64?], runs: [Int64], loop: Bool, calls: [[Int64]], period: Int64)] = [
            ([nil, 25, 30, nil], [67, 80, 90], false, [[0, 25], [92, 117], [197, 227], [317, 342], [432, 462], [542, 567], [634, 659]], 659),
            ([300, 20, 25, 40, 300], [100, 120, 90, 60], false,
             [[0, 300], [400, 420], [540, 565], [655, 695], [755, 1055], [1115, 1155], [1245, 1270], [1390, 1410], [1510, 1810]], 1810),
            ([0, 45], [70], false, [[0, 25], [95, 140], [210, 235]], 235),
            ([25, 25, 30], [50, 60, 70], true, [[0, 25], [75, 100], [160, 190], [260, 285]], 285),
        ]
        for c in cases {
            let result = StationDwell.periodicTimetable(dwells: c.dwells.map { $0.map { $0 * tenths } }, runs: c.runs.map { $0 * tenths }, isLoop: c.loop)
            XCTAssertEqual(result.calls.map { [$0.arrival, $0.departure] }, c.calls.map { $0.map { $0 * tenths } }, "\(c)")
            XCTAssertEqual(result.period, c.period * tenths)
        }
        // Out and back: 0, 1, 2, 3, 2, 1, 0.
        XCTAssertEqual(StationDwell.periodicTimetable(dwells: [nil, nil, nil, nil], runs: [1, 1, 1], isLoop: false).calls.map(\.station), [0, 1, 2, 3, 2, 1, 0])
        XCTAssertEqual(StationDwell.periodicTimetable(dwells: [nil, nil, nil], runs: [1, 1, 1], isLoop: true).calls.map(\.station), [0, 1, 2, 0])
    }

    func testTheObservedLineDwellIsTheReferences() {
        let cases: [(samples: [Int64], segments: Bool, firstRun: Int64, dwell: Int64?)] = [
            ([30, 28, 35, 25, 29, 31, 40, 22], true, 90, 30), ([30, 28, 35, 25, 29, 31, 40], true, 90, nil),
            ([200, 190, 185, 181, 250, 300, 400, 199], true, 90, nil), ([-3, -1, 0, -2, -5, 0, 0, -1, 4], true, 90, nil),
            ([30, 30, 30, 30, 30, 30, 30, 30, 31], false, 5, nil), ([30, 30, 30, 30, 30, 30, 30, 30, 31], false, 20, 30),
            ([100, 100, 100, 100, 100, 100, 100, 100], false, 150, nil),
        ]
        for c in cases {
            let dwell = StationDwell.observedLineDwell(samples: c.samples.map { $0 * tenths }, hasRunningTimes: c.segments, firstRun: c.firstRun * tenths)
            XCTAssertEqual(dwell, c.dwell.map { $0 * tenths }, "\(c)")
        }
        XCTAssertEqual(StationDwell.observedDwellFallback, 290)
    }

    func testTheLoopTrainsAreRetimedAsTheReferenceDoes() {
        let cases: [(lengths: [Int64], stops: [Bool], times: [[Int64]])] = [
            ([10, 20, 30, 40], [true, true, false, true, true], [[28800, 28920], [33204, 33324], [41892, 41892], [54744, 54864], [72000, 72000]]),
            ([7, 11, 13], [true, true, true, true], [[28800, 28920], [38594, 38714], [53915, 54035], [72000, 72000]]),
            ([3, 3, 3, 3, 3, 3, 3], [true, false, true, false, true, false, true, true],
             [[28800, 28920], [35023, 35023], [41126, 41246], [47349, 47349], [53452, 53572], [59675, 59675], [65778, 65898], [72000, 72000]]),
            ([123], [true, true], [[28800, 28920], [72000, 72000]]),
        ]
        for c in cases {
            let times = StationDwell.loopTimetable(lengths: c.lengths, stops: c.stops)
            XCTAssertEqual(times.map { [$0.arrival, $0.departure] }, c.times.map { $0.map { $0 * tenths } }, "\(c)")
        }
        XCTAssertEqual(StationDwell.highSpeedDepartureOffset, 300)
    }
}
