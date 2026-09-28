import GameCore
import XCTest

/// Stage I on generated networks: connectivity is derived from the map by the
/// link rule, answered the same whatever the build order, and read-only.
final class TopologyPropertyTests: XCTestCase {
    /// The link rule stated directly: both tiles on the map and track, and
    /// each has an exit toward the other.
    private func expectedNeighbors(of tile: GridPosition, in world: GameWorld) -> [GridPosition] {
        guard let track = world.track(at: tile) else { return [] }
        return TrackDirection.allCases.compactMap { way in
            guard track.connections.contains(TrackConnections(way)) else { return nil }
            let neighbor = step(tile, way)
            guard let other = world.track(at: neighbor), other.connections.contains(TrackConnections(way.opposite)) else { return nil }
            return neighbor
        }
    }

    /// Every tile of the map and a ring of positions just outside it.
    private func probes(in world: GameWorld) -> [GridPosition] {
        var result: [GridPosition] = []
        for y in -1...world.map.height {
            for x in -1...world.map.width {
                result.append(GridPosition(x: x, y: y))
            }
        }
        return result
    }

    func testNeighboursFollowTheLinkRuleSymmetricallyInCompassOrder() throws {
        var checked = 0
        let ran = try runCampaign("topology.linkRule", cases: 60) { c in
            let shape = c.random.element(of: NetworkShape.allCases)
            let (specs, width, height) = NetworkGenerator.specs(shape, using: &c.random)
            c.note("\(shape) \(width)x\(height), \(specs.count) tiles")
            let world = try NetworkGenerator.build(specs, width: width, height: height)
            let before = world
            let tiles = probes(in: world)
            for tile in tiles {
                let neighbors = world.connectedNeighbors(of: tile)
                checked += 1
                c.expect(neighbors == expectedNeighbors(of: tile, in: world), "neighbours of \(tile): \(neighbors)")
                c.expect(Set(neighbors).count == neighbors.count, "duplicate neighbours of \(tile)")
                let order = neighbors.compactMap { stepDirection(from: tile, to: $0) }
                c.expect(order.count == neighbors.count, "a neighbour of \(tile) is not adjacent")
                c.expect(order == TrackDirection.allCases.filter(order.contains), "neighbours of \(tile) out of N, E, S, W order")
                for neighbor in neighbors {
                    c.expect(world.map.contains(neighbor) && world.track(at: neighbor) != nil, "phantom neighbour \(neighbor) of \(tile)")
                }
                for way in TrackDirection.allCases {
                    let other = step(tile, way)
                    c.expect(
                        world.isConnected(tile, to: other) == world.isConnected(other, to: tile),
                        "isConnected is not symmetric for \(tile) and \(other)"
                    )
                    c.expect(world.isConnected(tile, to: other) == neighbors.contains(other), "isConnected disagrees with the neighbour list at \(tile)")
                }
                c.expect(!world.isConnected(tile, to: tile), "\(tile) is joined to itself")
            }
            c.expect(world == before, "queries changed the world")
        }
        assertVolume(ran == 60 * PropertySeeds.active.count, "every case should run")
        assertVolume(checked > 5_000, "too few tiles were checked")
    }

    func testConnectivityDoesNotDependOnBuildOrder() throws {
        try runCampaign("topology.buildOrder", cases: 40) { c in
            let shape = c.random.element(of: NetworkShape.allCases)
            let (specs, width, height) = NetworkGenerator.specs(shape, using: &c.random)
            c.note("\(shape) \(width)x\(height)")
            // Stations are numbered in build order, so only track is shuffled.
            let tracks = specs.filter { if case .track = $0.kind { true } else { false } }
            let stations = specs.filter { if case .station = $0.kind { true } else { false } }
            let forward = try NetworkGenerator.build(tracks + stations, width: width, height: height)
            let shuffled = try NetworkGenerator.build(c.random.shuffled(tracks) + stations, width: width, height: height)
            c.expect(forward == shuffled, "the same tiles built in another order give another world")
            for tile in probes(in: forward) {
                c.expect(forward.connectedNeighbors(of: tile) == shuffled.connectedNeighbors(of: tile), "neighbours of \(tile) depend on build order")
            }
        }
    }

    func testDisconnectedComponentsStayApartAndRemovalDisconnectsAtOnce() throws {
        try runCampaign("topology.components", cases: 40) { c in
            let height = 3 + c.random.below(3)
            let left = 2 + c.random.below(3)
            let right = 2 + c.random.below(3)
            let specs = NetworkGenerator.randomSpecs(width: left, height: height, originX: 0, using: &c.random)
                + NetworkGenerator.randomSpecs(width: right, height: height, originX: left + 1, using: &c.random)
            // Column `left` is empty: nothing may join across it.
            c.note("components \(left) + \(right) wide, \(height) high, gap column \(left)")
            var world = try NetworkGenerator.build(specs, width: left + 1 + right, height: height)
            for start in world.tracks.map(\.position) {
                var seen: Set<GridPosition> = [start]
                var queue = [start]
                while let tile = queue.popLast() {
                    for neighbor in world.connectedNeighbors(of: tile) where seen.insert(neighbor).inserted {
                        queue.append(neighbor)
                    }
                }
                c.expect(seen.allSatisfy { ($0.x < left) == (start.x < left) && $0.x != left }, "\(start) reaches across the empty column")
            }
            // Removing a track tile disconnects it from every neighbour at
            // once and leaves the neighbours' exits as built.
            guard let removed = world.tracks.first(where: { !world.connectedNeighbors(of: $0.position).isEmpty }) else { return }
            let neighbors = world.connectedNeighbors(of: removed.position)
            let neighborTracks = neighbors.map { world.track(at: $0) }
            try world.removeTrack(at: removed.position)
            c.expect(world.connectedNeighbors(of: removed.position).isEmpty, "removed tile still has neighbours")
            for (neighbor, track) in zip(neighbors, neighborTracks) {
                c.expect(!world.isConnected(neighbor, to: removed.position), "\(neighbor) still joined to removed \(removed.position)")
                c.expect(world.track(at: neighbor) == track, "removal changed the neighbour at \(neighbor)")
            }
        }
    }

    func testOnlyTheFourDirectionBitsBuildAndRejectionChangesNothing() throws {
        try runCampaign("topology.masks", cases: 16) { c in
            let (specs, width, height) = NetworkGenerator.specs(.random, using: &c.random)
            var world = try NetworkGenerator.build(specs, width: width, height: height)
            let before = world
            for raw in [UInt8(0), 16, 17, 32, 64, 128, 255, UInt8(16 + c.random.below(240))] {
                let tile = GridPosition(x: c.random.below(width + 2) - 1, y: c.random.below(height + 2) - 1)
                do throws(GameError) {
                    try world.buildTrack(at: tile, connections: TrackConnections(rawValue: raw))
                    c.fail("mask \(raw) was built at \(tile)")
                } catch {
                    c.expect(error == .invalidTrackConnections, "mask \(raw) at \(tile) gave \(error)")
                }
                c.expect(world == before, "a rejected mask \(raw) changed the world")
            }
        }
    }
}
