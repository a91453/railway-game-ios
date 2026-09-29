import Foundation
@testable import GameCore
import XCTest

/// Stage S4 (ARCHITECTURE decision 30): generated networks at several
/// levels (tunnels, surface, viaducts and ramps between them, with and
/// without vertical curves), stations with platforms on them and trains
/// running over them, on GameCore and on ``ReferenceWorld`` side by side.
/// After every operation the outcome, the whole state and everything
/// derived must agree: nodes with their heights, edges with their profile,
/// structure and centre line in 3D, the pose anywhere along them, their
/// alignment, tunnel portals, platforms and their levels, every train's
/// position, body, occupancy, pose and body path in 3D, the platforms each
/// whole train stands along, and routes; the world must keep every
/// invariant and survive a save exactly.
final class VerticalRailwayPropertyTests: XCTestCase {
    enum Operation {
        case buildNode(WorldCoordinate)
        case buildEdge(TrackNodeID, TrackNodeID, TrackCurve, TrackProfile, TrackStructure)
        case removeEdge(TrackEdgeID)
        case removeNode(TrackNodeID)
        case addPlatform(StationID, TrackEdgeID, Int64, Int64)
        case removePlatform(StationID, TrackEdgeID, Int64)
        case purchase
        case cars(TrainID, Int)
        case place(TrainID, TrainPosition)
        case unplace(TrainID)
        case reverse(TrainID)
        case rate(TrainID, Int64)
        case along(TrainID, [TrackTraversal])
        case advance(Int)
    }

    /// The heights lines are built at: ground level most often, then
    /// tunnels and viaducts a clearance or half of one apart.
    private static let levels: [Int64] = [0, 0, 0, -512, -256, 128, 256, 512, 1_024, -1_024]
    private static let ways: [(Int64, Int64)] = [(1, 0), (0, 1), (1, 1), (1, -1), (2, 1), (1, 2), (2, -1), (1, -2)]

    /// The structure that suits a stretch between two heights, now and then
    /// a wrong one.
    private static func structure(_ a: Int64, _ b: Int64, using random: inout SplitMix64) -> TrackStructure {
        if random.chance(1, in: 10) { return random.element(of: TrackStructure.allCases) }
        if a <= 0, b <= 0, min(a, b) < -128 { return .tunnel }
        if abs(a) <= 128, abs(b) <= 128, random.chance(3, in: 4) { return .surface }
        if a >= 0, b >= 0 { return random.chance(1, in: 3) ? .bridge : .elevated }
        return .tunnel
    }

    /// Transitions now and then: none, a share of the edge at one or both
    /// ends, or (rarely) too much.
    private static func profile(length: Int64, using random: inout SplitMix64) -> TrackProfile {
        switch random.below(6) {
        case 0: TrackProfile(startTransition: length / 4)
        case 1: TrackProfile(endTransition: length / 3)
        case 2: TrackProfile(startTransition: length / 5, endTransition: length / 5)
        case 3 where random.chance(1, in: 4): TrackProfile(startTransition: length, endTransition: 1)
        default: .uniform
        }
    }

    private struct Layout {
        var width: Int
        var height: Int
        var nodes: [WorldCoordinate]
        var edges: [(Int, Int, TrackCurve, TrackProfile, TrackStructure)]
    }

