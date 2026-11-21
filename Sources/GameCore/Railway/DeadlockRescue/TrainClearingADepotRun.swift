// One step of the dispatcher's way out of a deadlock (decision 910: one
// step a file, in the order of `DeadlockRescueList.swift`). Moved from
// GameWorld.swift unchanged.

extension GameWorld {
    /// Decision 808: the last resort of ``resolveDeadlock(memo:)``. With
    /// nothing else to do in the deadlock `stuck`, a train between runs
    /// that holds track of the empty run a train in the way would make
    /// into a depot (see ``depotRunClearing(memo:)``) runs empty into a
    /// depot with a siding for it itself, as its line sends a train in.
    /// Returns its ID, or `nil`. Never inlined, as
    /// ``departureIgnoringFollowerClaims(in:memo:)``.
    @inline(never)
    mutating func trainClearingADepotRun(in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DispatchMemo) -> TrainID? {
        guard !stuck.isEmpty, let (index, line, trip) = depotRunClearing(memo: &memo), stuck[trains[index].id] == nil,
              let timetable = trip.timetable(calling: line.stops, sentOutAt: clock.now)
        else { return nil }
        trains[index].trafficVisits = []
        trains[index].timetable = timetable
        trains[index].timetablePeriod = nil
        trains[index].execution = .waitingAtStop(0)
        trains[index].isDeadheading = true
        trains[index].isStandingAside = false
        trains[index].times = ServiceTimes(arrival: clock.now)
        logArrival(of: index)
        return trains[index].id
    }
}
