// The dispatcher's way out of a deadlock (Stage V2, ARCHITECTURE decision 58),
// in steps (decision 910). Each step is a file of its own in this folder, and
// `DeadlockRescueList.swift` lists them, one row each, with the order they are
// tried in: a fix to a new deadlock adds a file and a row, rather than one
// more `??` at the end of one long line every such fix changed.

extension GameWorld {
    /// Stage V2 (ARCHITECTURE decision 58): the dispatcher's phase, at a
    /// whole minute after the services' phase. Of the trains in a deadlock
    /// (see ``deadlock(memo:)``), the first in ID order whose service is due to
    /// leave a stop, or is stopped at a passing place, and that has a
    /// passing place letting another of them go (see
    /// ``passingPlace(for:in:memo:)``) sets off for it, taking the way there
    /// whole, as fast as it can: one train at most each minute. Leaving a
    /// stop so is a departure like any other (G1b, G1c), counted over the
    /// whole way to its call. Failing that, a line's spare holding track
    /// one of them waits for moves out of the way (a later fix, see
    /// ``spareStandingAside(in:memo:)``). Returns the train's ID, or `nil`.
    ///
    /// Decision 910: the ways out are tried one at a time, in the order of
    /// ``deadlockRescues``, and the first that moves a train ends the phase.
    mutating func resolveDeadlock(memo: inout DispatchMemo) -> TrainID? {
        guard isTrafficControlEnabled else { return nil }
        // Only such a service is ever sent: without one, nothing to find
        // but a spare in the way of a line's train due to be sent out (a
        // later fix: a new line's first train held by another line's spare
        // was never let go while no service was due).
        let serviceDue = trains.contains { train in
            if case .waitingAtStop? = train.execution, let due = departureDue(of: train), due <= clock.now { return true }
            return isAtPassingPlace(train)
        }
        guard serviceDue || anyTrainMayBeSentOut(memo: &memo) else { return nil }
        let stuck = deadlock(memo: &memo.directions)
        for rescue in Self.deadlockRescues {
            switch rescue.step {
            case .rescue(let step):
                if let id = step(&self, stuck, &memo) { return id }
            case .goesOnOnlyIf(let goesOn):
                guard goesOn(self, stuck, serviceDue) else { return nil }
            }
        }
        return nil
    }
}

/// One step of ``GameWorld/resolveDeadlock(memo:)`` (decision 910): a way out
/// of the deadlock that moves one train and returns its ID, or `nil` to let
/// the next step try; or a check that ends the phase when it fails.
struct DeadlockRescue: Sendable {
    typealias Stuck = [TrainID: (candidate: Train, departs: Bool)]

    enum Step: Sendable {
        /// Moves one train of the deadlock and returns its ID, or `nil`.
        case rescue(@Sendable (inout GameWorld, Stuck, inout GameWorld.DispatchMemo) -> TrainID?)
        /// Whether the later steps are tried at all, given the deadlock and
        /// whether a service is due to leave or stands at a passing place.
        case goesOnOnlyIf(@Sendable (GameWorld, Stuck, _ serviceDue: Bool) -> Bool)
    }

    /// Where the step comes, smallest first. The order is this number, not
    /// the row's place in the list: two branches that each add a row may
    /// leave them in either order when merged (the list merges as `union`),
    /// and `DeadlockRescueListTests` checks that no two steps share one.
    let order: Int
    /// The decision that added the step.
    let decision: Int
    /// The step's name, as its function's: what the tests pin.
    let name: String
    let step: Step

    init(order: Int, decision: Int, name: String,
         _ rescue: @escaping @Sendable (inout GameWorld, Stuck, inout GameWorld.DispatchMemo) -> TrainID?) {
        self.order = order
        self.decision = decision
        self.name = name
        self.step = .rescue(rescue)
    }

    init(order: Int, decision: Int, name: String,
         goesOnOnlyIf goesOn: @escaping @Sendable (GameWorld, Stuck, _ serviceDue: Bool) -> Bool) {
        self.order = order
        self.decision = decision
        self.name = name
        self.step = .goesOnOnlyIf(goesOn)
    }
}
