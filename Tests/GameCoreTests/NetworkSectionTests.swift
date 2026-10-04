import GameCore
import XCTest

/// Sections and parallel tracks of the track network (Stage F3c): the
/// network's versions of the grid's (see `TrackResourceTests`), so they
/// stay when the grid goes. Sections port the Railway reference's track
/// groups (`topology.js`, `trackGroups`): chains of edges through plain
/// nodes, between branch points. Every expected value is worked out by hand
/// in the comments.
final class NetworkSectionTests: XCTestCase {
    private static let tile = WorldCoordinate.tileSize
    /// The handle of a quarter turn of radius 1024 (as `KernelNetwork`).
    private static let quarter: Int64 = 563

    private static func centre(_ x: Int, _ y: Int) -> PlanPoint {
        PlanPoint(x: Int64(x) * tile + tile / 2, y: Int64(y) * tile + tile / 2)
    }

    private static func traversal(_ number: Int, _ forward: Bool = true) -> TrackTraversal {
        TrackTraversal(edge: .edge(number), direction: forward ? .forward : .backward)
    }

    private func makeWorld() throws -> GameWorld {
        try GameWorld(width: 9, height: 5, economy: GameEconomy(balance: 100_000_000, costs: testCosts))
    }

    /// Builds a node at the centre of each tile, in order: node 1, 2, …
    private func buildNodes(_ tiles: [(Int, Int)], in world: inout GameWorld) throws {
        for (x, y) in tiles {
            let centre = Self.centre(x, y)
            try world.buildTrackNode(at: WorldCoordinate(x: centre.x, y: centre.y))
        }
    }

    /// An S-curve from node `from` east to node `to`, leaving and arriving
    /// eastward (the kernel network's ladder rungs).
    private func buildS(from: Int, to: Int, in world: inout GameWorld) throws {
        let a = try XCTUnwrap(world.network.node(.node(from))).position
        let b = try XCTUnwrap(world.network.node(.node(to))).position
        try world.buildTrackEdge(
            from: .node(from), to: .node(to),
            curve: .cubic(PlanPoint(x: a.x + Self.tile, y: a.y), PlanPoint(x: b.x - Self.tile, y: b.y))
        )
    }

    /// A quarter turn from node `from` to node `to`, leaving and arriving
    /// the given ways.
    private func buildQuarter(from: Int, to: Int, leaving: (Int64, Int64), arriving: (Int64, Int64), in world: inout GameWorld) throws {
        let a = try XCTUnwrap(world.network.node(.node(from))).position
        let b = try XCTUnwrap(world.network.node(.node(to))).position
        try world.buildTrackEdge(
            from: .node(from), to: .node(to),
            curve: .cubic(
                PlanPoint(x: a.x + leaving.0 * Self.quarter, y: a.y + leaving.1 * Self.quarter),
                PlanPoint(x: b.x - arriving.0 * Self.quarter, y: b.y - arriving.1 * Self.quarter)
            )
        )
    }

    /// A main line along row 1, columns 0 to 7 (nodes 1–8), with a passing
    /// loop below it on row 3 (nodes 9 and 10):
    ///
    /// - edges 1–6 run along the main line from node 1 to node 7, except
    ///   edge 3, built from node 4 back to node 3;
    /// - edge 7 is an S-curve from node 2 down to node 9, edge 8 runs on to
    ///   node 10 and edge 9 is an S-curve back up to node 7;
    /// - edge 10 runs on from node 7 to node 8.
    ///
    /// So nodes 2 and 7 are turnouts (edges 2 and 7 leave node 2 eastward
    /// and both join edge 1; edges 6 and 9 reach node 7 from the west and
    /// both join edge 10), nodes 1 and 8 are ends of the line, and every
    /// other node is plain.
    ///
    /// Stations (points on row 0, beside their platforms): Alpha on edge 1;
    /// Beta on edge 4 of the main line and edge 8 of the loop; Delta on edge
    /// 6 and edge 9; Gamma on edge 10. Each platform covers its edge.
    private func makePassingLoop() throws -> (GameWorld, alpha: StationID, beta: StationID, delta: StationID, gamma: StationID) {
        var world = try makeWorld()
        try buildNodes([(0, 1), (1, 1), (2, 1), (3, 1), (4, 1), (5, 1), (6, 1), (7, 1), (3, 3), (4, 3)], in: &world)
        for (from, to) in [(1, 2), (2, 3), (4, 3), (4, 5), (5, 6), (6, 7)] {
            try world.buildTrackEdge(from: .node(from), to: .node(to))
        }
        try buildS(from: 2, to: 9, in: &world)
        try world.buildTrackEdge(from: .node(9), to: .node(10))
        try buildS(from: 10, to: 7, in: &world)
        try world.buildTrackEdge(from: .node(7), to: .node(8))
        func station(_ name: String, _ x: Int, on edges: [Int]) throws -> StationID {
            let id = try world.buildStation(named: name, at: Self.centre(x, 0)).id
            for number in edges {
                let length = try XCTUnwrap(world.network.edge(.edge(number))).length
                try world.addTrackPlatform(id, on: .edge(number), from: 0, to: length)
            }
            return id
        }
        let alpha = try station("Alpha", 0, on: [1])
        let beta = try station("Beta", 3, on: [4, 8])
        let delta = try station("Delta", 5, on: [6, 9])
        let gamma = try station("Gamma", 7, on: [10])
        return (world, alpha, beta, delta, gamma)
    }

