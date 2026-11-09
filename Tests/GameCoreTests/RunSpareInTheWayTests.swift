@testable import GameCore
import XCTest

/// Decision 666: under traffic control without block sections, a train
/// of a line with runs that stands between runs, no run of its own due
/// (one out of a depot too late for its run, say), whose line would send
/// it into a depot but for its way there, and that stands in the way of a
/// train waiting for its route, runs empty to the nearest berth of any
/// station where it lets that train go. Before, nothing moved it, and no
/// deadlock was seen (it waits for nothing): on the Taoyuan Airport MRT a
/// train out of Luzhu depot came to the National Taiwan Sport University
/// too late for its run and stood on the platform towards Taipei, its way
/// back to the depot never free at once, and the services behind it bound
/// for that platform waited for it all day
/// (docs/research/TYMC_AFTERNOON_2026-11-08.md).
final class RunSpareInTheWayTests: XCTestCase {
    private static let station = StationID(rawValue: 4)
    private static let depot = StationID(rawValue: 5)

    /// `SingleTrackMeet`'s W–M–E (M with a loop), the single track going
    /// on past E to C and on to depot D. C's run leaves at 06:05 for M,
    /// past E, where a train of the line stands without a run, facing C
    /// and D; C's train stands on the way between it and D.
    private func spareInTheWay() throws -> (world: GameWorld, line: LineID, spare: TrainID, service: TrainID) {
        var world = try GameWorld(bounds: WorldBounds(width: 69_632, height: 12_288),
                                  economy: GameEconomy(balance: 1_000_000, costs: SingleTrackMeet.costs), clock: GameClock(speed: .normal))
        for point in SingleTrackMeet.points() { _ = try world.buildTrackNode(at: point) }
        let (entrance, exit) = SingleTrackMeet.curves()
        for edge in 1...3 { _ = try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        _ = try world.buildTrackEdge(from: .node(2), to: .node(5), curve: entrance)
        _ = try world.buildTrackEdge(from: .node(5), to: .node(6))
        _ = try world.buildTrackEdge(from: .node(6), to: .node(3), curve: exit)
        for (name, x) in [("W", Int64(3_072)), ("M", 17_408), ("E", 31_744)] {
            _ = try world.buildStation(named: name, at: PlanPoint(x: x, y: 8_192))
        }
        for (station, edge, start, end) in SingleTrackMeet.platforms() {
            try world.addTrackPlatform(station, on: .edge(edge), from: start, to: end)
        }
        // C on e7, D on e8, straight on east of E.
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 49_152, y: 4_096))
        let d = try world.buildTrackNode(at: WorldCoordinate(x: 65_536, y: 4_096))
        _ = try world.buildTrackEdge(from: .node(4), to: c)
        _ = try world.buildTrackEdge(from: c, to: d)
        let station = try world.buildStation(named: "C", at: PlanPoint(x: 47_104, y: 8_192)).id
        let depot = try world.buildStation(named: "D", at: PlanPoint(x: 63_488, y: 8_192)).id
        XCTAssertEqual([station, depot], [Self.station, Self.depot])
        try world.addTrackPlatform(station, on: .edge(7), from: 5_120, to: 7_168)
        try world.addTrackPlatform(depot, on: .edge(8), from: 1_024, to: 3_072)
        try world.setStationDepot(depot, to: true)
        let line = try world.createLine(named: "L", stops: [station, SingleTrackMeet.middle]).id
        try world.setLineRuns(line, to: [
            LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 21_900, departure: 21_900), LineRunTime(arrival: 22_500, departure: 22_500)]),
        ])
        try world.setLineDepots(line, to: [depot])
        let spare = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(3), offset: 7_168)
        let service = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(7), offset: 7_168)
        for id in [spare, service] { try world.assignTrain(id, to: line) }
        try world.setTrafficControl(true)
        XCTAssertFalse(world.blockSections)
        return (world, line, spare, service)
    }

    /// From 06:05 C's run waits for E's train, whose way into D C's train
    /// stands on: E's train runs empty to M, the nearest berth where it
    /// lets C's run go, and C's run leaves. Before, E's train never moved
    /// and C's run was never sent out, with no deadlock found.
    func testATrainBetweenRunsInTheWayMakesWay() throws {
        var (world, line, spare, service) = try spareInTheWay()
        while world.clock.now < GameTime(minutes: 6 * 60 + 5) { try world.advance(ticks: 1) }
        XCTAssertTrue(world.stationsStoppedAt(by: spare).contains(SingleTrackMeet.east), "E's train is still where it stood")
        var sent = false
        while world.clock.now < GameTime(minutes: 6 * 60 + 30) {
            try world.advance(ticks: 1)
            if world.train(id: service)?.execution != nil { sent = true }
            XCTAssertEqual(WorldInvariants.violations(in: world), [])
        }
        XCTAssertFalse(world.stationsStoppedAt(by: spare).contains(SingleTrackMeet.east), "E's train made way")
        XCTAssertEqual(world.line(id: line)?.runDays[0], 0, "C's 06:05 left")
        XCTAssertTrue(sent, "C's train went on its run")
        XCTAssertEqual(world.stationsStoppedAt(by: service), [SingleTrackMeet.middle], "C's train ended its run at M")
        XCTAssertEqual(world.deadlockedTrains(), [])
    }

    /// The trains move at whole minutes, so a batch ends where minute by
    /// minute does.
    func testABatchEndsWhereMinutesDo() throws {
        var (world, _, _, _) = try spareInTheWay()
        while world.clock.now < GameTime(minutes: 6 * 60) { try world.advance(ticks: 1) }
        var single = world
        for _ in 0..<30 { try single.advance(ticks: 1) }
        var batched = world
        try batched.advance(ticks: 30)
        XCTAssertEqual(batched, single)
    }
}
