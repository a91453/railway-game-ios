import Foundation
import GameCore
import XCTest

/// Generated sequences of commands against one world: construction, trains,
/// routes, rates and time, mostly sensible and sometimes invalid. After every
/// step the world keeps its invariants; a refused command changes nothing; a
/// route query changes nothing and is always accepted as a continuation; the
/// world survives saving; and the same sequence always gives the same worlds.
final class WorldStateMachineTests: XCTestCase {
    enum Operation: CustomStringConvertible {
        case purchase(String)
        case place(TrainID, TrainPosition)
        case unplace(TrainID)
        case reverse(TrainID)
        case setRate(TrainID, Int64)
        case setContinuation(TrainID, [GridPosition])
        case routeAndCommit(TrainID, GridPosition)
        case advance(Int)
        case setSpeed(GameSpeed)
        case buildTrack(GridPosition, UInt8)
        case removeTrack(GridPosition)
        case buildStation(GridPosition)
        case query(TrainPosition, GridPosition)

        var description: String {
            switch self {
            case .purchase(let name): "purchase(\"\(name)\")"
            case .place(let id, let position): "place(\(id.rawValue), \(position))"
            case .unplace(let id): "unplace(\(id.rawValue))"
            case .reverse(let id): "reverse(\(id.rawValue))"
            case .setRate(let id, let rate): "setRate(\(id.rawValue), \(rate))"
            case .setContinuation(let id, let nodes): "setContinuation(\(id.rawValue), \(nodes))"
            case .routeAndCommit(let id, let destination): "routeAndCommit(\(id.rawValue), \(destination))"
            case .advance(let ticks): "advance(\(ticks))"
            case .setSpeed(let speed): "setSpeed(\(speed))"
            case .buildTrack(let tile, let raw): "buildTrack(\(tile), \(raw))"
            case .removeTrack(let tile): "removeTrack(\(tile))"
            case .buildStation(let tile): "buildStation(\(tile))"
            case .query(let start, let destination): "route(\(start), \(destination))"
            }
        }
    }

    private func randomTile(in world: GameWorld, using random: inout SplitMix64) -> GridPosition {
        GridPosition(x: random.below(world.map.width + 2) - 1, y: random.below(world.map.height + 2) - 1)
    }

    /// The next operation, drawn with the current world in view.
    private func nextOperation(in world: GameWorld, using random: inout SplitMix64) -> Operation {
        let trains = world.trains
        let id = trains.isEmpty || random.chance(1, in: 12) ? TrainID(rawValue: trains.count + 1 + random.below(2)) : random.element(of: trains).id
        let position = world.train(id: id)?.position
        switch random.below(100) {
        case 0..<6:
            return .purchase(random.chance(1, in: 8) ? " " : "T\(trains.count + 1)")
        case 6..<18:
            if random.chance(3, in: 4), let valid = PositionGenerator.validPosition(in: world, using: &random) {
                return .place(id, valid)
            }
            let tile = randomTile(in: world, using: &random)
            return random.chance(1, in: 2)
                ? .place(id, .atNode(tile, heading: random.element(of: TrackDirection.allCases)))
                : .place(id, .onLink(from: tile, to: step(tile, random.element(of: TrackDirection.allCases)), offset: random.element(of: [0, 1, 512, 1023, 1024])))
        case 18..<22:
            return .unplace(id)
        case 22..<27:
            return .reverse(id)
        case 27..<37:
            let rate: Int64 = random.chance(1, in: 20) ? -random.int64(in: 1...5) : random.element(of: [0, 1, 511, 1024, 3_000, random.int64(in: 0...4_096), .max])
            return .setRate(id, rate)
        case 37..<47:
            guard let position else { return .setContinuation(id, []) }
            var walk = PositionGenerator.walk(in: world, from: position, length: random.below(8), using: &random)
            if !walk.isEmpty, random.chance(1, in: 4) {
                // Break it: straight back, a gap, or off the map.
                let index = random.below(walk.count)
                switch random.below(3) {
                case 0: walk.append(walk.count >= 2 ? walk[walk.count - 2] : ahead(of: position).node)
                case 1: walk[index] = GridPosition(x: walk[index].x + 1, y: walk[index].y + 1)
                default: walk[index] = GridPosition(x: -5, y: walk[index].y)
                }
            }
            return .setContinuation(id, walk)
        case 47..<60:
            let tracks = world.tracks.map(\.position)
            let destination = !tracks.isEmpty && random.chance(5, in: 6) ? random.element(of: tracks) : randomTile(in: world, using: &random)
            return .routeAndCommit(id, destination)
        case 60..<80:
            return .advance(random.below(9))
        case 80..<83:
            return .setSpeed(random.element(of: GameSpeed.allCases))
        case 83..<90:
            let raw = random.chance(1, in: 10) ? random.element(of: [0, 16, 255]) : UInt8(1 + random.below(15))
            return .buildTrack(randomTile(in: world, using: &random), raw)
        case 90..<95:
            // Often the track under a train, which must be refused.
            if let position, random.chance(1, in: 3) {
                switch position {
                case .atNode(let tile, _): return .removeTrack(tile)
                case .onLink(let from, let to, _): return .removeTrack(random.chance(1, in: 2) ? from : to)
                case .onEdge: break
                }
            }
            return .removeTrack(randomTile(in: world, using: &random))
        case 95..<97:
            return .buildStation(randomTile(in: world, using: &random))
        default:
            let start = PositionGenerator.validPosition(in: world, using: &random) ?? .atNode(randomTile(in: world, using: &random), heading: .east)
            return .query(start, randomTile(in: world, using: &random))
        }
    }