    func testSectionsRunThroughPlainNodesBetweenBranchPoints() throws {
        let (world, _, _, _, _) = try makePassingLoop()
        let t = Self.traversal
        // Branch points in order: node 1 (an end) starts edge 1; node 2
        // starts the main line (edge 2, then edge 3 backwards, as it was
        // built) and the loop (edge 7); node 7 starts edge 10. Node 8 and
        // node 7's other ends are covered by then.
        XCTAssertEqual(world.networkSections(), [
            NetworkSection(traversals: [t(1, true)], nodes: [.node(1), .node(2)], isLoop: false),
            NetworkSection(
                traversals: [t(2, true), t(3, false), t(4, true), t(5, true), t(6, true)],
                nodes: [.node(2), .node(3), .node(4), .node(5), .node(6), .node(7)], isLoop: false
            ),
            NetworkSection(traversals: [t(7, true), t(8, true), t(9, true)], nodes: [.node(2), .node(9), .node(10), .node(7)], isLoop: false),
            NetworkSection(traversals: [t(10, true)], nodes: [.node(7), .node(8)], isLoop: false),
        ])
    }

    func testCuttingTheLoopMakesTwoDeadEnds() throws {
        var (world, _, beta, _, _) = try makePassingLoop()
        try world.removeTrackPlatform(beta, on: .edge(8), from: 0)
        try world.removeTrackEdge(.edge(8))
        let t = Self.traversal
        // Nodes 9 and 10 now end one edge each: branch points. Node 2 starts
        // edge 7 to node 9; node 7 starts edge 9 back to node 10, against
        // the way it was built, before edge 10.
        XCTAssertEqual(world.networkSections(), [
            NetworkSection(traversals: [t(1, true)], nodes: [.node(1), .node(2)], isLoop: false),
            NetworkSection(
                traversals: [t(2, true), t(3, false), t(4, true), t(5, true), t(6, true)],
                nodes: [.node(2), .node(3), .node(4), .node(5), .node(6), .node(7)], isLoop: false
            ),
            NetworkSection(traversals: [t(7, true)], nodes: [.node(2), .node(9)], isLoop: false),
            NetworkSection(traversals: [t(9, false)], nodes: [.node(7), .node(10)], isLoop: false),
            NetworkSection(traversals: [t(10, true)], nodes: [.node(7), .node(8)], isLoop: false),
        ])
    }

    func testAPassingLoopIsDoubleTrackBetweenItsPlatforms() throws {
        var (world, alpha, beta, delta, gamma) = try makePassingLoop()
        // Beta to Delta: along the main line (edge 4 on to edge 6 by edge
        // 5) and along the loop (edge 8 on to edge 9 at node 10).
        XCTAssertEqual(world.parallelTracks(between: beta, and: delta), 2)
        XCTAssertEqual(world.parallelTracks(between: delta, and: beta), 2)
        // Alpha's only way out is the end of edge 1 at node 2; Gamma's is
        // the start of edge 10 at node 7.
        XCTAssertEqual(world.parallelTracks(between: alpha, and: beta), 1)
        XCTAssertEqual(world.parallelTracks(between: delta, and: gamma), 1)
        XCTAssertEqual(world.parallelTracks(between: alpha, and: gamma), 1)
        XCTAssertEqual(world.parallelTracks(between: beta, and: beta), 0, "a station and itself")
        XCTAssertEqual(world.parallelTracks(between: alpha, and: StationID(rawValue: 9)), 0, "an unknown station")

        let line = try world.createLine(named: "Main", stops: [alpha, beta, delta, gamma])
        XCTAssertEqual(world.lineTrackCounts(line.id), [1, 2, 1])

        // Without edge 8 the loop is two sidings: Beta's platform on the
        // main line is its only way to Delta.
        try world.removeTrackPlatform(beta, on: .edge(8), from: 0)
        try world.removeTrackEdge(.edge(8))
        XCTAssertEqual(world.parallelTracks(between: beta, and: delta), 1)
        XCTAssertEqual(world.lineTrackCounts(line.id), [1, 1, 1])
    }