    /// Lines of collinear nodes, each at one level; ramps from a line's end
    /// on to a new node at a neighbouring level, long enough for the grade
    /// (sometimes too short); and curves between nodes of one level.
    private static func layout(using random: inout SplitMix64) -> Layout {
        let width = 10 + random.below(5)
        let height = 10 + random.below(5)
        let limitX = Int64(width) * 1024
        let limitY = Int64(height) * 1024
        var nodes: [WorldCoordinate] = []
        var edges: [(Int, Int, TrackCurve, TrackProfile, TrackStructure)] = []
        func onMap(_ x: Int64, _ y: Int64) -> Bool { x >= 0 && y >= 0 && x < limitX && y < limitY }
        func index(of point: WorldCoordinate) -> Int {
            if let existing = nodes.firstIndex(of: point) { return existing }
            nodes.append(point)
            return nodes.count - 1
        }
        for _ in 0..<(2 + random.below(3)) {
            let way = random.element(of: Self.ways)
            let level = random.element(of: Self.levels)
            let step = Int64(256 * (2 + random.below(6)))
            let start = (Int64(random.below(width * 4)) * 256, Int64(random.below(height * 4)) * 256)
            let scale = max(abs(way.0), abs(way.1))
            var previous: Int?
            var last = WorldCoordinate(x: start.0, y: start.1, z: level)
            for k in 0..<(2 + random.below(4)) {
                let x = start.0 + way.0 * step * Int64(k) / scale
                let y = start.1 + way.1 * step * Int64(k) / scale
                guard onMap(x, y) else { break }
                last = WorldCoordinate(x: x, y: y, z: level)
                let current = index(of: last)
                if let previous, previous != current {
                    edges.append((previous, current, .straight, .uniform, Self.structure(level, level, using: &random)))
                }
                previous = current
            }
            // A ramp on along the line's way to a level 128 or 256 away,
            // 25 times as long as the rise (1 in 25), or a little short.
            if let previous, random.chance(2, in: 3) {
                let rise: Int64 = random.element(of: [128, 256, -128, -256])
                let run = abs(rise) * (random.chance(1, in: 5) ? 20 : 26)
                let x = last.x + way.0 * run / scale
                let y = last.y + way.1 * run / scale
                if onMap(x, y) {
                    let top = index(of: WorldCoordinate(x: x, y: y, z: last.z + rise))
                    let length = Int64((Double(x - last.x) * Double(x - last.x) + Double(y - last.y) * Double(y - last.y)).squareRoot())
                    let profile = random.chance(1, in: 3) ? TrackProfile(startTransition: length / 8, endTransition: length / 8) : .uniform
                    edges.append((previous, top, .straight, profile, Self.structure(last.z, last.z + rise, using: &random)))
                }
            }
        }
        // Curves between two nodes at one height.
        for _ in 0..<(1 + random.below(4)) where nodes.count >= 2 {
            let a = random.below(nodes.count)
            let candidates = nodes.indices.filter { $0 != a && nodes[$0].z == nodes[a].z }
            guard !candidates.isEmpty else { continue }
            let b = random.element(of: candidates)
            let c1 = PlanPoint(x: Int64(random.below(width * 1024)), y: Int64(random.below(height * 1024)))
            let c2 = PlanPoint(x: Int64(random.below(width * 1024)), y: Int64(random.below(height * 1024)))
            edges.append((a, b, .cubic(c1, c2), .uniform, Self.structure(nodes[a].z, nodes[b].z, using: &random)))
        }
        return Layout(width: width, height: height, nodes: nodes, edges: edges)
    }

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
        func anyTrain() -> TrainID {
            trains.isEmpty || random.chance(1, in: 12) ? TrainID(rawValue: trains.count + 1 + random.below(2)) : random.element(of: trains).id
        }
        func anyNode() -> TrackNodeID { random.chance(1, in: 8) || network.nodes.isEmpty ? .node(99) : random.element(of: network.nodes).id }
        func anyEdge() -> TrackEdgeID { random.chance(1, in: 10) || network.edges.isEmpty ? .edge(99) : random.element(of: network.edges).id }
        func anyStation() -> StationID { StationID(rawValue: random.chance(1, in: 10) ? 9 : 1 + random.below(2)) }
        switch random.below(100) {
        case 0..<4:
            return .buildNode(WorldCoordinate(
                x: Int64(random.below(width * 8)) * 128, y: Int64(random.below(height * 8)) * 128, z: random.element(of: Self.levels + [4_097])
            ))
        case 4..<9:
            let from = anyNode()
            let to = anyNode()
            let heights = (network.node(from)?.position.z ?? 0, network.node(to)?.position.z ?? 0)
            let curve: TrackCurve = random.chance(1, in: 2)
                ? .straight
                : .cubic(PlanPoint(x: Int64(random.below(width * 1024)), y: Int64(random.below(height * 1024))), PlanPoint(x: Int64(random.below(width * 1024)), y: Int64(random.below(height * 1024))))
            let length: Int64 = {
                guard let a = network.node(from)?.position.plan, let b = network.node(to)?.position.plan else { return 1_024 }
                return max(abs(a.x - b.x), abs(a.y - b.y))
            }()
            return .buildEdge(from, to, curve, Self.profile(length: length, using: &random), Self.structure(heights.0, heights.1, using: &random))
        case 9..<12:
            if random.chance(1, in: 2), !trains.isEmpty, case .onEdge(let traversal, _)? = random.element(of: trains).position {
                return .removeEdge(traversal.edge)
            }
            return .removeEdge(anyEdge())
        case 12..<14:
            return .removeNode(anyNode())
        case 14..<22:
            // Often a stretch of a level edge; sometimes anything.
            let edge = anyEdge()
            let length = network.edge(edge)?.length ?? 2_048
            let start = random.int64(in: -1...length)
            let end = random.chance(1, in: 6) ? random.int64(in: -1...(length + 1)) : min(length, start + random.int64(in: 1...2_048))
            return .addPlatform(anyStation(), edge, start, end)
        case 22..<25:
            let platforms = world.stations.flatMap { station in station.trackPlatforms.map { (station.id, $0) } }
            if let (station, platform) = platforms.isEmpty || random.chance(1, in: 5) ? nil : random.element(of: platforms) {
                return .removePlatform(station, platform.edge, platform.start)
            }
            return .removePlatform(anyStation(), anyEdge(), random.int64(in: 0...2_048))
        case 25..<27:
            return trains.count < 5 ? .purchase : .cars(anyTrain(), random.below(6))
        case 27..<36:
            let id = trains.first(where: { $0.position == nil })?.id ?? anyTrain()
            if world.train(id: id)?.position == nil, random.chance(1, in: 3) { return .cars(id, 1 + random.below(4)) }
            guard let position = position(in: world, using: &random) else { return .purchase }
            return .place(id, position)
        case 36..<40:
            return .unplace(anyTrain())
        case 40..<46:
            return .reverse(anyTrain())
        case 46..<52:
            return .rate(anyTrain(), random.chance(1, in: 8) ? 0 : random.int64(in: 100...3_000))
        case 52..<75:
            let id = anyTrain()
            guard let position = world.train(id: id)?.position, case .onEdge(let traversal, _) = position else { return .along(id, []) }
            if random.chance(1, in: 2), !network.nodes.isEmpty, let route = world.route(from: position, to: random.element(of: network.nodes).id) {
                return .along(id, route)
            }
            var walk: [TrackTraversal] = []
            var arrival = traversal
            for _ in 0..<(1 + random.below(6)) {
                let options = world.transitions(after: arrival)
                guard !options.isEmpty else { break }
                let next = random.element(of: options)
                walk.append(next)
                arrival = next
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
            case .buildEdge(let from, let to, let curve, let profile, let structure):
                _ = try world.buildTrackEdge(from: from, to: to, curve: curve, profile: profile, structure: structure)
            case .removeEdge(let edge): try world.removeTrackEdge(edge)
            case .removeNode(let node): try world.removeTrackNode(node)
            case .addPlatform(let station, let edge, let start, let end): try world.addTrackPlatform(station, on: edge, from: start, to: end)
            case .removePlatform(let station, let edge, let start): try world.removeTrackPlatform(station, on: edge, from: start)
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
        case .buildEdge(let from, let to, let curve, let profile, let structure):
            return model.buildNetworkEdge(from: from, to: to, curve: curve, profile: profile, structure: structure)
        case .removeEdge(let edge): return model.removeNetworkEdge(edge)
        case .removeNode(let node): return model.removeNetworkNode(node)
        case .addPlatform(let station, let edge, let start, let end): return model.addTrackPlatform(station, on: edge, from: start, to: end)
        case .removePlatform(let station, let edge, let start): return model.removeTrackPlatform(station, on: edge, from: start)
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

    /// Every difference between the world and the model; poses at a few
    /// distances along each edge, and routes to each node of `targets`.
    private static func differences(_ world: GameWorld, _ model: ReferenceWorld, targets: [TrackNodeID], random: inout SplitMix64) -> [String] {
        var problems: [String] = []
        let nodes = Dictionary(uniqueKeysWithValues: world.network.nodes.map { ($0.id.number, $0.position) })
        if nodes != model.networkNodes { problems.append("nodes \(nodes) vs \(model.networkNodes)") }
        if world.network.edges.map(\.id.number) != model.networkEdges.keys.sorted() { problems.append("edges") }
        for edge in world.network.edges {
            guard let expected = model.networkEdges[edge.id.number] else { continue }
            let profile = TrackProfile(startTransition: expected.startTransition, endTransition: expected.endTransition)
            if edge.from.number != expected.from || edge.to.number != expected.to || edge.curve != expected.curve || edge.length != expected.length
                || edge.profile != profile || edge.structure != expected.structure {
                problems.append("edge \(edge.id.number): \(edge) vs \(expected)")
            }
            let geometry = world.trackGeometry(of: edge.id)
            let points = zip(expected.points, expected.distances).map { WorldCoordinate(x: $0.x, y: $0.y, z: ReferenceWorld.height(of: expected, at: $1)) }
            if geometry?.points != points { problems.append("edge \(edge.id.number)'s centre line in 3D") }
            let alignment = world.trackAlignment(of: edge.id)
            let reference = model.alignment(of: expected)
            if alignment?.segments != reference.segments || alignment?.steepestGrade != reference.steepest || alignment?.edge.structure != reference.structure {
                problems.append("edge \(edge.id.number)'s alignment \(String(describing: alignment?.segments)) vs \(reference)")
            }
            for direction in [TrackEdgeDirection.forward, .backward] {
                let traversal = TrackTraversal(edge: edge.id, direction: direction)
                if world.transitions(after: traversal) != model.networkTransitions(after: traversal) {
                    problems.append("transitions after \(traversal)")
                }
                for distance in [0, edge.length, random.int64(in: 0...edge.length), random.int64(in: 0...edge.length)] {
                    let pose = geometry?.location(at: distance, going: direction)
                    let expected = model.networkLocation(traversal, offset: distance)
                    if pose != expected { problems.append("pose on \(traversal) at \(distance): \(String(describing: pose)) vs \(String(describing: expected))") }
                }
            }
        }
        if world.network.nodes.map(\.id).filter(world.isTunnelPortal).map(\.number) != model.tunnelPortals { problems.append("tunnel portals") }
        if world.economy.balance.amount != model.balance { problems.append("balance \(world.economy.balance.amount) vs \(model.balance)") }
        let snapshot = world.railwaySnapshot()
        for station in world.stations {
            guard let expected = model.stations.first(where: { $0.id == station.id.rawValue }) else { continue }
            if station.trackPlatforms != expected.trackPlatforms { problems.append("station \(station.id.rawValue) platforms \(station.trackPlatforms) vs \(expected.trackPlatforms)") }
            let levels = snapshot.platforms.filter { $0.station == station.id }.map { "\($0.platform) \($0.height) \($0.structure)" }
            if levels != model.platformLevels(of: station.id).map({ "\($0.0) \($0.1) \($0.2)" }) { problems.append("station \(station.id.rawValue) platform levels") }
        }
        if world.trains.map(\.id.rawValue) != model.trains.map(\.id) { problems.append("train IDs") }
        for (train, expected) in zip(world.trains, model.trains) {
            let id = train.id.rawValue
            if train.position != expected.position { problems.append("train \(id) at \(String(describing: train.position)) vs \(String(describing: expected.position))") }
            if train.movement.rate != expected.rate || train.movement.edges.map(\.number) != expected.edges || train.movement.cursor != expected.cursor {
                problems.append("train \(id) movement")
            }
            if train.cars != expected.cars || train.trailEdges.map(\.number) != expected.trailEdges { problems.append("train \(id) body") }
            if world.occupiedResources(of: train.id) != model.networkResources(of: expected) { problems.append("train \(id) occupancy") }
            if case .onEdge(let traversal, let offset)? = train.position, world.location(of: train.position!) != model.networkLocation(traversal, offset: offset) {
                problems.append("train \(id) pose")
            }
            if world.bodyPath(of: train.id) != model.networkBodyPath(of: expected) {
                problems.append("train \(id) body path \(world.bodyPath(of: train.id)) vs \(model.networkBodyPath(of: expected))")
            }
            if world.trackPlatformsAlongWholeTrain(train.id) != model.trackPlatformsAlong(train.id) { problems.append("train \(id) platforms") }
        }
        for target in targets where model.networkNodes[target.number] != nil {
            let table = model.distancesToNode(target.number)
            for train in world.trains {
                guard let position = train.position else { continue }
                if world.route(from: position, to: target) != model.networkRoute(from: position, using: table) {
                    problems.append("train \(train.id.rawValue) route to \(target)")
                }
            }
        }
        return problems
    }

    /// A world reached by building a generated layout, two stations,
    /// trains on it and `operations` generated operations, on GameCore alone.
    static func generateWorld(_ testCase: inout PropertyCase, operations: Int) throws -> GameWorld {
        let layout = Self.layout(using: &testCase.random)
        var world = try GameWorld(
            width: layout.width, height: layout.height,
            economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 5_000)),
            clock: GameClock(speed: .normal)
        )
        for (name, x) in [("Upper", 0), ("Lower", 1)] {
            _ = try? world.buildStation(named: name, at: GridPosition(x: x, y: 0))
        }
        for point in layout.nodes { _ = Self.apply(.buildNode(point), to: &world) }
        for edge in layout.edges { _ = Self.apply(.buildEdge(.node(edge.0 + 1), .node(edge.1 + 1), edge.2, edge.3, edge.4), to: &world) }
        for id in 1...3 {
            _ = Self.apply(.purchase, to: &world)
            _ = Self.apply(.cars(TrainID(rawValue: id), 1 + testCase.random.below(4)), to: &world)
            if let position = Self.position(in: world, using: &testCase.random) {
                _ = Self.apply(.place(TrainID(rawValue: id), position), to: &world)
            }
        }
        for _ in 0..<operations {
            _ = Self.apply(Self.operation(in: world, using: &testCase.random, width: layout.width, height: layout.height), to: &world)
        }
        return world
    }

