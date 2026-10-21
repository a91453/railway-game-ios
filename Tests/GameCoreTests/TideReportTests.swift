import Foundation
@testable import GameCore
import XCTest

/// The tide's ruler (research RIDERSHIP_SOURCES_AND_TIME_OF_DAY_2026-10-20.md
/// §2.4, step 1): a commuter line from three homes to two offices, played
/// for days without a player, printed as Markdown beside Taipei Metro's 2025
/// (the real-ridership tool `build_trtc_hourly.py`, whose numbers are copied
/// here; the test reads no file), so a change to the hours
/// trips keep (step 2) has a before and an after. It asserts nothing, and
/// changes no rule, and runs only on request:
///
///     TIDE_REPORT=7 swift test --skip-build --filter TideReportTests
///
/// `TIDE_REPORT` is the days to play; 7 or more take in a weekend.
final class TideReportTests: XCTestCase {
    private static let track = TestLine(tiles: 142)
    private static let homes = [("Home 1", 10), ("Home 2", 40), ("Home 3", 70)]
    private static let offices = [("Office 1", 100), ("Office 2", 130)]
    private static let line = LineID(rawValue: 1)
    /// Taipei Metro's hours, 06:00 to 01:00: the line is closed 01–06.
    private static let window = ServiceWindow.hours(open: 360, close: 1500)
    private static let closed = 1..<6

    /// Taipei Metro, 2025 (the tool's `trtc_hourly_2025.json`, the
    /// 259 working days and 106 days off of 128506): each hour's share of a
    /// day's entries, hour 0 being the last trains after midnight.
    private static let realWorking: [Double] = [
        0.0059, 0.0004, 0.0001, 0, 0, 0.0001, 0.0143, 0.0624, 0.1125, 0.0648, 0.0417, 0.0403,
        0.0438, 0.0452, 0.0417, 0.0433, 0.0581, 0.0871, 0.118, 0.077, 0.0477, 0.0458, 0.0359, 0.0139,
    ]
    private static let realOff: [Double] = [
        0.006, 0.0002, 0, 0, 0, 0, 0.0109, 0.0215, 0.0357, 0.0444, 0.0535, 0.0648,
        0.066, 0.0717, 0.0723, 0.0727, 0.0783, 0.0898, 0.0799, 0.0623, 0.0549, 0.0534, 0.0425, 0.0194,
    ]
    /// The ten residential stations' (蘆洲, 南勢角, 徐匯中學…) morning
    /// (07–09) share of their working day's entries and morning entries ÷
    /// exits, and the ten office stations' (台大醫院, 松江南京, 南港軟體園區…)
    /// evening (17–19) entries ÷ morning entries: min, median, max.
    private static let realMorningShare = (0.346, 0.386, 0.431)
    private static let realMorningRatio = (5.8, 6.872, 12.974)
    private static let realEveningRatio = (4.578, 5.34, 9.465)

