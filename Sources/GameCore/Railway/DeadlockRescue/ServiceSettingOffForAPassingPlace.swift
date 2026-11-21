// One step of the dispatcher's way out of a deadlock (decision 910: one
// step a file, in the order of `DeadlockRescueList.swift`). Moved from
// GameWorld.swift unchanged.

extension GameWorld {
    /// Stage V2 (ARCHITECTURE decision 58): of the trains in the deadlock
    /// `stuck`, the first in ID order whose service is due to leave a stop,
    /// or is stopped at a passing place, and that has a passing place
    /// letting another of them go (see ``passingPlace(for:in:memo:)``)
    /// sets off for it, taking the way there whole, as fast as it can.
    /// Returns the train's ID, or `nil`. Never inlined, as
    /// ``departureIgnoringFollowerClaims(in:memo:)``.
    @inline(never)
    mutating func serviceSettingOffForAPassingPlace(in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DispatchMemo) -> TrainID? {
        for id in stuck.keys.sorted() {
            guard let request = stuck[id], request.departs, let index = trains.firstIndex(where: { $0.id == id }),
                  trains[index].execution != nil,
                  let passing = passingPlace(for: request.candidate, in: stuck, memo: &memo.directions)
            else { continue }
            var aside = request.candidate
            if passing.reverses, let place = aside.placement {
                let reverse = turnedRound(place)
                aside.position = reverse.position
                aside.trailEdges = reverse.trailEdges
            }
            follow(passing.path, &aside)
            let fastest = run(of: aside, length: passing.path.distance)
            aside.times?.run = fastest
            guard case .granted(let granted) = reserving(aside, memo: &memo.directions) else { continue }
            let left: Int? = if case .waitingAtStop(let stop, _)? = trains[index].execution { stop } else { nil }
            setOff(index, as: granted)
            if let left {
                serve(departureOf: id, from: left, distance: passing.distance)
            }
            return id
        }
        return nil
    }
}
