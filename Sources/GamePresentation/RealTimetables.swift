import Foundation

// The real timetables of the `Railway/` site (`site_archive_clean/data/`),
// typed. Two formats, both read as the site reads them:
//
// - `<system>_times.json` (metro and light rail, the site's `freq` systems):
//   for each line, its timetable sets ("平日", "週六", …), each a list of
//   trips; a trip is a flat list `[station index, second of the day,
//   station index, second, …]` along the line's stations in
//   `<system>.json`. Seconds run past 86,400 for trips after midnight.
//   `days` names the set of each weekday (Sunday first), `holiday` the set
//   for public holidays, `dates` a set for particular days, and `kinds` (the
//   Airport MRT) one character per trip of a set: its kind, `0` for none.
//   The site picks the set of a service day in `index.html`
//   `prepFreqTimes` (ported in ``RealLineTimetable/setName(forServiceDay:)``).
// - `api/thsr-schedule.json` (the High Speed Rail, a `sched` system): one
//   day's trains, each with its stops' arrival and departure seconds.
//
// Not bundled: the site's `tra_schedule_dense.json` (TRA's every train,
// 7.6 MB, more than the rest of the data together), which nothing in the
// game uses yet; TRA's lines keep the headways of `tra.json`.
//
// Nothing here reaches GameCore: a save keeps none of it.

/// Why a file of real railway data could not be read, for the debug list
/// of load problems (``RealRailways/loadIssues``). A problem drops only the
/// file (or the part of it) it names.
public struct RealDataLoadIssue: Hashable, Sendable, CustomStringConvertible {
    /// The file, as the app bundles it (`tra.json`).
    public let file: String
    public let reason: String

    public init(file: String, reason: String) {
        self.file = file
        self.reason = reason
    }

    public init(file: String, error: any Error) {
        self.init(file: file, reason: String(describing: error))
    }

    public var description: String { "\(file): \(reason)" }
}

/// One trip of a metro or light rail timetable: the stations it calls at,
/// in order, each with its second of the service day.
public struct RealTimetableTrip: Hashable, Sendable {
    public struct Call: Hashable, Sendable {
        /// Index into the line's stations (`<system>.json`).
        public let stationIndex: Int
        /// Second of the service day; past 86,400 after midnight.
        public let second: Int

        public init(stationIndex: Int, second: Int) {
            self.stationIndex = stationIndex
            self.second = second
        }
    }

    public let calls: [Call]
    /// The trip's kind from the set's `kinds` (the Airport MRT: `1` all
    /// stops, `2` express), or `nil` where there is none (`0`).
    public let kind: Character?

    public init(calls: [Call], kind: Character? = nil) {
        self.calls = calls
        self.kind = kind
    }

    /// The trip as the file has it, `[index, second, index, second, …]`;
    /// `nil` for an odd count or fewer than two calls.
    init?(flat: [Int], kind: Character?) {
        guard flat.count >= 4, flat.count.isMultiple(of: 2) else { return nil }
        calls = stride(from: 0, to: flat.count, by: 2).map { Call(stationIndex: flat[$0], second: flat[$0 + 1]) }
        self.kind = kind
    }

    /// The site's `freqTrainTime`: second `secondOfDay` (0 ..< 86,400) on
    /// the trip's own clock (a trip that runs past midnight sees the small
    /// hours as the day before's), or `nil` while it does not run.
    public func time(at secondOfDay: Int) -> Int? {
        guard let first = calls.first?.second, let last = calls.last?.second else { return nil }
        var t = secondOfDay
        if t < first, t + 86_400 <= last { t += 86_400 }
        return t < first || t > last ? nil : t
    }
}

