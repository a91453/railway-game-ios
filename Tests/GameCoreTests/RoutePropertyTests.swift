import GameCore
import XCTest

/// Stage L on generated networks: routes match the independent reference,
/// are shortest and first in N, E, S, W order among every shortest route
/// (checked by brute force), exist exactly when the destination is
/// reachable, can be followed by a train, and never change the world or
/// depend on build order.
final class RoutePropertyTests: XCTestCase {
    private struct State: Hashable {
        var node: GridPosition
        var heading: TrackDirection
    }

    private func makeWorld(_ c: inout PropertyCase, shapes: [NetworkShape] = NetworkShape.allCases) throws -> GameWorld {
        let shape = c.random.element(of: shapes)
        let (specs, width, height) = NetworkGenerator.specs(shape, using: &c.random)
        c.note("\(shape) \(width)x\(height), \(specs.count) tiles")
        return try NetworkGenerator.build(specs, width: width, height: height)
    }

    /// A start that is usually on the track and sometimes not, and a
    /// destination that is usually track and sometimes not.
    private func query(in world: GameWorld, using random: inout SplitMix64) -> (TrainPosition, GridPosition) {
        let start: TrainPosition
        if random.chance(1, in: 12) {
            start = random.element(of: [
                .atNode(GridPosition(x: random.below(world.map.width + 2) - 1, y: -1), heading: .north),
                .onLink(from: GridPosition(x: 0, y: 0), to: GridPosition(x: 1, y: 0), offset: random.element(of: [0, 1024, -3])),
                .onLink(from: GridPosition(x: .max, y: 0), to: GridPosition(x: .min, y: 0), offset: 5),
            ])
        } else {
            start = PositionGenerator.validPosition(in: world, using: &random) ?? .atNode(GridPosition(x: 0, y: 0), heading: .east)
        }
        let tracks = world.tracks.map(\.position)
        let destination = !tracks.isEmpty && random.chance(5, in: 6)
            ? random.element(of: tracks)
            : GridPosition(x: random.below(world.map.width + 2) - 1, y: random.below(world.map.height + 2) - 1)
        return (start, destination)
    }

    /// Where a train at `state` can go next: joined neighbours, not straight back.
    private func moves(in world: GameWorld, from state: State) -> [State] {
        world.connectedNeighbors(of: state.node).compactMap { neighbor in
            guard let way = stepDirection(from: state.node, to: neighbor), way != state.heading.opposite else { return nil }
            return State(node: neighbor, heading: way)
        }
    }

    private func startState(_ start: TrainPosition, in world: GameWorld) -> State? {
        switch start {
        case .atNode(let tile, let heading):
            return world.track(at: tile) == nil ? nil : State(node: tile, heading: heading)
        case .onLink(let from, let to, let offset):
            guard (1...1023).contains(offset), world.isConnected(from, to: to), let way = stepDirection(from: from, to: to) else { return nil }
            return State(node: to, heading: way)
        case .onEdge:
            return nil
        }
    }

    func testRoutesMatchTheReferenceAndHaveTheRightShape() throws {
        var found = 0
        var none = 0
        var digest = Digest()
        let ran = try runCampaign("route.reference", cases: 120) { c in
            let world = try makeWorld(&c)
            for _ in 0..<12 {
                let (start, destination) = query(in: world, using: &c.random)
                let route = world.route(from: start, to: destination)
                digest.add("\(start) \(destination) \(String(describing: route))")
                let reference = ReferenceRoute.route(in: world, from: start, to: destination)
                c.expect(route == reference, "\(start) to \(destination): \(String(describing: route)), reference \(String(describing: reference))")
                guard let route else {
                    none += 1
                    continue
                }
                found += 1
                // Joined, never straight back, and ending at the destination.
                guard let begin = startState(start, in: world) else { return c.fail("a route from invalid \(start)") }
                var state = begin
                for node in route {
                    guard let next = moves(in: world, from: state).first(where: { $0.node == node }) else {
                        c.fail("\(start) to \(destination): \(route) leaves \(state.node) illegally for \(node)")
                        break
                    }
                    state = next
                }
                c.expect(route.last.map { $0 == destination } ?? (begin.node == destination), "\(route) does not end at \(destination)")
            }
        }
        assertVolume(ran == 120 * PropertySeeds.active.count, "every case should run")
        assertVolume(found > 3_000, "too few routes were found")
        assertVolume(none > 200, "too few queries had no route")
        // Printed so that separate processes, with different hash seeds, can
        // be compared: the search keeps a Set, and no answer may depend on it.
        print("[digest] route.reference \(digest.hex)")
    }

    func testThereIsARouteExactlyWhenTheDestinationIsReachable() throws {
        try runCampaign("route.reachability", cases: 100) { c in
            let world = try makeWorld(&c)
            let tracks = world.tracks.map(\.position)
            guard let start = PositionGenerator.validPosition(in: world, using: &c.random), let begin = startState(start, in: world) else { return }
            // Every state the train can reach, by an independent closure.
            var reachable: Set<State> = [begin]
            var queue = [begin]
            while let state = queue.popLast() {
                for next in moves(in: world, from: state) where reachable.insert(next).inserted {
                    queue.append(next)
                }
            }
            let reachableNodes = Set(reachable.map(\.node))
            for destination in tracks {
                let route = world.route(from: start, to: destination)
                c.expect((route != nil) == reachableNodes.contains(destination), "from \(start): route to \(destination) is \(String(describing: route)) but reachable is \(reachableNodes.contains(destination))")
            }
        }
    }

