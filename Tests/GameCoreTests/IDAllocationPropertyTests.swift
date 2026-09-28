import Foundation
import GameCore
import XCTest

/// Generated sequences of station builds, train purchases and save/load
/// round trips, starting from ID counters that are either ordinary or a few
/// steps from the end. Each result is predicted from a model of the two
/// counters (hand out the counter's value, then add 1; refuse at `Int.max`)
/// and of which tiles are taken, and checked against GameCore: the IDs
/// handed out, the saved counters, and an unchanged world after every
/// refusal. See `IDAllocationTests` for the rule.
final class IDAllocationPropertyTests: XCTestCase {
    private static let side = 6

    private enum Kind: String, CaseIterable { case station, train }

    private func encode(_ world: GameWorld) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(world)
    }

    private func counters(_ world: GameWorld) throws -> [Kind: Int] {
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: try encode(world)) as? [String: Any])
        return [.station: try XCTUnwrap(saved["nextStationID"] as? Int), .train: try XCTUnwrap(saved["nextTrainID"] as? Int)]
    }

    /// Ordinary, or within a few allocations of the end (`Int.max` is
    /// already exhausted).
    private func startingCounter(_ c: inout PropertyCase) -> Int {
        c.random.chance(1, in: 4) ? 2 + c.random.below(40) : Int.max - c.random.below(6)
    }

    func testIDsAreHandedOutInOrderUntilTheyRunOutAndThenRefusedWithoutChange() throws {
        var digest = Digest()
        var created = 0, refused = 0, lastIDs = 0, roundTrips = 0
        let ran = try runCampaign("ids.allocation", cases: 40) { c in
            var world = try makeWorld(width: Self.side, height: Self.side, balance: 1_000_000_000)
            try world.buildTrack(at: GridPosition(x: 0, y: 0), connections: [.east])
            try world.buildTrack(at: GridPosition(x: 1, y: 0), connections: [.west])
            try world.buildStation(named: "Yard", at: GridPosition(x: 2, y: 0))
            try world.purchaseTrain(named: "Local")
            var next: [Kind: Int] = [.station: startingCounter(&c), .train: startingCounter(&c)]
            c.note("counters: station \(next[.station]!), train \(next[.train]!)")
            var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: try encode(world)) as? [String: Any])
            saved["nextStationID"] = next[.station]
            saved["nextTrainID"] = next[.train]
            world = try JSONDecoder().decode(GameWorld.self, from: try JSONSerialization.data(withJSONObject: saved))
            var taken: Set<GridPosition> = [GridPosition(x: 0, y: 0), GridPosition(x: 1, y: 0), GridPosition(x: 2, y: 0)]

            for step in 0..<16 {
                let before = world
                let roll = c.random.below(10)
                if roll < 2 {
                    c.note("\(step): save and load")
                    let loaded = try JSONDecoder().decode(GameWorld.self, from: try encode(world))
                    c.expect(loaded == world, "step \(step): the loaded world differs")
                    world = loaded
                    roundTrips += 1
                    continue
                }
                let kind: Kind = roll < 6 ? .station : .train
                let tile = GridPosition(x: c.random.below(Self.side + 1) - 1, y: c.random.below(Self.side))
                c.note("\(step): \(kind)\(kind == .station ? " at \(tile)" : "")")

                let expected: GameError?
                if kind == .station, !world.map.contains(tile) {
                    expected = .outOfBounds(tile)
                } else if kind == .station, taken.contains(tile) {
                    expected = .tileOccupied(tile)
                } else if next[kind] == Int.max {
                    expected = .idsExhausted
                } else {
                    expected = nil
                }

                let outcome = Result { () throws(GameError) -> Int in
                    switch kind {
                    case .station: try world.buildStation(named: "S\(step)", at: tile).id.rawValue
                    case .train: try world.purchaseTrain(named: "T\(step)").id.rawValue
                    }
                }
                digest.add("\(kind) \(outcome)")
                switch (outcome, expected) {
                case (.success(let id), nil):
                    c.expect(id == next[kind], "step \(step): got ID \(id), expected \(next[kind]!)")
                    if id == Int.max - 1 { lastIDs += 1 }
                    next[kind] = next[kind]! + 1
                    if kind == .station { taken.insert(tile) }
                    created += 1
                case (.failure(let error), let expected?):
                    c.expect(error == expected, "step \(step): refused with \(error), expected \(expected)")
                    c.expect(world == before, "step \(step): the refused \(kind) changed the world")
                    if error == .idsExhausted { refused += 1 }
                default:
                    c.fail("step \(step): got \(outcome), expected \(String(describing: expected))")
                }

                let savedCounters = try counters(world)
                c.expect(savedCounters == next, "step \(step): saved counters \(savedCounters), expected \(next)")
                let stationIDs = world.stations.map(\.id.rawValue)
                let trainIDs = world.trains.map(\.id.rawValue)
                for (kind, ids) in [(Kind.station, stationIDs), (.train, trainIDs)] {
                    c.expect(ids == ids.sorted() && Set(ids).count == ids.count, "step \(step): \(kind) IDs \(ids) repeat or are out of order")
                    c.expect(ids.allSatisfy { $0 >= 1 && $0 < next[kind]! }, "step \(step): a \(kind) ID is not in 1..<counter: \(ids)")
                }
                let problems = WorldInvariants.violations(in: world)
                c.expect(problems.isEmpty, "step \(step): \(problems)")
            }
            if let problem = WorldInvariants.roundTripProblem(of: world) { c.fail(problem) }
        }
        assertVolume(ran == 40 * PropertySeeds.active.count, "every case should run")
        assertVolume(created > 400, "too few IDs were handed out")
        assertVolume(refused > 300, "too few commands ran out of IDs")
        assertVolume(lastIDs > 80, "too few cases reached the last ID")
        assertVolume(roundTrips > 100, "too few worlds were saved and loaded")
        print("[digest] ids.allocation \(digest.hex) (\(created) handed out, \(refused) refused, \(lastIDs) last IDs, \(roundTrips) round trips)")
    }
}
