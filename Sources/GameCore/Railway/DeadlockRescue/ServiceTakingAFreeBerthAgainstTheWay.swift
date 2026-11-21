// One step of the dispatcher's way out of a deadlock (decision 910: one
// step a file, in the order of `DeadlockRescueList.swift`). Moved from
// GameWorld.swift unchanged.

extension GameWorld {
    /// Decision 571, continued: with nothing else to do, a service due
    /// to leave takes a free berth of its next call against the planned
    /// way (see ``counterflowRoute(of:to:avoiding:)``), taken whole. On a
    /// double track whose crossovers let each way into one berth at
    /// each end, two trains each standing on the berth the other is
    /// bound for waited for each other all day.
    ///
    /// Returns the train's ID, or `nil`. Never inlined, as
    /// ``departureIgnoringFollowerClaims(in:memo:)``.
    @inline(never)
    mutating func serviceTakingAFreeBerthAgainstTheWay(in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DispatchMemo) -> TrainID? {
        for id in stuck.keys.sorted() {
            guard let request = stuck[id], request.departs, let index = trains.firstIndex(where: { $0.id == id }),
                  case .waitingAtStop(let left, _)? = trains[index].execution,
                  let due = departureDue(of: trains[index]), due <= clock.now,
                  case .travellingToStop(let stop, let cycle)? = request.candidate.execution,
                  let way = counterflowRoute(of: request.candidate, to: request.candidate.timetable[stop].station,
                                             avoiding: blockedTrack(except: id, holders: trackHolders(memo: &memo.directions))),
                  case .granted(let granted) = reserving(rerouted(request.candidate, along: way, stop: stop, cycle: cycle), memo: &memo.directions)
            else { continue }
            setOff(index, as: granted)
            serve(departureOf: id, from: left, distance: way.distance)
            return id
        }
        return nil
    }
}