    /// Brute force, independent of both the search and the reference: every
    /// route of the shortest length is listed, and the answer must be the
    /// one whose exit directions come first in N, E, S, W order.
    func testTiesGoToTheFirstDirectionsAmongAllShortestRoutes() throws {
        var ties = 0
        try runCampaign("route.tieBreak", cases: 100) { c in
            let world = try makeWorld(&c, shapes: [.grid, .ladder, .loopWithTails, .random])
            for _ in 0..<6 {
                guard let start = PositionGenerator.validPosition(in: world, using: &c.random),
                      let begin = startState(start, in: world),
                      let destination = world.tracks.map(\.position).randomElement(using: &c.random)
                else { continue }
                guard let route = world.route(from: start, to: destination), route.count <= 8 else { continue }
                // Every walk of route.count links from the start that ends at
                // the destination, as direction sequences.
                var shortest: [[Int]] = []
                var shorter = false
                func explore(_ state: State, _ directions: [Int]) {
                    if state.node == destination, directions.count < route.count, !(directions.isEmpty && route.isEmpty) {
                        shorter = true
                    }
                    if directions.count == route.count {
                        if state.node == destination { shortest.append(directions) }
                        return
                    }
                    for next in moves(in: world, from: state) {
                        explore(next, directions + [TrackDirection.allCases.firstIndex(of: next.heading)!])
                    }
                }
                explore(begin, [])
                c.expect(!shorter, "\(start) to \(destination): a shorter route than \(route) exists")
                guard let best = shortest.min(by: { $0.lexicographicallyPrecedes($1) }) else {
                    c.fail("\(start) to \(destination): \(route) is not among the walks of its length")
                    continue
                }
                if shortest.count > 1 { ties += 1 }
                var directions: [Int] = []
                var previous = begin.node
                for node in route {
                    directions.append(TrackDirection.allCases.firstIndex(of: stepDirection(from: previous, to: node)!)!)
                    previous = node
                }
                c.expect(directions == best, "\(start) to \(destination): \(route) is not the first of \(shortest.count) shortest routes")
            }
        }
        assertVolume(ties > 100, "the networks should give many equal-length alternatives")
    }

    func testARouteIsAContinuationThatTakesTheTrainToTheDestination() throws {
        var driven = 0
        try runCampaign("route.consumable", cases: 120) { c in
            var world = try makeWorld(&c)
            try world.purchaseTrain(named: "Probe")
            let id = TrainID(rawValue: 1)
            for _ in 0..<4 {
                guard let start = PositionGenerator.validPosition(in: world, using: &c.random),
                      let destination = world.tracks.map(\.position).randomElement(using: &c.random),
                      let route = world.route(from: start, to: destination)
                else { continue }
                var follower = world
                try follower.placeTrain(id, at: start)
                do throws(GameError) {
                    try follower.setTrainContinuation(id, to: route)
                } catch {
                    c.fail("\(start) to \(destination): \(route) refused with \(error)")
                    continue
                }
                try follower.setTrainMovementRate(id, to: .max)
                try follower.advance(ticks: 1)
                driven += 1
                guard case .atNode(let end, _)? = follower.train(id: id)?.position else {
                    c.fail("\(start) via \(route) ended on a link")
                    continue
                }
                c.expect(end == destination, "\(start) via \(route) ended at \(end), not \(destination)")
                c.expect(follower.train(id: id)?.movement.continuation == [], "the route was not used up")
            }
        }
        assertVolume(driven > 1_000, "too few routes were driven")
    }

    func testRouteQueriesAreReadOnlyAndRepeatable() throws {
        try runCampaign("route.readOnly", cases: 80) { c in
            var world = try makeWorld(&c)
            // Trains on the track, some moving, so there is state to disturb.
            try world.purchaseTrain(named: "A")
            if let position = PositionGenerator.validPosition(in: world, using: &c.random) {
                try world.placeTrain(TrainID(rawValue: 1), at: position)
                try world.setTrainContinuation(TrainID(rawValue: 1), to: PositionGenerator.walk(in: world, from: position, length: 4, using: &c.random))
                try world.setTrainMovementRate(TrainID(rawValue: 1), to: 300)
                try world.advance(ticks: 2)
            }
            let before = world
            let (startA, destinationA) = query(in: world, using: &c.random)
            let (startB, destinationB) = query(in: world, using: &c.random)
            let first = world.route(from: startA, to: destinationA)
            _ = world.route(from: startB, to: destinationB)
            let again = world.route(from: startA, to: destinationA)
            c.expect(first == again, "route A changed after route B: \(String(describing: first)) then \(String(describing: again))")
            c.expect(world == before, "route queries changed the world")
            // Answers from a copy are the same.
            let copy = world
            c.expect(copy.route(from: startA, to: destinationA) == first, "a copy answers differently")
        }
    }

    func testRoutesDoNotDependOnBuildOrder() throws {
        try runCampaign("route.buildOrder", cases: 60) { c in
            let shape = c.random.element(of: NetworkShape.allCases)
            let (specs, width, height) = NetworkGenerator.specs(shape, using: &c.random)
            c.note("\(shape) \(width)x\(height)")
            let tracks = specs.filter { if case .track = $0.kind { true } else { false } }
            let stations = specs.filter { if case .station = $0.kind { true } else { false } }
            let forward = try NetworkGenerator.build(tracks + stations, width: width, height: height)
            let shuffled = try NetworkGenerator.build(c.random.shuffled(tracks).reversed() + stations, width: width, height: height)
            for _ in 0..<15 {
                let (start, destination) = query(in: forward, using: &c.random)
                c.expect(
                    forward.route(from: start, to: destination) == shuffled.route(from: start, to: destination),
                    "\(start) to \(destination) depends on build order"
                )
            }
        }
    }
}

private extension Array {
    func randomElement(using random: inout SplitMix64) -> Element? {
        isEmpty ? nil : self[random.below(count)]
    }
}
