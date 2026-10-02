import Foundation
import GameCore
import XCTest

/// Patterns (Stage Q3, decision 24) under generated command sequences:
/// lines on small networks with short workings and expresses added and
/// removed, counts and targets set for them, trains assigned to them and
/// standing at their first calls, mixed with the dispatch campaign's
/// operations (windows, days, stops, trains by hand, track built and
/// removed, advances short and long); some commands invalid on purpose
/// (calls that do not rise or run past the stops, unknown patterns, trains
/// on a service already).
///
/// - **Against the reference.** Every sequence runs on GameCore and on
///   ``ReferenceWorld``, which finds each service's room by counting down
///   over every segment rather than by a binary search over running
///   loads; outcomes, all state and everything derived for every line and
///   pattern (journeys, trains, headways and segment loads, every level)
///   must match after every step, and a refused command changes nothing.
/// - **Batches.** Every advance is also run as single ticks, and at 2x as
///   twice the ticks at 1x.
/// - **Invariants.** Every world reached keeps them; the world each case
///   ends in loads back equal and saves to the same bytes.
///
/// `PROPERTY_REPLAY=line.patterns@<seed>@<case>` runs one case.
final class LinePatternPropertyTests: XCTestCase {
    typealias Operation = KernelDifferentialTests.Operation

    static func generate(_ c: inout PropertyCase, operations count: Int) throws -> (KernelDifferentialTests.Setup, [Operation]) {
        var setup = KernelDifferentialTests.makeSetup(shapes: [.line, .line, .loopWithTails, .ladder], using: &c.random)
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
            if c.random.chance(1, in: 25) || (world.lines.isEmpty && c.random.chance(1, in: 4)) {
                operations += scriptedLine(in: &world, using: &c.random)
                continue
            }
            let operation: Operation = switch c.random.below(10) {
            case 0..<5: nextPatternOperation(in: world, using: &c.random)
            case 5..<9: LineDispatchPropertyTests.nextDispatchOperation(in: world, using: &c.random)
            default: KernelDifferentialTests.nextOperation(in: world, using: &c.random)
            }
            operations.append(operation)
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        return (setup, operations)
    }

