// Closing track by hand (decision 716). The player closes an edge of the
// track network to trains, for as long as they like, and opens it again.
//
// 1. An edge a train stands on, has reserved any of, or is on its way
//    along is not closed: the command is refused and names the train.
// 2. While an edge is closed no route is found along it
//    (``GameWorld/path(from:toStation:length:)`` and every search built on
//    it, ``GameWorld/route(from:to:)``), so nothing reserves it, and no
//    command places a train on it or sends one along it. Where another
//    way serves (a passing loop, the other track) services take it as
//    their default way; where none does, a service waits at its stop as
//    one without a route does, and a line plans no journey over it.
// 3. Opening is never refused. The next step finds the routes again.
//
// The closed edges are kept on the network (``RailwayNetwork/closedEdges``),
// beside its platforms: everything traffic control keeps between steps is
// kept for the network as it is, so a closure starts it again. Nothing here
// reads geometry or the clock.

extension GameWorld {
    /// The edges closed to trains (decision 716), in ascending ID order.
    public var closedTrack: [TrackEdgeID] {
        network.closedEdges
    }

    /// Whether edge `id` is closed to trains (decision 716).
    public func isTrackClosed(_ id: TrackEdgeID) -> Bool {
        network.isClosed(id)
    }

    /// Closes edge `id` to trains (decision 716): from now on no route is
    /// found along it, and no train is placed on it or sent along it,
    /// until ``openTrack(_:)``. Free. Closing a closed edge changes
    /// nothing.
    ///
    /// - Throws: ``GameError/unknownTrackEdge(_:)``; or, with or without
    ///   traffic control, ``GameError/trackReserved(_:)`` naming the
    ///   lowest numbered train that stands on the edge, has reserved any
    ///   of it, or has it on the path it is following (see
    ///   ``trainUsing(_:)``). A rejected call changes nothing.
    public mutating func closeTrack(_ id: TrackEdgeID) throws(GameError) {
        guard network.edge(id) != nil else { throw .unknownTrackEdge(id) }
        guard !network.isClosed(id) else { return }
        if let train = trainUsing(id) { throw .trackReserved(train) }
        setTrackClosed(id, true)
    }

    /// Opens edge `id` to trains again (decision 716). Never refused for a
    /// train; opening an edge that is not closed changes nothing.
    ///
    /// - Throws: ``GameError/unknownTrackEdge(_:)``.
    public mutating func openTrack(_ id: TrackEdgeID) throws(GameError) {
        guard network.edge(id) != nil else { throw .unknownTrackEdge(id) }
        guard network.isClosed(id) else { return }
        setTrackClosed(id, false)
    }

    /// The lowest numbered train that keeps edge `id` from being closed
    /// (decision 716), or `nil`: one that stands on it (its head's edge
    /// or any its body lies on), holds a span of it in its reservation, or
    /// whose path still to follow runs along it, reserved yet or not (a
    /// train following others, Stage U2, has taken only part of its way).
    public func trainUsing(_ id: TrackEdgeID) -> TrainID? {
        trains.filter { train in
            guard train.position != nil else { return false }
            if bodyStretches(of: train).contains(where: { $0.traversal.edge == id }) { return true }
            if routeStretches(of: train).stretches.contains(where: { $0.traversal.edge == id && $0.to > $0.from }) { return true }
            return train.reservation.contains { resource in
                if case .span(let span) = resource { span.edge == id } else { false }
            }
        }.map(\.id).min()
    }

    /// The lowest numbered closed edge `train` would stand on or run along
    /// (decision 716), or `nil`: what keeps a command from placing it
    /// there or giving it that path.
    func closedTrack(under train: Train) -> TrackEdgeID? {
        guard !network.closedEdges.isEmpty, train.position != nil else { return nil }
        let body = bodyStretches(of: train).map(\.traversal.edge)
        let route = routeStretches(of: train).stretches.filter { $0.to > $0.from }.map(\.traversal.edge)
        return (body + route).filter(network.isClosed).min()
    }
}
