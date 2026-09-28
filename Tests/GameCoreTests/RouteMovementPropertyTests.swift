import GameCore
import XCTest

/// Stage L feeding Stage K: a route committed as a continuation is followed
/// link by link, tick by tick, with exactly the distance each tick allows,
/// until the train stands at the destination. And a route that has gone
/// stale can only ever be refused, never produce an impossible train.
final class RouteMovementPropertyTests: XCTestCase {
    private let id = TrainID(rawValue: 1)

    private func makeWorld(_ c: inout PropertyCase) throws -> GameWorld {
        let shape = c.random.element(of: NetworkShape.allCases)
        let (specs, width, height) = NetworkGenerator.specs(shape, using: &c.random)
        c.note("\(shape) \(width)x\(height), \(specs.count) tiles")
        var world = try NetworkGenerator.build(specs, width: width, height: height)
        try world.purchaseTrain(named: "Probe")
        return world
    }

    /// How far along the committed route a train is, in units from where it
    /// started: the rest of the first link, then 1024 per route entry. `nil`
    /// if the position is not on the route at all.
    private func progress(
        of position: TrainPosition,
        entered: Int,
        start: TrainPosition,
        route: [GridPosition]
    ) -> Int64? {
        let (firstNode, _) = ahead(of: start)
        let startOffset: Int64 = { if case .onLink(_, _, let offset) = start { return offset } else { return TrainPosition.linkLength } }()
        let toFirstNode = TrainPosition.linkLength - startOffset
        let nodes = [firstNode] + route
        switch position {
        case .atNode(let tile, _):
            // At the node reached after `entered` entries.
            guard entered < nodes.count, nodes[entered] == tile else { return nil }
            return toFirstNode + TrainPosition.linkLength * Int64(entered)
        case .onLink(let from, let to, let offset):
            if entered == 0 {
                // Still on the link it started on.
                guard case .onLink(let startFrom, let startTo, _) = start, startFrom == from, startTo == to else { return nil }
                return offset - startOffset
            }
            guard entered <= route.count, nodes[entered - 1] == from, nodes[entered] == to else { return nil }
            return toFirstNode + TrainPosition.linkLength * Int64(entered - 1) + offset
        }
    }

    func testARouteIsFollowedTickByTickWithEveryUnitAccountedFor() throws {
        var ticks = 0
        var arrivals = 0
        try runCampaign("composition.follow", cases: 200) { c in
            var world = try makeWorld(&c)
            guard let start = PositionGenerator.validPosition(in: world, using: &c.random) else { return }
            let tracks = world.tracks.map(\.position)
            let destination = tracks[c.random.below(tracks.count)]
            guard let route = world.route(from: start, to: destination) else { return }
            c.note("from \(start) to \(destination) via \(route)")
            try world.placeTrain(id, at: start)
            try world.setTrainContinuation(id, to: route)
            if c.random.chance(1, in: 4) { world.setSpeed(.double) }
            let stepsPerTick: Int64 = world.clock.speed == .double ? 2 : 1

            let total = progress(of: .atNode(destination, heading: .north), entered: route.count, start: start, route: route) ?? -1
            var expected: Int64 = 0
            var arrived = false
            for tick in 0..<400 {
                // The rate may change between ticks, as the train tool allows.
                if tick == 0 || c.random.chance(1, in: 5) {
                    try world.setTrainMovementRate(id, to: c.random.int64(in: 1...2_600))
                }
                guard let rate = world.train(id: id)?.movement.rate else { return c.fail("train lost") }
                try world.advance(ticks: 1)
                ticks += 1
                expected = min(expected + rate * stepsPerTick, total)
                guard let train = world.train(id: id), let position = train.position else { return c.fail("train lost") }
                let entered = train.movement.continuation.isEmpty ? route.count : train.movement.cursor
                guard let done = progress(of: position, entered: entered, start: start, route: route) else {
                    return c.fail("tick \(tick): \(position) with \(entered) entries entered is off the route")
                }
                c.expect(done == expected, "tick \(tick): travelled \(done), expected \(expected) of \(total)")
                let problems = WorldInvariants.violations(in: world)
                c.expect(problems.isEmpty, "tick \(tick): \(problems)")
                if done == total {
                    arrived = true
                    break
                }
            }
            guard arrived else { return c.fail("never arrived") }
            arrivals += 1
            // Standing at the destination, facing the way it came in, with
            // the continuation used up; more time changes nothing.
            let finalHeading: TrackDirection = {
                if let last = route.last {
                    let previous = route.count >= 2 ? route[route.count - 2] : ahead(of: start).node
                    return stepDirection(from: previous, to: last)!
                }
                return ahead(of: start).heading
            }()
            c.expect(world.train(id: id)?.position == .atNode(destination, heading: finalHeading), "ended at \(String(describing: world.train(id: id)?.position))")
            c.expect(world.train(id: id)?.movement.continuation == [], "continuation not used up")
            let settled = world.trains
            try world.advance(ticks: 1 + c.random.below(20))
            c.expect(world.trains == settled, "the train moved on past its destination")
        }
        assertVolume(arrivals > 500, "too few routes were followed to the end")
        assertVolume(ticks > 2_000, "too few ticks were checked")
    }

