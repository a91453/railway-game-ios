// Closing track by hand (decision 716). The player closes edges of the
// track network to trains, for as long as they like, and opens them again.
//
// 1. Edges no train uses are closed at once. Edges a train stands on, has
//    reserved any of, or is on its way along are being closed instead
//    (decision 716, continued), together with the edges closed with them
//    and any being closed they join at a node: nothing is refused for a
//    train.
// 2. While an edge is closed no route is found along it
//    (``GameWorld/path(from:toStation:length:)`` and every search built on
//    it, ``GameWorld/route(from:to:)``), so nothing reserves it, and no
//    command places a train on it or sends one along it. Where another
//    way serves (a passing loop, the other track) services take it as
//    their default way; where none does, a service waits at its stop as
//    one without a route does, and a line plans no journey over it.
// 3. While an edge is being closed it is the same to every search and
//    command, but for a train that starts on track being closed: it runs
//    out along it. A train already on its way keeps the path it has, and
//    one following others goes on taking that path a part at a time
//    (``GameWorld/extendAuthorities()`` searches nothing).
// 4. At a step, edges being closed that join one another and that no train
//    uses any more are closed (``GameWorld/closeTrackTrainsHaveLeft()``).
// 5. Opening is never refused, closed or being closed. The next step finds
//    the routes again.
//
// Both lists are kept on the network (``RailwayNetwork/closedEdges``,
// ``RailwayNetwork/closingEdges``), beside its platforms: everything
// traffic control keeps between steps is kept for the network as it is, so
// a closure starts it again. Nothing here reads geometry or the clock.

extension GameWorld {
    /// The edges closed to trains (decision 716), in ascending ID order.
    public var closedTrack: [TrackEdgeID] {
        network.closedEdges
    }

    /// The edges being closed (decision 716, continued), in ascending ID
    /// order: closed once the trains using them have left.
    public var closingTrack: [TrackEdgeID] {
        network.closingEdges
    }

    /// Whether edge `id` is closed to trains (decision 716).
    public func isTrackClosed(_ id: TrackEdgeID) -> Bool {
        network.isClosed(id)
    }

    /// Whether edge `id` is being closed (decision 716, continued): no new
    /// route runs along it, and it is closed once no train uses it.
    public func isTrackClosing(_ id: TrackEdgeID) -> Bool {
        network.isClosing(id)
    }

    /// Closes edge `id` to trains (decision 716): ``closeTrack(_:)-([TrackEdgeID])``
    /// of that edge alone.
    public mutating func closeTrack(_ id: TrackEdgeID) throws(GameError) {
        try closeTrack([id])
    }

    /// Closes the edges `ids` to trains together (decision 716): from now
    /// on no route is found along them, and no train is placed on them or
    /// sent along them, until ``openTrack(_:)``. Free. With no train using
    /// any of them (see ``trainUsing(_:)``) they are closed at once.
    /// Otherwise all of them are being closed: the trains standing on
    /// them, holding them or on their way along them run on, a train on
    /// them finds its way out along them, and at the step after which no
    /// train uses any of them, nor any edge being closed that joins them,
    /// they are closed. Closed edges among `ids` stay closed; closing
    /// again changes nothing.
    ///
    /// - Throws: ``GameError/unknownTrackEdge(_:)`` for the first of `ids`
    ///   that is no edge. A rejected call changes nothing.
    public mutating func closeTrack(_ ids: [TrackEdgeID]) throws(GameError) {
        for id in ids {
            guard network.edge(id) != nil else { throw .unknownTrackEdge(id) }
        }
        let new = ids.filter { network.closure(of: $0) == .open }
        guard !new.isEmpty else { return }
        for id in new {
            setTrackClosure(id, .closing)
        }
        closeTrackTrainsHaveLeft()
    }

    /// Opens edge `id` to trains again (decision 716), closed or being
    /// closed. Never refused for a train; opening an open edge changes
    /// nothing.
    ///
    /// - Throws: ``GameError/unknownTrackEdge(_:)``.
    public mutating func openTrack(_ id: TrackEdgeID) throws(GameError) {
        guard network.edge(id) != nil else { throw .unknownTrackEdge(id) }
        guard network.closure(of: id) != .open else { return }
        setTrackClosure(id, .open)
    }

    /// The lowest numbered train that uses edge `id` (decision 716), or
    /// `nil`: one that stands on it (its head's edge or any its body lies
    /// on), holds a span of it in its reservation, or whose path still to
    /// follow runs along it, reserved yet or not (a train following
    /// others, Stage U2, has taken only part of its way). Track such a
    /// train uses is closed only after it has left.
    public func trainUsing(_ id: TrackEdgeID) -> TrainID? {
        trains.filter { edgesUsed(by: $0).contains(id) }.map(\.id).min()
    }

    /// The edges `train` uses (see ``trainUsing(_:)``).
    private func edgesUsed(by train: Train) -> Set<TrackEdgeID> {
        guard train.position != nil else { return [] }
        var edges = Set(bodyStretches(of: train).map(\.traversal.edge))
        edges.formUnion(routeStretches(of: train).stretches.filter { $0.to > $0.from }.map(\.traversal.edge))
        for resource in train.reservation {
            if case .span(let span) = resource { edges.insert(span.edge) }
        }
        return edges
    }

    /// Decision 716, continued: closes the edges being closed that no
    /// train uses any more, a group at a time: the edges being closed
    /// that join one another at their nodes are closed together, once no
    /// train uses any of them, so that a train standing on one still has
    /// its way out. Returns whether any was closed. Reads the trains and
    /// the network only.
    @discardableResult
    mutating func closeTrackTrainsHaveLeft() -> Bool {
        let closing = network.closingEdges
        guard !closing.isEmpty else { return false }
        var used: Set<TrackEdgeID> = []
        for train in trains {
            used.formUnion(edgesUsed(by: train))
        }
        // The groups, each from its lowest numbered edge.
        var grouped: Set<TrackEdgeID> = []
        var changed = false
        for first in closing where !grouped.contains(first) {
            var group = [first]
            grouped.insert(first)
            var next = 0
            while next < group.count {
                let edge = network.edge(group[next])!
                next += 1
                for node in [edge.from, edge.to] {
                    for end in network.node(node)?.ends ?? [] where network.isClosing(end.edge) && !grouped.contains(end.edge) {
                        grouped.insert(end.edge)
                        group.append(end.edge)
                    }
                }
            }
            guard !group.contains(where: used.contains) else { continue }
            for id in group {
                setTrackClosure(id, .closed)
            }
            changed = true
        }
        return changed
    }

    /// The lowest numbered edge `candidate` would stand on or run along
    /// that is closed, or being closed (decision 716), or `nil`: what
    /// keeps a command from placing it there or giving it that path.
    /// `current`, the train as it is, standing on track being closed may
    /// still be moved or sent along such track: it is on its way out.
    func closedTrack(under candidate: Train, now current: Train) -> TrackEdgeID? {
        guard !network.closedEdges.isEmpty || !network.closingEdges.isEmpty, candidate.position != nil else { return nil }
        let leaving = !network.closingEdges.isEmpty && bodyStretches(of: current).contains { network.isClosing($0.traversal.edge) }
        let body = bodyStretches(of: candidate).map(\.traversal.edge)
        let route = routeStretches(of: candidate).stretches.filter { $0.to > $0.from }.map(\.traversal.edge)
        return (body + route).filter { network.isClosed($0) || !leaving && network.isClosing($0) }.min()
    }
}
