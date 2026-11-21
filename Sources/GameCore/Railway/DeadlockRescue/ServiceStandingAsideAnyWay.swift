// One step of the dispatcher's way out of a deadlock (decision 910: one
// step a file, in the order of `DeadlockRescueList.swift`). Moved from
// GameWorld.swift unchanged.

extension GameWorld {
    /// Decision 556, continued (TYMCLIST8): the very last resort of
    /// ``resolveDeadlock(memo:)``. As its first way out, the first service
    /// in ID order of deadlock `stuck`, of a line with runs (decision
    /// 133), due to leave or at a passing place sets off for a passing place where its standing lets another of
    /// them go, but one found against the planned directions and however
    /// far round (``passingPlace(for:in:anyWay:memo:)``), its way there
    /// taken whole. On the Taoyuan Airport MRT under the simple rules with
    /// traffic control, Kengkou's two berths held trains bound for the
    /// first airport terminal, and two of the terminal's three held trains
    /// bound for Kengkou, its third behind a train in the way: one of
    /// those at the terminal backs out to a free berth of the second,
    /// and comes back. Returns the train's ID, or `nil`. Never inlined, as
    /// ``departureIgnoringFollowerClaims(in:memo:)``.
    @inline(never)
    mutating func serviceStandingAsideAnyWay(in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DispatchMemo) -> TrainID? {
        for id in stuck.keys.sorted() {
            guard let request = stuck[id], request.departs, let index = trains.firstIndex(where: { $0.id == id }),
                  trains[index].execution != nil, assignedLine(of: id, memo: &memo.directions)?.hasRuns == true,
                  let passing = passingPlace(for: request.candidate, in: stuck, anyWay: true, memo: &memo.directions)
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
