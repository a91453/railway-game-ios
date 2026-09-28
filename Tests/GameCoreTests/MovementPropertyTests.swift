import Foundation
import GameCore
import XCTest

/// Stage K on generated networks: each basic step matches the unit-by-unit
/// reference (`ReferenceMovement`), time can be split into ticks any way,
/// and nothing is lost, duplicated or invented at the boundaries.
final class MovementPropertyTests: XCTestCase {
    private let first = TrainID(rawValue: 1)

    /// A generated world with one placed train, its continuation set, and
    /// sometimes a track tile along the continuation removed afterwards.
    private struct Setup {
        var world: GameWorld
        var walk: [GridPosition]
    }

    private func makeSetup(_ c: inout PropertyCase, trains: Int = 1) throws -> Setup? {
        let shape = c.random.element(of: NetworkShape.allCases)
        let (specs, width, height) = NetworkGenerator.specs(shape, using: &c.random)
        var world = try NetworkGenerator.build(specs, width: width, height: height)
        c.note("\(shape) \(width)x\(height), \(specs.count) tiles")
        var firstWalk: [GridPosition] = []
        for number in 1...trains {
            let id = TrainID(rawValue: number)
            try world.purchaseTrain(named: "T\(number)")
            guard let position = PositionGenerator.validPosition(in: world, using: &c.random) else { return nil }
            try world.placeTrain(id, at: position)
            let walk = PositionGenerator.walk(in: world, from: position, length: c.random.below(9), using: &c.random)
            try world.setTrainContinuation(id, to: walk)
            c.note("train \(number) at \(position), continuation \(walk)")
            if number == 1 { firstWalk = walk }
        }
        // Track ahead may be removed after the continuation was set.
        if !firstWalk.isEmpty, c.random.chance(1, in: 4) {
            let tile = c.random.element(of: firstWalk)
            if (try? world.removeTrack(at: tile)) != nil {
                c.note("removed \(tile) after setting the continuation")
            }
        }
        return Setup(world: world, walk: firstWalk)
    }

    /// Rates around every boundary the train meets first: the end of its
    /// link, one and two links on, and some plain values.
    private func interestingRate(for position: TrainPosition, using random: inout SplitMix64) -> Int64 {
        let toEnd: Int64 = {
            if case .onLink(_, _, let offset) = position { return TrainPosition.linkLength - offset }
            return 0
        }()
        let base = random.element(of: [toEnd, toEnd + 1024, toEnd + 2048, 1024, 0])
        let nudge = Int64(random.element(of: [-2, -1, 0, 0, 1, 2]))
        return random.chance(1, in: 3) ? random.int64(in: 0...5_000) : max(0, base + nudge)
    }

    func testEachStepMatchesTheUnitByUnitReference() throws {
        var steps = 0
        let ran = try runCampaign("movement.reference", cases: 250) { c in
            guard var setup = try makeSetup(&c) else { return }
            for stepNumber in 0..<3 {
                guard let train = setup.world.train(id: first), let position = train.position else { return c.fail("train lost") }
                let rate = interestingRate(for: position, using: &c.random)
                try setup.world.setTrainMovementRate(first, to: rate)
                let expected = ReferenceMovement.travel(
                    in: setup.world,
                    from: position,
                    distance: rate,
                    continuation: train.movement.continuation,
                    cursor: train.movement.cursor
                )
                try setup.world.advance(ticks: 1)
                steps += 1
                guard let after = setup.world.train(id: first) else { return c.fail("train lost") }
                let context = "step \(stepNumber) from \(position) at rate \(rate), cursor \(train.movement.cursor) of \(train.movement.continuation)"
                c.expect(after.position == expected.position, "\(context): \(String(describing: after.position)), reference \(expected.position)")
                if expected.cursor == train.movement.continuation.count {
                    c.expect(after.movement.continuation.isEmpty && after.movement.cursor == 0, "\(context): spent continuation kept as \(after.movement)")
                } else {
                    c.expect(
                        after.movement.continuation == train.movement.continuation && after.movement.cursor == expected.cursor,
                        "\(context): cursor \(after.movement.cursor), reference \(expected.cursor)"
                    )
                }
                // Nothing lost: a train that ends on a link used its whole rate.
                if case .onLink = expected.position {
                    c.expect(expected.travelled == rate, "\(context): reference ended on a link with distance left")
                }
                c.expect(after.movement.rate == rate, "\(context): the rate changed")
                let problems = WorldInvariants.violations(in: setup.world)
                c.expect(problems.isEmpty, "\(context): \(problems)")
            }
        }
        assertVolume(ran == 250 * PropertySeeds.active.count, "every case should run")
        assertVolume(steps > 2_500, "too few steps were compared")
    }

    func testAHugeRateEndsWhereTheReferenceDoes() throws {
        try runCampaign("movement.hugeRate", cases: 120) { c in
            guard var setup = try makeSetup(&c) else { return }
            guard let train = setup.world.train(id: first), let position = train.position else { return c.fail("train lost") }
            // Enough to finish any continuation: the rest of the link plus
            // every entry, and one more unit.
            let enough = TrainPosition.linkLength * Int64(setup.walk.count + 1) + 1
            let expected = ReferenceMovement.travel(in: setup.world, from: position, distance: enough, continuation: train.movement.continuation, cursor: 0)
            try setup.world.setTrainMovementRate(first, to: .max)
            try setup.world.advance(ticks: 1)
            c.expect(setup.world.train(id: first)?.position == expected.position, "Int64.max ended at \(String(describing: setup.world.train(id: first)?.position)), reference \(expected.position)")
            // It ends at a node, and more time changes nothing.
            guard case .atNode? = setup.world.train(id: first)?.position else { return c.fail("a huge rate ended on a link") }
            let settled = setup.world.trains
            try setup.world.advance(ticks: 1_000_000)
            c.expect(setup.world.trains == settled, "a settled train moved again")
        }
    }

