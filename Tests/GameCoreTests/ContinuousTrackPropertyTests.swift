import Foundation
@testable import GameCore
import XCTest

/// Stage S3 (ARCHITECTURE decision 29): generated track networks and train
/// operations run on GameCore and on ``ReferenceWorld`` side by side. After
/// every operation the outcome, the whole state and everything derived must
/// agree: the network (every node, every edge's length and sampled centre
/// line, every traversal's transitions), every train (position, movement,
/// cars, body), the track each train occupies, where each train is in the
/// world, and routes to every node; the world must keep every invariant and
/// survive a save exactly.
final class ContinuousTrackPropertyTests: XCTestCase {
    enum Operation {
        case buildNode(WorldCoordinate)
        case buildEdge(TrackNodeID, TrackNodeID, TrackCurve)
        case removeEdge(TrackEdgeID)
        case removeNode(TrackNodeID)
        case purchase
        case cars(TrainID, Int)
        case place(TrainID, TrainPosition)
        case unplace(TrainID)
        case reverse(TrainID)
        case rate(TrainID, Int64)
        case along(TrainID, [TrackTraversal])
        case advance(Int)
    }

    /// Directions with small components, so points along them stay on the
    /// integer lattice.
    private static let ways: [(Int64, Int64)] = [(1, 0), (0, 1), (1, 1), (1, -1), (2, 1), (1, 2), (2, -1), (1, -2), (3, 1), (1, 3)]

    private struct Layout {
        var width: Int
        var height: Int
        var nodes: [WorldCoordinate]
        /// Each node's way, for handles that leave it smoothly.
        var ways: [(Int64, Int64)]
        var edges: [(Int, Int, TrackCurve)]
    }

    /// Lines of collinear nodes joined by straight edges, curves between
    /// lines with handles along each line's way (so they often join), and a
    /// few edges with handles anywhere.
    private static func layout(using random: inout SplitMix64) -> Layout {
        let width = 8 + random.below(5)
        let height = 8 + random.below(5)
        let limitX = Int64(width) * 1024
        let limitY = Int64(height) * 1024
        var nodes: [WorldCoordinate] = []
        var ways: [(Int64, Int64)] = []
        var edges: [(Int, Int, TrackCurve)] = []
        func onMap(_ x: Int64, _ y: Int64) -> Bool { x >= 0 && y >= 0 && x < limitX && y < limitY }
        for _ in 0..<(2 + random.below(3)) {
            let way = random.element(of: Self.ways)
            let step = Int64(128 * (2 + random.below(8)))
            let start = (Int64(random.below(width * 4)) * 256, Int64(random.below(height * 4)) * 256)
            var previous: Int?
            for k in 0..<(2 + random.below(4)) {
                let x = start.0 + way.0 * step * Int64(k) / max(abs(way.0), abs(way.1))
                let y = start.1 + way.1 * step * Int64(k) / max(abs(way.0), abs(way.1))
                guard onMap(x, y) else { break }
                let point = WorldCoordinate(x: x, y: y)
                let index: Int
                if let existing = nodes.firstIndex(of: point) {
                    index = existing
                } else {
                    nodes.append(point)
                    ways.append(way)
                    index = nodes.count - 1
                }
                if let previous, previous != index { edges.append((previous, index, .straight)) }
                previous = index
            }
        }
        for _ in 0..<(1 + random.below(5)) where nodes.count >= 2 {
            let a = random.below(nodes.count)
            let b = random.below(nodes.count)
            guard a != b else { continue }
            let (p, q) = (nodes[a].plan, nodes[b].plan)
            if random.chance(1, in: 4) {
                // Handles anywhere over the map.
                let c1 = PlanPoint(x: Int64(random.below(width * 1024)), y: Int64(random.below(height * 1024)))
                let c2 = PlanPoint(x: Int64(random.below(width * 1024)), y: Int64(random.below(height * 1024)))
                edges.append((a, b, .cubic(c1, c2)))
                continue
            }
            // Handles along each node's way, pointing toward the other end.
            func handle(from point: PlanPoint, way: (Int64, Int64), toward target: PlanPoint) -> PlanPoint {
                let sign: Int64 = way.0 * (target.x - point.x) + way.1 * (target.y - point.y) >= 0 ? 1 : -1
                let reach = Int64(64 * (1 + random.below(12)))
                return PlanPoint(x: point.x + sign * way.0 * reach, y: point.y + sign * way.1 * reach)
            }
            edges.append((a, b, .cubic(handle(from: p, way: ways[a], toward: q), handle(from: q, way: ways[b], toward: p))))
        }
        return Layout(width: width, height: height, nodes: nodes, ways: ways, edges: edges)
    }

