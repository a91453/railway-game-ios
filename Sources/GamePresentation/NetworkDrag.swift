import GameCore

// Drawing track with a finger (ARCHITECTURE decision 102, UI/UX step
// UX-1b): a one-finger drag that starts on the stretch's start, or on
// track to start from, draws the next stretch to the finger, and the
// preview (its curve, cost and problems) follows it; lifting the finger
// leaves the preview for the player to build or cancel, so nothing is
// spent until they confirm. A drag that starts anywhere else moves the
// map, as before, so navigating never picks an end (MapInteractionTests).
// The reference's editors (MapBuilder, `Simulator/`) place stations and
// pieces by tapping and dragging pieces; they draw no track, so this is
// the project's own, on the tap-to-tap builder of Stage C1.

extension GameSession {
    /// Where `anchor` stands on the plan, or `nil` for a node or edge the
    /// world no longer has.
    func planPoint(of anchor: NetworkAnchor) -> PlanPoint? {
        switch anchor {
        case .point(let point):
            return point
        case .node(let id):
            return world.network.node(id).map { PlanPoint(x: $0.position.x, y: $0.position.y) }
        case .track(let point):
            return world.trackGeometry(of: point.edge)?.location(at: point.distance).position.plan
        }
    }

    /// Whether a one-finger drag that starts at `point` draws track
    /// (decision 102) rather than moving the map: with the network tool
    /// building, when it starts within `reach` of the picked start, or of
    /// track to start from (a node, or a place on an edge, while the tool
    /// snaps to track).
    public func networkDragDraws(from point: PlanPoint, reach: Int64) -> Bool {
        guard tool == .network, networkMode == .build, world.bounds.contains(point) else { return false }
        if let start = networkStart, let at = planPoint(of: start), Self.distance(at, point) <= Double(reach) {
            return true
        }
        guard networkSnapsToTrack else { return false }
        return world.trackNode(near: point, within: reach) != nil || world.trackEdgePoint(near: point, within: reach) != nil
    }

    /// The finger, which went down at `start`, is at `end`: the stretch it
    /// draws runs from the picked start (when the drag began on it) or
    /// from the track it began on, to where the finger is (snapped to
    /// track as a tap is, see ``tapNetwork(at:reach:)``), and
    /// ``networkPreview`` shows it; back within `reach` of the start there
    /// is no stretch. Changes nothing in the world.
    public func dragNetwork(from start: PlanPoint, to end: PlanPoint, reach: Int64) {
        guard networkMode == .build else { return }
        if networkDragEndBefore == nil {
            networkDragEndBefore = .some(networkEnd)
            let onStart = networkStart.flatMap { planPoint(of: $0) }.map { Self.distance($0, start) <= Double(reach) } ?? false
            if !onStart {
                networkStart = networkAnchor(at: start, reach: reach)
            }
            message = nil
        }
        guard world.bounds.contains(end) else { return }
        // Back within reach of the start: no stretch, as tapping the start.
        if let at = networkStart.flatMap({ planPoint(of: $0) }), Self.distance(at, end) <= Double(reach) {
            networkEnd = nil
            return
        }
        let anchor = networkAnchor(at: end, reach: reach)
        networkEnd = anchor == networkStart ? nil : anchor
    }

    /// The finger lifted at `end`: the stretch stays previewed, to build
    /// with ``buildNetworkTrack()`` or to forget with
    /// ``clearNetworkDraft()``. Nothing is built or spent.
    public func endNetworkDrag(from start: PlanPoint, to end: PlanPoint, reach: Int64) {
        dragNetwork(from: start, to: end, reach: reach)
        networkDragEndBefore = nil
    }

    /// A second finger or the system took the drag: the end picked before
    /// it comes back (the start it picked stays).
    public func cancelNetworkDrag() {
        guard let before = networkDragEndBefore else { return }
        networkEnd = before
        networkDragEndBefore = nil
    }

    nonisolated static func distance(_ a: PlanPoint, _ b: PlanPoint) -> Double {
        let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
