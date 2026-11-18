import Foundation
@testable import GameCore
import XCTest

/// Decision 842: under traffic control without block sections, a service of
/// a line with runs holds its route only as far as just short of the first
/// junction or crossing within 1 km of its stop (the station's throat)
/// until it is within 1 km of it; a train that needs that junction
/// meanwhile crosses it.
///
///                                                   ┌── Zb (B's start)
///   P ──e0 (9 km)───────────────────────────────── J ──e1 (500 m)── Z (A's end)
///                                                   └──e3── Y (B's end)
///
/// `e2` runs from Zb to J and `e3` on from J to Y, straight across J; A runs
/// P → Z from 10:00 to 10:07, B Zb → Y from 10:01 to 10:04.
final class HomeSignalTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let z: StationID
        let y: StationID
        let a: TrainID
        let b: TrainID
        let j: TrackNodeID
    }

    private func at(_ minute: Int64) -> LineRunTime {
        LineRunTime(arrival: minute * 60, departure: minute * 60)
    }

    private func makeScene(blockSections: Bool = false) throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 1_024_000, height: 16_384), economy: GameEconomy(balance: 1_000_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 595), speed: .normal)
        )
        let p = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let j = try world.buildTrackNode(at: WorldCoordinate(x: 577_024, y: 8_192))
        let z = try world.buildTrackNode(at: WorldCoordinate(x: 609_024, y: 8_192))
        let zb = try world.buildTrackNode(at: WorldCoordinate(x: 609_024, y: 12_288))
        let y = try world.buildTrackNode(at: WorldCoordinate(x: 545_024, y: 4_096))
        try world.buildTrackEdge(from: p, to: j)   // e0
        try world.buildTrackEdge(from: j, to: z)   // e1
        try world.buildTrackEdge(from: zb, to: j)  // e2
        try world.buildTrackEdge(from: j, to: y)   // e3
        let pStation = try world.buildStation(named: "P", at: PlanPoint(x: 4_096, y: 10_240)).id
        let zStation = try world.buildStation(named: "Z", at: PlanPoint(x: 605_000, y: 4_096)).id
        let zbStation = try world.buildStation(named: "Zb", at: PlanPoint(x: 605_000, y: 14_336)).id
        let yStation = try world.buildStation(named: "Y", at: PlanPoint(x: 548_000, y: 2_048)).id
        try world.addTrackPlatform(pStation, on: .edge(1), from: 2_048, to: 10_240)
        try world.addTrackPlatform(zbStation, on: .edge(3), from: 2_048, to: 10_240)
        for (station, edge) in [(zStation, 2), (yStation, 4)] {
            let length = try XCTUnwrap(world.trackEdge(.edge(edge))?.length)
            try world.addTrackPlatform(station, on: .edge(edge), from: length - 10_240, to: length - 2_048)
        }
        let lineA = try world.createLine(named: "A", stops: [pStation, zStation]).id
        let lineB = try world.createLine(named: "B", stops: [zbStation, yStation]).id
        try world.setLineRuns(lineA, to: [LineRun(from: 0, to: 1, times: [at(600), at(607)])])
        try world.setLineRuns(lineB, to: [LineRun(from: 0, to: 1, times: [at(601), at(604)])])
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
        world.setBlockSections(blockSections)
        return Scene(world: world, z: zStation, y: yStation, a: a, b: b, j: j)
    }

    /// B crosses J and reaches Y while A is still far off, and A still
    /// reaches Z on time. On `main` A held J from 10:00 and B reached Y
    /// only after A had passed it.
    func testATrainFarOffLeavesTheThroatAtItsEndFree() throws {
        var scene = try makeScene()
        var bAtY: GameTime?, aAtZ: GameTime?
        for _ in 595..<615 {
            try scene.world.advance(ticks: 1)
            if bAtY == nil, scene.world.stationsStoppedAt(by: scene.b).contains(scene.y) { bAtY = scene.world.clock.now }
            if aAtZ == nil, scene.world.stationsStoppedAt(by: scene.a).contains(scene.z) { aAtZ = scene.world.clock.now }
        }
        let b = try XCTUnwrap(bAtY, "B reached Y")
        let a = try XCTUnwrap(aAtZ, "A reached Z")
        XCTAssertLessThanOrEqual(b.minute, 605, "B reached Y at minute \(b.minute), A at Z at \(a.minute)")
        XCTAssertLessThanOrEqual(a.minute, 607, "A reached Z at minute \(a.minute)")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// A holds its route only to short of J while it is farther than 1 km
    /// from J, and never J itself, then all of it.
    func testItTakesTheThroatOnlyNearIt() throws {
        var scene = try makeScene()
        try scene.world.advance(ticks: 6)
        let a = try XCTUnwrap(scene.world.train(id: scene.a))
        XCTAssertNotNil(a.execution, "A has set off")
        let held = try XCTUnwrap(scene.world.authorityLeft(of: a), "A holds its route only part of the way")
        let toJ = scene.world.routeLength(of: a) - 30_000
        XCTAssertLessThan(held, toJ, "A stops short of J")
        XCTAssertGreaterThan(toJ, GameWorld.homeReach)
        XCTAssertFalse(scene.world.reservedResources(of: scene.a).contains(.node(scene.j)), "A does not hold J")
        for _ in 0..<6 { try scene.world.advance(ticks: 1) }
        let near = try XCTUnwrap(scene.world.train(id: scene.a))
        XCTAssertNil(scene.world.authorityLeft(of: near), "near J A holds all its route")
    }

    /// With block sections, as before (decision 294): a leg shorter than
    /// 14 km is taken whole.
    func testWithBlockSectionsTheLegIsTakenWhole() throws {
        var scene = try makeScene(blockSections: true)
        try scene.world.advance(ticks: 6)
        let a = try XCTUnwrap(scene.world.train(id: scene.a))
        XCTAssertNotNil(a.execution, "A has set off")
        XCTAssertNil(scene.world.authorityLeft(of: a))
        XCTAssertTrue(scene.world.reservedResources(of: scene.a).contains(.node(scene.j)))
    }

    /// The same, a minute at a time and at once.
    func testABatchMatchesMinutes() throws {
        let scene = try makeScene()
        var single = scene.world, batched = scene.world
        for _ in 0..<15 { try single.advance(ticks: 1) }
        try batched.advance(ticks: 15)
        XCTAssertEqual(batched, single)
    }
}
