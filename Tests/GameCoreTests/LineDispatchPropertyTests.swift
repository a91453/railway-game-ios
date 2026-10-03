import Foundation
import GameCore
import XCTest

/// Automatic dispatch (Stage Q2b, decision 23) under generated command
/// sequences: lines on small networks with trains assigned and standing at
/// their first stops, mixed with target headways, counts, windows and
/// service days that change the service, assignments and removals, trains
/// moved and held by hand, track built and removed under them, lines made
/// rings and lines again (decision 49), and advances short and long; some commands invalid on purpose (targets out
/// of range, unknown trains and lines, trains on a line already, manual
/// timetables and services for a line's trains).
///
/// - **Against the reference.** Every sequence runs on GameCore and on
///   ``ReferenceWorld``, which steps every minute and checks every line's
///   dispatch then; outcomes and all state (lines' trains, targets and
///   last dispatch, every train's timetable and service) must match after
///   every step, and a refused command changes nothing. What is derived
///   for each line is left to the line campaign (`line.differential`): the
///   reference answers it by driving every line from scratch.
/// - **Batches.** Every advance is also run as single ticks, and at 2x as
///   twice the ticks at 1x, so the shortcut never skips a dispatch.
/// - **Invariants.** Every world reached keeps them
///   (``WorldInvariants/violations(in:)``). The world each case ends in
///   loads back equal and saves to the same bytes.
///
/// A failing sequence is shrunk before it is reported, with its seed and
/// case; `PROPERTY_REPLAY=line.dispatch@<seed>@<case>` runs one case.
final class LineDispatchPropertyTests: XCTestCase {
    typealias Operation = KernelDifferentialTests.Operation

