// Curve speed limits on the running side (ARCHITECTURE decision 217): the
// world's switch, and the limits a run or a planned leg meets on its way
// (``CurveSpeedLimit``, ``LimitedRunningCurve``).

extension GameWorld {
    /// Turns the curve speed limits on or off (decision 217). A train
    /// already on its way keeps its run; the next one that sets off, and
    /// the next timetable a line plans, keep to them.
    public mutating func setCurveSpeedLimits(_ enabled: Bool) {
        guard enabled != curveSpeedLimits else { return }
        curveSpeedLimits = enabled
        passengerPlan = PassengerPlanCache()
        passengerRouteMemo = PassengerRouteMemo()
        routeMemo = RouteMemo()
    }

    /// The curve speed limits a run of `train` meets over its next
    /// `distance` world units, from where its head is, along the rest of
    /// its path (see ``RailwayNetwork/speedLimits(from:offset:through:distance:trailing:)``),
    /// held for its length: empty with ``curveSpeedLimits`` off.
    func speedLimitsAhead(of train: Train, distance: Int64) -> [TrackSpeedLimit] {
        guard curveSpeedLimits, case .onEdge(let first, let offset)? = train.position else { return [] }
        var traversals: [TrackTraversal] = []
        var node = network.edge(first.edge)?.end(of: first.direction)
        for id in train.movement.remainingEdges {
            guard let at = node, let traversal = network.edge(id)?.traversal(leaving: at) else { break }
            traversals.append(traversal)
            node = network.edge(id)?.end(of: traversal.direction)
        }
        return network.speedLimits(from: first, offset: offset, through: traversals, distance: distance, trailing: train.length,
                                   below: train.performance.topSpeed)
    }

    /// The curve speed limits below `topSpeed` a train `placement` meets
    /// along `path`: empty with ``curveSpeedLimits`` off.
    func speedLimits(from placement: TrainPlacement, along path: TrainPath, below topSpeed: Int64) -> [TrackSpeedLimit] {
        guard curveSpeedLimits, case .onEdge(let first, let offset) = placement.position else { return [] }
        return network.speedLimits(from: first, offset: offset, through: path.traversals, distance: path.distance, trailing: placement.length,
                                   below: topSpeed)
    }

    /// Whether `train` serves a line of real runs (decision 133), whose
    /// timetable the curve limits never make it late for.
    func followsRealTimetable(_ train: Train) -> Bool {
        lines.contains { !$0.runs.isEmpty && $0.trains.contains(train.id) }
    }
}
