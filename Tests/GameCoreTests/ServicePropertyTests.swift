import Foundation
import GameCore
import XCTest

/// Timetable services (Stage P, decision 20) under generated command
/// sequences: the Stage I–N operations of ``KernelDifferentialTests`` with
/// timetables that start where a train is stopped, service starts and
/// stops, and advances short and long, for known and unknown trains.
///
/// - **Against the reference.** Every sequence runs on GameCore and on
///   ``ReferenceWorld``, which steps every minute with no shortcut and
///   looks every route up again; outcomes (the same `GameError`, in the
///   documented order) and all state, every train's service included, must
///   match after every step, and a refused command changes nothing.
/// - **Batches.** Every advance is also run as single ticks, and at 2x as
///   twice the ticks at 1x: the results must be equal (apart from the speed
///   itself), so the event-aware shortcut never skips a departure.
/// - **Invariants.** Every world reached keeps them, a service's included
///   (``WorldInvariants/serviceViolations(of:in:)``). The world each case
///   ends in loads back equal and saves to the same bytes, as do the worlds
///   at its generated save-and-load steps.
///
/// A failing sequence is shrunk before it is reported, with its seed and
/// case; `PROPERTY_REPLAY=service.differential@<seed>@<case>` runs one case.
///
/// Decision 21 adds a second campaign, `service.repeating`, whose generated
/// timetables turn trains round at some stops and mostly repeat: the same
/// checks, with its own volume of turns and new cycles. The first campaign
/// draws exactly as before, so its digest is unchanged.
final class ServicePropertyTests: XCTestCase {
    typealias Operation = KernelDifferentialTests.Operation

