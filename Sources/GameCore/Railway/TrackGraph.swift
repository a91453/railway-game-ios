// The railway graph (Phase 4.5 Stage S3, ARCHITECTURE decisions 28 and 29).
// Routes, movement, occupancy and the traffic control of Phase 4.6 see the
// railway as nodes joined by edges, whatever shape the track has. There are
// two kinds of each, behind one vocabulary:
//
// - the grid of Stages I–S2: a node is a track tile and an edge the link
//   between two joined tiles, 1024 units long, turning by the rules of the
//   tile's layout (see exits(from:facing:));
// - the continuous track network of Stage S3: numbered nodes at world
//   coordinates and numbered edges of any length and shape between them
//   (see TrackNetwork).
//
// Nothing here depends on north, east, south and west: the grid's
// directions stay inside its own adapter.

/// A node of the railway graph: a track tile of the grid, or a node of the
/// continuous track network.
public enum TrackNodeID: Hashable, Comparable, Sendable {
    /// The track tile at a grid position.
    case tile(GridPosition)
    /// The node of the track network with this number (see
    /// ``GameWorld/buildTrackNode(at:)``).
    case node(Int)

    /// The number of a network node, or `nil` for a tile.
    var networkNumber: Int? {
        if case .node(let number) = self { number } else { nil }
    }

    /// Tiles before network nodes; tiles in row-major order, network nodes
    /// by number.
    public static func < (lhs: TrackNodeID, rhs: TrackNodeID) -> Bool {
        switch (lhs, rhs) {
        case (.tile(let a), .tile(let b)): TrackEdgeID.precedes(a, b)
        case (.tile, .node): true
        case (.node, .tile): false
        case (.node(let a), .node(let b)): a < b
        }
    }
}

/// An edge of the railway graph: the link between two joined track tiles of
/// the grid, or an edge of the continuous track network.
public enum TrackEdgeID: Hashable, Comparable, Sendable {
    /// The link between two joined track tiles, the one further north (or,
    /// in the same row, further west) first. Use ``link(between:and:)`` to
    /// build one in that order.
    case link(GridPosition, GridPosition)
    /// The edge of the track network with this number (see
    /// ``GameWorld/buildTrackEdge(from:to:curve:)``).
    case edge(Int)

    /// The link between `a` and `b`, in either order.
    public static func link(between a: GridPosition, and b: GridPosition) -> TrackEdgeID {
        precedes(a, b) ? .link(a, b) : .link(b, a)
    }

    /// Row-major order: north before south, then west before east.
    static func precedes(_ a: GridPosition, _ b: GridPosition) -> Bool {
        (a.y, a.x) < (b.y, b.x)
    }

    /// The number of a network edge, or `nil` for a grid link.
    var networkNumber: Int? {
        if case .edge(let number) = self { number } else { nil }
    }

    /// Links before network edges; links by their first tile, then their
    /// second; network edges by number.
    public static func < (lhs: TrackEdgeID, rhs: TrackEdgeID) -> Bool {
        switch (lhs, rhs) {
        case (.link(let a, let b), .link(let c, let d)): a == c ? precedes(b, d) : precedes(a, c)
        case (.link, .edge): true
        case (.edge, .link): false
        case (.edge(let a), .edge(let b)): a < b
        }
    }
}

/// Which way along an edge: from its `from` node to its `to` node, or back.
/// A grid link's `from` is its first tile (see ``TrackEdgeID/link(_:_:)``).
public enum TrackEdgeDirection: String, Hashable, Codable, Sendable {
    case forward
    case backward

    public var reversed: TrackEdgeDirection {
        self == .forward ? .backward : .forward
    }
}

/// An edge travelled one way: what a train is on, and what a route is made
/// of.
public struct TrackTraversal: Hashable, Sendable {
    public let edge: TrackEdgeID
    public let direction: TrackEdgeDirection

    public init(edge: TrackEdgeID, direction: TrackEdgeDirection) {
        self.edge = edge
        self.direction = direction
    }

    /// The same edge, the other way.
    public var reversed: TrackTraversal {
        TrackTraversal(edge: edge, direction: direction.reversed)
    }

    /// The grid link from tile `from` to tile `to`, travelled that way.
    public static func link(from: GridPosition, to: GridPosition) -> TrackTraversal {
        TrackTraversal(edge: .link(between: from, and: to), direction: TrackEdgeID.precedes(from, to) ? .forward : .backward)
    }
}
