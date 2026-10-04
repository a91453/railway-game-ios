import GameCore

/// A straight line of the track network where a test used to lay a row of
/// grid track tiles (Stage F3b, ARCHITECTURE decision 51): a node at the
/// centre of each tile of row `row` from column 0 to `tiles - 1`, and a
/// straight edge 1024 long between each two neighbours, built in that order
/// in a world with no track yet, so the node at column `x` is `.node(x + 1)`
/// and the edge from column `x - 1` to column `x` is `.edge(x)`, forward
/// going east.
///
/// A station beside column `x` is a point station at the centre of its old
/// tile with a platform on the half tile of track either side of the node
/// (the last 512 of the edge from the west, the first 512 of the edge to the
/// east), so a train stops at the node going either way and drives as far
/// from call to call as it did on the grid. The golden scenarios moved to
/// the network the same way (GoldenScenarios/README.md, F3a-2).
struct TestLine {
    let tiles: Int
    var row = 1

    // The test layout's spacing: 1024 units, 16 m (the world has no cells).
    static let tile = Int64(1_024)

    /// The node at column `x`.
    func node(_ x: Int) -> TrackNodeID { .node(x + 1) }

    /// The edge from column `x - 1` to column `x`.
    func edge(_ x: Int) -> TrackEdgeID {
        precondition(x >= 1 && x < tiles, "no edge ends at column \(x) from the west")
        return .edge(x)
    }

    /// The centre of the tile at column `x`, row `y`.
    static func centre(_ x: Int, _ y: Int) -> PlanPoint {
        PlanPoint(x: Int64(x) * tile + tile / 2, y: Int64(y) * tile + tile / 2)
    }

    /// Builds the nodes, then the edges, west to east.
    func build(in world: inout GameWorld) throws {
        for x in 0..<tiles {
            let centre = Self.centre(x, row)
            try world.buildTrackNode(at: WorldCoordinate(x: centre.x, y: centre.y))
        }
        for x in 1..<tiles {
            try world.buildTrackEdge(from: node(x - 1), to: node(x))
        }
    }

    /// Builds station `name` at the centre of tile (`x`, `y`) with its
    /// platforms either side of the node at column `x`, and returns it.
    @discardableResult
    func buildStation(named name: String, beside x: Int, at y: Int, in world: inout GameWorld) throws -> StationID {
        let id = try world.buildStation(named: name, at: Self.centre(x, y)).id
        if x >= 1 {
            try world.addTrackPlatform(id, on: edge(x), from: Self.tile / 2, to: Self.tile)
        }
        if x + 1 < tiles {
            try world.addTrackPlatform(id, on: edge(x + 1), from: 0, to: Self.tile / 2)
        }
        return id
    }

    /// A train at the node at column `x`, facing east or west: at the end
    /// of the edge it arrived along, or at the start of the edge it faces
    /// when none leads in.
    func at(_ x: Int, facingEast: Bool) -> TrainPosition {
        if facingEast {
            return x >= 1
                ? .onEdge(TrackTraversal(edge: edge(x), direction: .forward), offset: Self.tile)
                : .onEdge(TrackTraversal(edge: edge(1), direction: .forward), offset: 0)
        }
        return x + 1 < tiles
            ? .onEdge(TrackTraversal(edge: edge(x + 1), direction: .backward), offset: Self.tile)
            : .onEdge(TrackTraversal(edge: edge(x), direction: .backward), offset: 0)
    }

    /// A train that came to the node at column `x` and turned round there,
    /// now facing east or west: it turns where it stands, so it is on the
    /// edge it arrived along, at the start of that edge for its new way.
    func turned(at x: Int, facingEast: Bool) -> TrainPosition {
        facingEast
            ? .onEdge(TrackTraversal(edge: edge(x + 1), direction: .forward), offset: 0)
            : .onEdge(TrackTraversal(edge: edge(x), direction: .backward), offset: 0)
    }

    /// A train `offset` along the way from column `from` to the next
    /// column, east or west.
    func between(_ from: Int, _ to: Int, offset: Int64) -> TrainPosition {
        precondition(abs(to - from) == 1, "columns \(from) and \(to) are not neighbours")
        return to > from
            ? .onEdge(TrackTraversal(edge: edge(to), direction: .forward), offset: offset)
            : .onEdge(TrackTraversal(edge: edge(from), direction: .backward), offset: offset)
    }

    /// The path that takes a train from column `start` through `columns`,
    /// one edge each.
    func path(from start: Int, through columns: [Int]) -> [TrackTraversal] {
        var previous = start
        return columns.map { next in
            defer { previous = next }
            precondition(abs(next - previous) == 1, "columns \(previous) and \(next) are not neighbours")
            return next > previous
                ? TrackTraversal(edge: edge(next), direction: .forward)
                : TrackTraversal(edge: edge(previous), direction: .backward)
        }
    }
}
