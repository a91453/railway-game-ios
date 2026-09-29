import Foundation
import GameCore
import XCTest

/// Route reservation under traffic control (Stage T, decision 28) under
/// generated command sequences: trains of one to three cars placed, sent
/// to tiles and stations, turned round, taken off and put back, lines and
/// services running them, track removed ahead of them, and traffic control
/// turned off and on; many commands refused on purpose because another
/// train holds the track.
///
/// - **Against the reference.** Every sequence runs on GameCore and on
///   ``ReferenceWorld``, which finds a holder by testing every other
///   train's track in turn; outcomes and all state, each train's held
///   track included, must match after every step.
/// - **Safety.** Under traffic control no two trains ever hold, or stand
///   on, the same track (``WorldInvariants/violations(in:)``).
/// - **Saves.** The world each case ends in loads back equal and saves to
///   the same bytes.
///
/// `PROPERTY_REPLAY=traffic.reservation@<seed>@<case>` runs one case.
final class TrafficControlPropertyTests: XCTestCase {
    typealias Operation = KernelDifferentialTests.Operation

    static func generate(_ c: inout PropertyCase, operations count: Int) throws -> (KernelDifferentialTests.Setup, [Operation]) {
        var setup = KernelDifferentialTests.makeSetup(shapes: [.line, .loopWithTails, .loopWithTails, .ladder, .ladder, .grid], using: &c.random)
        setup.minutes = c.random.int64(in: 0...3_000)
        setup.extraBalance = 10_000_000
        setup.speed = .normal
        var (world, _) = try setup.build()
        var operations: [Operation] = []
        func run(_ operation: Operation) {
            operations.append(operation)
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        run(.setTrafficControl(true))
        // Trains placed where they can, some refused for held track.
        for index in 0..<(3 + c.random.below(3)) {
            run(.purchase("R\(index + 1)"))
            guard let id = world.trains.last?.id else { continue }
            run(.setCars(id, c.random.element(of: [1, 1, 2, 3])))
            for _ in 0..<3 where world.train(id: id)?.position == nil {
                guard let position = StationFacilityPropertyTests.bodyPosition(in: world, using: &c.random) else { break }
                run(.place(id, position))
            }
            run(.setRate(id, c.random.element(of: [512, 1024, 1024, 2048])))
        }
        if c.random.chance(1, in: 2) {
            operations += LineDispatchPropertyTests.scriptedLine(in: &world, using: &c.random)
        }
        while operations.count < count {
            let trains = world.trains
            let train = trains.isEmpty ? nil : c.random.element(of: trains)
            switch c.random.below(26) {
            case 0..<5:
                guard let train else { run(.advance(3)); continue }
                let tracks = world.tracks.map(\.position)
                guard !tracks.isEmpty else { run(.advance(3)); continue }
                run(.sendToTile(train.id, c.random.element(of: tracks)))
            case 5, 6, 7:
                let stations = world.stations.map(\.id)
                guard let train, !stations.isEmpty else { run(.advance(3)); continue }
                run(.sendWholeTrainToStation(train.id, c.random.element(of: stations)))
            case 8, 9:
                guard let train else { run(.advance(3)); continue }
                run(.reverse(train.id))
            case 10:
                // Ahead of a train, mostly.
                let ahead = trains.compactMap { $0.movement.remainingContinuation.last }
                if !ahead.isEmpty, c.random.chance(3, in: 4) {
                    run(.removeTrack(c.random.element(of: ahead)))
                } else {
                    run(KernelDifferentialTests.nextOperation(in: world, using: &c.random))
                }
            case 11:
                guard let train else { run(.advance(3)); continue }
                run(.unplace(train.id))
                if let position = StationFacilityPropertyTests.bodyPosition(in: world, using: &c.random) { run(.place(train.id, position)) }
            case 12:
                run(.setTrafficControl(!world.trafficControl || c.random.chance(1, in: 3) ? true : false))
            case 13..<19:
                run(.advance(1 + c.random.below(8)))
            case 19, 20:
                run(LineDispatchPropertyTests.nextDispatchOperation(in: world, using: &c.random))
            default:
                run(KernelDifferentialTests.nextOperation(in: world, using: &c.random))
            }
        }
        return (setup, operations)
    }

    func testReservationsMatchTheReferenceAndKeepTrainsApart() throws {
        var counts: [String: Int] = [:]
        var digest = Digest()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ran = try runCampaign("traffic.reservation", cases: 12) { c in
            let (setup, operations) = try Self.generate(&c, operations: 60)
            c.note("setup: \(setup.width)x\(setup.height), \(setup.specs.count) tiles")

            if let failure = KernelDifferentialTests.firstProblem(setup, operations, lineAnswers: false) {
                let minimal = KernelDifferentialTests.minimalFailure(setup, operations, lineAnswers: false)
                c.fail("step \(failure.step): \(failure.problem)\n  minimal (\(minimal.count) of \(operations.count)): [\(minimal.map(\.description).joined(separator: ", "))]")
                return
            }

            var (world, model) = try setup.build()
            for (index, operation) in operations.enumerated() {
                let before = world
                let error = KernelDifferentialTests.apply(operation, to: &world)
                _ = KernelDifferentialTests.apply(operation, to: &model)
                switch (operation, error) {
                case (_, .trackReserved?):
                    counts["refused: \("\(operation)".dropFirst().prefix { $0 != "(" })", default: 0] += 1
                case (_, .trainsShareTrack?):
                    counts["trainsShareTrack", default: 0] += 1
                case (.setTrafficControl(true), nil) where !before.trafficControl:
                    counts["turned on", default: 0] += 1
                case (.removeTrack(let p), .trackInUse?) where before.trafficControl
                    && !before.trains.contains(where: { before.occupiedResources(of: $0.id).contains(.node(p)) }):
                    counts["route ahead locked", default: 0] += 1
                case (.advance, nil) where world.trafficControl:
                    for train in world.trains where train.position != before.train(id: train.id)?.position {
                        counts["moved under control", default: 0] += 1
                    }
                    for train in world.trains where world.trainHoldingRoute(of: train.id) != nil {
                        counts["service waited for track", default: 0] += 1
                    }
                default:
                    break
                }
                let problems = TrackResourcePropertyTests.resourceDifferences(world, model) + WorldInvariants.violations(in: world)
                c.expect(problems.isEmpty, "step \(index) \(operation): \(problems.prefix(5))")
                if !problems.isEmpty { return }
            }

            let data = try encoder.encode(world)
            let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
            c.expect(loaded == world, "the world under traffic control did not load back equal")
            let reloaded = try encoder.encode(loaded)
            c.expect(reloaded == data, "the same world saved to different bytes")
            digest.add(String(decoding: data, as: UTF8.self))
        }
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        print("[digest] traffic.reservation \(digest.hex) (\(summary))")
        assertVolume(ran == 12 * PropertySeeds.active.count, "every case should run")
        for (event, least) in [
            ("refused: sendToTile", 10), ("refused: place", 5), ("turned on", 10), ("trainsShareTrack", 2),
            ("route ahead locked", 2), ("moved under control", 50), ("service waited for track", 5),
        ] {
            assertVolume((counts[event] ?? 0) >= least, "too few \(event): \(summary)")
        }
    }
}
