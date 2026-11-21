// One step of the dispatcher's way out of a deadlock (decision 910: one
// step a file, in the order of `DeadlockRescueList.swift`). Moved from
// GameWorld.swift unchanged.

extension GameWorld {
    /// Decision 255: with no passing place and no spare to move, a
    /// service due to leave turns back short where it waits: a call
    /// made again there, its doors opening again as at any arrival.
    /// Those riding to the calls it leaves out get off, abandoned, and
    /// those waiting there for its way back get on, as at any call. It
    /// runs nowhere, so no departure is counted.
    /// Decision 288, a later fix (Codex's review of #823, R2): the
    /// doors open and the riders change as at any arrival, once its
    /// doors have opened (``stepDwell(_:at:memo:)``), not at once: a
    /// save in the seconds before they have opened loads again.
    ///
    /// Returns the train's ID, or `nil`. Never inlined, as
    /// ``departureIgnoringFollowerClaims(in:memo:)``.
    @inline(never)
    mutating func serviceTurningBackShort(in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DispatchMemo) -> TrainID? {
        for id in stuck.keys.sorted() {
            guard let index = trains.firstIndex(where: { $0.id == id }),
                  case .waitingAtStop? = trains[index].execution,
                  let due = departureDue(of: trains[index]), due <= clock.now,
                  let turned = shortTurn(of: trains[index], in: stuck),
                  case .waitingAtStop = turned.execution
            else { continue }
            setOff(index, as: turned)
            // Decision 288, a later fix (R1): the trip log's scheduled
            // arrival comes forward with the timetable.
            retimeRunningTrip(of: index)
            return id
        }
        return nil
    }
}
