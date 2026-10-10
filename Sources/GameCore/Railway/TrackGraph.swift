// The railway graph (Phase 4.5 Stage S3, ARCHITECTURE decisions 28 and 29).
// Routes, movement, occupancy and the traffic control of Phase 4.6 see the
// railway as nodes joined by edges, whatever shape the track has: numbered
// nodes at world coordinates and numbered edges of any length and shape
// between them (see RailwayNetwork). Until Stage F3c the grid of Stages
// I–S2 was a second kind of node and edge (a track tile, and the link
// between two joined tiles); it went with the grid (decision 51).

/// A node of the railway graph: a node of the track network.
public enum TrackNodeID: Hashable, Comparable, Sendable {
    /// The node of the track network with this number (see
    /// ``GameWorld/buildTrackNode(at:)``).
    case node(Int)

    /// The node's number.
    var networkNumber: Int? {
        switch self {
        case .node(let number): number
        }
    }

    /// By number.
    public static func < (lhs: TrackNodeID, rhs: TrackNodeID) -> Bool {
        switch (lhs, rhs) {
        case (.node(let a), .node(let b)): a < b
        }
    }
}

/// An edge of the railway graph: an edge of the track network.
public enum TrackEdgeID: Hashable, Comparable, Sendable {
    /// The edge of the track network with this number (see
    /// ``GameWorld/buildTrackEdge(from:to:curve:)``).
    case edge(Int)

    /// The edge's number.
    var networkNumber: Int? {
        switch self {
        case .edge(let number): number
        }
    }

    /// By number.
    public static func < (lhs: TrackEdgeID, rhs: TrackEdgeID) -> Bool {
        switch (lhs, rhs) {
        case (.edge(let a), .edge(let b)): a < b
        }
    }
}

/// Which way along an edge: from its `from` node to its `to` node, or back.
public enum TrackEdgeDirection: String, Hashable, Codable, Sendable {
    case forward
    case backward

    public var reversed: TrackEdgeDirection {
        self == .forward ? .backward : .forward
    }

    /// By case, not by raw value: hashing the raw value's string was a
    /// large part of every set of traversals and spans (equal values still
    /// hash equally).
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self == .forward)
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
}
