import Foundation
@testable import GamePresentation
import XCTest

/// Decision 417: one budget of triangles for what moves on the 3D map, and
/// the steps down and up under load.
final class Map3DMotionBudgetTests: XCTestCase {
    // MARK: The budget

    func testWithFewTrainsTheStreetsDrawAll() {
        for detail in [Map3DStreetDetail.reduced, .full] {
            XCTAssertEqual(Map3DMotionBudget(detail: detail).limits(), Map3DStreetLimits(detail), "\(detail)")
            // A line or two of trains near the eye: still all.
            XCTAssertEqual(Map3DMotionBudget(detail: detail, trainTriangles: 60_000).limits(), Map3DStreetLimits(detail), "\(detail)")
        }
        XCTAssertEqual(Map3DMotionBudget(detail: .off, trainTriangles: 0).limits(), Map3DStreetLimits(people: 0, vehicles: 0, buses: 0))
    }

    func testMoreTrainsLeaveTheStreetsFewerVehiclesFirstThenFewerPeople() {
        var last = Map3DStreetLimits(.full)
        var vehiclesFellBeforePeople = false
        for trains in stride(from: 0, through: 800_000, by: 20_000) {
            let limits = Map3DMotionBudget(detail: .full, trainTriangles: trains).limits()
            XCTAssertLessThanOrEqual(limits.vehicles, last.vehicles, "\(trains)")
            XCTAssertLessThanOrEqual(limits.people, last.people, "\(trains)")
            XCTAssertLessThanOrEqual(limits.buses, last.buses, "\(trains)")
            if limits.vehicles < Map3DStreetDetail.full.vehicles, limits.people == Map3DStreetDetail.full.people { vehiclesFellBeforePeople = true }
            last = limits
        }
        XCTAssertTrue(vehiclesFellBeforePeople)
        // However many trains, a tenth of the streets stays.
        XCTAssertEqual(last, Map3DStreetLimits(people: 140, vehicles: 40, buses: 3))
    }

    func testThePlayersBusesAreNeverCutAndShareTheStreetsBuses() {
        // Ten of the player's buses, with room for all: the streets keep
        // 20 of their own 30 buses.
        let roomy = Map3DMotionBudget(detail: .full).limits(routeBuses: 10)
        XCTAssertEqual(roomy.vehicles, 10 + Map3DStreetDetail.full.vehicles)
        XCTAssertEqual(roomy.buses, Map3DStreetLife.mostBuses)
        // However busy the lines, the player's buses are all drawn.
        let crowded = Map3DMotionBudget(detail: .full, trainTriangles: 2_000_000).limits(routeBuses: 40)
        XCTAssertEqual(crowded.buses, 40)
        XCTAssertEqual(crowded.vehicles, 40 + 40)
        // A bus takes a car's room 15 times over.
        let one = Map3DMotionBudget(detail: .full, trainTriangles: 470_000)
        XCTAssertLessThan(one.limits(routeBuses: 20).vehicles - 20, one.limits().vehicles)
    }

    func testAStepDownTakesAShareOfTheStreets() {
        let budget = Map3DMotionBudget(detail: .full, step: .fewerOnStreets)
        XCTAssertEqual(budget.limits(), Map3DStreetLimits(people: 700, vehicles: 200, buses: 15))
        XCTAssertEqual(Map3DMotionBudget(detail: .full, step: .fewerPixels).limits(), Map3DStreetLimits(people: 280, vehicles: 80, buses: 6))
        // The player's buses still all.
        XCTAssertEqual(Map3DMotionBudget(detail: .full, step: .fewestOnStreets).limits(routeBuses: 7).buses, 7 + 5)
    }

    func testTheTrainsTrianglesAreTheirModelsBoxesAndShadows() throws {
        let pack = Map3DModelPack.standard
        let head = try XCTUnwrap(pack.index(of: "set-emu3000-head"))
        var frame = Map3DTrains.Frame()
        frame.instances = [Map3DInstance(model: head, transform: [], stripe: (0, 0, 0)), Map3DInstance(model: head, transform: [], stripe: (0, 0, 0))]
        frame.boxes.addBox(base: .zero, forward: Map3DPoint(1, 0, 0), length: 20, width: 3, height: 3, top: 0, side: 0)
        XCTAssertEqual(frame.triangles(in: pack), 2 * pack.models[head].triangleCount + frame.boxes.triangleCount)
        XCTAssertEqual(frame.triangles(in: nil), frame.boxes.triangleCount)
    }

    // MARK: The trains' far models

