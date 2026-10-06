import Foundation
import GameCore
import XCTest

// Deterministic property testing: seeded generators, independent reference
// models and world invariants, shared by the property suites.
//
// Every campaign runs a fixed number of cases for each canonical seed. Each
// case draws from its own generator, derived only from (seed, case index),
// so a failure report ("[suite] seed 0x… case n") replays that one case
// without running the others. Nothing reads the clock, the locale or global
// randomness, and no expectation depends on Set or Dictionary order.

// MARK: - Randomness

/// A small deterministic generator (SplitMix64), so generated cases are the
/// same on every run and platform.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `0..<bound`. The modulo bias is irrelevant for generating
    /// test cases.
    mutating func below(_ bound: Int) -> Int {
        precondition(bound > 0, "below(_:) needs a positive bound")
        return Int(next() % UInt64(bound))
    }

    /// `true` with probability `numerator / denominator`.
    mutating func chance(_ numerator: Int, in denominator: Int) -> Bool {
        below(denominator) < numerator
    }

    mutating func element<T>(of array: [T]) -> T {
        array[below(array.count)]
    }

    mutating func int64(in range: ClosedRange<Int64>) -> Int64 {
        let span = UInt64(bitPattern: range.upperBound &- range.lowerBound) &+ 1
        guard span != 0 else { return Int64(bitPattern: next()) }
        return range.lowerBound &+ Int64(bitPattern: next() % span)
    }

    /// The elements of `array` in a generated order (Fisher–Yates).
    mutating func shuffled<T>(_ array: [T]) -> [T] {
        var result = array
        var index = result.count - 1
        while index > 0 {
            result.swapAt(index, below(index + 1))
            index -= 1
        }
        return result
    }
}

// MARK: - Campaigns

enum PropertySeeds {
    /// The seeds every campaign runs in CI. Fixed: CI never picks new ones.
    static let canonical: [UInt64] = [0x5EED_A001, 0x5EED_A002, 0x5EED_A003, 0x5EED_A004]

    /// The canonical seeds, plus `PROPERTY_STRESS=<n>` more for a longer
    /// local run. The extra seeds are derived from the canonical ones, so a
    /// stress run is as reproducible as CI.
    static var active: [UInt64] {
        let extra = ProcessInfo.processInfo.environment["PROPERTY_STRESS"].flatMap { Int($0) } ?? 0
        var derive = SplitMix64(seed: 0x5EED_5EED)
        return canonical + (0..<max(0, extra)).map { _ in derive.next() }
    }
}

/// What a campaign has seen so far. Owned by one campaign run, touched only
/// by the test thread; there is no global state.
final class CampaignLog {
    var failingCases = 0
    var failures = 0
}

/// Checks how many cases a campaign ran. Skipped while
/// `PROPERTY_REPLAY` runs a single case.
func assertVolume(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    guard ProcessInfo.processInfo.environment["PROPERTY_REPLAY"] == nil else { return }
    XCTAssertTrue(condition(), message, file: file, line: line)
}

/// One generated case of a campaign.
struct PropertyCase {
    let suite: String
    let seed: UInt64
    let index: Int
    /// This case's own generator.
    var random: SplitMix64
    /// Parameters written down while generating, for the failure report.
    private(set) var notes: [String] = []
    private let log: CampaignLog

    init(suite: String, seed: UInt64, index: Int, log: CampaignLog = CampaignLog()) {
        self.suite = suite
        self.seed = seed
        self.index = index
        self.log = log
        var mixer = SplitMix64(seed: seed ^ (UInt64(index) &* 0xD1B5_4A32_D192_ED03))
        self.random = SplitMix64(seed: mixer.next())
    }

    var label: String {
        "[\(suite)] seed 0x\(String(seed, radix: 16, uppercase: true)) case \(index)"
    }

    mutating func note(_ text: @autoclosure () -> String) {
        notes.append(text())
    }

    /// The failure text: which case, and how it was generated.
    func report(_ message: String) -> String {
        ([label + ": " + message] + notes.map { "  " + $0 }).joined(separator: "\n")
    }