    /// A position somewhere on the network: often an end of an edge, a
    /// middle, or anywhere along it.
    private static func position(in world: GameWorld, using random: inout SplitMix64) -> TrainPosition? {
        guard !world.network.edges.isEmpty else { return nil }
        let edge = random.element(of: world.network.edges)
        let offset: Int64 = switch random.below(4) {
        case 0: 0
        case 1: edge.length
        case 2: edge.length / 2
        default: random.int64(in: 0...edge.length)
        }
        return .onEdge(TrackTraversal(edge: edge.id, direction: random.chance(1, in: 2) ? .forward : .backward), offset: offset)
    }

    static func operation(in world: GameWorld, using random: inout SplitMix64, width: Int, height: Int) -> Operation {
        let network = world.network
        let trains = world.trains
        // Mostly a train that exists; now and then one that does not.
        func anyTrain() -> TrainID {
            trains.isEmpty || random.chance(1, in: 12) ? TrainID(rawValue: trains.count + 1 + random.below(2)) : random.element(of: trains).id
        }
        func anyNode() -> TrackNodeID { random.chance(1, in: 8) || network.nodes.isEmpty ? .node(99) : random.element(of: network.nodes).id }
        switch random.below(100) {
        case 0..<3:
            return .buildNode(WorldCoordinate(x: Int64(random.below(width * 8)) * 128, y: Int64(random.below(height * 8)) * 128))
        case 3..<6:
            let from = anyNode()
            let to = anyNode()
            if random.chance(1, in: 2) { return .buildEdge(from, to, .straight) }
            let c1 = PlanPoint(x: Int64(random.below(width * 1024)), y: Int64(random.below(height * 1024)))
            let c2 = PlanPoint(x: Int64(random.below(width * 1024)), y: Int64(random.below(height * 1024)))
            return .buildEdge(from, to, .cubic(c1, c2))
        case 6..<10:
            // Often an edge a train is on, which must be refused.
            if random.chance(1, in: 2), !trains.isEmpty, case .onEdge(let traversal, _)? = random.element(of: trains).position {
                return .removeEdge(traversal.edge)
            }
            return .removeEdge(network.edges.isEmpty ? .edge(1) : random.element(of: network.edges).id)
        case 10..<12:
            return .removeNode(anyNode())
        case 12..<14:
            return trains.count < 5 ? .purchase : .cars(anyTrain(), random.below(6))
        case 14..<26:
            let id = trains.first(where: { $0.position == nil })?.id ?? anyTrain()
            if world.train(id: id)?.position == nil, random.chance(1, in: 3) { return .cars(id, 1 + random.below(4)) }
            guard let position = position(in: world, using: &random) else { return .purchase }
            return .place(id, position)
        case 26..<31:
            return .unplace(anyTrain())
        case 31..<39:
            return .reverse(anyTrain())
        case 39..<47:
            return .rate(anyTrain(), random.chance(1, in: 8) ? 0 : random.int64(in: 100...3_000))
        case 47..<75:
            let id = anyTrain()
            guard let position = world.train(id: id)?.position, case .onEdge(let traversal, _) = position else { return .along(id, []) }
            if random.chance(1, in: 2), !network.nodes.isEmpty, let route = world.route(from: position, to: random.element(of: network.nodes).id) {
                return .along(id, route)
            }
            // A walk by the transitions, sometimes with a wrong step.
            var walk: [TrackTraversal] = []
            var arrival = traversal
            for _ in 0..<(1 + random.below(6)) {
                let options = world.transitions(after: arrival)
                guard !options.isEmpty else { break }
                let next = random.element(of: options)
                walk.append(next)
                arrival = next
            }
            if random.chance(1, in: 6), !network.edges.isEmpty {
                walk.append(TrackTraversal(edge: random.element(of: network.edges).id, direction: .forward))
            }
            return .along(id, walk)
        default:
            return .advance(1 + random.below(4))
        }
    }