    /// A ring of six edges through six plain nodes: a straight along row 1
    /// (edge 1, node 1 to node 2), a quarter turn down (edge 2, to node 3),
    /// a quarter turn back (edge 3, to node 4), a straight along row 3
    /// westward (edge 4, to node 5) and two quarter turns up to node 1
    /// (edges 5 and 6, by node 6).
    private func makeRing() throws -> GameWorld {
        var world = try makeWorld()
        try buildNodes([(1, 1), (2, 1), (3, 2), (2, 3), (1, 3), (0, 2)], in: &world)
        try world.buildTrackEdge(from: .node(1), to: .node(2))
        try buildQuarter(from: 2, to: 3, leaving: (1, 0), arriving: (0, 1), in: &world)
        try buildQuarter(from: 3, to: 4, leaving: (0, 1), arriving: (-1, 0), in: &world)
        try world.buildTrackEdge(from: .node(4), to: .node(5))
        try buildQuarter(from: 5, to: 6, leaving: (-1, 0), arriving: (0, -1), in: &world)
        try buildQuarter(from: 6, to: 1, leaving: (0, -1), arriving: (1, 0), in: &world)
        return world
    }

    func testARingWithoutABranchPointIsALoop() throws {
        let world = try makeRing()
        let t = Self.traversal
        // No branch point: the ring starts at the `from` node of its lowest
        // edge, along it.
        XCTAssertEqual(world.networkSections(), [
            NetworkSection(
                traversals: (1...6).map { t($0, true) },
                nodes: (1...6).map { .node($0) }, isLoop: true
            ),
        ])
    }

    func testARingIsTwoTracksBetweenAnyTwoOfItsPlatforms() throws {
        var world = try makeRing()
        let alpha = try world.buildStation(named: "Alpha", at: Self.centre(1, 0)).id
        let beta = try world.buildStation(named: "Beta", at: Self.centre(1, 4)).id
        let gamma = try world.buildStation(named: "Gamma", at: Self.centre(2, 0)).id
        try world.addTrackPlatform(alpha, on: .edge(1), from: 256, to: 768)
        try world.addTrackPlatform(beta, on: .edge(4), from: 256, to: 768)
        try world.addTrackPlatform(gamma, on: .edge(1), from: 768, to: 1024)
        // Alpha to Beta: either way round the ring.
        XCTAssertEqual(world.parallelTracks(between: alpha, and: beta), 2)
        // Alpha to Gamma on the same edge: where their platforms touch (a
        // stretch of no length), and the long way round, from the start of
        // edge 1 back to its end; it passes Beta's platform, which is not
        // one of theirs.
        XCTAssertEqual(world.parallelTracks(between: alpha, and: gamma), 2)
    }

    /// A diamond crossing: a line along row 1 (nodes 1–3, edges 1 and 2)
    /// and one down column 1 (nodes 4 and 5, edges 3 and 4) through node 2,
    /// whose edges join only straight across. Node 6 has no edges.
    func testACrossingEndsSectionsAndJoinsNothing() throws {
        var world = try makeWorld()
        try buildNodes([(0, 1), (1, 1), (2, 1), (1, 0), (1, 2), (3, 3)], in: &world)
        for (from, to) in [(1, 2), (2, 3), (4, 2), (2, 5)] {
            try world.buildTrackEdge(from: .node(from), to: .node(to))
        }
        let t = Self.traversal
        // Node 2 has four ends: a branch point, so every edge is a section.
        // Node 6 is in none.
        XCTAssertEqual(world.networkSections(), [
            NetworkSection(traversals: [t(1, true)], nodes: [.node(1), .node(2)], isLoop: false),
            NetworkSection(traversals: [t(2, true)], nodes: [.node(2), .node(3)], isLoop: false),
            NetworkSection(traversals: [t(3, false)], nodes: [.node(2), .node(4)], isLoop: false),
            NetworkSection(traversals: [t(4, true)], nodes: [.node(2), .node(5)], isLoop: false),
        ])
        let alpha = try world.buildStation(named: "Alpha", at: Self.centre(0, 0)).id
        let beta = try world.buildStation(named: "Beta", at: Self.centre(0, 2)).id
        let gamma = try world.buildStation(named: "Gamma", at: Self.centre(2, 0)).id
        try world.addTrackPlatform(alpha, on: .edge(1), from: 0, to: 1024)
        try world.addTrackPlatform(beta, on: .edge(4), from: 0, to: 1024)
        try world.addTrackPlatform(gamma, on: .edge(2), from: 0, to: 1024)
        // Edges 1 and 4 meet at node 2 but do not join: no track between
        // Alpha and Beta, as a train sees it.
        XCTAssertEqual(world.parallelTracks(between: alpha, and: beta), 0)
        XCTAssertEqual(world.parallelTracks(between: alpha, and: gamma), 1)
    }

    func testAnEmptyNetworkHasNoSections() throws {
        var world = try makeWorld()
        XCTAssertEqual(world.networkSections(), [])
        try world.buildTrackNode(at: WorldCoordinate(x: 512, y: 512))
        XCTAssertEqual(world.networkSections(), [], "a node without edges is no track")
    }
}