    static func generate(_ c: inout PropertyCase, operations count: Int) throws -> (KernelDifferentialTests.Setup, [Operation]) {
        // Small networks: the reference drives every line from scratch, and
        // its routes are slow on purpose. On the track network (Stage F3b).
        var setup = KernelDifferentialTests.makeNetworkSetup(shapes: [.balloons, .balloons, .balloons, .line, .line, .loopWithTails, .loopWithTails, .ladder, .crossings], using: &c.random)
        // Near the start of a day, so that windows and levels change within
        // a case; the end of time is left to the other campaigns.
        setup.seconds = 60 * (c.random.int64(in: -30...3_000))
        setup.speed = c.random.element(of: [.normal, .normal, .double, .paused])
        var (world, _) = try setup.build()
        let speed: Operation = .setSpeed(c.random.chance(1, in: 3) ? .double : .normal)
        _ = KernelDifferentialTests.apply(speed, to: &world)
        var operations = [speed]
        for _ in 0..<(1 + c.random.below(2)) {
            operations += scriptedLine(in: &world, using: &c.random)
        }
        while operations.count < count {
            if c.random.chance(1, in: 20) {
                operations += scriptedLine(in: &world, using: &c.random)
                continue
            }
            let operation = c.random.chance(4, in: 5)
                ? nextDispatchOperation(in: world, using: &c.random)
                : KernelDifferentialTests.nextOperation(in: world, using: &c.random)
            operations.append(operation)
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        return (setup, operations)
    }

    /// A working line: two or three stations with platforms, mostly ones a
    /// train drives to in turn (see ``KernelNetwork/drivableStops``), a
    /// count or a target at each level,
    /// usually open all day, and one to three trains bought, standing at
    /// the end of one of the first stop's platforms facing any way, given a
    /// rate and assigned; applied to `world` as they are drawn, and they
    /// may still fail.
    static func scriptedLine(in world: inout GameWorld, using random: inout SplitMix64) -> [Operation] {
        var operations: [Operation] = []
        func run(_ operation: Operation) {
            operations.append(operation)
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        let served = world.stations.filter { !KernelNetwork.endBerths(in: world, of: [$0.id]).isEmpty }.map(\.id)
        guard served.count >= 2, world.lines.count < 3 else {
            run(.advance(random.below(20)))
            return operations
        }
        let first = random.element(of: served)
        let berths = KernelNetwork.endBerths(in: world, of: [first])
        let start = random.element(of: berths)
        var stops = KernelNetwork.drivableStops(from: first, at: start, count: 1 + random.below(2), among: served, in: world, using: &random)
        if stops.count < 2 { stops.append(served.first { $0 != first }!) }
        run(.createLine("D\(world.lines.count + 1)", stops))
        guard let line = world.lines.last?.id else { return operations }
        // Decision 49: a third stop round, sometimes, to make a ring.
        if random.chance(1, in: 3), let third = served.first(where: { !stops.contains($0) }) {
            if stops.count == 2 { run(.setLineStops(line, stops + [third])) }
            run(.setLineRing(line, true))
        }
        if random.chance(4, in: 5) { run(.setLineWindow(line, .allDay)) }
        run(.setLineTrains(line, TrainsInService(peak: random.below(4), offPeak: 1 + random.below(3), low: random.below(3))))
        if random.chance(1, in: 3) { run(.setLineTargets(line, targets(using: &random))) }
        // Stage W2c: mostly a crawl, so that trips last minutes as before
        // (a train keeps to the time its line plans, whatever its own
        // performance).
        if random.chance(3, in: 4) {
            run(.setLinePerformance(line, PerformanceSamples.crawl))
        } else if random.chance(1, in: 2) {
            run(.setLinePerformance(line, random.element(of: PerformanceSamples.valid)))
        }
        for _ in 0..<(1 + random.below(3)) {
            run(.purchase("L\(world.trains.count + 1)"))
            guard let id = world.trains.last?.id, world.train(id: id)?.position == nil else { break }
            // Mostly where the stops were drawn from, now and then facing
            // any way (it turns round first).
            run(.place(id, random.chance(3, in: 4) ? start : random.element(of: berths)))
            run(.setRate(id, random.element(of: [700, 1024, 1024, 1500, 2048, 4096])))
            if random.chance(1, in: 4) { run(.setPerformance(id, random.element(of: PerformanceSamples.valid))) }
            run(.assign(id, line))
        }
        return operations
    }

    /// Targets at some levels, mostly within 2...1440.
    static func targets(using random: inout SplitMix64) -> TargetHeadways {
        func target() -> Int64? {
            guard random.chance(2, in: 3) else { return nil }
            return random.chance(1, in: 10)
                ? random.element(of: [0, 1, -3, 1441, .max])
                : random.element(of: [2, 3, 5, 8, 12, 20, 45, 1440, random.int64(in: 2...60)])
        }
        return TargetHeadways(peak: target(), offPeak: target(), low: target())
    }

    /// A dispatch operation, drawn with the world in view.
    static func nextDispatchOperation(in world: GameWorld, using random: inout SplitMix64) -> Operation {
        let lines = world.lines
        let trains = world.trains
        let unknownLine = LineID(rawValue: random.element(of: [0, -1, (lines.last?.id.rawValue ?? 0) + 1]))
        let unknownTrain = TrainID(rawValue: random.element(of: [0, -1, trains.count + 1]))
        func anyLine() -> LineID {
            lines.isEmpty || random.chance(1, in: 12) ? unknownLine : random.element(of: lines).id
        }
        func anyTrain() -> TrainID {
            trains.isEmpty || random.chance(1, in: 12) ? unknownTrain : random.element(of: trains).id
        }
        let assigned = lines.flatMap(\.trains)
        switch random.below(42) {
        case 0..<3:
            // Mostly a free train onto a first stop, then assigned there.
            let free = trains.filter { !assigned.contains($0.id) }
            if let line = lines.isEmpty ? nil : random.element(of: lines), let train = free.isEmpty ? nil : random.element(of: free),
               train.position == nil, case let berths = KernelNetwork.endBerths(in: world, of: [line.stops[0]]), !berths.isEmpty, random.chance(1, in: 2) {
                return .place(train.id, random.element(of: berths))
            }
            return .assign(anyTrain(), anyLine())
        case 3, 4:
            return .unassign(random.chance(3, in: 4) && !assigned.isEmpty ? random.element(of: assigned) : anyTrain())
        case 5..<8:
            return .setLineTargets(anyLine(), random.chance(1, in: 4) ? .none : targets(using: &random))
        case 8..<11:
            let counts = (0..<3).map { _ in random.chance(1, in: 20) ? -1 : random.below(5) }
            return .setLineTrains(anyLine(), TrainsInService(peak: counts[0], offPeak: counts[1], low: counts[2]))
        case 11, 12:
            let window: ServiceWindow = switch random.below(4) {
            case 0: .allDay
            case 1: .hours(open: random.below(1440), close: 1441 + random.below(359))
            default: .hours(open: random.below(1200), close: 1200 + random.below(240))
            }
            return .setLineWindow(anyLine(), window)
        case 13:
            var start = 0
            var bands: [ServiceDay.Band] = []
            while start < 1440, bands.count < 5 {
                bands.append(ServiceDay.Band(start: start, level: random.element(of: ServiceLevel.allCases)))
                start += 1 + random.below(400)
            }
            return .setServiceDay(ServiceDay(bands: bands))
        case 14:
            return random.chance(1, in: 2)
                ? .setLinePerformance(anyLine(), random.element(of: PerformanceSamples.valid + PerformanceSamples.invalid))
                : .setPerformance(anyTrain(), random.element(of: PerformanceSamples.valid + PerformanceSamples.invalid))
        case 15:
            guard let line = lines.isEmpty ? nil : random.element(of: lines) else { return .advance(5) }
            let stations = world.stations.map(\.id)
            var stops = line.stops
            if random.chance(1, in: 2), stops.count > 2 {
                stops.removeLast()
            } else if let extra = stations.first(where: { $0 != stops.last }) {
                stops.append(extra)
            }
            return .setLineStops(line.id, stops)
        case 16:
            return random.chance(1, in: 4) ? .removeLine(anyLine()) : .advance(random.below(30))
        case 17..<20:
            // A line's train by hand: its timetable or service (refused), or
            // held, released, turned or taken off.
            let id = !assigned.isEmpty && random.chance(4, in: 5) ? random.element(of: assigned) : anyTrain()
            switch random.below(8) {
            case 0: return .setTimetable(id, [])
            case 1: return .startService(id)
            case 2: return .stopService(id)
            case 3: return .setRate(id, 0)
            case 4: return .setRate(id, random.element(of: [700, 1024, 2048]))
            case 5: return .reverse(id)
            case 6: return .unplace(id)
            default:
                let berths = KernelNetwork.endBerths(in: world, of: lines.map { $0.stops[0] })
                guard !berths.isEmpty else { return .advance(5) }
                return .place(id, random.element(of: berths))
            }
        case 20, 21:
            // A line's train sent back to its first stop by hand.
            guard let line = lines.isEmpty ? nil : random.element(of: lines), let id = line.trains.isEmpty ? nil : random.element(of: line.trains) else {
                return .advance(10)
            }
            return .sendToStation(id, line.stops[0])
        case 22:
            // A line's train waiting at its first stop, turned round by hand:
            // it may then have to turn again as it leaves.
            let waiting = lines.flatMap { line in
                line.trains.filter { world.train(id: $0)?.execution == nil && world.stationsStoppedAt(by: $0).contains(line.stops[0]) }
            }
            return waiting.isEmpty ? .advance(10) : .reverse(random.element(of: waiting))
        case 23:
            if world.clock.isPaused { return .setSpeed(random.element(of: [.normal, .double])) }
            return .setSpeed(random.element(of: GameSpeed.allCases))
        case 24..<34:
            return .advance(random.below(40))
        case 40, 41:
            return .setLineRing(anyLine(), random.chance(2, in: 3))
        default:
            return .advance(60 + random.below(600))
        }
    }

    func testDispatchMatchesTheReferenceAndBatchesMatchSingleSteps() throws {
        var counts: [String: Int] = [:]
        var digest = Digest()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ran = try runCampaign("line.dispatch", cases: 16) { c in
            let (setup, operations) = try Self.generate(&c, operations: 70)
            c.note("setup: \(setup.summary), second \(setup.seconds), \(setup.speed)")

            if let failure = KernelDifferentialTests.firstProblem(setup, operations, lineAnswers: false) {
                let minimal = KernelDifferentialTests.minimalFailure(setup, operations, lineAnswers: false)
                c.fail("step \(failure.step): \(failure.problem)\n  minimal (\(minimal.count) of \(operations.count)): [\(minimal.map(\.description).joined(separator: ", "))]")
                return
            }

            var world = try setup.build().0
            for (index, operation) in operations.enumerated() {
                let before = world
                let error = KernelDifferentialTests.apply(operation, to: &world)
                let at = "step \(index) \(operation)"
                switch operation {
                case .assign, .unassign, .setLineTargets, .setLineRing:
                    let name = "\(operation)".dropFirst().prefix { $0 != "(" }
                    counts[error.map { String("\($0)".prefix { $0 != "(" }) } ?? "ok \(name)", default: 0] += 1
                case .setTimetable, .startService, .stopService:
                    if case .trainOnLine? = error { counts["trainOnLine", default: 0] += 1 }
                case .advance(let ticks):
                    guard error == nil else { break }
                    Self.countEvents(before: before, after: world, into: &counts)
                    if let problem = ServicePropertyTests.batchProblem(ticks: ticks, from: before, batch: world) {
                        c.fail("\(at): \(problem)")
                        return
                    }
                default:
                    break
                }
                let problems = WorldInvariants.violations(in: world)
                c.expect(problems.isEmpty, "\(at): \(problems)")
            }

            let data = try encoder.encode(world)
            let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
            c.expect(loaded == world, "the world with dispatching lines did not load back equal")
            let reloaded = try encoder.encode(loaded)
            c.expect(reloaded == data, "the same world saved to different bytes")
            digest.add(String(decoding: data, as: UTF8.self))
        }
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        print("[digest] line.dispatch \(digest.hex) (\(summary))")
        assertVolume(ran == 16 * PropertySeeds.active.count, "every case should run")
        for (event, least) in [
            ("ok assign", 150), ("ok unassign", 30), ("ok setLineTargets", 80), ("trainOnLine", 60), ("invalidHeadway", 10),
            ("unknownTrain", 5), ("unknownLine", 5), ("trainNotOnLine", 5),
            // On the track network (Stage F3b) fewer trips end within a
            // case than on the grid: 134 in the four seeds' run when this
            // floor was set.
            ("dispatched", 400), ("turned round first", 10), ("trips finished", 100), ("waiting to go", 400),
            ("ok setLineRing", 40), ("dispatched on a ring", 30),
        ] {
            assertVolume((counts[event] ?? 0) >= least, "too few \(event): \(summary)")
        }
    }

    /// Counts what an accepted advance did on the lines: trains sent out on
    /// a new trip ("dispatched", once per train however many trips it
    /// began), of them those turned round before leaving ("turned round
    /// first"), trains whose last trip in the advance ended ("trips
    /// finished"), and a line's trains at its first stop with no service
    /// after the advance ("waiting to go").
    static func countEvents(before: GameWorld, after: GameWorld, into counts: inout [String: Int]) {
        guard after.clock.now > before.clock.now else { return }
        for line in after.lines {
            for id in line.trains {
                guard let train = after.train(id: id), let old = before.train(id: id) else { continue }
                let sentOut = train.timetable != old.timetable
                if sentOut {
                    counts["dispatched", default: 0] += 1
                    if line.isRing { counts["dispatched on a ring", default: 0] += 1 }
                    if train.timetable.first?.reverses == true { counts["turned round first", default: 0] += 1 }
                }
                if (sentOut || old.execution != nil), train.execution == nil {
                    counts["trips finished", default: 0] += 1
                }
                if train.execution == nil, after.stationsStoppedAt(by: id).contains(line.stops[0]) {
                    counts["waiting to go", default: 0] += 1
                }
            }
        }
    }

    /// The same case gives the same operations and worlds in every run.
    func testGeneratedDispatchCasesReplayExactly() throws {
        try runCampaign("dispatch.replay", cases: 6) { c in
            var first = PropertyCase(suite: c.suite, seed: c.seed, index: c.index)
            var second = PropertyCase(suite: c.suite, seed: c.seed, index: c.index)
            let (setupA, operationsA) = try Self.generate(&first, operations: 40)
            let (setupB, operationsB) = try Self.generate(&second, operations: 40)
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
