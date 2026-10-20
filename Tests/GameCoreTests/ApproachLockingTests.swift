import Foundation
@testable import GameCore
import XCTest

/// Decision 294 (next step's candidate): under traffic control with block
/// sections, a service of a line with runs set off on a long leg holds its
/// route only as far as the last block boundary 4 km short of its stop until
/// it is within 14 km of the stop; a train that needs the junction near the
/// stop meanwhile takes it.
///
///                                                   ┌── Zb (B's start)
///   P ──e0 (30 km)──────────────────────────────── J ──e1── Z (A's end)
///                                                   └──e3── Y (B's end)
///
/// `e2` runs from Zb to J and `e3` on from J to Y, straight across J; A runs
/// P → Z from 10:00 to 10:20, B Zb → Y from 10:05 to 10:09.
final class ApproachLockingTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let z: StationID
        let y: StationID
        let a: TrainID
        let b: TrainID
    }

    private func at(_ minute: Int64) -> LineRunTime {
        LineRunTime(arrival: minute * 60, departure: minute * 60)
    }

    private func makeScene() throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 2_048_000, height: 16_384), economy: GameEconomy(balance: 1_000_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 595), speed: .normal)
        )
        let p = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let j = try world.buildTrackNode(at: WorldCoordinate(x: 1_921_024, y: 8_192))
        let z = try world.buildTrackNode(at: WorldCoordinate(x: 1_985_024, y: 8_192))
        let zb = try world.buildTrackNode(at: WorldCoordinate(x: 1_985_024, y: 12_288))
        let y = try world.buildTrackNode(at: WorldCoordinate(x: 1_857_024, y: 4_096))
        try world.buildTrackEdge(from: p, to: j)   // e0
        try world.buildTrackEdge(from: j, to: z)   // e1
        try world.buildTrackEdge(from: zb, to: j)  // e2
        try world.buildTrackEdge(from: j, to: y)   // e3
        let pStation = try world.buildStation(named: "P", at: PlanPoint(x: 4_096, y: 10_240)).id
        let zStation = try world.buildStation(named: "Z", at: PlanPoint(x: 1_980_000, y: 4_096)).id
        let zbStation = try world.buildStation(named: "Zb", at: PlanPoint(x: 1_980_000, y: 14_336)).id
        let yStation = try world.buildStation(named: "Y", at: PlanPoint(x: 1_860_000, y: 2_048)).id
        try world.addTrackPlatform(pStation, on: .edge(1), from: 2_048, to: 10_240)
        try world.addTrackPlatform(zbStation, on: .edge(3), from: 2_048, to: 10_240)
        for (station, edge) in [(zStation, 2), (yStation, 4)] {
            let length = try XCTUnwrap(world.trackEdge(.edge(edge))?.length)
            try world.addTrackPlatform(station, on: .edge(edge), from: length - 10_240, to: length - 2_048)
        }
        let lineA = try world.createLine(named: "A", stops: [pStation, zStation]).id
        try world.setLineRuns(lineA, to: [LineRun(from: 0, to: 1, times: [at(600), at(620)])])
        let lineB = try world.createLine(named: "B", stops: [zbStation, yStation]).id
        try world.setLineRuns(lineB, to: [LineRun(from: 0, to: 1, times: [at(605), at(609)])])
        func train(_ name: String, on edge: Int, line: LineID) throws -> TrainID {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(edge), direction: .forward), offset: 10_240))
            try world.setTrainContinuation(id, along: [], stoppingAt: 10_240)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.assignTrain(id, to: line)
            return id
        }
        let a = try train("A", on: 1, line: lineA)
        let b = try train("B", on: 3, line: lineB)
        try world.setTrafficControl(true)
        world.setBlockSections(true)
        return Scene(world: world, z: zStation, y: yStation, a: a, b: b)
    }

    /// B crosses J and reaches Y while A is still far off, and A still
    /// reaches Z on time.
    func testATrainFarOffLeavesTheJunctionAtItsEndFree() throws {
        var scene = try makeScene()
        var bAtY: GameTime?, aAtZ: GameTime?
        for _ in 595..<625 {
            try scene.world.advance(ticks: 1)
            if bAtY == nil, scene.world.stationsStoppedAt(by: scene.b).contains(scene.y) { bAtY = scene.world.clock.now }
            if aAtZ == nil, scene.world.stationsStoppedAt(by: scene.a).contains(scene.z) { aAtZ = scene.world.clock.now }
        }
        let b = try XCTUnwrap(bAtY, "B reached Y")
        let a = try XCTUnwrap(aAtZ, "A reached Z")
        XCTAssertLessThanOrEqual(b.minute, 610, "B reached Y at minute \(b.minute), A at Z at \(a.minute)")
        XCTAssertLessThanOrEqual(a.minute, 620, "A reached Z at minute \(a.minute)")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// A holds its route only to a boundary 4 km or more short of Z while
    /// it is farther than 14 km from it, then all of it.
    func testItTakesTheRestWithinTheApproach() throws {
        var scene = try makeScene()
        try scene.world.advance(ticks: 6)
        let a = try XCTUnwrap(scene.world.train(id: scene.a))
        XCTAssertNotNil(a.execution, "A has set off")
        let left = scene.world.routeLength(of: a)
        XCTAssertGreaterThan(left, GameWorld.approachReach)
        let held = try XCTUnwrap(scene.world.authorityLeft(of: a), "A holds its route only part of the way")
        XCTAssertLessThanOrEqual(held, left - GameWorld.approachHold)
        for _ in 0..<12 { try scene.world.advance(ticks: 1) }
        let near = try XCTUnwrap(scene.world.train(id: scene.a))
        XCTAssertLessThanOrEqual(scene.world.routeLength(of: near), GameWorld.approachReach)
        XCTAssertNil(scene.world.authorityLeft(of: near), "within the approach A holds all its route")
    }

    /// The same, a minute at a time and at once.
    func testABatchMatchesMinutes() throws {
        let scene = try makeScene()
        var single = scene.world, batched = scene.world
        for _ in 0..<30 { try single.advance(ticks: 1) }
        try batched.advance(ticks: 30)
        XCTAssertEqual(batched, single)
    }
}
