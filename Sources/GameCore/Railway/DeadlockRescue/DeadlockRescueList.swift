// Decision 910: the steps of the dispatcher's way out of a deadlock
// (``GameWorld/resolveDeadlock(memo:)``), one row each. Add a step as a
// row of its own with an `order` no other row has, between the steps it
// comes between; the rows are tried by `order`, not by their place here.
// This file merges as `union` (.gitattributes), so two branches that each
// add a row keep both; `DeadlockRescueListTests` checks the result.

extension GameWorld {
    static let deadlockRescues: [DeadlockRescue] = [
        DeadlockRescue(order: 100, decision: 740, name: "serviceTakingAnyListedPlatform") { world, stuck, memo in world.serviceTakingAnyListedPlatform(in: stuck, memo: &memo) },
        DeadlockRescue(order: 200, decision: 58, name: "serviceSettingOffForAPassingPlace") { world, stuck, memo in world.serviceSettingOffForAPassingPlace(in: stuck, memo: &memo) },
        DeadlockRescue(order: 300, decision: 58, name: "onlyWithAServiceDueOrASpare", goesOnOnlyIf: { world, stuck, serviceDue in serviceDue || stuck.keys.contains(where: { world.train(id: $0)?.execution == nil }) }),
        DeadlockRescue(order: 400, decision: 58, name: "spareSteppingAside") { world, stuck, memo in world.spareSteppingAside(in: stuck, memo: &memo) },
        DeadlockRescue(order: 500, decision: 255, name: "serviceTurningBackShort") { world, stuck, memo in world.serviceTurningBackShort(in: stuck, memo: &memo) },
        DeadlockRescue(order: 600, decision: 571, name: "serviceTakingAFreeBerthAgainstTheWay") { world, stuck, memo in world.serviceTakingAFreeBerthAgainstTheWay(in: stuck, memo: &memo) },
        DeadlockRescue(order: 700, decision: 556, name: "standingAsideServiceTakingAFreeBerth") { world, stuck, memo in world.standingAsideServiceTakingAFreeBerth(in: stuck, memo: &memo) },
        DeadlockRescue(order: 800, decision: 577, name: "departureIgnoringFollowerClaims") { world, stuck, memo in world.departureIgnoringFollowerClaims(in: stuck, memo: &memo) },
        DeadlockRescue(order: 900, decision: 556, name: "runTrainPutOnItsRun") { world, stuck, memo in world.runTrainPutOnItsRun(in: stuck, memo: &memo) },
        DeadlockRescue(order: 1000, decision: 556, name: "runTrainEmptyToDepot") { world, stuck, memo in world.runTrainEmptyToDepot(in: stuck, memo: &memo) },
        DeadlockRescue(order: 1100, decision: 556, name: "serviceStandingAsideAnyWay") { world, stuck, memo in world.serviceStandingAsideAnyWay(in: stuck, memo: &memo) },
        DeadlockRescue(order: 1200, decision: 808, name: "trainClearingADepotRun") { world, stuck, memo in world.trainClearingADepotRun(in: stuck, memo: &memo) },
        DeadlockRescue(order: 1300, decision: 816, name: "runTrainLeavingAFullEnd") { world, stuck, memo in world.runTrainLeavingAFullEnd(in: stuck, memo: &memo) },
    ].sorted { $0.order < $1.order }
}