    func testGeneratedThreeDimensionalNetworksMatchTheReferenceAtEveryStep() throws {
        var digest = Digest()
        var tally: [String: Int] = [:]
        var operations = 0
        let ran = try runCampaign("vertical.differential", cases: 40) { testCase in
            let layout = Self.layout(using: &testCase.random)
            testCase.note("map \(layout.width)x\(layout.height), \(layout.nodes.count) nodes, \(layout.edges.count) edges")
            let costs = ConstructionCosts(track: 100, station: 1_000, train: 5_000)
            var world = try GameWorld(width: layout.width, height: layout.height, economy: GameEconomy(balance: 1_000_000_000, costs: costs), clock: GameClock(speed: .normal))
            var model = ReferenceWorld(width: layout.width, height: layout.height, balance: 1_000_000_000, costs: costs, minutes: 0, speed: .normal)
            // Two stations on the grid to hang platforms on.
            for (name, x) in [("Upper", 0), ("Lower", 1)] {
                _ = try? world.buildStation(named: name, at: GridPosition(x: x, y: 0))
                _ = model.buildStation(named: name, at: GridPosition(x: x, y: 0))
            }
            var steps: [Operation] = layout.nodes.map { .buildNode($0) }
            steps += layout.edges.map { .buildEdge(.node($0.0 + 1), .node($0.1 + 1), $0.2, $0.3, $0.4) }
            let trainCount = 2 + testCase.random.below(3)
            steps += (0..<trainCount).map { _ in .purchase }
            steps += (1...trainCount).map { .cars(TrainID(rawValue: $0), 1 + testCase.random.below(4)) }
            let setup = steps.count
            for step in 0..<(setup + 2 * trainCount + 60) {
                let operation: Operation
                if step < setup {
                    operation = steps[step]
                } else if step < setup + 2 * trainCount {
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
                case .buildEdge(_, _, _, let profile, let structure): profile == .uniform ? "edge \(structure)" : "eased edge"
                case .removeEdge: "remove edge"
                case .removeNode: "remove node"
                case .addPlatform: "platform"
                case .removePlatform: "remove platform"
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
                if case .advance = operation {
                    for (old, new) in zip(before.trains, world.trains) where old.position != new.position {
                        tally["moved", default: 0] += 1
                        if let position = new.position, let z = world.location(of: position)?.position.z, z != 0 { tally["moved off the ground", default: 0] += 1 }
                    }
                }
                for train in world.trains where train.position != nil {
                    let heights = Set(world.bodyPath(of: train.id).map(\.z))
                    if heights.count > 1 { tally["bodies over several heights", default: 0] += 1 }
                    if !world.trackPlatformsAlongWholeTrain(train.id).isEmpty { tally["whole trains along platforms", default: 0] += 1 }
                }
                let nodes = world.network.nodes.map(\.id)
                let targets = nodes.isEmpty || step % 10 == 0 ? nodes : (0..<2).map { _ in testCase.random.element(of: nodes) }
                let problems = Self.differences(world, model, targets: targets, random: &testCase.random) + WorldInvariants.violations(in: world)
                guard problems.isEmpty else { return testCase.fail(problems.joined(separator: "\n")) }
                if let problem = WorldInvariants.roundTripProblem(of: world) { return testCase.fail(problem) }
            }
            tally["portals at the end", default: 0] += world.network.nodes.filter { world.isTunnelPortal($0.id) }.count
            tally["platforms at the end", default: 0] += world.stations.reduce(0) { $0 + $1.trackPlatforms.count }
            tally["levels at the end", default: 0] += Set(world.network.nodes.map(\.position.z)).count
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            digest.add(String(decoding: try encoder.encode(world), as: UTF8.self))
        }
        let summary = tally.keys.sorted().map { "\($0) \(tally[$0]!)" }.joined(separator: ", ")
        print("[digest] vertical.differential \(digest.hex) (\(summary))")
        print("[volume] vertical.differential \(ran) cases, \(operations) operations")
        assertVolume(ran == 40 * PropertySeeds.active.count, "every case ran")
        assertVolume(tally["moved off the ground", default: 0] > 50, "trains run off the ground")
        assertVolume(tally["bodies over several heights", default: 0] > 50, "long trains span heights")
        assertVolume(tally["trackConflict edge surface", default: 0] + tally["trackConflict edge elevated", default: 0] > 20, "crossings are refused")
        assertVolume(tally["trackTooSteep eased edge", default: 0] + tally["trackTooSteep edge elevated", default: 0] + tally["trackTooSteep edge surface", default: 0] > 10, "steep ramps are refused")
        assertVolume(tally["invalidTrackStructure edge surface", default: 0] + tally["invalidTrackStructure edge tunnel", default: 0] > 10, "structures are checked")
        assertVolume(tally["ok platform", default: 0] > 50, "platforms are added")
        assertVolume(tally["invalidPlatform platform", default: 0] > 50, "bad platforms are refused")
        assertVolume(tally["trackEdgeHasPlatform remove edge", default: 0] > 5, "edges under platforms stay")
        assertVolume(tally["portals at the end", default: 0] > 10, "tunnels have portals")
        assertVolume(tally["whole trains along platforms", default: 0] > 5, "trains stand along platforms")
    }
}
