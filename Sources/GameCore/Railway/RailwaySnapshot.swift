// What a renderer reads (Phase 4.5 Stage S4, ARCHITECTURE decision 30): the
// track network, its platforms and every placed train, in world coordinates,
// as plain values worked out on demand. Nothing here is authoritative or
// saved: a renderer may convert it to floating point, cache it by edge ID (an
// edge never changes and its ID is never reused) and draw it however it
// likes, but it never writes back. Every gameplay change is still a
// GameWorld command.

/// An edge with its whole alignment, for renderers: the edge (end nodes,
/// length, curve, profile, structure) and its geometry (the sampled centre
/// line with heights, and the height and grade anywhere along it).
public struct TrackAlignment: Hashable, Sendable {
    public let edge: TrackEdge
    public let geometry: TrackGeometry

    /// The stretches of the vertical profile, from the `from` node: level,
    /// up, down or transition.
    public var segments: [TrackProfileSegment] {
        geometry.segments
    }

    /// The steepest grade on the edge, toward its `to` node.
    public var steepestGrade: TrackGrade {
        geometry.steepestGrade
    }
}

/// The railway as a renderer needs it at one moment: the nodes, edges and
/// platforms of the track network and every placed train (see
/// ``GameWorld/railwaySnapshot()``). Edges are also available one by one
/// through ``GameWorld/trackAlignment(of:)``.
public struct RailwaySnapshot: Hashable, Sendable {
    /// A node of the track network.
    public struct Node: Hashable, Sendable {
        public let id: TrackNodeID
        public let position: WorldCoordinate
        /// Whether trains pass between a tunnel and the open here.
        public let isTunnelPortal: Bool
    }

    /// A station's platform on the track network, where it lies.
    public struct Platform: Hashable, Sendable {
        /// The platform: its station, edge, start and end.
        public let platform: TrackPlatform
        /// The platform's level: the height of the track along it, which is
        /// level, and what carries the track there.
        public let height: Int64
        public let structure: TrackStructure
        /// The centre line along the platform, from its start to its end.
        public let points: [WorldCoordinate]
    }

    /// A placed train.
    public struct Train: Hashable, Sendable {
        public let id: TrainID
        /// Where its head is, the way it faces and its grade that way.
        public let head: TrackLocation
        /// The centre line its cars stand along, head to tail (see
        /// ``GameWorld/bodyPath(of:)``).
        public let body: [WorldCoordinate]
    }

    /// In ascending ID order.
    public let nodes: [Node]
    public let edges: [TrackAlignment]
    /// In order along the track (see ``TrackPlatform``).
    public let platforms: [Platform]
    /// In ascending ID order; trains off the track are left out.
    public let trains: [Train]
}

extension GameWorld {
    /// Edge `id` of the track network with its alignment, or `nil` if there
    /// is none.
    public func trackAlignment(of id: TrackEdgeID) -> TrackAlignment? {
        guard let edge = trackEdge(id), let geometry = trackGeometry(of: id) else { return nil }
        return TrackAlignment(edge: edge, geometry: geometry)
    }

    /// Whether node `id` of the track network is a tunnel portal (see
    /// ``RailwayNetwork/isTunnelPortal(_:)``).
    public func isTunnelPortal(_ id: TrackNodeID) -> Bool {
        network.isTunnelPortal(id)
    }

    /// The platforms on the track network that the whole of train `id`
    /// stands along (Stage S4): its head is on the platform's edge, its body
    /// does not leave that edge, and every point from its head to its tail
    /// lies between the platform's start and end. In order along the track;
    /// empty for a train off the track or unknown.
    public func trackPlatformsAlongWholeTrain(_ id: TrainID) -> [TrackPlatform] {
        guard let train = train(id: id), case .onEdge(let traversal, let offset)? = train.position, train.trailEdges.isEmpty,
              let edge = network.edge(traversal.edge)
        else { return [] }
        // The stretch the train covers, measured from the edge's `from` node.
        let (tail, head) = traversal.direction == .forward
            ? (offset - train.length, offset)
            : (edge.length - offset, edge.length - offset + train.length)
        return network.platforms(on: edge.id).filter { $0.start <= min(tail, head) && max(tail, head) <= $0.end }
    }

    /// The railway as a renderer needs it now (Stage S4): every node of the
    /// track network (with whether it is a tunnel portal), every edge with
    /// its alignment, every platform on the network with its level and
    /// centre line, and every placed train's head and body. Worked out on
    /// each call, in time proportional to the samples of the network; read
    /// only.
    public func railwaySnapshot() -> RailwaySnapshot {
        let nodes = network.nodes.map { node in
            RailwaySnapshot.Node(id: node.id, position: node.position, isTunnelPortal: network.isTunnelPortal(node.id))
        }
        let edges = network.edges.compactMap { trackAlignment(of: $0.id) }
        let platforms = network.platforms.compactMap { platform -> RailwaySnapshot.Platform? in
            guard let edge = network.edge(platform.edge), let geometry = network.geometry(of: platform.edge) else { return nil }
            return RailwaySnapshot.Platform(
                platform: platform, height: geometry.height(at: platform.start), structure: edge.structure,
                points: geometry.points(from: platform.start, to: platform.end)
            )
        }
        let trains = self.trains.compactMap { train -> RailwaySnapshot.Train? in
            guard let position = train.position, let head = location(of: position) else { return nil }
            return RailwaySnapshot.Train(id: train.id, head: head, body: bodyPath(of: train.id))
        }
        return RailwaySnapshot(nodes: nodes, edges: edges, platforms: platforms, trains: trains)
    }
}