    /// Fails this case with its full report.
    func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        log.failures += 1
        XCTFail(report(message), file: file, line: line)
    }

    /// Fails this case unless `condition` holds.
    func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if !condition() {
            fail(message(), file: file, line: line)
        }
    }
}

/// Runs `body` for `cases` cases of every active seed and returns how many
/// ran. Stops a campaign after three failing cases, so one bug does not
/// flood the log; `PROPERTY_REPLAY=<suite>@<seed hex>@<case>` runs one case.
@discardableResult
func runCampaign(
    _ suite: String,
    cases: Int,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: (inout PropertyCase) throws -> Void
) rethrows -> Int {
    let replay = ProcessInfo.processInfo.environment["PROPERTY_REPLAY"]?.split(separator: "@").map(String.init)
    if let replay, replay.first != suite { return 0 }
    let log = CampaignLog()
    var ran = 0
    for seed in PropertySeeds.active {
        if let replay, replay.count == 3, UInt64(replay[1], radix: 16) != seed { continue }
        for index in 0..<cases {
            if let replay, replay.count == 3, Int(replay[2]) != index { continue }
            var testCase = PropertyCase(suite: suite, seed: seed, index: index, log: log)
            let failuresBefore = log.failures
            try body(&testCase)
            ran += 1
            if log.failures > failuresBefore {
                log.failingCases += 1
                if log.failingCases >= 3 {
                    XCTFail("[\(suite)] stopped after \(log.failingCases) failing cases", file: file, line: line)
                    return ran
                }
            }
        }
    }
    return ran
}

/// A running FNV-1a digest of everything a campaign observed. Two runs of
/// the same campaign (in one process, or in two processes with different
/// hash seeds) must give the same digest.
struct Digest {
    private(set) var value: UInt64 = 0xCBF2_9CE4_8422_2325

    mutating func add(_ text: String) {
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value &*= 0x0000_0100_0000_01B3
        }
        value ^= 0xFF
        value &*= 0x0000_0100_0000_01B3
    }

    var hex: String { String(value, radix: 16, uppercase: true) }
}

// MARK: - Generated values

/// Stage W2c: performances the campaigns give trains and lines: presets of
/// every kind (with and without coasting and alternatives), and some that
/// no train or line may have.
enum PerformanceSamples {
    /// A crawl at 1 km/h, about a link a minute, as trains went before
    /// Stage W2c: on the campaigns' small maps a real train's run is over in
    /// seconds, a crawl's lasts minutes.
    static let crawl = TrainPerformance(acceleration: 250, braking: 250, topSpeed: 1)
    static let valid: [TrainPerformance] = [.standard, .metro, .local, .express, .ordinary, .forestRailway, .highSpeed, .pushPull, crawl]
    static let invalid: [TrainPerformance] = [
        TrainPerformance(acceleration: 0, braking: 2_500, topSpeed: 110),
        TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: RunningCurve.maximumRate + 1),
        TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 110, coast: TrainPerformance.Coast(deceleration: 2_500, speedRatio: 450)),
        TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 110, alternativeBraking: -1),
    ]
}

// MARK: - World invariants

enum WorldInvariants {
    /// Decision 64: what ``GameWorld/routeWaits()`` must equal, asked one
    /// train at a time through the single queries.
    static func routeWaitsOneByOne(in world: GameWorld) -> [RouteWait] {
        let deadlocked = Set(world.deadlockedTrains())
        return world.trains.sorted { $0.id < $1.id }.compactMap { train in
            world.trainHoldingRoute(of: train.id).map {
                RouteWait(train: train.id, holder: $0, contested: world.contestedResources(of: train.id), isDeadlocked: deadlocked.contains(train.id))
            }
        }
    }