    func testACommuterLine() throws {
        guard let value = ProcessInfo.processInfo.environment["TIDE_REPORT"], let days = Int(value), days > 0 else {
            throw XCTSkip("set TIDE_REPORT=<days> to print the tide report")
        }
        var world = try build()
        let stations = world.stations.map(\.id)
        let homes = Array(stations.prefix(Self.homes.count)), offices = Array(stations.suffix(Self.offices.count))
        let positions = Dictionary(uniqueKeysWithValues: stations.enumerated().map { ($1, $0) })

        let zero = [Int64](repeating: 0, count: 24)
        // Entries as released, each hour of each kind of day.
        var released = (working: zero, off: zero)
        // The fullest train each minute, toward the offices and back, by
        // hour, in thousandths of its rated capacity.
        var fullest = (toward: zero, back: zero)
        var load = (toward: zero, back: zero, minutes: zero)
        // Each station's entries and exits by the hour they enter, as the
        // world's demand gives them on a working day (the hour of entry is
        // what 128506 counts both by).
        var table = Dictionary(uniqueKeysWithValues: stations.map { ($0, (entries: zero, exits: zero)) })
        var tabled = false
        var dayKinds: [Bool] = []
        // Working days: those released while the line is closed (01–06)
        // and still waiting when it opens, how many of them are still
        // waiting at 07:00, and how many boarded anywhere 06–07.
        var night = (piled: Int64(0), left: Int64(0), boarded: Int64(0), mornings: 0)

        func piled() -> Int64 {
            let now = world.clock.now.minute
            return world.passengers.reduce(0) { sum, station in
                sum + station.waiting.reduce(0) { sum, group in
                    let ago = now - group.since.minute
                    return sum + (ago < 1440 && Self.closed.contains(group.since.minuteOfDay / 60) ? group.count : 0)
                }
            }
        }
        // Released, less those who left a full station or gave up, less
        // those still waiting: those who have boarded.
        func boarded() -> Int64 {
            world.passengers.reduce(0) { $0 + $1.released - $1.overflowed - $1.abandoned - $1.waitingCount }
        }

        func total() -> Int64 { world.passengers.reduce(0) { $0 + $1.released } }
        for _ in 0..<days {
            let weekend = world.isDemandWeekend
            dayKinds.append(weekend)
            if !weekend, !tabled {
                tabled = true
                for origin in stations {
                    for destination in stations where origin != destination {
                        let trips = world.hourlyDemand(from: origin, to: destination)
                        let entries = table[origin]?.entries ?? zero, exits = table[destination]?.exits ?? zero
                        table[origin]?.entries = zip(entries, trips).map(+)
                        table[destination]?.exits = zip(exits, trips).map(+)
                    }
                }
            }
            for hour in 0..<24 {
                let before = total()
                let boardedBefore = boarded()
                if !weekend, hour == 6 {
                    night.piled += piled()
                    night.mornings += 1
                }
                for _ in 0..<60 {
                    try world.advance(ticks: 1)
                    var toward: Int64 = 0, back: Int64 = 0
                    for train in world.trains {
                        guard let riders = world.riders.first(where: { $0.train == train.id }) else { continue }
                        var on = (toward: Int64(0), back: Int64(0))
                        for group in riders.groups {
                            if positions[group.destination, default: 0] > positions[group.origin, default: 0] { on.toward += group.count } else { on.back += group.count }
                        }
                        toward = max(toward, 1_000 * on.toward / train.ratedCapacity)
                        back = max(back, 1_000 * on.back / train.ratedCapacity)
                    }
                    if !weekend {
                        fullest.toward[hour] = max(fullest.toward[hour], toward)
                        fullest.back[hour] = max(fullest.back[hour], back)
                        load.toward[hour] += toward
                        load.back[hour] += back
                        load.minutes[hour] += 1
                    }
                }
                if weekend { released.off[hour] += total() - before } else { released.working[hour] += total() - before }
                if !weekend, hour == 6 {
                    night.left += piled()
                    night.boarded += boarded() - boardedBefore
                }
            }
        }

        func shares(_ counts: [Int64]) -> [Double] {
            let sum = Double(counts.reduce(0, +))
            return counts.map { sum > 0 ? Double($0) / sum : 0 }
        }
        func band(_ shares: [Double], _ hours: Range<Int>) -> Double { hours.reduce(0) { $0 + shares[$1] } }
        func percent(_ value: Double) -> String { String(format: "%.1f%%", 100 * value) }
        func spread(_ values: [Double], _ format: (Double) -> String) -> String {
            let sorted = values.sorted()
            guard let low = sorted.first, let high = sorted.last else { return "-" }
            let median = sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            return "\(format(low)) / \(format(median)) / \(format(high))"
        }
        func times(_ value: Double) -> String { String(format: "%.1f×", value) }
        func percents(_ triple: (Double, Double, Double)) -> String { "\(percent(triple.0)) / \(percent(triple.1)) / \(percent(triple.2))" }
        func timesTriple(_ triple: (Double, Double, Double)) -> String { "\(times(triple.0)) / \(times(triple.1)) / \(times(triple.2))" }

        let working = shares(released.working), off = shares(released.off)
        let tableShares = shares((0..<24).map { hour in stations.reduce(0) { $0 + (table[$1]?.entries[hour] ?? 0) } })
        let hasOff = dayKinds.contains(true)
        let bands: [(String, Range<Int>)] = [("00–06", 0..<6), ("06–07", 6..<7), ("07–09 morning peak", 7..<9), ("09–16", 9..<16),
                                             ("16–19 evening peak", 16..<19), ("19–23", 19..<23), ("23–24", 23..<24)]
        var lines = [
            "### The tide: a line from three homes to two offices, \(days) days (\(dayKinds.filter { !$0 }.count) working, \(dayKinds.filter { $0 }.count) off)",
            "",
            "Each band's share of a day's entries. Game: as released (and, on a working day, as the demand table gives them by hour); Taipei Metro: 2025, 128506.",
            "",
            "| Hours | Game working day (released) | Game working day (table) | Taipei Metro working day | Game day off | Taipei Metro day off |",
            "| --- | --: | --: | --: | --: | --: |",
        ]
        for (name, hours) in bands {
            lines.append("| \(name) | \(percent(band(working, hours))) | \(percent(band(tableShares, hours))) | \(percent(band(Self.realWorking, hours))) | "
                + "\(hasOff ? percent(band(off, hours)) : "-") | \(percent(band(Self.realOff, hours))) |")
        }
        let busiest = working.indices.max { working[$0] < working[$1] } ?? 0
        let realBusiest = Self.realWorking.indices.max { Self.realWorking[$0] < Self.realWorking[$1] } ?? 0
        let offPeak = band(working, 10..<16) / 6, realOffPeak = band(Self.realWorking, 10..<16) / 6
        lines += [
            "",
            "Busiest hour of a working day: game \(busiest):00, \(percent(working[busiest])), \(times(working[busiest] / offPeak)) the 10–16 average; "
                + "Taipei Metro \(realBusiest):00, \(percent(Self.realWorking[realBusiest])), \(times(Self.realWorking[realBusiest] / realOffPeak)).",
            "",
            "Game working day as released, each hour (%): `\(working.map { String(format: "%.1f", 100 * $0) }.joined(separator: " "))`",
            "",
            "Taipei Metro working day, each hour (%): `\(Self.realWorking.map { String(format: "%.1f", 100 * $0) }.joined(separator: " "))`",
            "",
            "#### Homes and offices (working day; min / median / max)",
            "",
            "| | Game | Taipei Metro (ten stations each) |",
            "| --- | --- | --- |",
        ]
        func entries(_ id: StationID, _ hours: Range<Int>) -> Double { Double(hours.reduce(0) { $0 + (table[id]?.entries[$1] ?? 0) }) }
        func exits(_ id: StationID, _ hours: Range<Int>) -> Double { Double(hours.reduce(0) { $0 + (table[id]?.exits[$1] ?? 0) }) }
        let morningShare = homes.map { entries($0, 7..<9) / max(entries($0, 0..<24), 1) }
        let morningRatio = homes.map { entries($0, 7..<9) / max(exits($0, 7..<9), 1) }
        let eveningRatio = offices.map { entries($0, 17..<19) / max(entries($0, 7..<9), 1) }
        lines += [
            "| A home's 07–09 entries, share of its day | \(spread(morningShare, percent)) | \(percents(Self.realMorningShare)) |",
            "| A home's 07–09 entries ÷ exits | \(spread(morningRatio, times)) | \(timesTriple(Self.realMorningRatio)) |",
            "| An office's 17–19 entries ÷ its 07–09 entries | \(spread(eveningRatio, times)) | \(timesTriple(Self.realEveningRatio)) |",
            "",
            "#### Within the hours the line runs (06:00–01:00, as Taipei Metro; working day)",
            "",
            "The same shares with the day's entries between 06:00 and 01:00 as the whole: Taipei Metro has no trains 01–06, so its share is all within them.",
            "",
            "| | Game, of the whole day | Game, of 06–01 | Taipei Metro, of the whole day | Taipei Metro, of 06–01 |",
            "| --- | --: | --: | --: | --: |",
        ]
        let open = Array(0..<1) + Array(6..<24)
        func within(_ shares: [Double], _ hours: Range<Int>) -> Double { band(shares, hours) / open.reduce(0) { $0 + shares[$1] } }
        for (name, hours) in [("07–09, as released", 7..<9), ("17–19, as released", 17..<19), ("01–06, as released", 1..<6)] {
            let closedRow = hours == 1..<6
            lines.append("| \(name) | \(percent(band(working, hours))) | \(closedRow ? "-" : percent(within(working, hours))) | "
                + "\(percent(band(Self.realWorking, hours))) | \(closedRow ? "-" : percent(within(Self.realWorking, hours))) |")
        }
        let openMorningShare = homes.map { home in entries(home, 7..<9) / max(entries(home, 0..<1) + entries(home, 6..<24), 1) }
        // The file has no station's 01–06 hours apart, but they hold 0.06%
        // of Taipei Metro's working-day entries: the ten homes' share of
        // 06–01 is theirs of the whole day to a tenth of a point.
        let realClosed = band(Self.realWorking, 1..<6)
        func scaled(_ triple: (Double, Double, Double)) -> (Double, Double, Double) {
            (triple.0 / (1 - realClosed), triple.1 / (1 - realClosed), triple.2 / (1 - realClosed))
        }
        let mornings = Double(max(night.mornings, 1))
        let piledAMorning = Double(night.piled) / mornings
        let boardedFromNight = Double(night.piled - night.left) / mornings
        let boardedAt6 = Double(night.boarded) / mornings
        let releasedAtNight = Double((1..<6).reduce(0) { $0 + released.working[$1] }) / mornings
        lines += [
            "| A home's 07–09 entries (median of three; Taipei Metro min / median / max) | \(spread(morningShare, percent)) | "
                + "\(spread(openMorningShare, percent)) | \(percents(Self.realMorningShare)) | \(percents(scaled(Self.realMorningShare))) |",
            "",
            "Taipei Metro's homes, of 06–01: their whole-day share ÷ (1 − the system's 01–06 share, \(percent(realClosed))); the file keeps no station's night hours apart.",
            "",
            "#### The night: released while the line is closed (01–06), a working day",
            "",
            "| | Passengers |",
            "| --- | --: |",
            "| Released 01–06 (all stations) | \(String(format: "%.0f", releasedAtNight)) |",
            "| Of them still waiting at 06:00, when the first trains leave | \(String(format: "%.0f", piledAMorning)) |",
            "| Of those, boarded 06–07 | \(String(format: "%.0f", boardedFromNight)) |",
            "| Boarded 06–07 in all | \(String(format: "%.0f", boardedAt6)) |",
            "| Share of 06–07's boardings that waited from the night | \(percent(boardedFromNight / max(boardedAt6, 1))) |",
            "",
            "Taipei Metro: no trains 01–06, and the gates are shut; no one is counted entering then.",
            "",
            "#### Trains in the peaks (working day; load in % of rated capacity)",
            "",
            "| Hours | Fullest toward the offices | Fullest back | Average toward | Average back |",
            "| --- | --: | --: | --: | --: |",
        ]
        for (name, hours) in [("06–07, the first trains", 6..<7), ("07–09", 7..<9), ("17–19", 17..<19), ("10–16", 10..<16)] {
            let minutes = Double(max(hours.reduce(0) { $0 + load.minutes[$1] }, 1))
            func maximum(_ values: [Int64]) -> String { "\((hours.map { values[$0] }.max() ?? 0) / 10)%" }
            func mean(_ values: [Int64]) -> String { String(format: "%.0f%%", Double(hours.reduce(0) { $0 + values[$1] }) / minutes / 10) }
            lines.append("| \(name) | \(maximum(fullest.toward)) | \(maximum(fullest.back)) | \(mean(load.toward)) | \(mean(load.back)) |")
        }
        lines += ["", "Taipei Metro's trains: 128506 counts gates, not trains; no load to set beside these."]
        print(lines.joined(separator: "\n"))
    }

