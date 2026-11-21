// One step of the dispatcher's way out of a deadlock (decision 910: one
// step a file, in the order of `DeadlockRescueList.swift`). Moved from
// GameWorld.swift unchanged.

extension GameWorld {
    /// Decision 556, continued (TYMCLIST9): decision 571's way out
    /// (``counterflowRoute(of:to:avoiding:)``) for the first service in ID
    /// order of deadlock `stuck`, of a line with runs (decision 133), that
    /// stands aside at a passing place (Stage V2): it takes a free berth
    /// of its call against the planned way, its way there taken whole. On
    /// the Taoyuan Airport MRT under the realistic rules, the last train
    /// of the night stood aside at Airport Hotel bound for the first
    /// airport terminal, behind a service at the second bound for the
    /// berth a train between runs stood on; two of the terminal's three
    /// berths were free, and the trains between runs at the second
    /// terminal, bound for Qingpu depot, waited for the one at the hotel,
    /// all night. Only for lines with runs, as
    /// ``serviceStandingAsideAnyWay(in:memo:)``. Returns the train's ID,
    /// or `nil`. Never inlined, as
    /// ``departureIgnoringFollowerClaims(in:memo:)``.
    @inline(never)
    mutating func standingAsideServiceTakingAFreeBerth(in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DispatchMemo) -> TrainID? {
        for id in stuck.keys.sorted() {
            guard let request = stuck[id], request.departs, let index = trains.firstIndex(where: { $0.id == id }),
                  isAtPassingPlace(trains[index]), assignedLine(of: id, memo: &memo.directions)?.hasRuns == true,
                  case .travellingToStop(let stop, let cycle)? = request.candidate.execution,
                  let way = counterflowRoute(of: request.candidate, to: request.candidate.timetable[stop].station,
                                             avoiding: blockedTrack(except: id, holders: trackHolders(memo: &memo.directions))),
                  case .granted(let granted) = reserving(rerouted(request.candidate, along: way, stop: stop, cycle: cycle), memo: &memo.directions)
            else { continue }
            setOff(index, as: granted)
            return id
        }
        return nil
    }
}