    /// Every documented invariant a world reachable through commands must
    /// keep; each broken one is described. Checked from the public state only.
    static func violations(in world: GameWorld) -> [String] {
        var problems: [String] = []
        let ids = world.trains.map(\.id.rawValue)
        if ids != ids.sorted() || Set(ids).count != ids.count {
            problems.append("train IDs not unique and ascending: \(ids)")
        }
        // Stage F3d: every station stands at a point in the world's bounds.
        for station in world.stations where !world.bounds.contains(station.point) {
            problems.append("station \(station.id.rawValue) at \(station.point) is outside the world")
        }
        // Decision 22: lines in ID order, each with two stops or more (none
        // twice in a row) at known stations, a rate of 1 or more, a window
        // that opens within the day and closes after it by 06:00 the next
        // morning, and no negative count; a day that starts at minute 0 and
        // strictly increases within the day.
        let lineIDs = world.lines.map(\.id.rawValue)
        if lineIDs != lineIDs.sorted() || Set(lineIDs).count != lineIDs.count || lineIDs.contains(where: { $0 < 1 }) {
            problems.append("line IDs not unique, positive and ascending: \(lineIDs)")
        }
        for line in world.lines {
            let id = line.id.rawValue
            if line.stops.count < 2 || zip(line.stops, line.stops.dropFirst()).contains(where: { $0 == $1 }) {
                problems.append("line \(id) stops \(line.stops)")
            }
            for stop in line.stops where world.station(id: stop) == nil {
                problems.append("line \(id) calls at unknown station \(stop.rawValue)")
            }
            if !line.performance.isValid { problems.append("line \(id) performance \(line.performance)") }
            if case .hours(let open, let close) = line.window, !(open >= 0 && open < 1440 && close > open && close <= 1800) {
                problems.append("line \(id) window \(open)-\(close)")
            }
            // No negative count. Decision 23: targets of 2 to 1440 minutes;
            // trains in ID order, known, and on this line only; a last
            // dispatch from minute 0 to now; a line's train in service runs
            // a trip that is not repeated. Decision 24: the same for each
            // pattern, whose calls are two or more of the line's stops,
            // rising; no train on two services.
            let services: [(name: String, counts: TrainsInService, targets: TargetHeadways, trains: [TrainID], last: GameTime?)] =
                [("line \(id)", line.trainsInService, line.targetHeadways, line.trains, line.lastDispatch)]
                + line.patterns.enumerated().map { ("line \(id) pattern \($0)", $1.trainsInService, $1.targetHeadways, $1.trains, $1.lastDispatch) }
            for pattern in line.patterns {
                let calls = pattern.calls
                if calls.count < 2 || calls[0] < 0 || calls[calls.count - 1] >= line.stops.count || zip(calls, calls.dropFirst()).contains(where: { $0 >= $1 }) {
                    problems.append("line \(id) pattern calls \(calls) for \(line.stops.count) stops")
                }
            }
            for service in services {
                if min(service.counts.peak, service.counts.offPeak, service.counts.low) < 0 { problems.append("\(service.name) negative trains") }
                for level in ServiceLevel.allCases {
                    if let target = service.targets[level], !(2...1440).contains(target) {
                        problems.append("\(service.name) target \(target) at \(level)")
                    }
                }
                if zip(service.trains, service.trains.dropFirst()).contains(where: { $0 >= $1 }) {
                    problems.append("\(service.name) trains \(service.trains) not ascending")
                }
                for train in service.trains {
                    if world.train(id: train) == nil { problems.append("\(service.name) has unknown train \(train.rawValue)") }
                    let homes = world.lines.reduce(0) { count, other in
                        count + (other.trains.contains(train) ? 1 : 0) + other.patterns.filter { $0.trains.contains(train) }.count
                    }
                    if homes > 1 {
                        problems.append("train \(train.rawValue) is on two lines or services")
                    }
                    if let running = world.train(id: train), running.execution != nil, running.timetablePeriod != nil {
                        problems.append("\(service.name)'s train \(train.rawValue) runs a repeating timetable")
                    }
                }
                if let last = service.last, last.seconds < 0 || last > world.clock.now {
                    problems.append("\(service.name) last dispatch \(last.seconds) at second \(world.clock.now.seconds)")
                }
            }
        }
        // Decision 29: the track network.
        problems += NetworkInvariants.violations(in: world)
        // Decision 32: traffic control.
        problems += trafficViolations(in: world)
        problems += passengerViolations(in: world)
        problems += accountsViolations(in: world)
        let starts = world.serviceDay.bands.map(\.start)
        if starts.first != 0 || starts.contains(where: { $0 >= 1440 }) || zip(starts, starts.dropFirst()).contains(where: { $0 >= $1 }) {
            problems.append("service day starts \(starts)")
        }
        for train in world.trains {
            // Decision 19: times never go back from minute 0, and every stop
            // is at a station the world has, placed or not.
            let times = train.timetable.flatMap { [$0.arrival.seconds, $0.departure.seconds] }
            if times.contains(where: { $0 < 0 }) || zip(times, times.dropFirst()).contains(where: { $0 > $1 }) {
                problems.append("train \(train.id.rawValue) timetable goes back in time: \(times)")
            }
            for stop in train.timetable where world.station(id: stop.station) == nil {
                problems.append("train \(train.id.rawValue) timetable names unknown station \(stop.station.rawValue)")
            }
            // Decision 21: a repeating timetable has a stop and a period of a
            // minute or more, and does not go back when it starts again.
            if let period = train.timetablePeriod {
                if let first = train.timetable.first, let last = train.timetable.last {
                    // Stage W2a: times and periods are seconds.
                    let (again, overflow) = first.arrival.seconds.addingReportingOverflow(period)
                    if period < 1 || (!overflow && last.departure.seconds > again) {
                        problems.append("train \(train.id.rawValue) timetable cannot repeat every \(period) minutes")
                    }
                } else {
                    problems.append("train \(train.id.rawValue) repeats an empty timetable")
                }
            }
            problems += serviceViolations(of: train, in: world)
            problems += bodyViolations(of: train, in: world)
            guard train.position != nil else {
                if train.movement != .idle { problems.append("unplaced train \(train.id.rawValue) is not idle") }
                continue
            }
            // Decision 29: checked with the network's own invariants.
            problems += NetworkInvariants.trainViolations(of: train, in: world)
        }
        return problems
    }