    /// A straight track of 142 tiles (some 2.3 km), Home 1–3 and Office 1–2
    /// 480 m apart in that order, one line through them 06:00–01:00, three
    /// trains of one car (a test platform holds one; two off peak, one at
    /// night), homes of 4,000 trips a day and offices of 6,000, weekly
    /// demand on.
    private func build() throws -> GameWorld {
        var world = try makeWorld(width: Int64(Self.track.tiles + 2) * TestLine.tile, height: 4 * TestLine.tile, balance: 100_000_000)
        try Self.track.build(in: &world)
        var stops: [StationID] = []
        for (name, x) in Self.homes + Self.offices {
            stops.append(try Self.track.buildStation(named: name, beside: x, at: 1, in: &world))
        }
        try world.createLine(named: "Commuter", stops: stops)
        try world.setLineServiceWindow(Self.line, to: Self.window)
        try world.setLineTrainsInService(Self.line, to: TrainsInService(peak: 3, offPeak: 2, low: 1))
        for (index, (x, east)) in [(10, true), (70, true), (130, false)].enumerated() {
            let train = try world.purchaseTrain(named: "Train \(index + 1)").id
            try world.setTrainCars(train, to: 1)
            try world.placeTrain(train, at: Self.track.at(x, facingEast: east))
            try world.setTrainMovementRate(train, to: 1024)
            try world.assignTrain(train, to: Self.line)
        }
        for id in stops.prefix(Self.homes.count) {
            try world.setStationDemand(id, to: StationDemand(kind: .residential, dailyTrips: 4_000))
        }
        for id in stops.suffix(Self.offices.count) {
            try world.setStationDemand(id, to: StationDemand(kind: .office, dailyTrips: 6_000))
        }
        world.setWeeklyDemand(true)
        world.setSpeed(.normal)
        return world
    }
}