    /// Applies `operation`. Returns the error of a refused command.
    private func apply(_ operation: Operation, to world: inout GameWorld, _ c: PropertyCase) -> GameError? {
        do throws(GameError) {
            switch operation {
            case .purchase(let name): try world.purchaseTrain(named: name)
            case .place(let id, let position): try world.placeTrain(id, at: position)
            case .unplace(let id): try world.unplaceTrain(id)
            case .reverse(let id): try world.reverseTrain(id)
            case .setRate(let id, let rate): try world.setTrainMovementRate(id, to: rate)
            case .setContinuation(let id, let nodes): try world.setTrainContinuation(id, to: nodes)
            case .routeAndCommit(let id, let destination):
                // The train tool's send: the route from where the train is
                // now, committed unchanged.
                guard let position = world.train(id: id)?.position,
                      let route = world.route(from: position, to: destination)
                else { return nil }
                do throws(GameError) {
                    try world.setTrainContinuation(id, to: route)
                } catch {
                    c.fail("GameCore refused its own route \(route) with \(error)")
                }
            case .advance(let ticks): try world.advance(ticks: ticks)
            case .setSpeed(let speed): world.setSpeed(speed)
            case .buildTrack(let tile, let raw): try world.buildTrack(at: tile, connections: TrackConnections(rawValue: raw))
            case .removeTrack(let tile): try world.removeTrack(at: tile)
            case .buildStation(let tile): try world.buildStation(named: "Stop", at: tile)
            case .query(let start, let destination):
                let before = world
                let first = world.route(from: start, to: destination)
                c.expect(world == before && world.route(from: start, to: destination) == first, "a route query changed the world or its answer")
            }
            return nil
        } catch {
            return error
        }
    }

    /// Runs one generated sequence and returns every world it passed through.
    private func run(_ c: inout PropertyCase, operations count: Int) throws -> [GameWorld] {
        let shape = c.random.element(of: NetworkShape.allCases)
        let (specs, width, height) = NetworkGenerator.specs(shape, using: &c.random)
        c.note("\(shape) \(width)x\(height), \(specs.count) tiles")
        var world = try NetworkGenerator.build(specs, width: width, height: height)
        var worlds = [world]
        for step in 0..<count {
            let operation = nextOperation(in: world, using: &c.random)
            c.note("\(step): \(operation)")
            let before = world
            if let error = apply(operation, to: &world, c) {
                c.expect(world == before, "step \(step) \(operation) was refused with \(error) but changed the world")
            }
            let problems = WorldInvariants.violations(in: world)
            c.expect(problems.isEmpty, "after step \(step) \(operation): \(problems)")
            if step % 10 == 9, let problem = WorldInvariants.roundTripProblem(of: world) {
                c.fail("after step \(step): \(problem)")
            }
            worlds.append(world)
        }
        return worlds
    }

    func testGeneratedCommandSequencesKeepEveryInvariant() throws {
        var operations = 0
        let ran = try runCampaign("stateMachine.world", cases: 60) { c in
            let worlds = try run(&c, operations: 60)
            operations += worlds.count - 1
            c.expect(WorldInvariants.roundTripProblem(of: worlds.last!) == nil, "the final world did not round-trip")
        }
        assertVolume(ran == 60 * PropertySeeds.active.count, "every case should run")
        assertVolume(operations == 60 * 60 * PropertySeeds.active.count, "every operation should run")
    }

    func testReplayingASequenceGivesTheSameWorldsEveryTime() throws {
        var digest = Digest()
        try runCampaign("stateMachine.replay", cases: 30) { c in
            var firstCase = PropertyCase(suite: c.suite, seed: c.seed, index: c.index)
            var secondCase = PropertyCase(suite: c.suite, seed: c.seed, index: c.index)
            let first = try run(&firstCase, operations: 50)
            let second = try run(&secondCase, operations: 50)
            c.expect(first == second, "the same sequence gave different worlds")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            digest.add(String(decoding: try encoder.encode(first.last!), as: UTF8.self))
        }
        // Printed so that two separate processes (with different hash seeds)
        // can be compared: the value must not change between runs.
        print("[digest] stateMachine.replay \(digest.hex)")
    }
}