    /// Decision 34: every passenger released at a station is accounted
    /// for (released = waiting + overflowed + abandoned), no station holds
    /// more than its capacity, groups wait in the order they came, no later
    /// than now, for a trip the world still has; records are by station,
    /// each of an existing station, and none says nothing.
    static func passengerViolations(in world: GameWorld) -> [String] {
        var problems: [String] = []
        let stations = world.passengers.map(\.station)
        if stations != stations.sorted() || Set(stations).count != stations.count {
            problems.append("passenger records not by ascending station")
        }
        for record in world.passengers {
            let id = record.station.rawValue
            if world.station(id: record.station) == nil { problems.append("passengers at station \(id), which does not exist") }
            let waiting = record.waiting.reduce(Int64(0)) { $0 + $1.count }
            let ledger = world.passengerLedger(of: record.station)
            if ledger.waiting != waiting { problems.append("station \(id) counts \(ledger.waiting) waiting in \(waiting)") }
            // Decision 35: and those riding or arrived.
            let riding = world.riders.flatMap(\.groups).filter { $0.origin == record.station }.reduce(Int64(0)) { $0 + $1.count }
            if ledger.riding != riding { problems.append("station \(id) counts \(ledger.riding) riding of \(riding)") }
            if ledger.released != waiting + riding + ledger.arrived + ledger.overflowed + ledger.abandoned
                || ledger.overflowed < 0 || ledger.abandoned < 0 || ledger.arrived < 0 || ledger.refused < 0 {
                problems.append("station \(id) does not account for its passengers: \(ledger)")
            }
            if waiting > StationPassengers.capacity { problems.append("station \(id) holds \(waiting) waiting") }
            if record.demand == nil, record.released == 0, record.remainders.isEmpty { problems.append("station \(id) keeps an empty record") }
            for (earlier, later) in zip(record.waiting, record.waiting.dropFirst())
            where later.since < earlier.since || (later.since == earlier.since && later.destination <= earlier.destination) {
                problems.append("station \(id) queue out of order")
            }
            for group in record.waiting {
                if group.count < 1 || group.since >= world.clock.now { problems.append("station \(id) has a group \(group)") }
                let line = world.lines.first { $0.id == group.line }
                let from = line?.stops.firstIndex(of: record.station)
                let to = line?.stops.firstIndex(of: group.destination)
                if let from, let to, from != to, (to > from ? LineDirection.outbound : .inbound) == group.direction { continue }
                problems.append("station \(id) has a group whose line does not take it that way")
            }
            for remainder in record.remainders where !(1..<3600).contains(remainder.value) || remainder.destination == record.station {
                problems.append("station \(id) keeps remainder \(remainder)")
            }
        }
        problems += riderViolations(in: world)
        return problems
    }