/// One line's timetable sets (`<system>_times.json` `lines[id]`).
public struct RealLineTimetable: Hashable, Sendable {
    /// The set of each weekday, Sunday first (the site's `days`).
    public let days: [String]
    /// The set for public holidays.
    public let holiday: String?
    /// Each set's trips, by its name.
    public let sets: [String: [RealTimetableTrip]]
    /// The set for particular service days (`YYYY-MM-DD`).
    public let dates: [String: String]
    /// Whether the trips are worked out from the official headway and
    /// first and last trains rather than published (the site's
    /// `estimated`).
    public let isEstimated: Bool

    /// The site's `prepFreqTimes`: the set a service day (`YYYY-MM-DD`)
    /// runs. A public holiday (``RealTimetables/publicHolidays``) runs the
    /// holiday set (or the first day's), any other day its weekday's; a
    /// day the file names runs its own set.
    public func setName(forServiceDay day: String) -> String? {
        var name: String?
        switch RealTimetables.publicHolidays[day] {
        case 1: name = holiday ?? days.first
        case 2: name = days.count > 1 ? days[1] : nil
        default: name = RealTimetables.weekday(of: day).flatMap { days.indices.contains($0) ? days[$0] : nil }
        }
        if let special = dates[day], sets[special] != nil { name = special }
        return name
    }

    /// The trips of the set a service day runs; none for an unknown set.
    public func trips(forServiceDay day: String) -> [RealTimetableTrip] {
        setName(forServiceDay: day).flatMap { sets[$0] } ?? []
    }
}

/// A system's timetables (`<system>_times.json`).
public struct RealSystemTimetable: Hashable, Sendable {
    public let system: String
    public let sourceNotes: String?
    public let isEstimated: Bool
    /// Each line's, by the line's ID in `<system>.json`.
    public let lines: [String: RealLineTimetable]

    public init(data: Data) throws {
        struct RawLine: Decodable {
            let days: [String]?
            let holiday: String?
            let sets: [String: [[Int]]]
            let dates: [String: String]?
            let kinds: [String: String]?
            let estimated: Bool?
        }
        struct RawFile: Decodable {
            let system: String
            let source_notes: String?
            let estimated: Bool?
            let lines: [String: RawLine]
        }
        let raw = try JSONDecoder().decode(RawFile.self, from: data)
        var lines: [String: RealLineTimetable] = [:]
        for (id, line) in raw.lines {
            var sets: [String: [RealTimetableTrip]] = [:]
            for (name, flat) in line.sets {
                // The site applies a set's kinds only when there is one for
                // each trip.
                let kinds = line.kinds?[name].map(Array.init).flatMap { $0.count == flat.count ? $0 : nil }
                sets[name] = try flat.enumerated().map { index, trip in
                    let kind = kinds.flatMap { $0[index] == "0" ? nil : $0[index] }
                    guard let parsed = RealTimetableTrip(flat: trip, kind: kind) else {
                        throw RealTimetables.FormatError.malformedTrip(line: id, set: name, index: index)
                    }
                    return parsed
                }
            }
            lines[id] = RealLineTimetable(
                days: line.days ?? [],
                holiday: line.holiday,
                sets: sets,
                dates: line.dates ?? [:],
                isEstimated: line.estimated ?? raw.estimated ?? false
            )
        }
        system = raw.system
        sourceNotes = raw.source_notes
        isEstimated = raw.estimated ?? false
        self.lines = lines
    }
}

/// One day's trains of a scheduled system (`api/thsr-schedule.json`).
public struct RealDailySchedule: Hashable, Sendable {
    public struct Stop: Hashable, Sendable {
        public let name: String
        public let coordinate: RealRailways.Coordinate
        public let arrivalSecond: Int
        public let departureSecond: Int
        /// Whether the train stops (`stop`), not just passes.
        public let stops: Bool
    }

    public struct Train: Hashable, Sendable {
        public let number: String
        public let stops: [Stop]
    }

    public let system: String
    /// The day, `YYYYMMDD`.
    public let date: String?
    public let trains: [Train]

