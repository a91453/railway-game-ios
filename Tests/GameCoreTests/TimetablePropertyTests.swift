import Foundation
import GameCore
import XCTest

/// Timetables (Stage O, decision 19) under generated command sequences: the
/// Stage I–N operations of ``KernelDifferentialTests`` with timetable
/// replacements mixed in, valid and broken, for known and unknown trains.
///
/// - **Atomicity, against the reference.** Every sequence runs on GameCore
///   and on ``ReferenceWorld``, which checks timetables its own way; outcomes
///   (the same `GameError`, in the documented order) and all state must
///   match after every step, and a refused command changes nothing. An
///   accepted replacement changes that train's timetable and nothing else.
/// - **Inert.** The same Stage I–N operations also run on a twin world that
///   never gets a timetable. After every step, the world with its timetables
///   cleared must equal the twin, every command must have the same outcome
///   on both, and every train must stop at the same stations: a timetable
///   never changes movement, routes, stops, money, time or IDs. Timetables
///   themselves change only through `setTrainTimetable`.
/// - **Saving.** Worlds with timetables load back equal, and the same world
///   always saves to the same bytes.
/// - **Reference integrity.** Every world reached keeps the invariants,
///   including that every stop names a station the world has.
///
/// A failing sequence is shrunk before it is reported, with its seed and
/// case; `PROPERTY_REPLAY=timetable.differential@<seed>@<case>` runs one case.
final class TimetablePropertyTests: XCTestCase {
    typealias Operation = KernelDifferentialTests.Operation

