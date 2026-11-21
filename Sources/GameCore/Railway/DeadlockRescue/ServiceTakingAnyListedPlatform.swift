// One step of the dispatcher's way out of a deadlock (decision 910: one
// step a file, in the order of `DeadlockRescueList.swift`). Moved from
// GameWorld.swift unchanged.

extension GameWorld {
    /// Decision 740: a service whose leg's list of platforms keeps it in
    /// the deadlock stops, this once, at any platform it can take.
    ///
    /// Returns the train's ID, or `nil`. Never inlined, as
    /// ``departureIgnoringFollowerClaims(in:memo:)``.
    @inline(never)
    mutating func serviceTakingAnyListedPlatform(in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DispatchMemo) -> TrainID? {
        for id in stuck.keys.sorted() {
            guard let request = stuck[id], request.departs,
                  listedDepartures(of: request.candidate, memo: &memo.directions.paths) != nil,
                  let index = trains.firstIndex(where: { $0.id == id }),
                  case .waitingAtStop(let stop, _)? = trains[index].execution,
                  case .granted(let granted) = takingAnyDeparture(request.candidate, memo: &memo.directions),
                  turnOwed(by: granted, memo: &memo.directions) == nil
            else { continue }
            setOff(index, as: granted)
            serve(departureOf: id, from: stop, distance: routeLength(of: granted))
            return id
        }
        return nil
    }
}
