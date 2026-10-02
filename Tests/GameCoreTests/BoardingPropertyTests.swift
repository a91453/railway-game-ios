import Foundation
import GameCore
import XCTest

/// Boarding, alighting and capacity (G1b, decision 35) under generated
/// command sequences: the dispatch campaign's small networks, lines and
/// trains (`LineDispatchPropertyTests`), with demand at their stations, from
/// a trickle to more than any train or station holds, trains of several
/// cars, and everything that ends a trip early: trains taken off their
/// lines, services stopped, lines re-stopped and removed.
///
/// - **Against the reference.** Every sequence runs on GameCore and on
///   ``ReferenceWorld``, which steps every minute and serves each stop the
///   moment it is left; outcomes and all state, every station's queue and
///   counts and every train's riders included, must match after every
///   step, and a refused command changes nothing.
/// - **Batches.** Every advance is also run as single ticks, and at 2x as
///   twice the ticks at 1x, so skipping idle minutes never skips a stop.
/// - **Invariants.** Every world reached keeps them (every passenger
///   accounted for, no train over its capacity, every rider bound for a
///   stop ahead). The world each case ends in loads back equal and saves
///   to the same bytes.
///
/// A failing sequence is shrunk before it is reported, with its seed and
/// case; `PROPERTY_REPLAY=boarding.differential@<seed>@<case>` runs one
/// case.
final class BoardingPropertyTests: XCTestCase {
    typealias Operation = KernelDifferentialTests.Operation

