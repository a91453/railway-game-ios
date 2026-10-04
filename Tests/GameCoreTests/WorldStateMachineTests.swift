import Foundation
import GameCore
import XCTest

/// Generated sequences of commands against one world: construction, trains,
/// routes, rates and time, mostly sensible and sometimes invalid. After every
/// step the world keeps its invariants; a refused command changes nothing; a
/// route query changes nothing and is always accepted as a path; the world
/// survives saving; and the same sequence always gives the same worlds. On
/// the track network (Stage F3b): its nodes and edges, stations at points
/// with platforms, positions along edges and paths.
final class WorldStateMachineTests: XCTestCase {
    enum Operation: CustomStringConvertible {
        case purchase(String)
        case place(TrainID, TrainPosition)
        case unplace(TrainID)
        case reverse(TrainID)
        case setRate(TrainID, Int64)
        case setPath(TrainID, [TrackTraversal], Int64?)
        case routeAndCommit(TrainID, TrackNodeID)
        case advance(Int)
        case setSpeed(GameSpeed)
        case buildNode(WorldCoordinate)
        case buildEdge(TrackNodeID, TrackNodeID, TrackCurve)
        case removeEdge(TrackEdgeID)
        case buildStation(PlanPoint)
        case addPlatform(StationID, TrackEdgeID, Int64, Int64)
        case query(TrainPosition, TrackNodeID)

        var description: String {
            switch self {
            case .purchase(let name): "purchase(\"\(name)\")"
            case .place(let id, let position): "place(\(id.rawValue), \(position))"
            case .unplace(let id): "unplace(\(id.rawValue))"
            case .reverse(let id): "reverse(\(id.rawValue))"
            case .setRate(let id, let rate): "setRate(\(id.rawValue), \(rate))"
            case .setPath(let id, let path, let end): "setPath(\(id.rawValue), \(path), \(String(describing: end)))"
            case .routeAndCommit(let id, let node): "routeAndCommit(\(id.rawValue), \(node))"
            case .advance(let ticks): "advance(\(ticks))"
            case .setSpeed(let speed): "setSpeed(\(speed))"
            case .buildNode(let point): "buildNode(\(point))"
            case .buildEdge(let from, let to, let curve): "buildEdge(\(from), \(to), \(curve))"
            case .removeEdge(let edge): "removeEdge(\(edge))"
            case .buildStation(let point): "buildStation(\(point))"
            case .addPlatform(let id, let edge, let start, let end): "addPlatform(\(id.rawValue), \(edge), \(start), \(end))"
            case .query(let start, let node): "route(\(start), \(node))"
            }
        }
    }

    /// A point on a 1024-unit lattice, or now and then one just off the
    /// world.
    private func randomPoint(in world: GameWorld, using random: inout SplitMix64) -> PlanPoint {
        let (columns, rows) = (Int(world.bounds.width / 1_024), Int(world.bounds.height / 1_024))
        return PlanPoint(x: Int64(random.below(columns + 2) - 1) * 1_024 + 512, y: Int64(random.below(rows + 2) - 1) * 1_024 + 512)
    }

    /// A node of the network, now and then one that does not exist.
    private func randomNode(in world: GameWorld, using random: inout SplitMix64) -> TrackNodeID {
        world.network.nodes.isEmpty || random.chance(1, in: 10) ? .node(world.network.nodes.count + 5) : random.element(of: world.network.nodes).id
    }