    public init(data: Data) throws {
        struct RawStop: Decodable {
            let name: String
            let lat: Double
            let lon: Double
            let arrSec: Int
            let depSec: Int
            let stop: Bool?
        }
        struct RawTrain: Decodable {
            let train: String
            let stops: [RawStop]
        }
        struct RawFile: Decodable {
            let system: String
            let date: String?
            let trains: [RawTrain]
        }
        let raw = try JSONDecoder().decode(RawFile.self, from: data)
        system = raw.system
        date = raw.date
        trains = raw.trains.map { train in
            Train(number: train.train, stops: train.stops.map {
                Stop(
                    name: $0.name,
                    coordinate: RealRailways.Coordinate(latitude: $0.lat, longitude: $0.lon),
                    arrivalSecond: $0.arrSec,
                    departureSecond: $0.depSec,
                    stops: $0.stop ?? true
                )
            })
        }
    }

    /// Each way's headway, in seconds, in the site's peak hours
    /// (``RealTimetables/peakHours``) or outside them: the time divided by
    /// the trains of the busier direction that leave their first stop in
    /// it. The site has no headway for a scheduled system (it runs each
    /// train), so this is the game's own reading of the day's trains.
    /// `nil` without trains.
    public func headwaySeconds(peak: Bool) -> Int? {
        var counts: [String: Int] = [:]
        var first = Int.max, last = Int.min
        for train in trains {
            guard let start = train.stops.first, let end = train.stops.last, train.stops.count >= 2 else { continue }
            first = min(first, start.departureSecond)
            last = max(last, start.departureSecond)
            guard RealTimetables.isPeak(second: start.departureSecond) == peak else { continue }
            // The High Speed Rail runs north and south.
            counts[end.coordinate.latitude < start.coordinate.latitude ? "south" : "north", default: 0] += 1
        }
        guard let busiest = counts.values.max(), busiest > 0, first < last else { return nil }
        let peakSeconds = RealTimetables.peakHours.reduce(0.0) { $0 + ($1.upperBound - $1.lowerBound) * 3_600 }
        let span = peak ? peakSeconds : max(Double(last - first) - peakSeconds, 3_600)
        return Int((span / Double(busiest)).rounded())
    }
}

public enum RealTimetables {
    public enum FormatError: Error, Hashable {
        case malformedTrip(line: String, set: String, index: Int)
    }

    /// The site's peak hours (`index.html` `PEAK`): 07:00–09:00 and
    /// 17:00–19:30.
    public static let peakHours: [ClosedRange<Double>] = [7 ... 9, 17 ... 19.5]

    /// The site's `isPeak(h)`: whether hour `hour` (fractional) is in the
    /// peak, `[a, b)`.
    public static func isPeak(hour: Double) -> Bool {
        peakHours.contains { hour >= $0.lowerBound && hour < $0.upperBound }
    }

    /// ``isPeak(hour:)`` at a second of the day (past 86,400 wraps).
    public static func isPeak(second: Int) -> Bool {
        isPeak(hour: Double(second % 86_400) / 3_600)
    }

    /// The site's `headwayOf(ln, h)`: the peak headway in the peak, the
    /// off-peak one otherwise.
    public static func headway(of line: RealOperationLine, atHour hour: Double) -> Int? {
        isPeak(hour: hour) ? line.peakHeadwaySec : line.offpeakHeadwaySec
    }