    static func generate(_ c: inout PropertyCase, operations count: Int) throws -> (KernelDifferentialTests.Setup, [Operation]) {
        var setup = KernelDifferentialTests.makeSetup(shapes: [.line, .line, .loopWithTails, .loopWithTails, .ladder, .grid], using: &c.random)
        // Around the morning peak, and now and then the night.
        setup.seconds = 60 * (c.random.chance(1, in: 5) ? c.random.int64(in: -30...300) : c.random.int64(in: 400...1_100))
        setup.speed = c.random.element(of: [.normal, .normal, .double, .paused])
        var (world, _) = try setup.build()
        let speed: Operation = .setSpeed(c.random.chance(1, in: 3) ? .double : .normal)
        _ = KernelDifferentialTests.apply(speed, to: &world)
        var operations = [speed]
        func run(_ operation: Operation) {
            operations.append(operation)
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        for _ in 0..<(1 + c.random.below(2)) {
            for operation in LineDispatchPropertyTests.scriptedLine(in: &world, using: &c.random) {
                operations.append(operation)
            }
            longTrain(in: &world, using: &c.random, into: &operations)
        }
        for station in world.stations where c.random.chance(3, in: 4) {
            run(.setStationDemand(station.id, demand(using: &c.random)))
        }
        while operations.count < count {
            switch c.random.below(16) {
            case 0:
                operations += LineDispatchPropertyTests.scriptedLine(in: &world, using: &c.random)
                longTrain(in: &world, using: &c.random, into: &operations)
            case 1, 2:
                let station = world.stations.isEmpty || c.random.chance(1, in: 15) ? StationID(rawValue: 99) : c.random.element(of: world.stations).id
                run(.setStationDemand(station, c.random.chance(1, in: 6) ? nil : demand(using: &c.random)))
            case 3, 4:
                // A line's train off its line mid-trip, then its service
                // stopped: its riders are abandoned.
                let running = world.lines.flatMap(\.trains).filter { world.train(id: $0)?.execution != nil && world.riderCount(of: $0) > 0 }
                guard let id = running.isEmpty ? nil : c.random.element(of: running) else {
                    run(.advance(1 + c.random.below(6)))
                    continue
                }
                run(.unassign(id))
                if c.random.chance(1, in: 2) { run(.advance(c.random.below(4))) }
                run(.stopService(id))
            default:
                run(LineDispatchPropertyTests.nextDispatchOperation(in: world, using: &c.random))
            }
        }
        return (setup, operations)
    }

    /// Mostly a train of two or three cars on a line of its own: bought,
    /// lengthened, placed at the first platform (and heading) of any
    /// station where its body fits, and given a line from there to up to
    /// two other served stations, running all day; applied to `world` as
    /// they are drawn.
    private static func longTrain(in world: inout GameWorld, using random: inout SplitMix64, into operations: inout [Operation]) {
        guard random.chance(3, in: 4), world.lines.count < 4 else { return }
        func run(_ operation: Operation) -> GameError? {
            operations.append(operation)
            return KernelDifferentialTests.apply(operation, to: &world)
        }
        _ = run(.purchase("C\(world.trains.count + 1)"))
        guard let id = world.trains.last?.id else { return }
        _ = run(.setCars(id, 2 + random.below(2)))
        let served = world.stations.filter { !world.platforms(of: $0.id).isEmpty }.map(\.id)
        var first: StationID?
        search: for station in served {
            for platform in world.platforms(of: station) {
                for heading in TrackDirection.allCases {
                    var trial = world
                    if KernelDifferentialTests.apply(.place(id, .atNode(platform, heading: heading)), to: &trial) == nil {
                        _ = run(.place(id, .atNode(platform, heading: heading)))
                        first = station
                        break search
                    }
                }
            }
        }
        guard let first else { return }
        var stops = [first]
        for station in served where station != first && stops.count < 3 && random.chance(2, in: 3) {
            stops.append(station)
        }
        if stops.count < 2, let other = served.first(where: { $0 != first }) { stops.append(other) }
        guard stops.count >= 2, run(.createLine("C", stops)) == nil, let line = world.lines.last?.id else { return }
        _ = run(.setLineWindow(line, .allDay))
        _ = run(.setLineTrains(line, TrainsInService(peak: 1, offPeak: 1, low: 1)))
        _ = run(.setRate(id, random.element(of: [1024, 1500, 2048])))
        _ = run(.assign(id, line))
    }

    /// A demand of any kind: a trickle, enough to fill trains now and then,
    /// or more than any train holds.
    static func demand(using random: inout SplitMix64) -> StationDemand {
        let trips: Int64 = switch random.below(10) {
        case 0: 0
        case 1: StationDemand.maximumDailyTrips
        case 2, 3, 4: random.int64(in: 500...10_000)
        case 5, 6, 7: random.int64(in: 10_000...100_000)
        default: random.int64(in: 100_000...1_000_000)
        }
        return StationDemand(kind: random.element(of: StationDemandKind.allCases), dailyTrips: trips)
    }

    /// A world of this campaign after `operations` generated operations;
    /// for the save mutation campaign.
    static func generateWorld(_ c: inout PropertyCase, operations: Int) throws -> GameWorld {
        let (setup, generated) = try generate(&c, operations: operations)
        var world = try setup.build().0
        for operation in generated {
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        return world
    }

    func testBoardingMatchesTheReferenceAndBatchesMatchSingleSteps() throws {
        var counts: [String: Int] = [:]
        var digest = Digest()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ran = try runCampaign("boarding.differential", cases: 16) { c in
            let (setup, operations) = try Self.generate(&c, operations: 70)
            c.note("setup: \(setup.width)x\(setup.height), \(setup.specs.count) tiles, second \(setup.seconds), \(setup.speed)")

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
                if case .advance(let ticks) = operation, error == nil {
                    // Tick by tick, counting what each tick did; the batch
                    // must end where the single ticks do.
                    var single = before
                    for _ in 0..<ticks {
                        let previous = single
                        try single.advance(ticks: 1)
                        Self.countEvents(before: previous, after: single, into: &counts)
                    }
                    guard single == world else {
                        c.fail("\(at): \(ticks) ticks at once differ from \(ticks) single ticks")
                        return
                    }
                    if before.clock.speed == .double, let problem = ServicePropertyTests.batchProblem(ticks: ticks, from: before, batch: world) {
                        c.fail("\(at): \(problem)")
                        return
                    }
                }
                if case .stopService = operation, error == nil, before.riders != world.riders {
                    counts["riders abandoned", default: 0] += 1
                }
                let problems = WorldInvariants.violations(in: world)
                c.expect(problems.isEmpty, "\(at): \(problems)")
            }

            let data = try encoder.encode(world)
            let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
            c.expect(loaded == world, "the world with riders did not load back equal")
            let reloaded = try encoder.encode(loaded)
            c.expect(reloaded == data, "the same world saved to different bytes")
            digest.add(String(decoding: data, as: UTF8.self))
        }
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        print("[digest] boarding.differential \(digest.hex) (\(summary))")
        assertVolume(ran == 16 * PropertySeeds.active.count, "every case should run")
        for (event, least) in [
            ("boarded", 300), ("arrived", 300), ("refused", 150), ("full trains", 300), ("several cars", 100), ("riders abandoned", 10),
            ("several destinations", 200),
        ] {
            assertVolume((counts[event] ?? 0) >= least, "too few \(event): \(summary)")
        }
    }

    /// Counts what one tick did to the passengers: stations whose
    /// passengers arrived or were refused, trains whose riders changed, and
    /// trains that end it full, with several cars and riders, or with
    /// riders for several destinations.
    static func countEvents(before: GameWorld, after: GameWorld, into counts: inout [String: Int]) {
        for station in after.stations {
            let old = before.passengerLedger(of: station.id)
            let new = after.passengerLedger(of: station.id)
            if new.arrived > old.arrived { counts["arrived", default: 0] += 1 }
            if new.refused > old.refused { counts["refused", default: 0] += 1 }
        }
        for entry in after.riders {
            guard let train = after.train(id: entry.train) else { continue }
            if entry != before.riders.first(where: { $0.train == entry.train }) { counts["boarded", default: 0] += 1 }
            if entry.count == train.capacity { counts["full trains", default: 0] += 1 }
            if train.cars > 1 { counts["several cars", default: 0] += 1 }
            if Set(entry.groups.map(\.destination)).count > 1 { counts["several destinations", default: 0] += 1 }
        }
    }
}
