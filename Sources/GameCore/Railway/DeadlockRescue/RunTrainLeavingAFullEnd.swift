// One step of the dispatcher's way out of a deadlock (decision 910: one
// step a file, in the order of `DeadlockRescueList.swift`). Moved from
// GameWorld.swift unchanged.

extension GameWorld {
    /// Decision 816: the last resort of ``resolveDeadlock(memo:)``, after
    /// decision 808's. With nothing else to do in the deadlock `stuck`, a
    /// train between runs of a line with runs and no depot, on track a
    /// train of the deadlock waits for, runs empty to another stop of its
    /// line with a free berth (see ``runTrainToAnotherEnd(in:memo:)``),
    /// where its line sends it out on a run as from any stop. Returns its
    /// ID, or `nil`. Never inlined, as
    /// ``departureIgnoringFollowerClaims(in:memo:)``.
    @inline(never)
    mutating func runTrainLeavingAFullEnd(in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DispatchMemo) -> TrainID? {
        guard let (index, line, trip) = runTrainToAnotherEnd(in: stuck, memo: &memo),
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