    /// Decision 35: riders are listed once for each train that has any, by
    /// train; the train runs a service and holds no more than its cars ×
    /// 352; each group, listed once by origin and destination, came from a
    /// station with a record and rides to a station the train calls at
    /// from the stop it is at or heading for up to the next stop where it
    /// turns round (or its last). Stage W2b: a train waiting at a stop
    /// where it turns round may already carry those it took on there, for
    /// the calls after it.
    static func riderViolations(in world: GameWorld) -> [String] {
        var problems: [String] = []
        let trains = world.riders.map(\.train)
        if trains != trains.sorted() || Set(trains).count != trains.count { problems.append("riders not by ascending train") }
        for entry in world.riders {
            let id = entry.train.rawValue
            guard let train = world.train(id: entry.train), let execution = train.execution else {
                problems.append("riders on train \(id), which runs no service")
                continue
            }
            let pairs = entry.groups.map { [$0.origin.rawValue, $0.destination.rawValue] }
            if entry.groups.isEmpty || pairs != pairs.sorted(by: { $0.lexicographicallyPrecedes($1) }) || Set(pairs).count != pairs.count {
                problems.append("train \(id) riders not listed once each by origin and destination")
            }
            let total = entry.groups.reduce(Int64(0)) { $0 + $1.count }
            if total > Int64(train.cars) * 320 * 11 / 10 { problems.append("train \(id) carries \(total) on \(train.cars) cars") }
            var ahead: Set<StationID> = []
            let waiting = if case .waitingAtStop = execution { true } else { false }
            for stop in execution.stop..<train.timetable.count {
                ahead.insert(train.timetable[stop].station)
                if train.timetable[stop].reverses, !(waiting && stop == execution.stop) { break }
            }
            for group in entry.groups {
                if group.count < 1 { problems.append("train \(id) has an empty group") }
                if !world.passengers.contains(where: { $0.station == group.origin }) { problems.append("train \(id) riders from a station without a record") }
                if !ahead.contains(group.destination) { problems.append("train \(id) riders to \(group.destination.rawValue), which it does not call at next") }
            }
        }
        return problems
    }

    /// Decision 36: a managed company's accounts are open, never after
    /// now; the hour's counts are not negative and its fares whole dollars;
    /// at most 50 rows, none dated after now, each of its kind's items with
    /// fares in, costs out and the items adding up to the row; at most 720
    /// days, once each and ascending, no total negative.
    static func accountsViolations(in world: GameWorld) -> [String] {
        var problems: [String] = []
        let accounts = world.accounts
        if accounts.mode == .management, accounts.openedAt == nil { problems.append("managed accounts never opened") }
        if let opened = accounts.openedAt, opened > world.clock.now { problems.append("accounts open at second \(opened.seconds), after now") }
        let pending = accounts.pending
        if [pending.fareTrips, pending.departures, pending.trainDistance, pending.passengers, pending.seats, pending.fareRevenue.amount].contains(where: { $0 < 0 }) {
            problems.append("the hour's counts go negative: \(pending)")
        }
        if pending.fareRevenue.amount % 100 != 0 { problems.append("the hour's fares \(pending.fareRevenue.amount) are not whole dollars") }
        if accounts.entries.count > 50 { problems.append("\(accounts.entries.count) ledger rows kept") }
        for entry in accounts.entries {
            if entry.time > world.clock.now { problems.append("ledger row dated second \(entry.time.seconds), after now") }
            let expected: [LedgerItem] = switch entry.kind {
            case .hourlyNet: [.fareRevenue, .operatingCost, .maintenanceCost]
            case .dailyEnergy: [.routeEnergy, .trainEnergy]
            case .dailyStaff: [.stationStaff, .trainStaff]
            case .dailyInterest: [.loanInterest]
            }
            var sum: Int64 = 0
            for line in entry.breakdown {
                sum += line.amount.amount
                if (line.item == .fareRevenue) != (line.amount.amount >= 0) && line.amount.amount != 0 {
                    problems.append("ledger row \(entry.kind) has \(line.item) of \(line.amount.amount)")
                }
            }
            if entry.breakdown.map(\.item) != expected || sum != entry.amount.amount || (entry.crowding != nil) != (entry.kind == .hourlyNet) {
                problems.append("ledger row \(entry) is not shaped as settlements write it")
            }
        }
        if accounts.days.count > 720 { problems.append("\(accounts.days.count) days kept") }
        let days = accounts.days.map(\.day)
        if days != days.sorted() || Set(days).count != days.count { problems.append("days not once each, ascending: \(days)") }
        for day in accounts.days {
            let totals = [day.fareRevenue, day.operatingCost, day.maintenanceCost, day.energyCost, day.staffCost].map(\.amount)
            if totals.contains(where: { $0 < 0 }) { problems.append("day \(day.day) has a negative total") }
        }
        return problems
    }