    func testSplittingTicksNeverChangesTheOutcome() throws {
        try runCampaign("movement.tickPartition", cases: 120) { c in
            guard let setup = try makeSetup(&c, trains: 1 + c.random.below(3)) else { return }
            var start = setup.world
            for train in start.trains where train.position != nil {
                try start.setTrainMovementRate(train.id, to: c.random.int64(in: 0...2_500))
            }
            let total = 1 + c.random.below(40)
            var whole = start
            try whole.advance(ticks: total)

            // The same ticks in random chunks, zero-length chunks included.
            var pieces = start
            var left = total
            var chunks: [Int] = []
            while left > 0 {
                let chunk = min(left, c.random.below(6))
                chunks.append(chunk)
                try pieces.advance(ticks: chunk)
                left -= chunk
            }
            c.note("\(total) ticks as \(chunks)")
            c.expect(pieces == whole, "advance(\(total)) differs from the chunks")

            // One tick at 2x is two ticks at 1x, apart from the speed itself.
            var double = start
            double.setSpeed(.double)
            try double.advance(ticks: total)
            var normal = start
            try normal.advance(ticks: 2 * total)
            double.setSpeed(.normal)
            c.expect(double == normal, "\(total) ticks at 2x differ from \(2 * total) at 1x")
        }
    }

    /// Not a stated rule, but a consequence of the per-step rules on a map
    /// that does not change: a step of a + b units ends where a step of a
    /// and then a step of b end (exact arrival never consumes the next
    /// entry, and a blocked train drops its distance in both cases).
    func testSplittingAStepsDistanceNeverChangesWhereTheTrainEnds() throws {
        try runCampaign("movement.distancePartition", cases: 250) { c in
            guard let setup = try makeSetup(&c) else { return }
            guard let position = setup.world.train(id: first)?.position else { return c.fail("train lost") }
            let a = interestingRate(for: position, using: &c.random)
            let b = c.random.chance(1, in: 2) ? interestingRate(for: position, using: &c.random) : c.random.int64(in: 0...3_000)
            c.note("a = \(a), b = \(b)")
            var split = setup.world
            try split.setTrainMovementRate(first, to: a)
            try split.advance(ticks: 1)
            try split.setTrainMovementRate(first, to: b)
            try split.advance(ticks: 1)
            var whole = setup.world
            try whole.setTrainMovementRate(first, to: a + b)
            try whole.advance(ticks: 1)
            let splitTrain = split.train(id: first)
            let wholeTrain = whole.train(id: first)
            c.expect(splitTrain?.position == wholeTrain?.position, "a then b: \(String(describing: splitTrain?.position)); a + b: \(String(describing: wholeTrain?.position))")
            c.expect(
                splitTrain?.movement.continuation == wholeTrain?.movement.continuation
                    && splitTrain?.movement.cursor == wholeTrain?.movement.cursor,
                "cursor differs"
            )
        }
    }

    func testZeroDistanceAndZeroTicksChangeNothing() throws {
        try runCampaign("movement.zero", cases: 80) { c in
            guard var setup = try makeSetup(&c, trains: 1 + c.random.below(3)) else { return }
            let before = setup.world
            try setup.world.advance(ticks: 0)
            c.expect(setup.world == before, "advance(0) changed the world")
            // Every rate is 0 (new trains are idle): only the clock moves.
            let ticks = 1 + c.random.below(50)
            try setup.world.advance(ticks: ticks)
            c.expect(setup.world.trains == before.trains, "rate 0 moved a train")
            c.expect(setup.world.clock.now.minutes == before.clock.now.minutes + Int64(ticks), "the clock did not move \(ticks) minutes")
            setup.world.pause()
            let paused = setup.world
            try setup.world.advance(ticks: 1 + c.random.below(1_000))
            c.expect(setup.world == paused, "paused ticks changed the world")
        }
    }

    func testTheSameInputsGiveTheSameWorldAndTheSameSave() throws {
        var digests: [String] = []
        for run in 0..<2 {
            var digest = Digest()
            try runCampaign("movement.determinism.\(run)", cases: 60) { c in
                // Both runs use the same seeds and indexes, so the same cases.
                var replay = PropertyCase(suite: "movement.determinism", seed: c.seed, index: c.index)
                guard var setup = try makeSetup(&replay, trains: 1 + replay.random.below(3)) else { return }
                for train in setup.world.trains where train.position != nil {
                    try setup.world.setTrainMovementRate(train.id, to: replay.random.int64(in: 1...3_000))
                }
                try setup.world.advance(ticks: 1 + replay.random.below(30))
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                digest.add(String(decoding: try encoder.encode(setup.world), as: UTF8.self))
            }
            digests.append(digest.hex)
        }
        XCTAssertEqual(digests[0], digests[1], "two runs of the same cases differ")
        print("[digest] movement.determinism \(digests[0])")
    }
}
