// One step of the dispatcher's way out of a deadlock (decision 910: one
// step a file, in the order of `DeadlockRescueList.swift`). Moved from
// GameWorld.swift unchanged.

extension GameWorld {
    /// A later fix to decision 58: with no service to step aside, a
    /// line's spare in the way of the deadlock `stuck` steps aside instead
    /// (see ``spareStandingAside(in:memo:)``).
    /// Returns the train's ID, or `nil`. Never inlined, as
    /// ``departureIgnoringFollowerClaims(in:memo:)``.
    @inline(never)
    mutating func spareSteppingAside(in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DispatchMemo) -> TrainID? {
        if let aside = spareStandingAside(in: stuck, memo: &memo.directions),
           let index = trains.firstIndex(where: { $0.id == aside.id }) {
            trains[index] = aside
            // A train of a line with runs stands aside at its own station
            // (decision 212), where its next run finds it.
            trains[index].isStandingAside = assignedLine(of: aside.id, memo: &memo.directions)?.hasRuns != true
            return aside.id
        }
        return nil
    }
}