    /// Decision 32: without traffic control nothing is reserved. With it,
    /// no two trains hold the same track; a reservation is in resource
    /// order without repeats, belongs to a placed train and holds what the
    /// train stands on; a train plainly standing (at the end of its path on
    /// its own edge) has none, and one plainly on its way (short of where
    /// its path ends on its own edge) has one.
    static func trafficViolations(in world: GameWorld) -> [String] {
        guard world.isTrafficControlEnabled else {
            return world.trains.contains { !$0.reservation.isEmpty } ? ["a reservation while traffic control is off"] : []
        }
        var problems: [String] = []
        let placed = world.trains.filter { $0.position != nil }
        for (index, train) in placed.enumerated() {
            let held = Set(world.heldResources(of: train.id))
            for other in placed[..<index] where !held.isDisjoint(with: world.heldResources(of: other.id)) {
                problems.append("trains \(other.id.rawValue) and \(train.id.rawValue) hold the same track")
            }
        }
        for train in world.trains {
            let id = train.id.rawValue
            let reservation = train.reservation
            if zip(reservation, reservation.dropFirst()).contains(where: { $0 >= $1 }) {
                problems.append("train \(id)'s reservation is not in resource order without repeats")
            }
            if world.reservedResources(of: train.id) != reservation { problems.append("train \(id)'s reservation reads differently") }
            guard let position = train.position else {
                if !reservation.isEmpty { problems.append("unplaced train \(id) has a reservation") }
                continue
            }
            if !reservation.isEmpty, !Set(world.occupiedResources(of: train.id)).isSubset(of: reservation) {
                problems.append("train \(id)'s reservation does not hold what it stands on")
            }
            let movement = train.movement
            var stands: Bool?
            switch position {
            case .onEdge(let traversal, let offset):
                if movement.cursor == movement.edges.count, let length = world.trackEdge(traversal.edge)?.length {
                    stands = offset == (movement.end ?? length)
                }
            }
            if stands == true, !reservation.isEmpty { problems.append("standing train \(id) has a reservation") }
            if stands == false, reservation.isEmpty { problems.append("train \(id) on its way has no reservation") }
        }
        return problems
    }

    /// Decision 27: 1 to 16 cars. The body on the track network is checked
    /// with the network's own invariants (``NetworkInvariants``).
    static func bodyViolations(of train: Train, in world: GameWorld) -> [String] {
        (1...16).contains(train.cars) ? [] : ["train \(train.id.rawValue) has \(train.cars) cars"]
    }

