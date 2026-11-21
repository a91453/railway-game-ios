import XCTest
@testable import GameCore

/// Decision 910: the steps of the way out of a deadlock, one row each in
/// `DeadlockRescueList.swift`, which merges as `union`.
final class DeadlockRescueListTests: XCTestCase {
    /// The steps as `resolveDeadlock(memo:)` tried them before they were
    /// split into a list: later steps may come between, never reorder them.
    private let original = [
        "serviceTakingAnyListedPlatform",
        "serviceSettingOffForAPassingPlace",
        "onlyWithAServiceDueOrASpare",
        "spareSteppingAside",
        "serviceTurningBackShort",
        "serviceTakingAFreeBerthAgainstTheWay",
        "standingAsideServiceTakingAFreeBerth",
        "departureIgnoringFollowerClaims",
        "runTrainPutOnItsRun",
        "runTrainEmptyToDepot",
        "serviceStandingAsideAnyWay",
        "trainClearingADepotRun",
        "runTrainLeavingAFullEnd",
    ]

    func testNoTwoStepsShareAnOrderOrAName() {
        let rescues = GameWorld.deadlockRescues
        XCTAssertEqual(Set(rescues.map(\.order)).count, rescues.count, "two steps share an order: give the new one a number of its own")
        XCTAssertEqual(Set(rescues.map(\.name)).count, rescues.count, "two steps share a name")
    }

    func testTheStepsAreTriedByOrder() {
        let orders = GameWorld.deadlockRescues.map(\.order)
        XCTAssertEqual(orders, orders.sorted())
    }

    func testTheOriginalStepsKeepTheirOrder() {
        let names = GameWorld.deadlockRescues.map(\.name).filter(original.contains)
        XCTAssertEqual(names, original)
    }

    func testEveryStepNamesItsDecision() {
        for rescue in GameWorld.deadlockRescues {
            XCTAssertGreaterThan(rescue.decision, 0, rescue.name)
        }
    }
}
