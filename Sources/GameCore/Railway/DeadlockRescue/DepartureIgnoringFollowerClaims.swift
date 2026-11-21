// One step of the dispatcher's way out of a deadlock (decision 910: one
// step a file, in the order of `DeadlockRescueList.swift`). Moved from
// GameWorld.swift unchanged.

extension GameWorld {
    /// Decision 577: the last resort of ``resolveDeadlock(memo:)``. In the
    /// deadlock `stuck`, the first service in ID order due to leave whose
    /// route only the track the trains following others there wait for
    /// (decision 56, point 6) keeps it from takes its route whole and sets
    /// off. Such a claim reaches as far as the follower's route goes,
    /// against the way of the trains it crosses as well: an empty train
    /// bound for the Taoyuan Airport MRT's Luzhu depot, still past Linkou
    /// behind trains that waited for the service, kept it from leaving
    /// Kengkou over the track the empty train would cross into the depot.
    /// Returns the train's ID, or `nil`. Never inlined: in the deadlock
    /// path alone, its locals stay off the stack of every tick, which a
    /// WebAssembly build's small stack cannot spare.
    @inline(never)
    mutating func departureIgnoringFollowerClaims(in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DispatchMemo) -> TrainID? {
        let followers = Set(stuck.filter { !$0.value.departs }.keys)
        guard !followers.isEmpty else { return nil }
        for id in stuck.keys.sorted() {
            guard let request = stuck[id], request.departs, let index = trains.firstIndex(where: { $0.id == id }),
                  case .waitingAtStop(let left, _)? = trains[index].execution,
                  let due = departureDue(of: trains[index]), due <= clock.now,
                  case .travellingToStop? = request.candidate.execution,
                  case .granted(let granted)? = reserving(request.candidate, ignoringClaimsOf: followers, memo: &memo.directions)
            else { continue }
            setOff(index, as: granted)
            serve(departureOf: id, from: left, distance: routeLength(of: granted))
            return id
        }
        return nil
    }
}
