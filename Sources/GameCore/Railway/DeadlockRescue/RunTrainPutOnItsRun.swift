// One step of the dispatcher's way out of a deadlock (decision 910: one
// step a file, in the order of `DeadlockRescueList.swift`). Moved from
// GameWorld.swift unchanged.

extension GameWorld {
    /// Decision 556, continued (TYMCLIST7): the last resort of
    /// ``resolveDeadlock(memo:)``. In the deadlock `stuck`, the first
    /// train in ID order of a line with runs (decision 133) that has no
    /// service, whose due run's first leg could take a free berth of its
    /// call against the planned way now (see
    /// ``counterflowRoute(of:to:avoiding:)``), is put on that run, as
    /// ``dispatchRuns(ofLine:)`` puts a ready train: its doors open where
    /// it stands. Once due to leave it is a service of the deadlock, which
    /// decision 571's way out sends to that berth. On the Taoyuan Airport
    /// MRT, trains that had ended their runs at one airport terminal were
    /// each bound for the berth at the other where another such train
    /// stood, with free berths beside, and waited for good: that way out
    /// was only for a service already waiting at a stop.
    ///
    /// TYMCLIST8: so too a train whose due run's first leg could take its
    /// own route now but for the track the trains following others in
    /// the deadlock wait for (decision 56, point 6): once due to leave,
    /// decision 577's way out sends it. Under the simple rules with
    /// traffic control, a train between runs at the airport's first
    /// terminal waited for an empty train following others towards it,
    /// which waited, through the others, for the berth the first stood
    /// on. Returns the train's ID, or `nil`. Never inlined, as
    /// ``departureIgnoringFollowerClaims(in:memo:)``.
    @inline(never)
    mutating func runTrainPutOnItsRun(in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DispatchMemo) -> TrainID? {
        let followers = Set(stuck.filter { !$0.value.departs }.keys)
        for id in stuck.keys.sorted() {
            guard let request = stuck[id], request.departs, let index = trains.firstIndex(where: { $0.id == id }),
                  trains[index].execution == nil,
                  let line = assignedLineIndex(of: id, known: &memo.directions.paths.trainLines), lines[line].hasRuns,
                  let due = dueRun(of: trains[index], on: lines[line], memo: &memo.directions),
                  case .travellingToStop(let stop, let cycle)? = request.candidate.execution
            else { continue }
            // TYMCLIST8: or, once on its run, decision 577's way out would
            // send it along its own route.
            var goes = false
            if let way = counterflowRoute(of: request.candidate, to: request.candidate.timetable[stop].station,
                                          avoiding: blockedTrack(except: id, holders: trackHolders(memo: &memo.directions))),
               case .granted = reserving(rerouted(request.candidate, along: way, stop: stop, cycle: cycle), memo: &memo.directions) {
                goes = true
            } else if !followers.isEmpty, case .granted? = reserving(request.candidate, ignoringClaimsOf: followers, memo: &memo.directions) {
                goes = true
            }
            guard goes else { continue }
            trains[index].trafficVisits = []
            trains[index].timetable = due.timetable
            trains[index].timetablePeriod = nil
            trains[index].execution = .waitingAtStop(0)
            trains[index].isStandingAside = false
            trains[index].times = ServiceTimes(arrival: clock.now)
            logArrival(of: index)
            lines[line].runDays[due.run] = due.day
            return id
        }
        return nil
    }
}