    static func apply(_ operation: Operation, to world: inout GameWorld) -> GameError? {
        do throws(GameError) {
            switch operation {
            case .buildNode(let point): _ = try world.buildTrackNode(at: point)
            case .buildEdge(let from, let to, let curve): _ = try world.buildTrackEdge(from: from, to: to, curve: curve)
            case .removeEdge(let edge): try world.removeTrackEdge(edge)
            case .removeNode(let node): try world.removeTrackNode(node)
            case .purchase: _ = try world.purchaseTrain(named: "T")
            case .cars(let id, let cars): try world.setTrainCars(id, to: cars)
            case .place(let id, let position): try world.placeTrain(id, at: position)
            case .unplace(let id): try world.unplaceTrain(id)
            case .reverse(let id): try world.reverseTrain(id)
            case .rate(let id, let rate): try world.setTrainMovementRate(id, to: rate)
            case .along(let id, let path): try world.setTrainContinuation(id, along: path)
            case .advance(let ticks): try world.advance(ticks: ticks)
            }
            return nil
        } catch {
            return error
        }
    }

    private static func apply(_ operation: Operation, to model: inout ReferenceWorld) -> GameError? {
        switch operation {
        case .buildNode(let point): return model.buildNetworkNode(at: point)
        case .buildEdge(let from, let to, let curve): return model.buildNetworkEdge(from: from, to: to, curve: curve)
        case .removeEdge(let edge): return model.removeNetworkEdge(edge)
        case .removeNode(let node): return model.removeNetworkNode(node)
        case .purchase: return model.purchaseTrain(named: "T")
        case .cars(let id, let cars): return model.setCars(id, cars)
        case .place(let id, let position): return model.placeTrain(id, at: position)
        case .unplace(let id): return model.unplaceTrain(id)
        case .reverse(let id): return model.reverseTrain(id)
        case .rate(let id, let rate): return model.setRate(id, rate)
        case .along(let id, let path): return model.setContinuation(id, along: path)
        case .advance(let ticks): return model.advance(ticks: ticks)
        }
    }

    /// Every difference between the world and the model, state and derived;
    /// routes from every train to each node of `targets`.
    private static func differences(_ world: GameWorld, _ model: ReferenceWorld, targets: [TrackNodeID]) -> [String] {
        var problems: [String] = []
        let nodes = Dictionary(uniqueKeysWithValues: world.network.nodes.map { ($0.id.number, $0.position) })
        if nodes != model.networkNodes { problems.append("nodes \(nodes) vs \(model.networkNodes)") }
        let edgeNumbers = world.network.edges.map(\.id.number)
        if edgeNumbers != model.networkEdges.keys.sorted() { problems.append("edges \(edgeNumbers) vs \(model.networkEdges.keys.sorted())") }
        for edge in world.network.edges {
            guard let expected = model.networkEdges[edge.id.number] else { continue }
            if edge.from.number != expected.from || edge.to.number != expected.to || edge.curve != expected.curve || edge.length != expected.length {
                problems.append("edge \(edge.id.number): \(edge) vs \(expected)")
            }
            if world.trackGeometry(of: edge.id)?.points.map(\.plan) != expected.points {
                problems.append("edge \(edge.id.number)'s centre line")
            }
            for direction in [TrackEdgeDirection.forward, .backward] {
                let traversal = TrackTraversal(edge: edge.id, direction: direction)
                if world.transitions(after: traversal) != model.networkTransitions(after: traversal) {
                    problems.append("transitions after \(traversal): \(world.transitions(after: traversal)) vs \(model.networkTransitions(after: traversal))")
                }
            }
        }
        if world.economy.balance.amount != model.balance { problems.append("balance \(world.economy.balance.amount) vs \(model.balance)") }
        if world.trains.map(\.id.rawValue) != model.trains.map(\.id) { problems.append("train IDs") }
        for (train, expected) in zip(world.trains, model.trains) {
            let id = train.id.rawValue
            if train.position != expected.position { problems.append("train \(id) at \(String(describing: train.position)) vs \(String(describing: expected.position))") }
            if train.movement.rate != expected.rate || train.movement.edges.map(\.number) != expected.edges || train.movement.cursor != expected.cursor {
                problems.append("train \(id) movement \(train.movement) vs \(expected.rate) \(expected.edges) \(expected.cursor)")
            }
            if train.cars != expected.cars || train.trailEdges.map(\.number) != expected.trailEdges {
                problems.append("train \(id) body \(train.cars) \(train.trailEdges) vs \(expected.cars) \(expected.trailEdges)")
            }
            if world.occupiedResources(of: train.id) != model.networkResources(of: expected) {
                problems.append("train \(id) occupies \(world.occupiedResources(of: train.id)) vs \(model.networkResources(of: expected))")
            }
            if case .onEdge(let traversal, let offset)? = train.position, world.location(of: train.position!) != model.networkLocation(traversal, offset: offset) {
                problems.append("train \(id) location")
            }
        }
        for target in targets where model.networkNodes[target.number] != nil {
            let table = model.distancesToNode(target.number)
            for train in world.trains {
                guard let position = train.position else { continue }
                let route = world.route(from: position, to: target)
                let expected = model.networkRoute(from: position, using: table)
                if route != expected {
                    problems.append("train \(train.id.rawValue) route to \(target): \(String(describing: route)) vs \(String(describing: expected))")
                }
            }
        }
        return problems
    }