    /// A mix of Stage I–N operations and service operations, drawn with the
    /// world stepped along so that operations fit the state they meet.
    static func generate(_ c: inout PropertyCase, operations count: Int, repeating: Bool = false) throws -> (KernelDifferentialTests.Setup, [Operation]) {
        // Mostly networks with loops, where a train can reach most stations
        // whichever way it faces, so that services run far.
        let setup = KernelDifferentialTests.makeSetup(shapes: [.loopWithTails, .loopWithTails, .grid, .grid, .ladder, .ladder, .random, .line, .twoComponents], using: &c.random)
        var (world, _) = try setup.build()
        var operations: [Operation] = []
        for _ in 0..<count {
            if c.random.chance(1, in: 16) {
                operations += scriptedService(in: &world, repeating: repeating, using: &c.random)
                continue
            }
            let operation = c.random.chance(3, in: 5)
                ? nextServiceOperation(in: world, repeating: repeating, using: &c.random)
                : KernelDifferentialTests.nextOperation(in: world, using: &c.random)
            operations.append(operation)
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        return (setup, operations)
    }

    /// A whole service, applied to `world` as it is drawn: an idle train
    /// (bought if there is none) put on a platform unless it is already
    /// stopped at a station, a rate, a timetable from there that it can
    /// mostly drive, the start, and time to run it. The operations drawn
    /// after it may still interrupt the service.
    static func scriptedService(in world: inout GameWorld, repeating: Bool = false, using random: inout SplitMix64) -> [Operation] {
        var operations: [Operation] = []
        func run(_ operation: Operation) {
            operations.append(operation)
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        let platforms = world.stations.flatMap { world.platforms(of: $0.id) }
        guard !platforms.isEmpty else { return [.advance(random.below(10))] }
        let idle = world.trains.filter { $0.execution == nil && ($0.position == nil || !world.stationsStoppedAt(by: $0.id).isEmpty) }
        let id: TrainID
        if let train = idle.isEmpty ? nil : random.element(of: idle) {
            id = train.id
        } else {
            run(.purchase("S\(world.trains.count + 1)"))
            guard let bought = world.trains.last, bought.position == nil, bought.execution == nil else { return operations }
            id = bought.id
        }
        if world.train(id: id)?.position == nil {
            run(.place(id, .atNode(random.element(of: platforms), heading: random.element(of: TrackDirection.allCases))))
        }
        run(.setRate(id, random.element(of: [256, 700, 1024, 1024, 1500, 3000, 4096])))
        guard let train = world.train(id: id), let from = world.stationsStoppedAt(by: id).first else { return operations }
        run(ServiceGenerator.setTimetable(for: train, from: from, in: world, repeating: repeating, using: &random))
        run(.startService(id))
        if world.clock.isPaused {
            run(.setSpeed(random.element(of: [.normal, .double])))
        }
        run(.advance(random.below(60)))
        return operations
    }

    /// A service operation: mostly a train put on a platform, a timetable
    /// that starts where a train is stopped and leads to stations it can
    /// reach, starting it and giving it a rate; sometimes a stop, and
    /// advances long enough for services to run.
    static func nextServiceOperation(in world: GameWorld, repeating: Bool = false, using random: inout SplitMix64) -> Operation {
        let trains = world.trains
        let unknown = TrainID(rawValue: random.element(of: [0, -1, trains.count + 1, Int.max]))
        func anyTrain() -> TrainID {
            trains.isEmpty || random.chance(1, in: 12) ? unknown : random.element(of: trains).id
        }
        switch random.below(20) {
        case 0..<3:
            // An unplaced train onto a platform, facing any way.
            let platforms = world.stations.flatMap { world.platforms(of: $0.id) }
            guard let train = trains.first(where: { $0.position == nil }), !platforms.isEmpty else { return .advance(random.below(10)) }
            return .place(train.id, .atNode(random.element(of: platforms), heading: random.element(of: TrackDirection.allCases)))
        case 3..<7:
            // A timetable from where an idle train is stopped.
            let ready = trains.filter { $0.execution == nil && !world.stationsStoppedAt(by: $0.id).isEmpty }
            guard !ready.isEmpty else { return .setTimetable(anyTrain(), TimetableGenerator.valid(in: world, using: &random)) }
            let train = random.element(of: ready)
            let from = random.element(of: world.stationsStoppedAt(by: train.id))
            return ServiceGenerator.setTimetable(for: train, from: from, in: world, repeating: repeating, using: &random)
        case 7..<11:
            // Mostly a train that could start.
            let ready = trains.filter { train in
                guard let first = train.timetable.first else { return false }
                return train.execution == nil && world.stationsStoppedAt(by: train.id).contains(first.station)
            }
            return .startService(!ready.isEmpty && random.chance(4, in: 5) ? random.element(of: ready).id : anyTrain())
        case 11:
            return .stopService(anyTrain())
        case 12..<16:
            // A rate that crosses links in whole and in part, mostly for a
            // train that runs a service or has a timetable.
            let running = trains.filter { $0.execution != nil || ($0.position != nil && !$0.timetable.isEmpty) }
            let id = !running.isEmpty && random.chance(3, in: 4) ? random.element(of: running).id : anyTrain()
            return .setRate(id, random.element(of: [0, 256, 700, 1024, 1024, 1500, 3000, 4096]))
        case 16:
            let stations = world.stations.map(\.id)
            guard !stations.isEmpty else { return .advance(random.below(10)) }
            return .sendToStation(anyTrain(), random.element(of: stations))
        case 17..<19:
            // A paused clock runs no step: often set it going first.
            if world.clock.isPaused, random.chance(1, in: 2) {
                return .setSpeed(random.element(of: [.normal, .double]))
            }
            return .advance(random.below(30))
        default:
            return .advance(100 + random.below(400))
        }
    }

    // MARK: - The campaign

    func testServicesMatchTheReferenceAndBatchesMatchSingleSteps() throws {
        let counts = try runServiceCampaign("service.differential", repeating: false)
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        for (event, least) in [
            ("startService", 500), ("stopService", 40), ("trainNotAtFirstStop", 70), ("trainServiceActive", 150),
            ("trainServiceNotActive", 80), ("noTimetable", 60), ("unknownTrain", 300), ("refused while running", 280),
            ("departures", 120), ("arrivals", 45), ("further without moving", 400), ("completed", 400), ("waits without a route", 400),
        ] {
            assertVolume((counts[event] ?? 0) >= least, "too few \(event): \(summary)")
        }
    }

    /// Decision 21: services that turn trains round and repeat, under the
    /// same checks.
    func testRepeatingServicesMatchTheReferenceAndBatchesMatchSingleSteps() throws {
        let counts = try runServiceCampaign("service.repeating", repeating: true)
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        for (event, least) in [
            ("startService", 400), ("invalidTimetable", 40), ("departures", 100), ("arrivals", 40),
            ("turned round", 150), ("new cycles", 150), ("started late in a later cycle", 20), ("completed", 100),
            ("waits without a route", 150),
        ] {
            assertVolume((counts[event] ?? 0) >= least, "too few \(event): \(summary)")
        }
    }

    /// Runs one service campaign and returns how often each event happened.
    private func runServiceCampaign(_ name: String, repeating: Bool) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        var digest = Digest()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ran = try runCampaign(name, cases: 30) { c in
            let (setup, operations) = try Self.generate(&c, operations: 120, repeating: repeating)
            c.note("setup: \(setup.width)x\(setup.height), \(setup.specs.count) tiles, +\(setup.extraBalance), minute \(setup.minutes), \(setup.speed)")

            // Every outcome and all state, against the reference model.
            if let failure = KernelDifferentialTests.firstProblem(setup, operations) {
                let minimal = KernelDifferentialTests.minimalFailure(setup, operations)
                c.fail("step \(failure.step): \(failure.problem)\n  minimal (\(minimal.count) of \(operations.count)): [\(minimal.map(\.description).joined(separator: ", "))]")
                return
            }

            var world = try setup.build().0
            for (index, operation) in operations.enumerated() {
                let before = world
                let error = KernelDifferentialTests.apply(operation, to: &world)
                let at = "step \(index) \(operation)"
                switch operation {
                case .startService(let id), .stopService(let id):
                    let accepted = if case .startService = operation { "startService" } else { "stopService" }
                    counts[error.map { String("\($0)".prefix { $0 != "(" }) } ?? accepted, default: 0] += 1
                    if case .startService = operation, error == nil, let cycle = world.train(id: id)?.execution?.cycle, cycle > 0 {
                        counts["started late in a later cycle", default: 0] += 1
                    }
                case .setTimetable:
                    if case .trainServiceActive? = error { counts["refused while running", default: 0] += 1 }
                    if repeating, case .invalidTimetable? = error { counts["invalidTimetable", default: 0] += 1 }
                case .setContinuation, .reverse, .unplace, .sendToTile, .sendToStation:
                    if case .trainServiceActive? = error { counts["refused while running", default: 0] += 1 }
                case .advance(let ticks):
                    if error == nil {
                        Self.countEvents(before: before, after: world, into: &counts)
                        if let problem = Self.batchProblem(ticks: ticks, from: before, batch: world) {
                            c.fail("\(at): \(problem)")
                            return
                        }
                    }
                default:
                    break
                }
                let problems = WorldInvariants.violations(in: world)
                c.expect(problems.isEmpty, "\(at): \(problems)")
            }

            // Saving: equal after loading, and the same bytes every time.
            let data = try encoder.encode(world)
            let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
            c.expect(loaded == world, "the world with services did not load back equal")
            let reloaded = try encoder.encode(loaded)
            c.expect(reloaded == data, "the same world saved to different bytes")
            digest.add(String(decoding: data, as: UTF8.self))
        }
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        print("[digest] \(name) \(digest.hex) (\(summary))")
        assertVolume(ran == 30 * PropertySeeds.active.count, "every case should run")
        return counts
    }

    /// Counts what an accepted advance did to the services that ran in it:
    /// trains that left a stop and moved ("departures"), are waiting
    /// further on after moving ("arrivals"), got at least a whole stop
    /// further without moving (a station reached at once, or the last stop
    /// left: "further without moving"), finished ("completed"), or still
    /// wait after a departure that passed before the last step ("waits
    /// without a route"; the last stop of a repeating timetable included).
    /// Decision 21 adds services that left a stop marked to turn the train
    /// ("turned round") and services in a later cycle than before ("new
    /// cycles").
    static func countEvents(before: GameWorld, after: GameWorld, into counts: inout [String: Int]) {
        // A paused clock runs no step.
        guard after.clock.now > before.clock.now else { return }
        for (old, new) in zip(before.trains, after.trains) {
            guard let was = old.execution else { continue }
            let moved = old.position != new.position
            // Waiting at stop i is 2i, travelling to it 2i - 1, done 2 * count,
            // within a cycle; each later cycle is 2 * count further on.
            let count = old.timetable.count
            func progress(_ execution: TimetableExecution?) -> (cycle: Int64, step: Int) {
                switch execution {
                case .waitingAtStop(let stop, let cycle)?: (cycle, 2 * stop)
                case .travellingToStop(let stop, let cycle)?: (cycle, 2 * stop - 1)
                case nil: (was.cycle, 2 * count)
                }
            }
            let (from, to) = (progress(was), progress(new.execution))
            let gained = Int(to.cycle - from.cycle) * 2 * count + to.step - from.step
            if case .waitingAtStop = was, moved { counts["departures", default: 0] += 1 }
            if gained >= 1, moved, case .waitingAtStop? = new.execution { counts["arrivals", default: 0] += 1 }
            if gained >= 2, !moved { counts["further without moving", default: 0] += 1 }
            if new.execution == nil { counts["completed", default: 0] += 1 }
            if to.cycle > from.cycle { counts["new cycles", default: 0] += 1 }
            if gained >= 1, case .waitingAtStop(let stop, _) = was, old.timetable[stop].reverses {
                counts["turned round", default: 0] += 1
            }
            if gained == 0, case .waitingAtStop(let stop, let cycle) = was, stop + 1 < count || old.timetablePeriod != nil,
               old.timetable[stop].departure.minutes + cycle * (old.timetablePeriod ?? 0) < after.clock.now.minutes {
                counts["waits without a route", default: 0] += 1
            }
        }
    }

    /// Whether `ticks` single ticks from `before` give `batch`, and a tick
    /// at 2x two at 1x: described if not.
    static func batchProblem(ticks: Int, from before: GameWorld, batch: GameWorld) -> String? {
        var single = before
        for _ in 0..<ticks {
            do {
                try single.advance(ticks: 1)
            } catch {
                return "a single tick was refused after the batch was accepted: \(error)"
            }
        }
        guard single == batch else { return "\(ticks) ticks at once differ from \(ticks) single ticks" }
        guard before.clock.speed == .double else { return nil }
        var normal = before
        normal.setSpeed(.normal)
        do {
            try normal.advance(ticks: 2 * ticks)
        } catch {
            return "twice the ticks at 1x were refused: \(error)"
        }
        normal.setSpeed(.double)
        return normal == batch ? nil : "\(ticks) ticks at 2x differ from \(2 * ticks) at 1x"
    }

    /// The same case gives the same operations and worlds in every run.
    func testGeneratedServiceCasesReplayExactly() throws {
        try runCampaign("service.replay", cases: 10) { c in
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
}

// MARK: - Generated service timetables

enum ServiceGenerator {
    /// A timetable operation for `train` from `station`: the Stage P
    /// timetable, drawn exactly as before, unless `repeating`. Then some
    /// stops turn the train round (and the stations after them are drawn
    /// from where the train would face), and the timetable mostly repeats:
    /// usually back at the first station and with a period that fits,
    /// sometimes with one that is too short or not positive.
    static func setTimetable(
        for train: Train,
        from station: StationID,
        in world: GameWorld,
        repeating: Bool,
        using random: inout SplitMix64
    ) -> KernelDifferentialTests.Operation {
        guard repeating else { return .setTimetable(train.id, timetable(for: train, from: station, in: world, using: &random)) }
        var stops = timetable(for: train, from: station, in: world, turning: true, using: &random)
        if random.chance(2, in: 3), let first = stops.first, let last = stops.last, last.station != first.station,
           let departure = Optional(last.departure.minutes), departure < .max {
            // Back to the first station: the wrap is then a journey home,
            // or no journey at all when the last stop turns round there.
            stops.append(ScheduledStop(
                station: first.station, arrival: GameTime(minutes: departure), departure: GameTime(minutes: departure),
                reverses: random.chance(1, in: 2)
            ))
        }
        guard random.chance(5, in: 6), let first = stops.first, let last = stops.last else {
            return .setTimetable(train.id, stops)
        }
        let span = last.departure.minutes - first.arrival.minutes
        let period: Int64 = switch random.below(12) {
        case 0: random.element(of: [0, -1, -60, .min])
        case 1: max(0, span - random.int64(in: 1...5))
        case 2: span
        case 3: .max
        default: span.addingReportingOverflow(random.int64(in: 1...30)).overflow ? .max : span + random.int64(in: 1...30)
        }
        return .setTimetable(train.id, stops, period: period)
    }

    /// A valid timetable for `train` that starts at `station`: then up to
    /// four more stops, each mostly at a station the train could reach from
    /// where the route to the stop before would leave it (so that most
    /// services can run to the end on an unchanged map), sometimes at any
    /// station; the previous station again is common. Times start around
    /// now, never go back, are often equal, and are clamped at the largest
    /// minute.
    static func timetable(
        for train: Train,
        from station: StationID,
        in world: GameWorld,
        turning: Bool = false,
        using random: inout SplitMix64
    ) -> [ScheduledStop] {
        let all = world.stations.map(\.id)
        func later(_ time: Int64, by gap: Int64) -> Int64 {
            let (sum, overflow) = time.addingReportingOverflow(gap)
            return overflow ? .max : sum
        }
        var time = max(0, later(world.clock.now.minutes, by: random.int64(in: -10...10)))
        var stops: [ScheduledStop] = []
        var current = station
        var position = train.position
        for index in 0..<(1 + random.below(5)) {
            if index > 0 {
                if random.chance(1, in: 8) {
                    // The same station again: reached at once.
                } else if let from = position, random.chance(9, in: 10) {
                    // Mostly a journey rather than a station already reached.
                    let routes = all.compactMap { id in world.route(from: from, toStation: id).map { (id, $0) } }
                    let journeys = routes.filter { !$0.1.isEmpty }
                    let choices = !journeys.isEmpty && random.chance(9, in: 10) ? journeys : routes
                    if let (next, route) = choices.isEmpty ? nil : random.element(of: choices) {
                        current = next
                        position = end(of: route, from: from)
                    } else {
                        current = random.element(of: all)
                        position = nil
                    }
                } else {
                    current = random.element(of: all)
                    position = nil
                }
                time = later(time, by: random.chance(1, in: 3) ? 0 : random.int64(in: 1...20))
            }
            let departure = later(time, by: random.chance(1, in: 3) ? 0 : random.int64(in: 1...10))
            // Only drawn when turning, so Stage P's timetables are as before.
            let reverses = turning && random.chance(1, in: 3)
            if reverses {
                position = position.map(ReferenceWorld.turned)
            }
            stops.append(ScheduledStop(
                station: current, arrival: GameTime(minutes: time), departure: GameTime(minutes: departure), reverses: reverses
            ))
            time = departure
        }
        return stops
    }

    /// Where a train at `start` stands after following `route` to its end.
    private static func end(of route: [GridPosition], from start: TrainPosition) -> TrainPosition {
        guard let last = route.last else { return start }
        let before = route.count >= 2 ? route[route.count - 2] : ahead(of: start).node
        return .atNode(last, heading: stepDirection(from: before, to: last)!)
    }
}