    /// Decision 20: a service points at an entry of the timetable of a
    /// placed train; a waiting train is stopped at that entry's station; a
    /// travelling one heads for an entry after the service's first, has not
    /// ended its journey, and ends it next to that entry's station.
    /// Decision 21: the cycle is 0 unless the timetable repeats, and then
    /// its latest time still fits in a game minute. Decision 31: on the
    /// track network a travelling train's path is not spent and ends at the
    /// far end, the way it travels, of a platform of that station no shorter
    /// than the train. Decision 58: or of another station's, a passing
    /// place, where its path may also be spent.
    static func serviceViolations(of train: Train, in world: GameWorld) -> [String] {
        guard let execution = train.execution else { return [] }
        let id = train.id.rawValue
        guard train.timetable.indices.contains(execution.stop) else {
            return ["train \(id) service at stop \(execution.stop) of \(train.timetable.count)"]
        }
        if execution.cycle != 0 {
            guard let period = train.timetablePeriod, execution.cycle > 0 else {
                return ["train \(id) service in cycle \(execution.cycle) of a timetable that does not repeat"]
            }
            let (shift, overflow) = execution.cycle.multipliedReportingOverflow(by: period)
            if overflow || train.timetable.last!.departure.seconds.addingReportingOverflow(shift).overflow {
                return ["train \(id) service in cycle \(execution.cycle), whose times do not fit"]
            }
        }
        guard let position = train.position else { return ["unplaced train \(id) runs a service"] }
        let target = train.timetable[execution.stop].station
        // Stage W2c: a run only while travelling, set off no later than now,
        // with a curve for the train's performance.
        if let run = train.times?.run {
            if case .waitingAtStop = execution { return ["train \(id) waits with a run"] }
            if run.start > world.clock.now || run.length < 1 || !(1...RunningCurve.maximumSeconds).contains(run.seconds)
                || run.curve(for: train.performance) == nil {
                return ["train \(id) run \(run)"]
            }
        }
        switch execution {
        case .waitingAtStop:
            return world.stationsStoppedAt(by: train.id).contains(target) ? [] : ["train \(id) waits at station \(target.rawValue) but is not stopped there"]
        case .travellingToStop(let stop, let cycle):
            var problems: [String] = []
            if stop < 1, cycle < 1 { problems.append("train \(id) travels to the service's first stop") }
            switch position {
            case .onEdge(let traversal, let offset):
                return problems + networkServiceViolations(of: train, at: traversal, offset: offset, to: target, in: world)
            }
        }
    }

    /// Decision 31: a travelling train on the network has path left and
    /// ends it at a berth of `target` it fits: followed along its edges to
    /// the last where it can be, otherwise one way or the other on its last
    /// edge.
    static func networkServiceViolations(of train: Train, at traversal: TrackTraversal, offset: Int64, to target: StationID, in world: GameWorld) -> [String] {
        let id = train.id.rawValue
        let left = train.movement.remainingEdges
        guard let lastEdge = world.trackEdge(left.last ?? traversal.edge) else { return ["train \(id) travels along a path whose last edge is gone"] }
        let end = train.movement.end ?? lastEdge.length
        let ahead = world.pathAhead(of: train.id)
        let lastWay: TrackEdgeDirection? = left.isEmpty ? traversal.direction : ahead.count == left.count ? ahead.last?.direction : nil
        let length = Int64(train.cars - 1) * 1024
        func endsAtBerth(of station: StationID) -> Bool {
            let fits = world.trackPlatforms(of: station).filter { $0.edge == lastEdge.id && $0.end - $0.start >= length }
            let berths = fits.flatMap { platform -> [(TrackEdgeDirection, Int64)] in [(.forward, platform.end), (.backward, lastEdge.length - platform.start)] }
            return berths.contains { berth in berth.1 == end && (lastWay == nil || berth.0 == lastWay) }
        }
        // Decision 58: a passing place is a berth of another station.
        let passing = world.stations.contains { $0.id != target && endsAtBerth(of: $0.id) }
        if left.isEmpty, offset == end {
            guard passing, !world.stationsStoppedAt(by: train.id).contains(target) else { return ["train \(id) travels but its path is spent"] }
            return []
        }
        return endsAtBerth(of: target) || passing ? [] : ["train \(id) travels to station \(target.rawValue) on a path that ends at \(end) on \(lastEdge.id), no berth of it"]
    }

    /// The world survives a save and load unchanged: the decoder accepts
    /// every state the commands can reach, and loses nothing.
    static func roundTripProblem(of world: GameWorld) -> String? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(world)
            let decoded = try JSONDecoder().decode(GameWorld.self, from: data)
            return decoded == world ? nil : "decoded world differs"
        } catch {
            return "round trip failed: \(error)"
        }
    }
}
