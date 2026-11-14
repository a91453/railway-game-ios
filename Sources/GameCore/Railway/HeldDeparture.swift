// Trains held where they stand by something other than a train in their
// way (decision 497, P2-7): a service due to leave a stop with no way to
// its next call (decision 204), and a train its line would send into a
// depot whose sidings are all taken (decision 280). The deadlock search
// counts both as trains that will go, so a train waiting for one of them
// is never reported as deadlocked, yet neither moves until the track or
// the depot changes. Read-only: nothing here changes what the dispatcher
// does.

/// Why a train stands where it is although its departure is due (see
/// ``GameWorld/heldDeparture(of:)``).
public enum HeldDeparture: Hashable, Sendable {
    /// Its service is due to leave and no way leads on to the next call,
    /// at station `to`.
    case noRoute(to: StationID)
    /// Its line would send it into depot `depot`, whose sidings it fits
    /// are all taken or spoken for.
    case depotFull(StationID)
}

extension GameWorld {
    /// Why train `id` stands where it is although it is due to go (decision
    /// 497, P2-7), or `nil`: its service is due to leave a stop and has no
    /// way to the next call (``HeldDeparture/noRoute(to:)``, decision 204),
    /// or, under traffic control, its line would send it into a depot now
    /// but no siding there is left for it (``HeldDeparture/depotFull(_:)``,
    /// decision 280). Derived on every call, never saved.
    public func heldDeparture(of id: TrainID) -> HeldDeparture? {
        guard let train = train(id: id) else { return nil }
        var memo = questionMemo()
        if let station = stranding(train, memo: &memo) { return .noRoute(to: station) }
        var dispatch = DispatchMemo()
        return waitsForDepotRoom(train, memo: &dispatch).map(HeldDeparture.depotFull)
    }

    /// ``heldDeparture(of:)`` of every train that has one, worked out
    /// together for a map to draw at once: each line's depot candidates
    /// once, not once a train.
    public func heldDepartures() -> [TrainID: HeldDeparture] {
        var held: [TrainID: HeldDeparture] = [:]
        var memo = questionMemo()
        for train in trains {
            if let station = stranding(train, memo: &memo) { held[train.id] = .noRoute(to: station) }
        }
        guard isTrafficControlEnabled else { return held }
        var dispatch = DispatchMemo()
        for line in lines where !line.depots.isEmpty {
            for index in depotCandidates(of: line, memo: &dispatch) where held[trains[index].id] == nil {
                if let depot = fullDepot(for: trains[index], of: line, memo: &dispatch) { held[trains[index].id] = .depotFull(depot) }
            }
        }
        return held
    }

    /// Decision 735: the trains standing at a stop half an hour or more
    /// after the departure their timetable gives, doors closed, that ask
    /// for no way on at all (``departureRequest(of:memo:)`` has none) and
    /// wait for no train by the traffic plan: no route held by another
    /// train keeps them there, so ``deadlockedTrains()`` never names them,
    /// yet they never leave by themselves (the Western Trunk Line train at
    /// Badu, 37 hours). By ascending ID. What the reports count; the map's
    /// bubble for such a train is ``heldDeparture(of:)``'s. Derived on
    /// every call, never saved.
    public func strandedTrains() -> [TrainID] {
        var memo = questionMemo()
        return trains.filter { isStrandedLong($0, memo: &memo) }.map(\.id).sorted()
    }

    /// How long after its timetabled departure a train standing with no
    /// way asked for counts in ``strandedTrains()``: half an hour, longer
    /// than any wait for a meeting or a late train it waits for.
    public static let strandedAfter: Int64 = 1_800

    /// See ``strandedTrains()``.
    func isStrandedLong(_ train: Train, memo: inout DirectionMemo) -> Bool {
        guard case .waitingAtStop(let stop, let cycle)? = train.execution, train.position != nil,
              clock.now >= Self.saturating(train.scheduledDeparture(of: stop, cycle: cycle), plus: Self.strandedAfter),
              let due = departureDue(of: train), due <= clock.now,
              currentTrafficWait(train, plan: trafficPlan(memo: &memo), memo: &memo) == nil else { return false }
        return departureRequest(of: train, memo: &memo) == nil
    }

    /// The station of the next call `train` is due to leave for and has no
    /// way to (see ``isStranded(_:memo:)``), or `nil`.
    private func stranding(_ train: Train, memo: inout DirectionMemo) -> StationID? {
        guard isStranded(train, memo: &memo), case .waitingAtStop(let stop, let cycle)? = train.execution,
              let next = train.call(after: stop, cycle: cycle) else { return nil }
        return train.timetable[next.stop].station
    }

    /// The depot `train`'s line would send it into now but has no siding
    /// left for it (decision 280), or `nil`: only under traffic control,
    /// where a train waits for one; without it, the train goes in anyway.
    func waitsForDepotRoom(_ train: Train, memo: inout DispatchMemo) -> StationID? {
        guard isTrafficControlEnabled, train.execution == nil, let lineID = assignedLine(of: train.id),
              let line = line(id: lineID), !line.depots.isEmpty,
              let index = trains.firstIndex(where: { $0.id == train.id }),
              depotCandidates(of: line, memo: &memo).contains(index) else { return nil }
        return fullDepot(for: train, of: line, memo: &memo)
    }

    /// The trains of `line` it would send into a depot now, by index (see
    /// ``depotEntryCandidates(of:_:memo:)`` and
    /// ``runDepotEntryCandidates(of:memo:)``).
    private func depotCandidates(of line: ServiceLine, memo: inout DispatchMemo) -> [Int] {
        if line.hasRuns { return runDepotEntryCandidates(of: line, memo: &memo) }
        return line.dispatchStreams.flatMap { depotEntryCandidates(of: line, $0, memo: &memo) }
    }

    /// The depot of `line` that `train`'s empty run would go to, when it
    /// has no siding left for it (see ``depotHasRoom(_:for:)``).
    private func fullDepot(for train: Train, of line: ServiceLine, memo: inout DispatchMemo) -> StationID? {
        guard let depot = emptyRun(of: line, for: train, to: line.depots)?.deadhead?.to,
              !depotHasRoom(depot, for: train) else { return nil }
        // Decision 556, continued (TYMCLIST9): a line with runs sends a
        // train in a waiting service's way into another depot with room
        // instead, when it can reach one (``otherDepotRun(of:for:besides:memo:)``).
        if otherDepotRun(of: line, for: train, besides: depot, memo: &memo.directions) != nil { return nil }
        return depot
    }
}