    func testSteppedDownTheFarModelsAndBoxesComeNearer() throws {
        let pack = Map3DModelPack.standard
        let head = try XCTUnwrap(pack.index(of: "set-emu3000-head"))
        let far = try XCTUnwrap(pack.index(of: "set-emu3000Far-head"))
        let reach = Map3DTrainSet.reach(of: "EMU3000")
        // In full, as before (decision 408).
        XCTAssertEqual(pack.model(head, forType: "EMU3000", count: 8, at: reach - 1), head)
        XCTAssertEqual(pack.model(head, forType: "EMU3000", count: 8, at: reach + 1), far)
        XCTAssertNil(pack.model(head, forType: "EMU3000", count: 8, at: Map3DTrains.modelReach + 1))
        // Stepped down: the far model from half as far, a box from 0.8.
        XCTAssertEqual(pack.model(head, forType: "EMU3000", count: 8, at: reach * 0.5 - 1, step: .nearerFarModels), head)
        XCTAssertEqual(pack.model(head, forType: "EMU3000", count: 8, at: reach * 0.5 + 1, step: .nearerFarModels), far)
        XCTAssertNil(pack.model(head, forType: "EMU3000", count: 8, at: Map3DTrains.modelReach * 0.8 + 1, step: .fewerPixels))
        // The steps before leave the trains alone.
        XCTAssertEqual(pack.model(head, forType: "EMU3000", count: 8, at: reach * 0.5 + 1, step: .fewestOnStreets), head)
    }

    func testACarWithNoFarModelKeepsItsOwnAsFarAsBefore() throws {
        let pack = Map3DModelPack.standard
        let head = try XCTUnwrap(pack.index(of: "set-puyuma-head"))
        let reach = Map3DTrainSet.reach(of: "puyuma")
        XCTAssertEqual(pack.model(head, forType: "puyuma", count: 8, at: reach * 0.7, step: .nearerFarModels), head)
        XCTAssertEqual(pack.model(head, forType: "puyuma", count: 8, at: Map3DTrains.modelReach * 0.8 - 1, step: .nearerFarModels), head)
        XCTAssertNil(pack.model(head, forType: "puyuma", count: 8, at: Map3DTrains.modelReach * 0.8 + 1, step: .nearerFarModels))
    }

    // MARK: Stepping down and up

    static let heavy = Map3DLoadGovernor.Sample(framesPerSecond: 38, aim: 60, gpuMilliseconds: 8, drawingStreets: true)
    static let middling = Map3DLoadGovernor.Sample(framesPerSecond: 52, aim: 60, gpuMilliseconds: 8, drawingStreets: true)
    static let light = Map3DLoadGovernor.Sample(framesPerSecond: 60, aim: 60, gpuMilliseconds: 5, drawingStreets: true)

    func testWhatIsHeavyAndWhatIsLight() {
        XCTAssertTrue(Self.heavy.isHeavy)
        XCTAssertFalse(Self.heavy.isLight)
        XCTAssertFalse(Self.middling.isHeavy)
        XCTAssertFalse(Self.middling.isLight)
        XCTAssertTrue(Self.light.isLight)
        // The frames kept, but the GPU over its 10 ms.
        XCTAssertTrue(Map3DLoadGovernor.Sample(framesPerSecond: 60, aim: 60, gpuMilliseconds: 11, drawingStreets: true).isHeavy)
        // The frames kept, the GPU within its budget but not well within.
        XCTAssertFalse(Map3DLoadGovernor.Sample(framesPerSecond: 60, aim: 60, gpuMilliseconds: 8, drawingStreets: true).isLight)
        // At 30 a second (Saving, Low Power Mode).
        XCTAssertTrue(Map3DLoadGovernor.Sample(framesPerSecond: 21, aim: 30, gpuMilliseconds: 8, drawingStreets: true).isHeavy)
        XCTAssertTrue(Map3DLoadGovernor.Sample(framesPerSecond: 30, aim: 30, gpuMilliseconds: 12, drawingStreets: true).isLight)
    }

    func testItStepsDownInOrderAfterThreeHeavyHalfSeconds() {
        var governor = Map3DLoadGovernor()
        var steps: [Map3DLoadStep] = []
        for _ in 0..<20 {
            if governor.record(Self.heavy) { steps.append(governor.step) }
        }
        XCTAssertEqual(steps, [.fewerOnStreets, .fewestOnStreets, .nearerFarModels, .fewerPixels])
        // Two heavy half seconds and a middling one: no step.
        var other = Map3DLoadGovernor()
        for sample in [Self.heavy, Self.heavy, Self.middling, Self.heavy, Self.heavy] { XCTAssertFalse(other.record(sample)) }
        XCTAssertEqual(other.step, .full)
    }

    func testWithNothingOnTheStreetsItGoesStraightToTheTrains() {
        var governor = Map3DLoadGovernor()
        var away = Self.heavy
        away.drawingStreets = false
        for _ in 0..<3 { governor.record(away) }
        XCTAssertEqual(governor.step, .nearerFarModels)
    }