    /// A route found before the world changed is only a proposal: the
    /// commit checks it against the world as it is now. It is accepted
    /// exactly when it is still a path from the node ahead of the train, and
    /// a refusal changes nothing.
    func testAStaleRouteIsCheckedAgainstTheWorldAsItIsNow() throws {
        var refused = 0
        var accepted = 0
        try runCampaign("composition.staleRoute", cases: 250) { c in
            var world = try makeWorld(&c)
            guard let start = PositionGenerator.validPosition(in: world, using: &c.random) else { return }
            let tracks = world.tracks.map(\.position)
            let destination = tracks[c.random.below(tracks.count)]
            try world.placeTrain(id, at: start)
            guard let route = world.route(from: start, to: destination), !route.isEmpty else { return }
            // Something happens between the query and the commit.
            let change = c.random.below(4)
            switch change {
            case 0:
                // The train moves on along another path.
                try world.setTrainContinuation(id, to: PositionGenerator.walk(in: world, from: start, length: 3, using: &c.random))
                try world.setTrainMovementRate(id, to: c.random.int64(in: 1...2_048))
                try world.advance(ticks: 1 + c.random.below(3))
            case 1:
                try world.reverseTrain(id)
            case 2:
                // Track on the route is removed, if nothing rests on it.
                _ = try? world.removeTrack(at: route[c.random.below(route.count)])
            default:
                // A fresh unplace and place elsewhere.
                try world.unplaceTrain(id)
                if let elsewhere = PositionGenerator.validPosition(in: world, using: &c.random) {
                    try world.placeTrain(id, at: elsewhere)
                } else {
                    return
                }
            }
            c.note("change \(change), route \(route)")
            guard let now = world.train(id: id)?.position else { return c.fail("train lost") }
            // Is the old route still a path from where the train is now?
            var (node, heading) = ahead(of: now)
            var stillPath = true
            for next in route {
                guard let way = stepDirection(from: node, to: next), way != heading.opposite, world.isConnected(node, to: next) else {
                    stillPath = false
                    break
                }
                (node, heading) = (next, way)
            }
            let before = world
            do throws(GameError) {
                try world.setTrainContinuation(id, to: route)
                accepted += 1
                c.expect(stillPath, "a stale route that is no path from \(now) was accepted")
                c.expect(WorldInvariants.violations(in: world).isEmpty, "accepting the stale route broke \(WorldInvariants.violations(in: world))")
            } catch {
                refused += 1
                c.expect(!stillPath && error == .invalidContinuation, "refused with \(error) although still a path: \(stillPath)")
                c.expect(world == before, "a refused commit changed the world")
            }
        }
        assertVolume(refused > 200, "too few stale routes were refused")
        assertVolume(accepted > 50, "too few stale routes were still paths")
    }

    /// Removing track after the route was committed follows Stage K's rule:
    /// the train waits at the last node it can reach, loses the distance it
    /// could not use, and carries on once the track is back.
    func testTrackRemovedAlongACommittedRouteMakesTheTrainWaitAndResume() throws {
        var waits = 0
        try runCampaign("composition.waitAndResume", cases: 150) { c in
            var world = try makeWorld(&c)
            guard let start = PositionGenerator.validPosition(in: world, using: &c.random) else { return }
            let tracks = world.tracks.map(\.position)
            let destination = tracks[c.random.below(tracks.count)]
            guard let route = world.route(from: start, to: destination), route.count >= 2 else { return }
            try world.placeTrain(id, at: start)
            try world.setTrainContinuation(id, to: route)
            try world.setTrainMovementRate(id, to: c.random.int64(in: 200...3_000))
            let blocked = route[1 + c.random.below(route.count - 1)]
            guard let track = world.track(at: blocked), (try? world.removeTrack(at: blocked)) != nil else { return }
            c.note("route \(route), removed \(blocked)")
            // Enough ticks to reach the gap at the slowest rate.
            try world.advance(ticks: 20 * (route.count + 2))
            // It waits at the node before the first link into the gap.
            guard case .atNode(let waiting, _)? = world.train(id: id)?.position,
                  let index = route.firstIndex(of: blocked),
                  waiting == (index == 0 ? ahead(of: start).node : route[index - 1])
            else { return c.fail("not waiting before \(blocked): \(String(describing: world.train(id: id)?.position))") }
            waits += 1
            let waitingState = world.train(id: id)
            try world.advance(ticks: 5)
            c.expect(world.train(id: id) == waitingState, "a waiting train moved or saved up distance")
            try world.buildTrack(at: blocked, connections: track.connections)
            try world.setTrainMovementRate(id, to: .max)
            try world.advance(ticks: 1)
            c.expect(world.train(id: id)?.position.map { if case .atNode(destination, _) = $0 { true } else { false } } == true,
                     "did not resume to \(destination): \(String(describing: world.train(id: id)?.position))")
        }
        assertVolume(waits > 100, "too few trains waited for removed track")
    }
}