    /// A world reached by building a generated layout, putting trains on it
    /// and `operations` generated operations, on GameCore alone.
    static func generateWorld(_ testCase: inout PropertyCase, operations: Int) throws -> GameWorld {
        let layout = Self.layout(using: &testCase.random)
        var world = try GameWorld(
            bounds: WorldBounds(width: Int64(layout.width) * 1_024, height: Int64(layout.height) * 1_024),
            economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 5_000)),
            clock: GameClock(speed: .normal)
        )
        for point in layout.nodes { _ = Self.apply(.buildNode(point), to: &world) }
        for edge in layout.edges { _ = Self.apply(.buildEdge(.node(edge.0 + 1), .node(edge.1 + 1), edge.2), to: &world) }
        for id in 1...3 {
            _ = Self.apply(.purchase, to: &world)
            _ = Self.apply(.cars(TrainID(rawValue: id), 1 + testCase.random.below(4)), to: &world)
            if let position = Self.position(in: world, using: &testCase.random) {
                _ = Self.apply(.place(TrainID(rawValue: id), position), to: &world)
            }
            _ = Self.apply(.rate(TrainID(rawValue: id), testCase.random.int64(in: 100...2_000)), to: &world)
        }
        for _ in 0..<operations {
            _ = Self.apply(Self.operation(in: world, using: &testCase.random, width: layout.width, height: layout.height), to: &world)
        }
        return world
    }

    func testGeneratedNetworksMatchTheReferenceAtEveryStep() throws {
        var digest = Digest()
        var tally: [String: Int] = [:]
        var operations = 0
        let ran = try runCampaign("network.differential", cases: 48) { testCase in
            let layout = Self.layout(using: &testCase.random)
            testCase.note("map \(layout.width)x\(layout.height), \(layout.nodes.count) nodes, \(layout.edges.count) edges")
            let costs = ConstructionCosts(track: 100, station: 1_000, train: 5_000)
            var world = try GameWorld(bounds: WorldBounds(width: Int64(layout.width) * 1_024, height: Int64(layout.height) * 1_024), economy: GameEconomy(balance: 1_000_000_000, costs: costs), clock: GameClock(speed: .normal))
            var model = ReferenceWorld(width: Int64(layout.width) * 1_024, height: Int64(layout.height) * 1_024, balance: 1_000_000_000, costs: costs, minutes: 0, speed: .normal)
            var steps: [Operation] = layout.nodes.map { .buildNode($0) }
            steps += layout.edges.map { .buildEdge(.node($0.0 + 1), .node($0.1 + 1), $0.2) }
            let trainCount = 2 + testCase.random.below(3)
            steps += (0..<trainCount).map { _ in .purchase }
            steps += (1...trainCount).map { .cars(TrainID(rawValue: $0), 1 + testCase.random.below(4)) }
            let setup = steps.count
            for step in 0..<(setup + 2 * trainCount + 50) {
                let operation: Operation
                if step < setup {
                    operation = steps[step]
                } else if step < setup + 2 * trainCount {
                    // Put each train on the network and set it going.
                    let id = TrainID(rawValue: 1 + (step - setup) / 2)
                    if (step - setup) % 2 == 0, let position = Self.position(in: world, using: &testCase.random) {
                        operation = .place(id, position)
                    } else {
                        operation = .rate(id, testCase.random.int64(in: 100...2_000))
                    }
                } else {
                    operation = Self.operation(in: world, using: &testCase.random, width: layout.width, height: layout.height)
                }
                testCase.note("\(step): \(operation)")
                let before = world
                let outcome = Self.apply(operation, to: &world)
                let expected = Self.apply(operation, to: &model)
                operations += 1
                guard outcome == expected else {
                    return testCase.fail("\(operation): \(String(describing: outcome)) vs reference \(String(describing: expected))")
                }
                if outcome != nil, world != before { return testCase.fail("refused \(operation) but changed the world") }
                let name: String = switch operation {
                case .buildNode: "node"
                case .buildEdge: "edge"
                case .removeEdge: "remove edge"
                case .removeNode: "remove node"
                case .purchase: "purchase"
                case .cars: "cars"
                case .place: "place"
                case .unplace: "unplace"
                case .reverse: "reverse"
                case .rate: "rate"
                case .along: "continuation"
                case .advance: "advance"
                }
                tally["\(outcome.map { "\($0)".components(separatedBy: "(")[0] } ?? "ok") \(name)", default: 0] += 1
                if case .reverse(let id) = operation, outcome == nil, (before.train(id: id)?.cars ?? 1) > 1 {
                    tally["turned with a body", default: 0] += 1
                }
                if case .advance = operation {
                    for (old, new) in zip(before.trains, world.trains) where old.position != new.position {
                        tally["moved", default: 0] += 1
                        if case .onEdge(let a, _)? = old.position, case .onEdge(let b, _)? = new.position, a.edge != b.edge { tally["changed edge", default: 0] += 1 }
                    }
                }
                // Routes to a few nodes each step, all of them now and then.
                let nodes = world.network.nodes.map(\.id)
                let targets = nodes.isEmpty || step % 10 == 0 ? nodes : (0..<3).map { _ in testCase.random.element(of: nodes) }
                let problems = Self.differences(world, model, targets: targets) + WorldInvariants.violations(in: world)
                guard problems.isEmpty else { return testCase.fail(problems.joined(separator: "\n")) }
                if let problem = WorldInvariants.roundTripProblem(of: world) { return testCase.fail(problem) }
            }
            tally["trains with bodies at the end", default: 0] += world.trains.filter { !$0.trailEdges.isEmpty }.count
            tally["joined ends at the end", default: 0] += world.network.nodes.reduce(0) { $0 + $1.ends.filter { !$0.exits.isEmpty }.count }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            digest.add(String(decoding: try encoder.encode(world), as: UTF8.self))
        }
        let summary = tally.keys.sorted().map { "\($0) \(tally[$0]!)" }.joined(separator: ", ")
        print("[digest] network.differential \(digest.hex) (\(summary))")
        print("[volume] network.differential \(ran) cases, \(operations) operations")
        assertVolume(ran == 48 * PropertySeeds.active.count, "every case ran")
        assertVolume(tally["moved", default: 0] > 200, "trains move on the network")
        assertVolume(tally["changed edge", default: 0] > 50, "trains pass from edge to edge")
        assertVolume(tally["turned with a body", default: 0] > 20, "long trains turn round")
        assertVolume(tally["trains with bodies at the end", default: 0] > 20, "long trains are left on the network")
        assertVolume(tally["joined ends at the end", default: 0] > 200, "networks have joined ends")
        assertVolume(tally["ok continuation", default: 0] > 200, "trains are given paths")
        assertVolume(tally["trackEdgeInUse remove edge", default: 0] > 20, "edges under trains are refused")
    }
}