    func testALookThatKeepsItsPixelsStopsAtTheTrains() {
        var governor = Map3DLoadGovernor(lowest: .nearerFarModels)
        for _ in 0..<30 { governor.record(Self.heavy) }
        XCTAssertEqual(governor.step, .nearerFarModels)
        var lowered = Map3DLoadGovernor()
        for _ in 0..<30 { lowered.record(Self.heavy) }
        lowered.lowest = .nearerFarModels
        XCTAssertEqual(lowered.step, .nearerFarModels)
    }

    func testItStepsBackUpAfterTenLightSecondsAndNotBetween() {
        var governor = Map3DLoadGovernor()
        for _ in 0..<3 { governor.record(Self.heavy) }
        XCTAssertEqual(governor.step, .fewerOnStreets)
        for _ in 0..<19 { XCTAssertFalse(governor.record(Self.light)) }
        // A middling half second starts the count again.
        governor.record(Self.middling)
        for _ in 0..<19 { governor.record(Self.light) }
        XCTAssertEqual(governor.step, .fewerOnStreets)
        XCTAssertTrue(governor.record(Self.light))
        XCTAssertEqual(governor.step, .full)
        // Already in full: no further.
        for _ in 0..<100 { XCTAssertFalse(governor.record(Self.light)) }
    }

    func testAStepUpTakenBackSoonWaitsTwiceAsLongNextTime() {
        var governor = Map3DLoadGovernor()
        func down() { for _ in 0..<3 { governor.record(Self.heavy) } }
        func lightUntilUp() -> Int {
            var windows = 0
            while governor.step > .full, windows < 1_000 {
                governor.record(Self.light)
                windows += 1
            }
            return windows
        }
        down()
        XCTAssertEqual(lightUntilUp(), 20)
        // Heavy again 1.5 s after the step up: next time 20 s.
        down()
        XCTAssertEqual(lightUntilUp(), 40)
        down()
        XCTAssertEqual(lightUntilUp(), 80)
        down()
        XCTAssertEqual(lightUntilUp(), 160)
        down()
        XCTAssertEqual(lightUntilUp(), 240, "at most 2 minutes")
        // Heavy only long after the step up: no longer.
        for _ in 0..<Map3DLoadGovernor.relapseWindows { governor.record(Self.middling) }
        down()
        XCTAssertEqual(lightUntilUp(), 240)
    }

    // MARK: Measured

    /// The triangles of the trains near the eye, as a frame draws them,
    /// against what the budget leaves the streets: `lines` lines with two
    /// trains each of `cars` cars within the trains' models' reach (one
    /// each way), their cars spread from 50 m to 850 m from the eye, and
    /// two of the player's buses a bus route (decision 400's measure:
    /// 9 buses a route, one every 5 minutes). Only on request:
    /// `MOTION_BUDGET_REPORT=1`.
    func testTheBudgetByLines() throws {
        guard ProcessInfo.processInfo.environment["MOTION_BUDGET_REPORT"] != nil else { throw XCTSkip("Set MOTION_BUDGET_REPORT=1.") }
        let pack = Map3DModelPack.standard
        var rows = ["| Type | Lines | Bus routes | Step | Train triangles | People | Vehicles | Buses | Moving triangles |",
                    "| --- | --: | --: | --- | --: | --: | --: | --: | --: |"]
        for (type, cars) in [("EMU3000", 8), ("HSR", 12), ("A", 6)] {
            let laid = try XCTUnwrap(Map3DTrainSet.set(forKey: type, count: cars, locked: []))
            let models = (0..<cars).compactMap { pack.modelIndex(forType: type, carIndex: $0, count: cars) }
            XCTAssertEqual(models.count, cars, laid.key)
            for (lines, routes) in [(1, 1), (2, 2), (5, 5), (10, 10), (20, 20)] {
                for step in [Map3DLoadStep.full, .nearerFarModels] {
                    var trains = 0
                    for train in 0..<(2 * lines) {
                        for (car, near) in models.enumerated() {
                            let distance = 50 + Float((train * cars + car) % 16) * 50
                            trains += pack.model(near, forType: type, count: cars, at: distance, step: step).map { pack.models[$0].triangleCount } ?? 20
                        }
                    }
                    let buses = 2 * routes
                    let limits = Map3DMotionBudget(detail: .full, step: step, trainTriangles: trains).limits(routeBuses: buses)
                    let moving = trains + limits.people * Map3DMotionBudget.personTriangles
                        + (limits.vehicles - limits.buses) * Map3DMotionBudget.vehicleTriangles + limits.buses * Map3DMotionBudget.busTriangles
                    rows.append("| \(type) ×\(cars) | \(lines) | \(routes) | \(step) | \(trains) | \(limits.people) | \(limits.vehicles) | \(limits.buses) | \(moving) |")
                }
            }
        }
        print(rows.joined(separator: "\n"))
    }
}
