import Foundation
@testable import GameCore
import XCTest

/// Decision 968: under traffic control without block sections, an empty run
/// of a line with runs into a depot holds its route only as far as just
/// short of the first junction or crossing after the last station it passes
/// (the depot's throat) until it is within 1 km of it; a train that needs
/// that junction meanwhile crosses it.
///
///                                                   ┌── Zb (B's start)
///   P ── X ──e0 (9 km)──────────────────────────── J ──e1 (500 m)── D (A's depot)
///                                                   └──e3── Y (B's end)
///
/// `e2` runs from Zb to J and `e3` on from J to Y, straight across J. A's
/// line calls at P and X and its next run from P is hours away, so its
/// train at P runs empty into D; B runs Zb → Y meanwhile.
final class DepotSignalTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let depot: StationID
        let y: StationID
        let a: TrainID
        let b: TrainID
        let j: TrackNodeID
    }

    private func at(_ minute: Int64) -> LineRunTime {
        LineRunTime(arrival: minute * 60, departure: minute * 60)
    }

    /// At 09:55. B's run leaves Zb at `bLeaves` and is due at Y three
    /// minutes later.
    private func makeScene(blockSections: Bool = false, bLeaves: Int64 = 598) throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 1_024_000, height: 16_384), economy: GameEconomy(balance: 1_000_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 595), speed: .normal)
        )
        let p = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let j = try world.buildTrackNode(at: WorldCoordinate(x: 577_024, y: 8_192))
        let d = try world.buildTrackNode(at: WorldCoordinate(x: 609_024, y: 8_192))
        let zb = try world.buildTrackNode(at: WorldCoordinate(x: 609_024, y: 12_288))
        let y = try world.buildTrackNode(at: WorldCoordinate(x: 545_024, y: 4_096))
        try world.buildTrackEdge(from: p, to: j)   // e0
        try world.buildTrackEdge(from: j, to: d)   // e1
        try world.buildTrackEdge(from: zb, to: j)  // e2
        try world.buildTrackEdge(from: j, to: y)   // e3
        let pStation = try world.buildStation(named: "P", at: PlanPoint(x: 4_096, y: 10_240)).id
        let xStation = try world.buildStation(named: "X", at: PlanPoint(x: 104_448, y: 10_240)).id
        let depot = try world.buildStation(named: "D", at: PlanPoint(x: 605_000, y: 4_096)).id
        let zbStation = try world.buildStation(named: "Zb", at: PlanPoint(x: 605_000, y: 14_336)).id
        let yStation = try world.buildStation(named: "Y", at: PlanPoint(x: 548_000, y: 2_048)).id
        try world.addTrackPlatform(pStation, on: .edge(1), from: 2_048, to: 10_240)
        try world.addTrackPlatform(xStation, on: .edge(1), from: 100_000, to: 108_192)
        try world.addTrackPlatform(zbStation, on: .edge(3), from: 2_048, to: 10_240)
        for (station, edge) in [(depot, 2), (yStation, 4)] {
            let length = try XCTUnwrap(world.trackEdge(.edge(edge))?.length)
            try world.addTrackPlatform(station, on: .edge(edge), from: length - 10_240, to: length - 2_048)
        }
        try world.setStationDepot(depot, to: true)
        let lineA = try world.createLine(named: "A", stops: [pStation, xStation]).id
        let lineB = try world.createLine(named: "B", stops: [zbStation, yStation]).id
        try world.setLineRuns(lineA, to: [LineRun(from: 0, to: 1, times: [at(900), at(903)])])
        try world.setLineDepots(lineA, to: [depot])
        try world.setLineRuns(lineB, to: [LineRun(from: 0, to: 1, times: [at(bLeaves), at(bLeaves + 3)])])
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
        return Scene(world: world, depot: depot, y: yStation, a: a, b: b, j: j)
    }

    /// B crosses J and reaches Y on time while A is still far off, and A
    /// reaches the depot as soon as before. On `main` A held J from 09:55
    /// and B left Zb only once A had passed it, three minutes late.
    func testAnEmptyRunFarOffLeavesTheDepotThroatFree() throws {
        var scene = try makeScene()
        var bAtY: GameTime?, aInDepot: GameTime?
        for _ in 0..<20 {
            try scene.world.advance(ticks: 1)
            if bAtY == nil, scene.world.stationsStoppedAt(by: scene.b).contains(scene.y) { bAtY = scene.world.clock.now }
            if aInDepot == nil, scene.world.stationsStoppedAt(by: scene.a).contains(scene.depot) { aInDepot = scene.world.clock.now }
        }
        let b = try XCTUnwrap(bAtY, "B reached Y")
        let a = try XCTUnwrap(aInDepot, "A reached the depot")
        XCTAssertLessThanOrEqual(b.minute, 601, "B reached Y at minute \(b.minute), A the depot at \(a.minute)")
        XCTAssertLessThanOrEqual(a.minute, 602, "A reached the depot at minute \(a.minute)")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// A, running empty, holds its route only to short of J while it is
    /// farther than 1 km from J, and never J itself, then all of it.
    func testItTakesTheThroatOnlyNearIt() throws {
        var scene = try makeScene()
        try scene.world.advance(ticks: 2)
        let a = try XCTUnwrap(scene.world.train(id: scene.a))
        XCTAssertTrue(a.isDeadheading, "A runs empty into the depot")
        let held = try XCTUnwrap(scene.world.authorityLeft(of: a), "A holds its route only part of the way")
        let toJ = scene.world.routeLength(of: a) - 30_000
        XCTAssertLessThan(held, toJ, "A stops short of J")
        XCTAssertGreaterThan(toJ, GameWorld.homeReach)
        XCTAssertFalse(scene.world.reservedResources(of: scene.a).contains(.node(scene.j)), "A does not hold J")
        try scene.world.advance(ticks: 4)
        let near = try XCTUnwrap(scene.world.train(id: scene.a))
        XCTAssertNotNil(near.execution, "A is still on its way")
        XCTAssertNil(scene.world.authorityLeft(of: near), "near J A holds all its route")
        XCTAssertTrue(scene.world.reservedResources(of: scene.a).contains(.node(scene.j)))
    }

    /// With the throat taken (B stands across J and cannot go on), A waits
    /// short of J, clear of it, and goes in once B has gone.
    func testItWaitsShortOfTheThroatWhileAnotherTrainHoldsIt() throws {
        var scene = try makeScene(bLeaves: 596)
        try scene.world.advance(ticks: 2)
        try scene.world.setTrainMovementRate(scene.b, to: 0)
        try scene.world.advance(ticks: 10)
        let a = try XCTUnwrap(scene.world.train(id: scene.a))
        let b = try XCTUnwrap(scene.world.train(id: scene.b))
        XCTAssertNotNil(b.execution, "B is held on its way")
        XCTAssertTrue(a.isDeadheading)
        XCTAssertFalse(scene.world.stationsStoppedAt(by: scene.a).contains(scene.depot), "A has not passed B")
        guard case .onEdge(let traversal, let offset)? = a.position else { return XCTFail("A is placed") }
        XCTAssertEqual(traversal.edge, .edge(1), "A waits on the line")
        XCTAssertLessThanOrEqual(offset, try XCTUnwrap(scene.world.trackEdge(.edge(1))?.length) - RailwayNetwork.junctionZone, "clear of J")
        try scene.world.setTrainMovementRate(scene.b, to: 4_096)
        try scene.world.advance(ticks: 8)
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.a).contains(scene.depot), "A went in after B")
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.b).contains(scene.y))
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// With block sections the rule does not apply: A takes its whole
    /// route at once, as before.
    func testWithBlockSectionsItTakesItsWholeRoute() throws {
        var scene = try makeScene(blockSections: true)
        try scene.world.advance(ticks: 2)
        let a = try XCTUnwrap(scene.world.train(id: scene.a))
        XCTAssertTrue(a.isDeadheading)
        XCTAssertNil(scene.world.authorityLeft(of: a), "A holds all its route")
        XCTAssertTrue(scene.world.reservedResources(of: scene.a).contains(.node(scene.j)))
    }

    /// The same, a minute at a time and at once.
    func testABatchMatchesMinutes() throws {
        for bLeaves: Int64 in [598, 600] {
            let scene = try makeScene(bLeaves: bLeaves)
            var single = scene.world, batched = scene.world
            for _ in 0..<15 { try single.advance(ticks: 1) }
            try batched.advance(ticks: 15)
            XCTAssertEqual(batched, single, "B leaving at \(bLeaves)")
        }
    }
}
