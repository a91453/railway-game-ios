import Foundation
import GameCore
import XCTest

/// Fares, settlements and the ledger (G1c, decision 36) under generated
/// command sequences: the boarding campaign's networks, lines, trains and
/// demand (`BoardingPropertyTests`), mostly with a managed company, fare
/// rules of every shape set and refused along the way, the economy mode
/// switched now and then, and advances long enough to settle hours and
/// days.
///
/// - **Against the reference.** Every sequence runs on GameCore and on
///   ``ReferenceWorld``, which charges fares as each stop is served and
///   keeps its accounts in its own way; outcomes and all state, the
///   balance, accounts, reports and fares included, must match after every
///   step, and a refused command changes nothing.
/// - **Batches.** Every advance is also run as single ticks, and at 2x as
///   twice the ticks at 1x, so skipping idle minutes never skips a
///   settlement.
/// - **Invariants.** Every world reached keeps them. The world each case
///   ends in loads back equal and saves to the same bytes.
///
/// `PROPERTY_REPLAY=economy.differential@<seed>@<case>` runs one case.
final class EconomyPropertyTests: XCTestCase {
    typealias Operation = KernelDifferentialTests.Operation

    static func generate(_ c: inout PropertyCase, operations count: Int) throws -> (KernelDifferentialTests.Setup, [Operation]) {
        let (setup, base) = try BoardingPropertyTests.generate(&c, operations: count)
        var operations: [Operation] = []
        if c.random.chance(9, in: 10) { operations.append(.setEconomyMode(.management)) }
        if c.random.chance(1, in: 2) { operations.append(.setFareRules(fareRules(using: &c.random))) }
        for operation in base {
            operations.append(operation)
            switch c.random.below(24) {
            case 0, 1: operations.append(.setFareRules(fareRules(using: &c.random)))
            case 2: operations.append(.setEconomyMode(c.random.chance(1, in: 3) ? .free : .management))
            case 3: operations.append(.advance(c.random.element(of: [60, 61, 1_440, 1_441])))
            default: break
            }
        }
        return (setup, operations)
    }

    /// Fare rules of every shape: flat, from free to dear; distance steps
    /// over the few hundred metres of a small map; and, now and then, ones
    /// the engine refuses.
    static func fareRules(using random: inout SplitMix64) -> FareRules {
        if random.chance(1, in: 8) {
            return random.element(of: [
                .flat(-1), .distance([]), .distance([FareBand(fromMeters: 5, toMeters: nil, fare: 50)]),
                .distance([FareBand(fromMeters: 0, toMeters: 40, fare: 50), FareBand(fromMeters: 60, toMeters: nil, fare: 70)]),
                .distance([FareBand(fromMeters: 0, toMeters: 40, fare: 50)]),
            ])
        }
        if random.chance(1, in: 3) {
            return .flat(Money(random.element(of: [0, 1, 40, 75, 120, 500, 2_000, random.int64(in: 0...800)])))
        }
        var bands: [FareBand] = []
        var from: Int64 = 0
        for _ in 0..<random.below(4) {
            let to = from + random.int64(in: 0...120)
            bands.append(FareBand(fromMeters: from, toMeters: to, fare: Money(random.int64(in: 0...400))))
            from = to
        }
        bands.append(FareBand(fromMeters: from, toMeters: nil, fare: Money(random.int64(in: 0...600))))
        return .distance(bands)
    }

    static func generateWorld(_ c: inout PropertyCase, operations: Int) throws -> GameWorld {
        let (setup, generated) = try generate(&c, operations: operations)
        var world = try setup.build().0
        for operation in generated {
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        return world
    }

    func testTheEconomyMatchesTheReferenceAndBatchesMatchSingleSteps() throws {
        var counts: [String: Int] = [:]
        var digest = Digest()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ran = try runCampaign("economy.differential", cases: 12) { c in
            let (setup, operations) = try Self.generate(&c, operations: 60)
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
                switch operation {
                case .setFareRules:
                    counts[error == nil ? "fare rules set" : "fare rules refused", default: 0] += 1
                case .advance(let ticks) where error == nil:
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
            c.expect(loaded == world, "the world with accounts did not load back equal")
            let reloaded = try encoder.encode(loaded)
            c.expect(reloaded == data, "the same world saved to different bytes")
            digest.add(String(decoding: data, as: UTF8.self))
        }
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        print("[digest] economy.differential \(digest.hex) (\(summary))")
        assertVolume(ran == 12 * PropertySeeds.active.count, "every case should run")
        for (event, least) in [
            ("hours settled", 200), ("hours with fares", 60), ("days settled", 20), ("fare rules set", 60), ("fare rules refused", 5),
            ("below zero", 10),
        ] {
            assertVolume((counts[event] ?? 0) >= least, "too few \(event): \(summary)")
        }
    }

    /// Counts what an accepted advance settled.
    static func countEvents(before: GameWorld, after: GameWorld, into counts: inout [String: Int]) {
        let new = after.accounts.entries.filter { entry in !before.accounts.entries.contains(entry) }
        counts["hours settled", default: 0] += new.count { $0.kind == .hourlyNet }
        counts["hours with fares", default: 0] += new.count { $0.kind == .hourlyNet && $0.breakdown[0].amount > .zero }
        counts["days settled", default: 0] += new.count { $0.kind == .dailyStaff }
        if after.economy.balance < .zero, before.economy.balance >= .zero { counts["below zero", default: 0] += 1 }
    }
}