    /// A mix of Stage I–N operations and timetable replacements, drawn with
    /// the world stepped along so that operations fit the state they meet.
    static func generate(_ c: inout PropertyCase, operations count: Int) throws -> (KernelDifferentialTests.Setup, [Operation]) {
        let setup = KernelDifferentialTests.makeSetup(using: &c.random)
        var (world, _) = try setup.build()
        var operations: [Operation] = []
        for _ in 0..<count {
            // Rarely before a train exists, often once one does.
            let operation = c.random.chance(1, in: world.trains.isEmpty ? 40 : 5)
                ? nextTimetable(in: world, using: &c.random)
                : KernelDifferentialTests.nextOperation(in: world, using: &c.random)
            operations.append(operation)
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        return (setup, operations)
    }

    /// A timetable replacement: mostly for a known train, mostly valid,
    /// sometimes empty (clearing), sometimes broken.
    static func nextTimetable(in world: GameWorld, using random: inout SplitMix64) -> Operation {
        let trains = world.trains
        let id = trains.isEmpty || random.chance(1, in: 12)
            ? TrainID(rawValue: random.element(of: [0, -1, trains.count + 1, Int.max]))
            : random.element(of: trains).id
        let valid = TimetableGenerator.valid(in: world, using: &random)
        switch random.below(8) {
        case 0: return .setTimetable(id, [])
        case 1, 2, 3: return .setTimetable(id, TimetableGenerator.broken(valid, in: world, using: &random))
        default: return .setTimetable(id, valid)
        }
    }

    // MARK: - The campaign

    func testTimetablesAreAtomicInertAndSavedExactly() throws {
        var outcomes: [String: Int] = [:]
        var inertSteps = 0
        var scheduledAdvances = 0
        var digest = Digest()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ran = try runCampaign("timetable.differential", cases: 60) { c in
            let (setup, operations) = try Self.generate(&c, operations: 120)
            c.note("setup: \(setup.width)x\(setup.height), \(setup.specs.count) tiles, +\(setup.extraBalance), minute \(setup.minutes), \(setup.speed)")

            // Atomicity and every outcome, against the reference model.
            if let failure = KernelDifferentialTests.firstProblem(setup, operations) {
                let minimal = KernelDifferentialTests.minimalFailure(setup, operations)
                c.fail("step \(failure.step): \(failure.problem)\n  minimal (\(minimal.count) of \(operations.count)): [\(minimal.map(\.description).joined(separator: ", "))]")
                return
            }

            // Inert: the same run on a twin that never gets a timetable.
            var scheduled = try setup.build().0
            var plain = scheduled
            var expected: [TrainID: [ScheduledStop]] = [:]
            for (index, operation) in operations.enumerated() {
                let before = scheduled
                let error = KernelDifferentialTests.apply(operation, to: &scheduled)
                let at = "step \(index) \(operation)"
                if case .setTimetable(let id, let stops, _) = operation {
                    let outcome = error.map { "\($0)".prefix { $0 != "(" } } ?? (stops.isEmpty ? "cleared" : "set")
                    outcomes[String(outcome), default: 0] += 1
                    if error == nil {
                        expected[id] = stops
                        if let problem = Self.isolationProblem(id: id, stops: stops, before: before, after: scheduled) {
                            c.fail("\(at): \(problem)")
                            return
                        }
                    } else {
                        c.expect(scheduled == before, "\(at) was refused but changed the world")
                    }
                } else {
                    let plainError = KernelDifferentialTests.apply(operation, to: &plain)
                    c.expect(error == plainError, "\(at): \(String(describing: error)) with timetables, \(String(describing: plainError)) without")
                    if case .advance = operation, scheduled.trains.contains(where: { !$0.timetable.isEmpty }) {
                        scheduledAdvances += 1
                    }
                }
                var cleared = scheduled
                for train in cleared.trains {
                    try cleared.setTrainTimetable(train.id, to: [])
                }
                guard cleared == plain else {
                    c.fail("\(at): with its timetables cleared the world differs from the twin without timetables")
                    return
                }
                for train in scheduled.trains {
                    c.expect(train.timetable == expected[train.id] ?? [], "\(at): train \(train.id.rawValue)'s timetable changed without setTrainTimetable")
                    c.expect(
                        scheduled.stationsStoppedAt(by: train.id) == plain.stationsStoppedAt(by: train.id),
                        "\(at): train \(train.id.rawValue) stops differently with a timetable"
                    )
                }
                let problems = WorldInvariants.violations(in: scheduled)
                c.expect(problems.isEmpty, "\(at): \(problems)")
                inertSteps += 1
            }
            for train in scheduled.trains {
                guard let position = train.position else { continue }
                for station in scheduled.stations {
                    c.expect(
                        scheduled.route(from: position, toStation: station.id) == plain.route(from: position, toStation: station.id),
                        "a route to station \(station.id.rawValue) differs with timetables"
                    )
                }
            }

            // Saving: equal after loading, and the same bytes every time.
            let data = try encoder.encode(scheduled)
            let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
            let again = try encoder.encode(scheduled)
            let reloaded = try encoder.encode(loaded)
            c.expect(loaded == scheduled, "the world with timetables did not load back equal")
            c.expect(again == data && reloaded == data, "the same world saved to different bytes")
            digest.add(String(decoding: data, as: UTF8.self))
        }
        let summary = outcomes.keys.sorted().map { "\($0) \(outcomes[$0]!)" }.joined(separator: ", ")
        print("[digest] timetable.differential \(digest.hex) (\(inertSteps) steps; \(summary); \(scheduledAdvances) advances with timetables)")
        assertVolume(ran == 60 * PropertySeeds.active.count, "every case should run")
        assertVolume(inertSteps == 60 * 120 * PropertySeeds.active.count, "every step should be compared")
        assertVolume((outcomes["set"] ?? 0) > 1_000, "too few timetables set: \(summary)")
        assertVolume((outcomes["cleared"] ?? 0) > 500, "too few timetables cleared: \(summary)")
        assertVolume((outcomes["invalidTimetable"] ?? 0) > 800, "too few invalid timetables: \(summary)")
        assertVolume((outcomes["unknownStation"] ?? 0) > 120, "too few unknown stations: \(summary)")
        assertVolume((outcomes["unknownTrain"] ?? 0) > 300, "too few unknown trains: \(summary)")
        assertVolume(scheduledAdvances > 1_500, "too few advances with timetables: \(scheduledAdvances)")
    }

    /// Whether an accepted replacement changed exactly the train's timetable:
    /// described if anything else changed.
    static func isolationProblem(id: TrainID, stops: [ScheduledStop], before: GameWorld, after: GameWorld) -> String? {
        guard after.train(id: id)?.timetable == stops else { return "the timetable is not the one given" }
        guard after.map == before.map, after.stations == before.stations, after.clock == before.clock, after.economy == before.economy else {
            return "the map, stations, clock or money changed"
        }
        guard after.trains.map(\.id) == before.trains.map(\.id) else { return "the trains changed" }
        for (train, old) in zip(after.trains, before.trains) {
            guard train.name == old.name, train.position == old.position, train.movement == old.movement else {
                return "train \(train.id.rawValue)'s name, position or movement changed"
            }
            guard train.id == id || train.timetable == old.timetable else {
                return "train \(train.id.rawValue)'s timetable changed too"
            }
        }
        // The old timetable, which was valid, put back gives back the same
        // world, the private ID counters included.
        var restored = after
        do {
            try restored.setTrainTimetable(id, to: before.train(id: id)?.timetable ?? [])
        } catch {
            return "the old timetable could not be put back: \(error)"
        }
        return restored == before ? nil : "putting the old timetable back does not restore the world"
    }

    /// The same case gives the same operations and worlds in every run.
    func testGeneratedTimetableCasesReplayExactly() throws {
        try runCampaign("timetable.replay", cases: 10) { c in
            var first = PropertyCase(suite: c.suite, seed: c.seed, index: c.index)
            var second = PropertyCase(suite: c.suite, seed: c.seed, index: c.index)
            let (setupA, operationsA) = try Self.generate(&first, operations: 60)
            let (setupB, operationsB) = try Self.generate(&second, operations: 60)
            c.expect(operationsA == operationsB, "the same case generated different operations")
            var (a, _) = try setupA.build()
            var (b, _) = try setupB.build()
            for (x, y) in zip(operationsA, operationsB) {
                _ = KernelDifferentialTests.apply(x, to: &a)
                _ = KernelDifferentialTests.apply(y, to: &b)
            }
            c.expect(a == b, "the same operations gave different worlds")
        }
    }

    /// The generator's valid timetables are valid and its broken ones mostly
    /// are not, judged by the rules written here once more.
    func testTheGeneratorsMakeWhatTheySay() throws {
        var broken = 0
        var total = 0
        try runCampaign("timetable.generator", cases: 50) { c in
            let (setup, _) = try Self.generate(&c, operations: 0)
            let world = try setup.build().0
            for _ in 0..<20 {
                let valid = TimetableGenerator.valid(in: world, using: &c.random)
                c.expect(Self.isValid(valid, in: world), "a valid timetable is not: \(valid)")
                if !world.stations.isEmpty {
                    let bad = TimetableGenerator.broken(valid, in: world, using: &c.random)
                    total += 1
                    if !Self.isValid(bad, in: world) { broken += 1 }
                }
            }
        }
        assertVolume(total > 0 && broken * 10 >= total * 9, "only \(broken) of \(total) broken timetables are broken")
    }

    private static func isValid(_ stops: [ScheduledStop], in world: GameWorld) -> Bool {
        let times = stops.flatMap { [$0.arrival.minutes, $0.departure.minutes] }
        let ordered = times.allSatisfy { $0 >= 0 } && zip(times, times.dropFirst()).allSatisfy { $0 <= $1 }
        return ordered && stops.allSatisfy { stop in world.stations.contains { $0.id == stop.station } }
    }
}

// MARK: - Generated timetables

enum TimetableGenerator {
    /// A valid timetable for `world`: up to five stops at its stations
    /// (repeats allowed), with times that never go back, often equal, near
    /// the clock, at 0 or at the largest minute. Empty without stations.
    static func valid(in world: GameWorld, using random: inout SplitMix64) -> [ScheduledStop] {
        let stations = world.stations.map(\.id)
        guard !stations.isEmpty else { return [] }
        let count = random.below(6)
        let now = world.clock.now.minutes
        let times = (0..<(2 * count)).map { _ -> Int64 in
            switch random.below(10) {
            case 0..<4: return random.int64(in: 0...30)
            case 4, 5:
                let (near, overflow) = now.addingReportingOverflow(random.int64(in: -20...20))
                return overflow ? now : max(0, near)
            case 6: return 0
            case 7: return .max
            default: return random.int64(in: 0...1_000_000)
            }
        }.sorted()
        return (0..<count).map { index in
            ScheduledStop(
                station: random.element(of: stations),
                arrival: GameTime(minutes: times[2 * index]),
                departure: GameTime(minutes: times[2 * index + 1])
            )
        }
    }

