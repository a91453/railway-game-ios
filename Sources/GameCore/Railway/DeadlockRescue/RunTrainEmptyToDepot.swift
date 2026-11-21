// One step of the dispatcher's way out of a deadlock (decision 910: one
// step a file, in the order of `DeadlockRescueList.swift`). Moved from
// GameWorld.swift unchanged.

extension GameWorld {
    /// Decision 556, continued (TYMCLIST8): the last resort of
    /// ``resolveDeadlock(memo:)``, after ``runTrainPutOnItsRun(in:memo:)``.
    /// In the deadlock `stuck`, the first train in ID order of a line with
    /// runs and depots (decision 221) that has no service, stands outside
    /// them and waits for its due run at a stop another of them is bound
    /// for (alone, it would only come out again), runs empty into the first of its
    /// line's depots, in the order the line lists them, that has a siding
    /// for it (decision 280) and whose way it can take now, as
    /// ``runTrainEnteringDepot(of:memo:)`` sends a train in: the berth it
    /// leaves is free for the others. Its run is left to another train, or
    /// to one out of a depot. On the Taoyuan Airport MRT under the
    /// realistic rules, the three berths of each airport terminal held
    /// trains all bound for the other, those at the second between runs,
    /// with no free berth for decision 571's way out. Returns the train's
    /// ID, or `nil`. Never inlined, as
    /// ``departureIgnoringFollowerClaims(in:memo:)``.
    @inline(never)
    mutating func runTrainEmptyToDepot(in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DispatchMemo) -> TrainID? {
        for id in stuck.keys.sorted() {
            guard let request = stuck[id], request.departs, let index = trains.firstIndex(where: { $0.id == id }),
                  trains[index].execution == nil,
                  let line = assignedLine(of: id, memo: &memo.directions), line.hasRuns, !line.depots.isEmpty,
                  !isInDepot(trains[index], of: line)
            else { continue }
            let standing = Set(stationsStoppedAt(by: id))
            guard stuck.contains(where: { other in
                other.key != id && other.value.candidate.timetable.dropFirst().contains { standing.contains($0.station) }
            }) else { continue }
            for depot in line.depots {
                guard let trip = emptyRun(of: line, for: trains[index], to: [depot]), depotHasRoom(depot, for: trains[index]),
                      let leaving = firstDeparture(of: trains[index], on: trip, calling: line.stops),
                      case .granted = reservingDeparture(leaving, memo: &memo.directions),
                      let timetable = trip.timetable(calling: line.stops, sentOutAt: clock.now)
                else { continue }
                trains[index].trafficVisits = []
                trains[index].timetable = timetable
                trains[index].timetablePeriod = nil
                trains[index].execution = .waitingAtStop(0)
                trains[index].isDeadheading = true
                trains[index].isStandingAside = false
                trains[index].times = ServiceTimes(arrival: clock.now)
                logArrival(of: index)
                return id
            }
        }
        return nil
    }
}