    /// A position along an edge, either way, anywhere on it.
    private func validPosition(in world: GameWorld, using random: inout SplitMix64) -> TrainPosition? {
        guard let edge = world.network.edges.isEmpty ? nil : random.element(of: world.network.edges) else { return nil }
        let offset = random.chance(1, in: 2) ? random.element(of: [0, edge.length]) : random.int64(in: 0...edge.length)
        return .onEdge(TrackTraversal(edge: edge.id, direction: random.chance(1, in: 2) ? .forward : .backward), offset: offset)
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
            if random.chance(3, in: 4), let valid = validPosition(in: world, using: &random) {
                return .place(id, valid)
            }
            // Off its edge, or on an edge that does not exist (no grid
            // position: nothing the grid's removal in Stage F3c takes away).
            switch random.below(3) {
            case 0:
                guard let edge = world.network.edges.isEmpty ? nil : random.element(of: world.network.edges) else { return .place(id, .onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 0)) }
                return .place(id, .onEdge(TrackTraversal(edge: edge.id, direction: .forward), offset: random.element(of: [-1, edge.length + 1])))
            case 1:
                return .place(id, .onEdge(TrackTraversal(edge: .edge(world.network.edges.count + 9), direction: .backward), offset: 0))
            default:
                return .place(id, .onEdge(TrackTraversal(edge: .edge(0), direction: .forward), offset: 1))
            }
        case 18..<22:
            return .unplace(id)
        case 22..<27:
            return .reverse(id)
        case 27..<37:
            let rate: Int64 = random.chance(1, in: 20) ? -random.int64(in: 1...5) : random.element(of: [0, 1, 511, 1024, 3_000, random.int64(in: 0...4_096), .max])
            return .setRate(id, rate)
        case 37..<47:
            // A walk by the transitions, stopping somewhere along its last
            // edge or at its end; now and then broken by a step that does
            // not follow.
            guard case .onEdge(let traversal, _)? = position else { return .setPath(id, [], nil) }
            var walk: [TrackTraversal] = []
            var last = traversal
            for _ in 0..<random.below(8) {
                let options = world.transitions(after: last)
                guard !options.isEmpty else { break }
                last = random.element(of: options)
                walk.append(last)
            }
            if random.chance(1, in: 4), let edge = world.network.edges.isEmpty ? nil : random.element(of: world.network.edges) {
                walk.insert(TrackTraversal(edge: edge.id, direction: random.chance(1, in: 2) ? .forward : .backward), at: random.below(walk.count + 1))
            }
            let length = world.trackEdge(last.edge)?.length ?? 0
            return .setPath(id, walk, random.chance(1, in: 2) ? nil : random.int64(in: -1...(length + 1)))
        case 47..<60:
            return .routeAndCommit(id, randomNode(in: world, using: &random))
        case 60..<80:
            return .advance(random.below(9))
        case 80..<83:
            return .setSpeed(random.element(of: GameSpeed.allCases))
        case 83..<90:
            if random.chance(1, in: 2) {
                let point = randomPoint(in: world, using: &random)
                return .buildNode(WorldCoordinate(x: point.x, y: point.y))
            }
            let from = randomNode(in: world, using: &random)
            let to = randomNode(in: world, using: &random)
            return .buildEdge(from, to, random.chance(1, in: 2) ? .straight : .cubic(randomPoint(in: world, using: &random), randomPoint(in: world, using: &random)))
        case 90..<95:
            // Often the edge under a train, which must be refused.
            if case .onEdge(let traversal, _)? = position, random.chance(1, in: 3) {
                return .removeEdge(traversal.edge)
            }
            return .removeEdge(world.network.edges.isEmpty || random.chance(1, in: 8) ? .edge(world.network.edges.count + 9) : random.element(of: world.network.edges).id)
        case 95:
            return .buildStation(randomPoint(in: world, using: &random))
        case 96:
            guard let station = world.stations.isEmpty ? nil : random.element(of: world.stations),
                  let edge = world.network.edges.isEmpty ? nil : random.element(of: world.network.edges)
            else { return .buildStation(randomPoint(in: world, using: &random)) }
            let start = random.int64(in: -1...edge.length)
            return .addPlatform(station.id, edge.id, start, start + random.int64(in: 0...2_048))
        default:
            let start = validPosition(in: world, using: &random) ?? .onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 0)
            return .query(start, randomNode(in: world, using: &random))
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
            case .setPath(let id, let path, let end): try world.setTrainContinuation(id, along: path, stoppingAt: end)
            case .routeAndCommit(let id, let node):
                // The train tool's send: the route from where the train is
                // now, committed unchanged.
                guard let position = world.train(id: id)?.position, let route = world.route(from: position, to: node) else { return nil }
                do throws(GameError) {
                    try world.setTrainContinuation(id, along: route)
                } catch {
                    c.fail("GameCore refused its own route \(route) with \(error)")
                }
            case .advance(let ticks): try world.advance(ticks: ticks)
            case .setSpeed(let speed): world.setSpeed(speed)
            case .buildNode(let point): try world.buildTrackNode(at: point)
            case .buildEdge(let from, let to, let curve): try world.buildTrackEdge(from: from, to: to, curve: curve)
            case .removeEdge(let edge): try world.removeTrackEdge(edge)
            case .buildStation(let point): try world.buildStation(named: "Stop", at: point)
            case .addPlatform(let id, let edge, let start, let end): try world.addTrackPlatform(id, on: edge, from: start, to: end)
            case .query(let start, let node):
                let before = world
                let first = world.route(from: start, to: node)
                c.expect(world == before && world.route(from: start, to: node) == first, "a route query changed the world or its answer")
            }
            return nil
        } catch {
            return error
        }
    }

    /// Runs one generated sequence and returns every world it passed through.
    private func run(_ c: inout PropertyCase, operations count: Int) throws -> [GameWorld] {
        var setup = KernelDifferentialTests.makeNetworkSetup(using: &c.random)
        setup.extraBalance = 1_000_000_000
        setup.seconds = 0
        setup.speed = .normal
        c.note(setup.summary)
        var world = try setup.build().0
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
