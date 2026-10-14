// Why a line's train is not being sent out (TestFlight 60.1: "assigned
// trains never leave"). Read-only: it asks the same questions dispatching
// asks (``GameWorld/readyTrip(of:on:_:memo:)``,
// ``GameWorld/isDispatchDue(_:_:at:deadhead:memo:)`` and, under traffic
// control, the route of the first departure) and changes nothing.

/// Why a train assigned to a line waits instead of being sent out, from
/// ``GameWorld/lineDispatchHold(of:)``.
public enum LineDispatchHold: Hashable, Sendable {
    /// Not on the track: the line can only send out a placed train.
    case notPlaced(firstStop: StationID)
    /// Stopped by the player (its rate is 0).
    case stopped
    /// Not stopped at its service's first call, and flexible dispatch is
    /// off, so the line will not send it from where it stands.
    case awayFromFirstStop(firstStop: StationID)
    /// Where it stands, it cannot drive the whole round trip.
    case noRoundTrip(firstStop: StationID)
    /// Its service already runs as many trains as it plans to now:
    /// `running` of `planned` (the service's count at this level, after
    /// headway and capacity).
    case serviceFull(running: Int, planned: Int)
    /// Under traffic control, the route of its first departure is taken.
    case routeHeld
}

extension GameWorld {
    /// Why train `id`, assigned to a line and without a service, is not
    /// sent out now, or `nil` when nothing holds it beyond the next
    /// headway slot, or when it is not a line's waiting train, its line
    /// runs to timed runs (decision 133), it stands in its line's depot
    /// (decision 209), or the line's window is closed or its service
    /// cannot be planned (the caller says when the line opens).
    ///
    /// Checked in the order dispatching checks: where the train is, whether
    /// the service has room for it, then its route.
    public func lineDispatchHold(of id: TrainID) -> LineDispatchHold? {
        guard let train = train(id: id), train.execution == nil,
              let line = lines.first(where: { $0.assignedTrains.contains(id) }), !line.hasRuns,
              let stream = line.dispatchStream(of: id)
        else { return nil }
        let firstStop = line.stops[line.calls(ofService: stream.service)[0]]
        guard train.position != nil else { return .notPlaced(firstStop: firstStop) }
        guard train.movement.rate > 0 else { return .stopped }
        guard !isInDepot(train, of: line) else { return nil }
        var memo = DispatchMemo()
        guard let trip = readyTrip(of: train, on: line, stream.service, memo: &memo) else {
            return !flexDispatch && !isStopped(train, at: firstStop)
                ? .awayFromFirstStop(firstStop: firstStop)
                : .noRoundTrip(firstStop: firstStop)
        }
        let now = clock.now
        guard isDispatchDue(line, stream, at: now, deadhead: trip.deadhead != nil, memo: &memo) else {
            guard let planned = plannedService(of: line, stream.service, at: now, memo: &memo) else { return nil }
            let room = stream.direction == nil ? planned.trains : planned.trains / 2
            let running = runningTrains(of: line, stream)
            return running >= room ? .serviceFull(running: running, planned: planned.trains) : nil
        }
        if isTrafficControlEnabled, let leaving = firstDeparture(of: train, on: trip, calling: line.stops),
           case .held = reservingDeparture(leaving, memo: &memo.directions) {
            return .routeHeld
        }
        return nil
    }
}