    /// `stops` with one or two defects: a negative time, a departure before
    /// its arrival, an arrival before the previous departure, or a station
    /// the world does not have.
    static func broken(_ stops: [ScheduledStop], in world: GameWorld, using random: inout SplitMix64) -> [ScheduledStop] {
        var stops = stops
        let stations = world.stations.map(\.id)
        let unknown = StationID(rawValue: random.element(of: [0, -1, (stations.map(\.rawValue).max() ?? 0) + 1, Int.max, Int.min]))
        func make(_ station: StationID, _ arrival: Int64, _ departure: Int64) -> ScheduledStop {
            ScheduledStop(station: station, arrival: GameTime(minutes: arrival), departure: GameTime(minutes: departure))
        }
        let anyStation = stations.isEmpty ? unknown : random.element(of: stations)
        for _ in 0..<(1 + random.below(2)) {
            switch random.below(4) {
            case 0:
                // A negative time.
                let negative = random.chance(1, in: 4) ? Int64.min : -random.int64(in: 1...30)
                if stops.isEmpty || random.chance(1, in: 4) {
                    stops.insert(make(anyStation, negative, random.chance(1, in: 2) ? negative : 5), at: random.below(stops.count + 1))
                } else {
                    let index = random.below(stops.count)
                    let old = stops[index]
                    stops[index] = random.chance(1, in: 2)
                        ? make(old.station, negative, old.departure.minutes)
                        : make(old.station, old.arrival.minutes, negative)
                }
            case 1:
                // A departure before its arrival.
                let index = random.below(stops.count + 1)
                if index == stops.count {
                    stops.append(make(anyStation, .max, 0))
                } else {
                    let old = stops[index]
                    let arrival = max(old.arrival.minutes, 1)
                    stops[index] = make(old.station, arrival, arrival - 1 - random.int64(in: 0...min(arrival - 1, 10)))
                }
            case 2:
                // An arrival before the previous departure.
                if stops.count >= 2 {
                    let index = 1 + random.below(stops.count - 1)
                    let previous = stops[index - 1].departure.minutes
                    let old = stops[index]
                    let arrival = previous > 0 ? previous - 1 : -1
                    stops[index] = make(old.station, arrival, max(arrival, old.departure.minutes))
                } else {
                    stops = [make(anyStation, 10, 20), make(anyStation, 5, 30)]
                }
            default:
                // A station the world does not have.
                if stops.isEmpty || random.chance(1, in: 3) {
                    let last = stops.last?.departure.minutes ?? 0
                    stops.insert(make(unknown, last, last), at: stops.count)
                } else {
                    let index = random.below(stops.count)
                    let old = stops[index]
                    stops[index] = make(unknown, old.arrival.minutes, old.departure.minutes)
                }
            }
        }
        return stops
    }
}