    /// The site's `TW_DAYTYPE`: Taiwan's public holidays of 2026 and 2027,
    /// as `index.html` lists them (1: a holiday).
    public static let publicHolidays: [String: Int] = [
        "2026-01-01": 1, "2026-02-15": 1, "2026-02-16": 1, "2026-02-17": 1, "2026-02-18": 1, "2026-02-19": 1,
        "2026-02-20": 1, "2026-02-27": 1, "2026-02-28": 1, "2026-04-03": 1, "2026-04-04": 1, "2026-04-05": 1,
        "2026-04-06": 1, "2026-05-01": 1, "2026-06-19": 1, "2026-09-25": 1, "2026-09-28": 1, "2026-10-09": 1,
        "2026-10-10": 1, "2026-10-25": 1, "2026-10-26": 1, "2026-12-25": 1,
        "2027-01-01": 1, "2027-02-04": 1, "2027-02-05": 1, "2027-02-06": 1, "2027-02-07": 1, "2027-02-08": 1,
        "2027-02-09": 1, "2027-02-10": 1, "2027-02-28": 1, "2027-03-01": 1, "2027-04-04": 1, "2027-04-05": 1,
        "2027-04-06": 1, "2027-04-30": 1, "2027-05-01": 1, "2027-06-09": 1, "2027-09-15": 1, "2027-09-28": 1,
        "2027-10-10": 1, "2027-10-11": 1, "2027-10-25": 1, "2027-12-24": 1, "2027-12-25": 1, "2027-12-31": 1,
    ]

    /// The weekday of `YYYY-MM-DD`, 0 for Sunday (JavaScript's
    /// `getUTCDay`), or `nil` for anything else. Computed from the
    /// proleptic Gregorian calendar, without a clock or time zone.
    public static func weekday(of day: String) -> Int? {
        let parts = day.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1 ... 12).contains(m), (1 ... 31).contains(d) else { return nil }
        // Days from 1970-01-01 (Howard Hinnant's days_from_civil).
        let year = m <= 2 ? y - 1 : y
        let era = (year >= 0 ? year : year - 399) / 400
        let yoe = year - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146_097 + doe - 719_468
        // 1970-01-01 was a Thursday.
        return ((days % 7) + 7 + 4) % 7
    }
}

/// One line's real trains for the real-world demo (decision 133), as
/// `tools/real-timetables/extract_pingxi_runs.py` writes them
/// (`tra_pingxi_runs.json`, from TRA's open data): the line's stations in
/// order, its trains each from one of them to another with every call's
/// arrival and departure second of the day and the weekdays it runs (0
/// Sunday), and where its trainsets stand at midnight.
public struct RealLineRuns: Sendable, Equatable {
    public struct Call: Sendable, Equatable {
        public let station: String
        public let arrival: Int64
        public let departure: Int64
    }

    public struct Run: Sendable, Equatable {
        /// The train number (`回送` for a positioning run).
        public let train: String
        public let calls: [Call]
        public let days: [Int]
        /// Whether it is not one of TRA's trains but added so the day ends
        /// where it began.
        public let positioning: Bool
    }

    /// The line's stations, by their Chinese names.
    public let stops: [String]
    public let runs: [Run]
    /// The trainsets standing at each station at midnight.
    public let overnight: [String: Int]

    /// Reads the file. Throws for one out of shape: a call that is not
    /// `[station, arrival, departure]`, or a run calling at a station that
    /// is not one of the line's.
    public init(data: Data) throws {
        struct File: Decodable {
            struct Run: Decodable {
                let train: String
                let calls: [[Call]]
                let days: [Int]
                let positioning: Bool?
            }

            enum Call: Decodable {
                case name(String)
                case second(Int64)

                init(from decoder: any Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let second = try? container.decode(Int64.self) {
                        self = .second(second)
                    } else {
                        self = .name(try container.decode(String.self))
                    }
                }
            }

            let stops: [String]
            let overnight: [String: Int]
            let runs: [Run]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        func corrupt(_ why: String) -> DecodingError {
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: why))
        }
        stops = file.stops
        overnight = file.overnight
        runs = try file.runs.map { run in
            let calls = try run.calls.map { call -> Call in
                guard call.count == 3, case .name(let station) = call[0], case .second(let arrival) = call[1], case .second(let departure) = call[2],
                      file.stops.contains(station)
                else { throw corrupt("Train \(run.train)'s call is not [one of the line's stations, arrival, departure].") }
                return Call(station: station, arrival: arrival, departure: departure)
            }
            return Run(train: run.train, calls: calls, days: run.days, positioning: run.positioning ?? false)
        }
    }
}