    /// A line of three or four stations with platforms, mostly ones a
    /// train can reach from the one before, usually open all day, with
    /// counts for its own service, one or two patterns with counts (a
    /// target now and then), and a train or two bought, placed at a
    /// pattern's first call facing any way, and assigned to it; applied to
    /// `world` as drawn, and they may still fail.
    static func scriptedLine(in world: inout GameWorld, using random: inout SplitMix64) -> [Operation] {
        var operations: [Operation] = []
        func run(_ operation: Operation) {
            operations.append(operation)
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        let served = world.stations.filter { !world.platforms(of: $0.id).isEmpty }.map(\.id)
        guard served.count >= 2, world.lines.count < 3 else {
            run(.advance(random.below(20)))
            return operations
        }
        var stops = [random.element(of: served)]
        for _ in 0..<(2 + random.below(2)) {
            let from = world.platforms(of: stops.last!)
            let reachable = served.filter { station in
                station != stops.last && from.contains { platform in
                    TrackDirection.allCases.contains { world.route(from: .atNode(platform, heading: $0), toStation: station) != nil }
                }
            }
            let next = random.element(of: !reachable.isEmpty && random.chance(5, in: 6) ? reachable : served)
            if next != stops.last { stops.append(next) }
        }
        if stops.count < 2 { stops.append(served.first { $0 != stops[0] }!) }
        run(.createLine("P\(world.lines.count + 1)", stops))
        guard let line = world.lines.last?.id else { return operations }
        if random.chance(4, in: 5) { run(.setLineWindow(line, .allDay)) }
        run(.setLineTrains(line, TrainsInService(peak: random.below(5), offPeak: random.below(3), low: random.below(2))))
        for _ in 0..<(1 + random.below(2)) {
            run(.addPattern(line, calls(forStops: stops.count, using: &random)))
            guard let pattern = world.line(id: line).map({ $0.patterns.count - 1 }), pattern >= 0 else { continue }
            run(.setLineTrains(line, TrainsInService(peak: random.below(5), offPeak: 1 + random.below(3), low: random.below(3)), pattern: pattern))
            if random.chance(1, in: 4) { run(.setLineTargets(line, LineDispatchPropertyTests.targets(using: &random), pattern: pattern)) }
            let first = world.line(id: line)!.stops[world.line(id: line)!.patterns[pattern].calls[0]]
            let platforms = world.platforms(of: first)
            guard !platforms.isEmpty else { continue }
            for _ in 0..<(1 + random.below(2)) {
                run(.purchase("Q\(world.trains.count + 1)"))
                guard let id = world.trains.last?.id, world.train(id: id)?.position == nil else { break }
                run(.place(id, .atNode(random.element(of: platforms), heading: random.element(of: TrackDirection.allCases))))
                run(.setRate(id, random.element(of: [700, 1024, 1024, 2048, 4096])))
                run(.assign(id, line, pattern: pattern))
            }
        }
        return operations
    }

    /// Calls for a line of `count` stops: mostly two or more rising indices
    /// (a run of neighbours, or a spread with some left out), now and then
    /// ones that break a rule.
    static func calls(forStops count: Int, using random: inout SplitMix64) -> [Int] {
        if random.chance(1, in: 10) {
            return random.element(of: [[], [0], [1, 0], [0, 0], [-1, 1], [0, count], [0, count + 3]])
        }
        let first = random.below(count - 1)
        let last = first + 1 + random.below(count - 1 - first)
        let middle = (first + 1..<last).filter { _ in random.chance(1, in: 2) || random.chance(1, in: 3) }
        return [first] + middle + [last]
    }

    /// A pattern operation, drawn with the world in view.
    static func nextPatternOperation(in world: GameWorld, using random: inout SplitMix64) -> Operation {
        let lines = world.lines
        let unknownLine = LineID(rawValue: random.element(of: [0, -1, (lines.last?.id.rawValue ?? 0) + 1]))
        guard let line = lines.isEmpty || random.chance(1, in: 15) ? nil : random.element(of: lines) else {
            return random.chance(1, in: 2) ? .addPattern(unknownLine, [0, 1]) : .removePattern(unknownLine, 0)
        }
        func anyPattern() -> Int {
            line.patterns.isEmpty || random.chance(1, in: 10) ? random.element(of: [-1, line.patterns.count, 7]) : random.below(line.patterns.count)
        }
        let assigned = lines.flatMap { $0.trains + $0.patterns.flatMap(\.trains) }
        switch random.below(20) {
        case 0..<3:
            return .addPattern(line.id, calls(forStops: line.stops.count, using: &random))
        case 3, 4:
            return .removePattern(line.id, anyPattern())
        case 5, 6:
            let counts = (0..<3).map { _ in random.chance(1, in: 20) ? -1 : random.below(5) }
            return .setLineTrains(line.id, TrainsInService(peak: counts[0], offPeak: counts[1], low: counts[2]), pattern: anyPattern())
        case 7, 8:
            return .setLineTargets(line.id, random.chance(1, in: 4) ? .none : LineDispatchPropertyTests.targets(using: &random), pattern: anyPattern())
        case 9..<12:
            // Mostly a free train onto a pattern's first call, then assigned.
            let free = world.trains.filter { !assigned.contains($0.id) }
            let pattern = anyPattern()
            if let train = free.isEmpty ? nil : random.element(of: free), line.patterns.indices.contains(pattern), random.chance(1, in: 2) {
                let first = line.stops[line.patterns[pattern].calls[0]]
                if train.position == nil, let platform = world.platforms(of: first).first {
                    return .place(train.id, .atNode(platform, heading: random.element(of: TrackDirection.allCases)))
                }
                return .assign(train.id, line.id, pattern: pattern)
            }
            let train = world.trains.isEmpty || random.chance(1, in: 10) ? TrainID(rawValue: 99) : random.element(of: world.trains).id
            return .assign(train, line.id, pattern: random.chance(1, in: 4) ? nil : pattern)
        case 12:
            return .unassign(assigned.isEmpty ? TrainID(rawValue: 99) : random.element(of: assigned))
        case 13:
            // A pattern's train sent back to its first call by hand.
            guard let pattern = line.patterns.isEmpty ? nil : random.element(of: line.patterns), !pattern.trains.isEmpty else { return .advance(10) }
            return .sendToStation(random.element(of: pattern.trains), line.stops[pattern.calls[0]])
        case 14:
            // Stops that keep or break the patterns' calls.
            var stops = line.stops
            if random.chance(1, in: 2), stops.count > 2 {
                stops.removeLast()
            } else if let extra = world.stations.map(\.id).first(where: { $0 != stops.last }) {
                stops.append(extra)
            }
            return .setLineStops(line.id, stops)
        case 15..<18:
            return .advance(random.below(40))
        default:
            return .advance(60 + random.below(400))
        }
    }

    func testPatternsMatchTheReferenceAndBatchesMatchSingleSteps() throws {
        var counts: [String: Int] = [:]
        var digest = Digest()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ran = try runCampaign("line.patterns", cases: 6) { c in
            let (setup, operations) = try Self.generate(&c, operations: 45)
            c.note("setup: \(setup.width)x\(setup.height), \(setup.specs.count) tiles, second \(setup.seconds), \(setup.speed)")

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
                case .addPattern, .removePattern, .setLineTrains(_, _, pattern: _?), .setLineTargets(_, _, pattern: _?), .assign(_, _, pattern: _?):
                    let name = "\(operation)".dropFirst().prefix { $0 != "(" }
                    counts[error.map { String("\($0)".prefix { $0 != "(" }) } ?? "ok \(name)", default: 0] += 1
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
            for line in world.lines where !line.patterns.isEmpty {
                for level in ServiceLevel.allCases {
                    let loads = world.lineSegmentLoads(line.id, at: level) ?? []
                    if loads.contains(where: { $0 > 0 }) && (0..<line.patterns.count).contains(where: { world.lineTrainsInService(line.id, at: level, pattern: $0) == 0 }) {
                        counts["pattern left without room or trains", default: 0] += 1
                    }
                    if loads.contains(ServiceLine.segmentCapacity) { counts["segment full", default: 0] += 1 }
                }
            }

            let data = try encoder.encode(world)
            let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
            c.expect(loaded == world, "the world with patterns did not load back equal")
            let reloaded = try encoder.encode(loaded)
            c.expect(reloaded == data, "the same world saved to different bytes")
            digest.add(String(decoding: data, as: UTF8.self))
        }
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        print("[digest] line.patterns \(digest.hex) (\(summary))")
        assertVolume(ran == 6 * PropertySeeds.active.count, "every case should run")
        for (event, least) in [
            ("ok addPattern", 40), ("ok removePattern", 8), ("ok setLineTrains", 35), ("ok assign", 50), ("invalidLinePattern", 6),
            ("unknownLinePattern", 8), ("pattern dispatched", 60), ("express dispatched", 15), ("segment full", 8),
        ] {
            assertVolume((counts[event] ?? 0) >= least, "too few \(event): \(summary)")
        }
    }

    /// Counts trains a pattern sent out in an advance ("pattern
    /// dispatched"), those whose trip leaves a stop out ("express
    /// dispatched").
    static func countEvents(before: GameWorld, after: GameWorld, into counts: inout [String: Int]) {
        guard after.clock.now > before.clock.now else { return }
        for line in after.lines {
            for pattern in line.patterns {
                for id in pattern.trains {
                    guard let train = after.train(id: id), let old = before.train(id: id), train.timetable != old.timetable else { continue }
                    counts["pattern dispatched", default: 0] += 1
                    if zip(pattern.calls, pattern.calls.dropFirst()).contains(where: { $1 - $0 > 1 }) {
                        counts["express dispatched", default: 0] += 1
                    }
                }
            }
        }
    }
}
