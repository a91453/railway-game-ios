import Foundation
@testable import GameCore
import XCTest

/// Route reservation under traffic control (Phase 4.6 Stage T, ARCHITECTURE
/// decision 32): turning traffic control on and off, what a route
/// reserves on the track network (spans, partial edges,
/// where a path ends, long trains, curves, levels and platforms), junctions
/// and fouling, refused commands and infrastructure changes, services and
/// lines that wait for their routes, and saves. The grid's half went with
/// the grid (Stage F3c-3b); the rules only it covered were first written
/// again on the network (the section "Rules first tested on the grid").
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run. Span boundaries follow S3A: an edge `L`
/// long is cut into `n = ⌈L ÷ 1024⌉` parts at `⌊k × L ÷ n⌋`, and again at
/// its platforms' ends.
final class TrafficControlTests: XCTestCase {
    private func node(_ number: Int) -> TrackResource {
        .node(.node(number))
    }

    private func span(_ edge: Int, _ start: Int64, _ end: Int64) -> TrackResource {
        .span(TrackSpan(edge: .edge(edge), start: start, end: end))
    }

    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private func backward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .backward)
    }

    private func buy(_ world: inout GameWorld, cars: Int = 1) throws -> TrainID {
        let id = try world.purchaseTrain(named: "T\(world.trains.count + 1)").id
        try world.setTrainCars(id, to: cars)
        return id
    }

    /// Places a train on the network and stops it where it is placed (a
    /// path ending at its head; none at the end of an edge).
    private func stand(_ world: inout GameWorld, cars: Int = 1, at traversal: TrackTraversal, _ offset: Int64) throws -> TrainID {
        let id = try buy(&world, cars: cars)
        try world.placeTrain(id, at: .onEdge(traversal, offset: offset))
        let length = try XCTUnwrap(world.trackEdge(traversal.edge)?.length)
        try world.setTrainContinuation(id, along: [], stoppingAt: offset < length ? offset : nil)
        return id
    }

    // MARK: - The straight network
    //
    //   n1 ──e1── n2 ──e2── n3     y = 1024, on the surface
    //
    // e1 is 5120 long: five spans of 1024. e2 is 3000 long: three spans cut
    // at 1000 and 2000. n2 is plain track, n1 and n3 dead ends.

    private func makeLineWorld() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 12_288, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let n1 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 1_024))
        let n2 = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 1_024))
        let n3 = try world.buildTrackNode(at: WorldCoordinate(x: 9_144, y: 1_024))
        try world.buildTrackEdge(from: n1, to: n2)
        try world.buildTrackEdge(from: n2, to: n3)
        return world
    }

    /// Trains on one long edge take only the spans they need; spans another
    /// train holds are refused. A train placed part of the way along an
    /// edge runs on to its end by itself, and takes that.
    func testTrainsReserveTheSpansOfAnEdgeTheyNeed() throws {
        var world = try makeLineWorld()
        XCTAssertEqual(world.trackSpans(of: .edge(2)).map(\.end), [1_000, 2_000, 3_000])
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 500))
        XCTAssertEqual(world.reservedResources(of: one), [
            node(2), span(1, 0, 1_024), span(1, 1_024, 2_048), span(1, 2_048, 3_072), span(1, 3_072, 4_096), span(1, 4_096, 5_120),
        ])
        try world.setTrainContinuation(one, along: [], stoppingAt: 1_500)
        XCTAssertEqual(world.reservedResources(of: one), [span(1, 0, 1_024), span(1, 1_024, 2_048)])

        let two = try buy(&world)
        try world.placeTrain(two, at: .onEdge(forward(1), offset: 3_000))
        try world.setTrainContinuation(two, along: [], stoppingAt: 4_000)
        XCTAssertEqual(world.reservedResources(of: two), [span(1, 2_048, 3_072), span(1, 3_072, 4_096)])

        let three = try buy(&world)
        let before = world
        XCTAssertThrowsGameError(try world.placeTrain(three, at: .onEdge(forward(1), offset: 1_800)), .trackReserved(one))
        XCTAssertEqual(world, before)
        try world.placeTrain(three, at: .onEdge(forward(2), offset: 100))
        XCTAssertEqual(world.reservedResources(of: three), [node(3), span(2, 0, 1_000), span(2, 1_000, 2_000), span(2, 2_000, 3_000)])
    }

    /// The rest of the train's edge, the edges between whole, the last up
    /// to where the path stops; released behind the train as it goes
    /// (Stage U), and all of it when the head gets there.
    func testAPathTakesPartsOfItsFirstAndLastEdges() throws {
        var world = try makeLineWorld()
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 4_600))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 1_500)
        let route = [node(2), span(1, 4_096, 5_120), span(2, 0, 1_000), span(2, 1_000, 2_000)]
        XCTAssertEqual(world.reservedResources(of: one), route)
        try world.setTrainMovementRate(one, to: 1_024)
        // 520 to n2, then 504 along e2: n2 and e1 are behind it now.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(2), offset: 504))
        XCTAssertEqual(world.reservedResources(of: one), [span(2, 0, 1_000), span(2, 1_000, 2_000)])
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(2), offset: 1_500))
        XCTAssertEqual(world.reservedResources(of: one), [])
        XCTAssertEqual(world.heldResources(of: one), [span(2, 1_000, 2_000)])
    }

    /// A path that stops on a span boundary takes the spans on both sides,
    /// as a train standing there holds both: nothing is left for another
    /// train to slip into.
    func testAPathEndingOnABoundaryTakesBothSides() throws {
        var world = try makeLineWorld()
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 1_000))
        try world.setTrainContinuation(one, along: [], stoppingAt: 2_048)
        XCTAssertEqual(world.reservedResources(of: one), [span(1, 0, 1_024), span(1, 1_024, 2_048), span(1, 2_048, 3_072)])
        try world.setTrainMovementRate(one, to: 1_024)
        try world.advance(ticks: 2)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(1), offset: 2_048))
        XCTAssertEqual(world.heldResources(of: one), [span(1, 1_024, 2_048), span(1, 2_048, 3_072)])
        let two = try buy(&world)
        XCTAssertThrowsGameError(try world.placeTrain(two, at: .onEdge(forward(1), offset: 2_500)), .trackReserved(one))
    }

    /// A long train reserves from its tail: its body's spans are part of
    /// its route.
    func testALongNetworkTrainReservesFromItsTail() throws {
        var world = try makeLineWorld()
        try world.setTrafficControl(true)
        // Three cars, 2048 long, head at 3000: the body covers 952 to 3000.
        let one = try buy(&world, cars: 3)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 3_000))
        try world.setTrainContinuation(one, along: [], stoppingAt: 4_500)
        let all = [span(1, 0, 1_024), span(1, 1_024, 2_048), span(1, 2_048, 3_072), span(1, 3_072, 4_096), span(1, 4_096, 5_120)]
        XCTAssertEqual(world.reservedResources(of: one), all)
        XCTAssertEqual(world.occupiedResources(of: one), Array(all.prefix(3)))
        // Backward from 4700 is chainage 420; placed there a train runs on
        // to n1, over span 0–1024, which holds the long train's tail.
        let two = try buy(&world)
        XCTAssertThrowsGameError(try world.placeTrain(two, at: .onEdge(backward(1), offset: 4_700)), .trackReserved(one))
    }

    // MARK: - Curves, levels and an underground platform
    //
    // - e1: the quarter curve of network-service.json, (12288, 4096) to
    //   (16384, 8192), 6346 long: seven spans cut at ⌊k × 6346 ÷ 7⌋ = 906,
    //   1813, 2719, 3626, 4532, 5439.
    // - e2: a viaduct 512 up from (2048, 12288) to (10240, 12288), 8192.
    // - e3: a tunnel 512 down from (2048, 16384) to (10240, 16384), 8192,
    //   with Deep's platform from 1500 to 5596: its spans are the eight of
    //   1024 cut again at 1500 and 5596.

    private func makeLevelsWorld() throws -> (world: GameWorld, deep: StationID) {
        var world = try GameWorld(bounds: WorldBounds(width: 20_480, height: 20_480), economy: GameEconomy(balance: 10_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let c1 = try world.buildTrackNode(at: WorldCoordinate(x: 12_288, y: 4_096))
        let c2 = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        try world.buildTrackEdge(from: c1, to: c2, curve: .cubic(PlanPoint(x: 14_336, y: 4_096), PlanPoint(x: 16_384, y: 6_144)))
        let v1 = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 12_288, z: 512))
        let v2 = try world.buildTrackNode(at: WorldCoordinate(x: 10_240, y: 12_288, z: 512))
        try world.buildTrackEdge(from: v1, to: v2, structure: .elevated)
        let t1 = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 16_384, z: -512))
        let t2 = try world.buildTrackNode(at: WorldCoordinate(x: 10_240, y: 16_384, z: -512))
        try world.buildTrackEdge(from: t1, to: t2, structure: .tunnel)
        let deep = try world.buildStation(named: "Deep", at: PlanPoint(x: 1_536, y: 1_536)).id
        try world.addTrackPlatform(deep, on: .edge(3), from: 1_500, to: 5_596)
        return (world, deep)
    }

    /// Curves and levels change nothing: only the integer chainage counts.
    func testCurvedElevatedAndUndergroundTrackReserveBySpan() throws {
        var (world, deep) = try makeLevelsWorld()
        XCTAssertEqual(world.trackEdge(.edge(1))?.length, 6_346)
        try world.setTrafficControl(true)
        let curve = try buy(&world)
        try world.placeTrain(curve, at: .onEdge(forward(1), offset: 1_000))
        try world.setTrainContinuation(curve, along: [], stoppingAt: 3_000)
        XCTAssertEqual(world.reservedResources(of: curve), [span(1, 906, 1_813), span(1, 1_813, 2_719), span(1, 2_719, 3_626)])

        let viaduct = try buy(&world)
        try world.placeTrain(viaduct, at: .onEdge(forward(2), offset: 100))
        try world.setTrainContinuation(viaduct, along: [], stoppingAt: 2_000)
        XCTAssertEqual(world.reservedResources(of: viaduct), [span(2, 0, 1_024), span(2, 1_024, 2_048)])

        // Three cars into the tunnel to Deep's forward berth, 5596, its body
        // from 952: the spans from 0 to the berth, and the one beyond it
        // that the head touches there.
        let mole = try buy(&world, cars: 3)
        try world.placeTrain(mole, at: .onEdge(forward(3), offset: 3_000))
        let path = try XCTUnwrap(world.path(from: .onEdge(forward(3), offset: 3_000), toStation: deep, length: 2_048))
        XCTAssertEqual(path, TrainPath(traversals: [], end: 5_596, distance: 2_596))
        try world.setTrainContinuation(mole, along: path.traversals, stoppingAt: path.end)
        XCTAssertEqual(world.reservedResources(of: mole), [
            span(3, 0, 1_024), span(3, 1_024, 1_500), span(3, 1_500, 2_048), span(3, 2_048, 3_072),
            span(3, 3_072, 4_096), span(3, 4_096, 5_120), span(3, 5_120, 5_596), span(3, 5_596, 6_144),
        ])
        try world.setTrainMovementRate(mole, to: 2_048)
        try world.advance(ticks: 2)
        XCTAssertEqual(world.stationsBesideWholeTrain(mole), [deep])
        XCTAssertEqual(world.reservedResources(of: mole), [])
        XCTAssertEqual(world.heldResources(of: mole), [span(3, 3_072, 4_096), span(3, 4_096, 5_120), span(3, 5_120, 5_596), span(3, 5_596, 6_144)])
    }

    /// The backward berth of an underground platform: the head stops at
    /// its start, 8192 − 1500 = 6692 along the way it runs.
    func testABackwardBerthIsReservedToThePlatformsStart() throws {
        var (world, deep) = try makeLevelsWorld()
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(backward(3), offset: 100))
        let path = try XCTUnwrap(world.path(from: .onEdge(backward(3), offset: 100), toStation: deep))
        XCTAssertEqual(path, TrainPath(traversals: [], end: 6_692, distance: 6_592))
        try world.setTrainContinuation(one, along: path.traversals, stoppingAt: path.end)
        // Chainage 8092 back to 1500, touching the boundary at 1500.
        XCTAssertEqual(world.reservedResources(of: one), [
            span(3, 1_024, 1_500), span(3, 1_500, 2_048), span(3, 2_048, 3_072), span(3, 3_072, 4_096), span(3, 4_096, 5_120),
            span(3, 5_120, 5_596), span(3, 5_596, 6_144), span(3, 6_144, 7_168), span(3, 7_168, 8_192),
        ])
    }

    // MARK: - A turnout on the network
    //
    //   j0 ──s── J ──a── A      a: J (7168, 8192) east to (15360, 8192), 8192
    //             ╲
    //              b── B        b: J to (15872, 8720), 8720 (a 1088-66-1090
    //                           triangle times 8), 1 in 16.5 off a
    //
    // s (5120, five spans) arrives at J from the west; a and b both join it
    // there but not each other, so a's and b's ends at J are fouling ends
    // and s's is not. b's spans are cut at ⌊k × 8720 ÷ 9⌋: 968, 1937, ...

    private func makeJunctionWorld() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 20_480, height: 12_288), economy: GameEconomy(balance: 10_000_000, costs: testCosts))
        let j0 = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 8_192))
        let junction = try world.buildTrackNode(at: WorldCoordinate(x: 7_168, y: 8_192))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 15_360, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 15_872, y: 8_720))
        try world.buildTrackEdge(from: j0, to: junction)
        try world.buildTrackEdge(from: junction, to: a)
        try world.buildTrackEdge(from: junction, to: b)
        return world
    }

    /// Routes onto either branch meet at the junction node.
    func testRoutesThroughATurnoutMeetAtItsNode() throws {
        var world = try makeJunctionWorld()
        XCTAssertEqual(world.transitions(after: forward(1)), [forward(2), forward(3)])
        XCTAssertEqual(world.trackEdge(.edge(3))?.length, 8_720)
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 1_000))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 2_000)
        XCTAssertEqual(world.reservedResources(of: one), [
            node(2), span(1, 0, 1_024), span(1, 1_024, 2_048), span(1, 2_048, 3_072), span(1, 3_072, 4_096), span(1, 4_096, 5_120),
            span(2, 0, 1_024), span(2, 1_024, 2_048),
        ])
        // Back along b from chainage 1720 to J: alone, it takes J and two
        // spans of b, so all it shares with the first route is J.
        var alone = try makeJunctionWorld()
        try alone.setTrafficControl(true)
        let lone = try buy(&alone)
        try alone.placeTrain(lone, at: .onEdge(backward(3), offset: 7_000))
        XCTAssertEqual(alone.reservedResources(of: lone), [node(2), span(3, 0, 968), span(3, 968, 1_937)])
        let two = try buy(&world)
        XCTAssertThrowsGameError(try world.placeTrain(two, at: .onEdge(backward(3), offset: 7_000)), .trackReserved(one))
    }

    /// A train standing on a branch within 1024 of the junction fouls it:
    /// it holds the node, and no route may pass there; one on the stem
    /// does not.
    func testATrainNearAJunctionFoulsIt() throws {
        var world = try makeJunctionWorld()
        // Placed facing the junction, a train would run on to it: these two
        // stand before traffic control is on.
        let one = try stand(&world, at: forward(1), 1_000)
        let branch = try stand(&world, at: forward(2), 300)
        try world.setTrafficControl(true)
        XCTAssertEqual(world.occupiedResources(of: branch), [span(2, 0, 1_024)])
        XCTAssertEqual(world.heldResources(of: branch), [node(2), span(2, 0, 1_024)])
        XCTAssertEqual(world.heldResources(of: one), [span(1, 0, 1_024)])
        // On the stem, 320 short of J: no fouling end there.
        var stemWorld = try makeJunctionWorld()
        let stem = try stand(&stemWorld, at: forward(1), 4_800)
        XCTAssertEqual(stemWorld.heldResources(of: stem), [span(1, 4_096, 5_120)])

        let before = world
        XCTAssertThrowsGameError(try world.setTrainContinuation(one, along: [forward(3)], stoppingAt: 4_000), .trackReserved(branch))
        XCTAssertEqual(world, before)
        // Past the zone a train on a no longer holds the junction, but until
        // a and b have parted (b is less than 256 from a up to about 4228
        // along it) it fouls a route along b there (Stage F2b).
        try world.unplaceTrain(branch)
        let near = try stand(&world, at: forward(2), 1_024)
        XCTAssertEqual(world.heldResources(of: near), [span(2, 0, 1_024), span(2, 1_024, 2_048)])
        XCTAssertThrowsGameError(try world.setTrainContinuation(one, along: [forward(3)], stoppingAt: 4_000), .trackReserved(near))
        // Beyond the parting (b is 310 from a at 5120 along a) the branch is
        // free to share the junction.
        try world.unplaceTrain(near)
        let far = try stand(&world, at: forward(2), 6_144)
        XCTAssertEqual(world.heldResources(of: far), [span(2, 5_120, 6_144), span(2, 6_144, 7_168)])
        try world.setTrainContinuation(one, along: [forward(3)], stoppingAt: 4_000)

        // Two trains within the zone on the two branches cannot both stand
        // there under traffic control.
        var both = try makeJunctionWorld()
        let first = try stand(&both, at: forward(2), 300)
        let second = try stand(&both, at: forward(3), 300)
        XCTAssertThrowsGameError(try both.setTrafficControl(true), .trainsShareTrack(first, second))
    }

    /// A new edge at a junction a train holds, or is close to, would change
    /// who fouls it: refused. Elsewhere building goes on.
    func testTrackCannotBeAddedAtAHeldJunction() throws {
        var world = try makeJunctionWorld()
        try world.setTrafficControl(true)
        let branch = try stand(&world, at: forward(2), 300)
        let spur = try world.buildTrackNode(at: WorldCoordinate(x: 7_168, y: 11_264))
        let before = world
        XCTAssertThrowsGameError(try world.buildTrackEdge(from: .node(2), to: spur), .trackReserved(branch))
        XCTAssertEqual(world, before)
        let far = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 11_264))
        try world.buildTrackEdge(from: far, to: spur)
        try world.unplaceTrain(branch)
        try world.buildTrackEdge(from: .node(2), to: spur)
    }

    // MARK: - A level crossing and a flyover on the network
    //
    // A diamond at C (6144, 8192): w (4096 long) from the west, e east, n
    // from the north, s south; w and e join, n and s join, the two lines do
    // not. A viaduct g 512 up runs north–south over e at x = 8192.

    private func makeCrossingWorld() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 16_384, height: 16_384), economy: GameEconomy(balance: 10_000_000, costs: testCosts))
        let w = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 8_192))
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 8_192))
        let e = try world.buildTrackNode(at: WorldCoordinate(x: 10_240, y: 8_192))
        let n = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 4_096))
        let s = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 12_288))
        try world.buildTrackEdge(from: w, to: c)
        try world.buildTrackEdge(from: c, to: e)
        try world.buildTrackEdge(from: n, to: c)
        try world.buildTrackEdge(from: c, to: s)
        let g1 = try world.buildTrackNode(at: WorldCoordinate(x: 8_192, y: 4_096, z: 512))
        let g2 = try world.buildTrackNode(at: WorldCoordinate(x: 8_192, y: 12_288, z: 512))
        try world.buildTrackEdge(from: g1, to: g2, structure: .elevated)
        return world
    }

    /// Both lines of a level crossing need its node; a train waiting just
    /// short of it fouls it. A flyover shares nothing with the line below.
    func testALevelCrossingIsSharedAndAFlyoverIsNot() throws {
        var world = try makeCrossingWorld()
        try world.setTrafficControl(true)
        // Each placed facing C runs on to it by itself until stopped.
        let down = try stand(&world, at: forward(3), 500)
        let across = try stand(&world, at: forward(1), 1_000)
        try world.setTrainContinuation(across, along: [forward(2)], stoppingAt: 1_000)
        XCTAssertThrowsGameError(try world.setTrainContinuation(down, along: [forward(4)], stoppingAt: 2_000), .trackReserved(across))
        try world.unplaceTrain(across)
        let waiting = try stand(&world, at: forward(1), 3_500)
        XCTAssertEqual(world.heldResources(of: waiting), [node(2), span(1, 3_072, 4_096)])
        XCTAssertThrowsGameError(try world.setTrainContinuation(down, along: [forward(4)], stoppingAt: 2_000), .trackReserved(waiting))

        var flyover = try makeCrossingWorld()
        let over = try stand(&flyover, at: forward(5), 4_096)
        let under = try stand(&flyover, at: forward(2), 2_048)
        try flyover.setTrafficControl(true)
        XCTAssertEqual(flyover.heldResources(of: over), [span(5, 3_072, 4_096), span(5, 4_096, 5_120)])
        XCTAssertEqual(flyover.heldResources(of: under), [span(2, 1_024, 2_048), span(2, 2_048, 3_072)])
    }

    // MARK: - Infrastructure

    /// Under traffic control the spans of an edge a train holds keep their
    /// meaning: no platform comes or goes there, and a reserved edge stays.
    /// Other edges change as before.
    func testHeldEdgesKeepTheirSpans() throws {
        var world = try makeLineWorld()
        let station = try world.buildStation(named: "P", at: PlanPoint(x: 1_536, y: 3_584)).id
        try world.addTrackPlatform(station, on: .edge(2), from: 100, to: 1_100)
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 500))
        try world.setTrainContinuation(one, along: [], stoppingAt: 1_500)
        let before = world
        XCTAssertThrowsGameError(try world.addTrackPlatform(station, on: .edge(1), from: 3_000, to: 4_000), .trackReserved(one))
        XCTAssertEqual(world, before)
        try world.removeTrackPlatform(station, on: .edge(2), from: 100)
        try world.addTrackPlatform(station, on: .edge(2), from: 2_000, to: 3_000)

        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 1_000)
        XCTAssertThrowsGameError(try world.removeTrackPlatform(station, on: .edge(2), from: 2_000), .trackReserved(one))
        XCTAssertThrowsGameError(try world.removeTrackEdge(.edge(2)), .trackEdgeHasPlatform(.edge(2)))
        // Standing at its end it still holds the spans it stands on.
        try world.setTrainMovementRate(one, to: 8_192)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.reservedResources(of: one), [])
        XCTAssertThrowsGameError(try world.removeTrackPlatform(station, on: .edge(2), from: 2_000), .trackReserved(one))
        try world.unplaceTrain(one)
        try world.removeTrackPlatform(station, on: .edge(2), from: 2_000)

        // A reserved edge cannot be removed, though no train is on it yet.
        let two = try buy(&world)
        try world.placeTrain(two, at: .onEdge(forward(1), offset: 4_000))
        try world.setTrainContinuation(two, along: [forward(2)], stoppingAt: 500)
        XCTAssertThrowsGameError(try world.removeTrackEdge(.edge(2)), .trackReserved(two))
    }

    // MARK: - Services on the network

    /// A timetable on the network waits for its route and turns round only
    /// once it can go.
    func testANetworkServiceWaitsAndTurnsRoundOnlyToGo() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 20_480, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let nodes = try [1_024, 9_216, 17_408].map { try world.buildTrackNode(at: WorldCoordinate(x: $0, y: 1_024)) }
        try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        try world.buildTrackEdge(from: nodes[1], to: nodes[2])
        let west = try world.buildStation(named: "W", at: PlanPoint(x: 1_536, y: 3_584)).id
        let east = try world.buildStation(named: "E", at: PlanPoint(x: 2_560, y: 3_584)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 1_024, to: 5_120)
        try world.addTrackPlatform(east, on: .edge(2), from: 3_072, to: 7_168)
        // At E's forward berth, 7168 along e2; back to W's backward berth on
        // e1, 8192 − 1024 = 7168 along e1 run backward.
        let one = try stand(&world, at: forward(2), 7_168)
        try world.setTrainMovementRate(one, to: 1_024)
        try world.setTrainTimetable(one, to: [
            ScheduledStop(station: east, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1), reverses: true),
            ScheduledStop(station: west, arrival: GameTime(minutes: 30), departure: GameTime(minutes: 30)),
        ])
        try world.startTrainService(one)
        let blocker = try stand(&world, at: forward(1), 3_000)
        try world.setTrafficControl(true)
        try world.advance(ticks: 3)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(2), offset: 7_168))
        XCTAssertEqual(world.train(id: one)?.execution, .waitingAtStop(0, cycle: 0))
        XCTAssertEqual(world.trainHoldingRoute(of: one), blocker)

        try world.unplaceTrain(blocker)
        try world.advance(ticks: 1)
        // Turned round (1024 along e2 backward), then a minute along its run
        // of 7168 + 7168 = 14336 units in the 29 minutes its timetable gives
        // it.
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(backward(2), offset: 1_024 + runDistance(14_336, in: 1_740, after: 60)))
        XCTAssertEqual(world.train(id: one)?.execution, .travellingToStop(1, cycle: 0))
        // From chainage 7168 back along e2 to n2, and e1 back to 7168 along
        // it: chainage 1024. Standing on the boundary at 7168 it held e2's
        // span beyond it too; it has left that behind (Stage U), less than
        // 1024 along, so it is still on the span before.
        XCTAssertLessThan(runDistance(14_336, in: 1_740, after: 60), 1_024)
        XCTAssertEqual(world.reservedResources(of: one), [
            node(2), span(1, 1_024, 2_048), span(1, 2_048, 3_072), span(1, 3_072, 4_096), span(1, 4_096, 5_120), span(1, 5_120, 6_144),
            span(1, 6_144, 7_168), span(1, 7_168, 8_192), span(1, 0, 1_024),
            span(2, 0, 1_024), span(2, 1_024, 2_048), span(2, 2_048, 3_072), span(2, 3_072, 4_096), span(2, 4_096, 5_120),
            span(2, 5_120, 6_144), span(2, 6_144, 7_168),
        ].sorted())
    }

    // MARK: - Rules first tested on the grid, on the network (Stage F3c)
    //
    // The grid tests went with the grid (Stage F3c-3b); these keep each
    // rule they alone covered, on the straight network (`makeLineWorld`) or
    // the network of two stations below. Each names the test it replaced.

    /// `testWithoutTrafficControlTrainsShareTrackAsBefore`: off, trains on
    /// the network stand on the same span; nothing is reserved or saved.
    func testWithoutTrafficControlNetworkTrainsShareTrackAsBefore() throws {
        var world = try makeLineWorld()
        XCTAssertFalse(world.isTrafficControlEnabled)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 700))
        let two = try buy(&world)
        try world.placeTrain(two, at: .onEdge(forward(1), offset: 700))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 1_500)
        XCTAssertEqual(world.occupancyConflicts(), [TrackConflict(resource: span(1, 0, 1_024), trains: [one, two])])
        XCTAssertEqual(world.reservedResources(of: one), [])
        XCTAssertEqual(world.heldResources(of: one), [span(1, 0, 1_024)])
        XCTAssertNil(world.trainHoldingRoute(of: one))
        let json = try encoded(world)
        XCTAssertNil(json["trafficControl"])
        let trains = try XCTUnwrap(json["trains"] as? [[String: Any]])
        XCTAssertTrue(trains.allSatisfy { $0["reservation"] == nil })
    }

    /// `testTurningTrafficControlOnAndOff`: on, a train with a way to go
    /// takes all of it and a standing train only its place; on twice is on;
    /// off gives back exactly the world before.
    func testTurningTrafficControlOnAndOffOnTheNetwork() throws {
        var world = try makeLineWorld()
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 4_600))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 1_500)
        let two = try stand(&world, at: forward(1), 1_500)
        let off = world

        try world.setTrafficControl(true)
        XCTAssertTrue(world.isTrafficControlEnabled)
        let route = [node(2), span(1, 4_096, 5_120), span(2, 0, 1_000), span(2, 1_000, 2_000)]
        XCTAssertEqual(world.reservedResources(of: one), route)
        XCTAssertEqual(world.train(id: one)?.reservation, route)
        XCTAssertEqual(world.heldResources(of: one), route)
        XCTAssertEqual(world.reservedResources(of: two), [])
        XCTAssertEqual(world.heldResources(of: two), [span(1, 1_024, 2_048)])
        let on = world
        try world.setTrafficControl(true)
        XCTAssertEqual(world, on)

        try world.setTrafficControl(false)
        XCTAssertEqual(world, off)
        XCTAssertEqual(world.reservedResources(of: one), [])
    }

    /// `testGridRoutesAreTakenWholeAndKeptForTheTrip`, the parts no network
    /// test had: rate 0 and a new rate keep the reservation, and removing
    /// an edge a train stands on is refused as in use before as reserved.
    func testANetworkReservationOutlastsRate0AndTrackInUseComesFirst() throws {
        var world = try makeLineWorld()
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 4_600))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 1_500)
        let route = [node(2), span(1, 4_096, 5_120), span(2, 0, 1_000), span(2, 1_000, 2_000)]
        let before = world
        // e1 is in use (one stands on it) and reserved; e2 only reserved.
        XCTAssertThrowsGameError(try world.removeTrackEdge(.edge(1)), .trackEdgeInUse(.edge(1)))
        XCTAssertThrowsGameError(try world.removeTrackEdge(.edge(2)), .trackReserved(one))
        XCTAssertEqual(world, before)

        try world.setTrainMovementRate(one, to: 0)
        try world.advance(ticks: 2)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(1), offset: 4_600))
        XCTAssertEqual(world.reservedResources(of: one), route)
        try world.setTrainMovementRate(one, to: 1_024)
        XCTAssertEqual(world.reservedResources(of: one), route)
    }

    /// `testALinkRunsOnToItsEnd`: a train part of the way along an edge runs
    /// to its end by itself, so turning it round there takes the other end;
    /// refused, with nothing changed, while another train holds that.
    func testATrainTurnedRoundOnAnEdgeTakesItsOtherEnd() throws {
        var world = try makeLineWorld()
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 500))
        XCTAssertEqual(world.reservedResources(of: one), [
            node(2), span(1, 0, 1_024), span(1, 1_024, 2_048), span(1, 2_048, 3_072), span(1, 3_072, 4_096), span(1, 4_096, 5_120),
        ])
        // At n1, the end of e1 run backward: it holds n1 alone and stands.
        let two = try buy(&world)
        try world.placeTrain(two, at: .onEdge(backward(1), offset: 5_120))
        XCTAssertEqual(world.heldResources(of: two), [node(1)])
        XCTAssertEqual(world.reservedResources(of: two), [])
        let before = world
        XCTAssertThrowsGameError(try world.reverseTrain(one), .trackReserved(two))
        XCTAssertEqual(world, before)

        try world.unplaceTrain(two)
        try world.reverseTrain(one)
        // 5120 − 500 along e1 run backward, the same point, running to n1.
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(backward(1), offset: 4_620))
        XCTAssertEqual(world.reservedResources(of: one), [node(1), span(1, 0, 1_024)])
    }

    /// `testATrainWaitingForRemovedTrackKeepsItsWayThroughTheGap`, where the
    /// network differs: an edge that was removed never comes back, so a
    /// path broken by one is reserved to where it breaks, the end of the
    /// last edge the train can reach.
    func testAPathBrokenByARemovedEdgeIsReservedToWhereItBreaks() throws {
        var world = try makeLineWorld()
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 4_600))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 1_500)
        try world.removeTrackEdge(.edge(2))
        try world.setTrafficControl(true)
        XCTAssertEqual(world.reservedResources(of: one), [node(2), span(1, 4_096, 5_120)])
        XCTAssertNil(WorldInvariants.roundTripProblem(of: world))
    }

    // Two stations on two edges of 8192, n1 (1024, 1024) to n2 (9216,
    // 1024) to n3 (17408, 1024): W's platform on e1 from 1024 to 5120, E's
    // on e2 from 3072 to 7168. Every span is 1024 long. The stations stand
    // at points, as every station will once the grid is gone.
    private func makeStationsWorld() throws -> (world: GameWorld, west: StationID, east: StationID) {
        var world = try GameWorld(bounds: WorldBounds(width: 20_480, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let nodes = try [1_024, 9_216, 17_408].map { try world.buildTrackNode(at: WorldCoordinate(x: $0, y: 1_024)) }
        try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        try world.buildTrackEdge(from: nodes[1], to: nodes[2])
        let west = try world.buildStation(named: "W", at: PlanPoint(x: 3_072, y: 2_048)).id
        let east = try world.buildStation(named: "E", at: PlanPoint(x: 13_312, y: 2_048)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 1_024, to: 5_120)
        try world.addTrackPlatform(east, on: .edge(2), from: 3_072, to: 7_168)
        return (world, west, east)
    }

    /// From W's forward berth (5120 along e1) to E's (7168 along e2): the
    /// rest of e1, n2 and e2 up to 7168, with the spans on both sides of
    /// each end, where the train stands and where it stops.
    private var westToEast: [TrackResource] {
        [node(2), span(1, 4_096, 5_120), span(1, 5_120, 6_144), span(1, 6_144, 7_168), span(1, 7_168, 8_192)]
            + stride(from: Int64(0), through: 7_168, by: 1_024).map { span(2, $0, $0 + 1_024) }
    }

    /// `testAServiceWaitsForItsRoute`, the part no network test had:
    /// stopping a service keeps its reservation, released when the train
    /// gets to the end of its path. A minute after it set off from the
    /// boundary at 5120 (less than 1024 along its run of 10240 in 29
    /// minutes) it has left W's last span behind (Stage U).
    func testStoppingANetworkServiceKeepsItsReservation() throws {
        var (world, west, east) = try makeStationsWorld()
        try world.setTrafficControl(true)
        let one = try stand(&world, at: forward(1), 5_120)
        try world.setTrainMovementRate(one, to: 1_024)
        try world.setTrainTimetable(one, to: [
            ScheduledStop(station: west, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
            ScheduledStop(station: east, arrival: GameTime(minutes: 30), departure: GameTime(minutes: 30)),
        ])
        try world.startTrainService(one)
        try world.advance(ticks: 2)
        XCTAssertEqual(world.train(id: one)?.execution, .travellingToStop(1, cycle: 0))
        let along = runDistance(10_240, in: 1_740, after: 60)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(1), offset: 5_120 + along))
        XCTAssertLessThan(along, 1_024)
        let ahead = westToEast.filter { $0 != span(1, 4_096, 5_120) }
        XCTAssertEqual(world.reservedResources(of: one), ahead)

        try world.stopTrainService(one)
        XCTAssertEqual(world.reservedResources(of: one), ahead)
        // Without its service it goes on at its rate: 3072 + 7168 = 10240
        // units at most, ten minutes.
        try world.advance(ticks: 10)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(2), offset: 7_168))
        XCTAssertEqual(world.reservedResources(of: one), [])
    }

    /// `testALineWaitsToSendATrainOut`: a line does not send out a train
    /// whose first route another train holds: no dispatch, no timetable, no
    /// service; it goes at the first step the route is free. Sent out at 2,
    /// it dwells 42 s and then runs as fast as it can: from a stand at 1.5
    /// km/h/s, by 3 it has run ½ · (1.5 / 3.6) · 18² ≈ 67.5 m ≈ 4320 units,
    /// past n2 (3072) and e2's first span, which it has released (Stage U).
    func testALineWaitsToSendANetworkTrainOut() throws {
        var (world, west, east) = try makeStationsWorld()
        let one = try stand(&world, at: forward(1), 5_120)
        try world.setTrainMovementRate(one, to: 1_024)
        let line = try world.createLine(named: "L", stops: [west, east]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.assignTrain(one, to: line)
        let blocker = try stand(&world, at: forward(2), 3_000)
        try world.setTrafficControl(true)
        XCTAssertEqual(world.trainHoldingRoute(of: one), blocker)

        try world.advance(ticks: 2)
        XCTAssertNil(world.line(id: line)?.lastDispatch)
        XCTAssertNil(world.train(id: one)?.execution)
        XCTAssertEqual(world.train(id: one)?.timetable, [])
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(1), offset: 5_120))
        XCTAssertEqual(world.reservedResources(of: one), [])

        try world.unplaceTrain(blocker)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.line(id: line)?.lastDispatch, GameTime(minutes: 2))
        XCTAssertEqual(world.train(id: one)?.execution, .travellingToStop(1, cycle: 0))
        let run = try XCTUnwrap(RunningCurve.leastSeconds(length: 10_240, performance: .standard))
        let along = runDistance(10_240, in: run, after: 18) - 3_072
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(2), offset: along))
        XCTAssertTrue((1_025..<2_048).contains(along), "\(along)")
        XCTAssertEqual(world.reservedResources(of: one), stride(from: Int64(1_024), through: 7_168, by: 1_024).map { span(2, $0, $0 + 1_024) })
        XCTAssertNil(world.trainHoldingRoute(of: one))
    }

    // MARK: - Track released behind a train (Stage U)
    //
    // ARCHITECTURE decision 55: as a train moves on, its reservation keeps
    // only what it still needs, so track its tail has left is free for
    // other trains, commands and building at once.

    /// Track a train has left behind can be built on and taken at once,
    /// while what lies ahead of it stays its own.
    func testTrackLeftBehindIsFreeAtOnce() throws {
        var world = try makeLineWorld()
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 4_600))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 2_500)
        let two = try buy(&world)
        // Placed at 4000 with no path, two would run on to n2.
        XCTAssertThrowsGameError(try world.placeTrain(two, at: .onEdge(forward(1), offset: 4_000)), .trackReserved(one))
        XCTAssertThrowsGameError(try world.removeTrackEdge(.edge(1)), .trackEdgeInUse(.edge(1)))

        // 520 to n2, then 504 along e2: e1 and n2 are behind it.
        try world.setTrainMovementRate(one, to: 1_024)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(2), offset: 504))
        XCTAssertEqual(world.reservedResources(of: one), [span(2, 0, 1_000), span(2, 1_000, 2_000), span(2, 2_000, 3_000)])
        var built = world
        try built.removeTrackEdge(.edge(1))
        try world.placeTrain(two, at: .onEdge(forward(1), offset: 4_000))
        XCTAssertEqual(world.reservedResources(of: two), [node(2), span(1, 3_072, 4_096), span(1, 4_096, 5_120)])
        // Ahead of it, e2 is still its own.
        let three = try buy(&world)
        XCTAssertThrowsGameError(try world.placeTrain(three, at: .onEdge(forward(2), offset: 2_200)), .trackReserved(one))
    }

    /// A train that has passed through a turnout keeps the junction in its
    /// reservation while it is within 1024 of it on the branch, where it
    /// fouls it (decision 32, point 5), and lets it go beyond that.
    func testATrainKeepsAJunctionItHasPassedWhileItFoulsIt() throws {
        var world = try makeJunctionWorld()
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 4_600))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 3_000)
        XCTAssertEqual(world.reservedResources(of: one), [node(2), span(1, 4_096, 5_120), span(2, 0, 1_024), span(2, 1_024, 2_048), span(2, 2_048, 3_072)])
        try world.setTrainMovementRate(one, to: 1_024)
        world.setSpeed(.normal)
        // 520 to J, then 504 along a: within 1024 of J on a branch.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(2), offset: 504))
        XCTAssertEqual(world.reservedResources(of: one), [node(2), span(2, 0, 1_024), span(2, 1_024, 2_048), span(2, 2_048, 3_072)])
        // 1528 along a: past the zone and off a's first span.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(2), offset: 1_528))
        XCTAssertEqual(world.reservedResources(of: one), [span(2, 1_024, 2_048), span(2, 2_048, 3_072)])
    }

    /// Three edges of 8192 in a line, n1 (1024, 1024) to n4 (25600, 1024):
    /// W's platform on e1 from 1024 to 5120, E's on e2 from 3072 to 7168.
    /// Every span is 1024 long.
    private func makeLongStationsWorld() throws -> (world: GameWorld, west: StationID, east: StationID) {
        var world = try GameWorld(bounds: WorldBounds(width: 28_672, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let nodes = try [1_024, 9_216, 17_408, 25_600].map { try world.buildTrackNode(at: WorldCoordinate(x: $0, y: 1_024)) }
        for (from, to) in zip(nodes, nodes.dropFirst()) {
            try world.buildTrackEdge(from: from, to: to)
        }
        let west = try world.buildStation(named: "W", at: PlanPoint(x: 3_072, y: 2_048)).id
        let east = try world.buildStation(named: "E", at: PlanPoint(x: 13_312, y: 2_048)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 1_024, to: 5_120)
        try world.addTrackPlatform(east, on: .edge(2), from: 3_072, to: 7_168)
        return (world, west, east)
    }

    /// A service waiting behind a train ahead of it goes at the second the
    /// train ahead has left the track it needs, not when that train's route
    /// ends; stepping by minutes gives the same second as one second at a
    /// time.
    func testAFollowerLeavesOnceTheTrainAheadHasLeftItsTrack() throws {
        var (world, west, east) = try makeLongStationsWorld()
        try world.setTrafficControl(true)
        // The leader, 1024 along e2, runs on to the end of e3 at 20 units a
        // second.
        let leader = try stand(&world, at: forward(2), 1_024)
        try world.setTrainContinuation(leader, along: [forward(3)])
        // The follower, at W's forward berth, goes to E's: e2 up to 7168,
        // with e2's span beyond the boundary there.
        let follower = try stand(&world, at: forward(1), 5_120)
        try world.setTrainMovementRate(follower, to: 1_024)
        try world.setTrainTimetable(follower, to: [
            ScheduledStop(station: west, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
            ScheduledStop(station: east, arrival: GameTime(minutes: 30), departure: GameTime(minutes: 30)),
        ])
        try world.startTrainService(follower)
        try world.setTrainMovementRate(leader, to: 1_200)
        let start = world

        // Due at 1, it waits: the leader holds e2 ahead of itself.
        try world.advance(ticks: 5)
        XCTAssertEqual(world.train(id: follower)?.execution, .waitingAtStop(0, cycle: 0))
        XCTAssertEqual(world.trainHoldingRoute(of: follower), leader)
        // The leader's tail is past 8192, off e2, after ⌈7169 ÷ 20⌉ = 359
        // seconds (8184 along e2 after 358, 12 along e3 after 359; it is
        // never on the node itself). Stage T would have held the follower
        // until the leader's route ended, 15360 ÷ 20 = 768 seconds.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: follower)?.execution, .travellingToStop(1, cycle: 0))
        XCTAssertEqual(world.train(id: follower)?.times?.departure, GameTime(seconds: 359))
        XCTAssertEqual(world.train(id: leader)?.position, .onEdge(forward(3), offset: 32))
        XCTAssertEqual(world.reservedResources(of: leader), [node(4)] + stride(from: Int64(0), through: 7_168, by: 1_024).map { span(3, $0, $0 + 1_024) })

        var single = start
        single.setSpeed(.x1)
        for _ in 0..<3_600 {
            try single.advance(ticks: 1)
        }
        single.setSpeed(.normal)
        XCTAssertEqual(single, world)
    }

    // MARK: - Following (Stage U2)

    /// Four straight edges of 32768 (512 m) in a line along y = 1024, n1
    /// (1024, 1024) to n5 (132096, 1024), with a station on each: A on e1
    /// from 1024 to 3072, M on e2, N on e3 and B on e4, each from 14336 to
    /// 16384 (B from 28672 to 30720). Every span is 1024 long.
    private func makeFollowingWorld() throws -> (world: GameWorld, stations: [StationID]) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 133_120, height: 4_096), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let nodes = try (0..<5).map { try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + Int64($0) * 32_768, y: 1_024)) }
        for (from, to) in zip(nodes, nodes.dropFirst()) {
            try world.buildTrackEdge(from: from, to: to)
        }
        var stations: [StationID] = []
        for (name, edge, start) in [("A", 1, Int64(1_024)), ("M", 2, 14_336), ("N", 3, 14_336), ("B", 4, 28_672)] {
            let station = try world.buildStation(named: name, at: PlanPoint(x: 1_024 + Int64(edge - 1) * 32_768 + start + 1_024, y: 2_048)).id
            try world.addTrackPlatform(station, on: .edge(edge), from: start, to: start + 2_048)
            stations.append(station)
        }
        return (world, stations)
    }

    /// Stage U2: a service whose route a service ahead of it holds sets off
    /// behind it, holding its route only as far as 400 m short of the track
    /// the one ahead holds; it takes the rest as that is freed, and never
    /// comes within 400 m of it while it follows. Under U1 it would have
    /// waited at A until the leader's tail had left its whole route.
    func testAServiceFollowsAServiceAheadOfItBetweenCalls() throws {
        var (world, stations) = try makeFollowingWorld()
        let (a, m, n, b) = (stations[0], stations[1], stations[2], stations[3])
        try world.setTrafficControl(true)
        // The leader stands at M's forward berth and runs on to B, slowly:
        // 79872 units in 20 minutes.
        let leader = try stand(&world, cars: 2, at: forward(2), 16_384)
        try world.setTrainMovementRate(leader, to: 1_024)
        try world.setTrainTimetable(leader, to: [
            ScheduledStop(station: m, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
            ScheduledStop(station: b, arrival: GameTime(minutes: 21), departure: GameTime(minutes: 21)),
        ])
        // The follower stands at A's and runs to N, past M, in 7 minutes.
        let follower = try stand(&world, cars: 2, at: forward(1), 3_072)
        try world.setTrainMovementRate(follower, to: 1_024)
        try world.setTrainTimetable(follower, to: [
            ScheduledStop(station: a, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 0)),
            ScheduledStop(station: n, arrival: GameTime(minutes: 7), departure: GameTime(minutes: 7)),
        ])
        try world.startTrainService(leader)
        try world.startTrainService(follower)
        world.setSpeed(.x10)
        let start = world

        // Due at 0:42, the follower waits while the leader stands at M: a
        // train that stands is not one to follow.
        try world.advance(ticks: 50)
        XCTAssertEqual(world.train(id: follower)?.execution, .waitingAtStop(0, cycle: 0))
        XCTAssertEqual(world.trainHoldingRoute(of: follower), leader)
        // The leader leaves at 1:00, and the follower right behind it, in the
        // same step. Its route is free up to 14335 along e2 (the leader's
        // tail, at 15360 on a span boundary, holds the span ending there
        // too), 44031 from its head; 400 m short of that is 18431 on, 21503
        // along e1, and it holds its route to the end of the span there.
        try world.advance(ticks: 11)
        XCTAssertEqual(world.train(id: leader)?.execution, .travellingToStop(1, cycle: 0))
        XCTAssertEqual(world.train(id: follower)?.execution, .travellingToStop(1, cycle: 0))
        XCTAssertEqual(world.train(id: follower)?.times?.departure, GameTime(seconds: 60))
        XCTAssertEqual(world.reservedResources(of: follower).last, span(1, 20_480, 21_504))
        XCTAssertEqual(world.trainHoldingRoute(of: follower), leader)

        // Second by second until the follower arrives at N: it never holds
        // track the leader holds, and while it follows, its head stays 400 m
        // short of the first span the leader holds, to the span: at least
        // 25600 − 1023.
        var seconds = 61
        var following = 0
        while world.train(id: follower)?.execution == .travellingToStop(1, cycle: 0), seconds < 2_000 {
            try world.advance(ticks: 1)
            seconds += 1
            XCTAssertTrue(Set(world.heldResources(of: leader)).isDisjoint(with: Set(world.heldResources(of: follower))), "second \(seconds)")
            guard world.trainHoldingRoute(of: follower) == leader,
                  case .onEdge(let traversal, let offset)? = world.train(id: follower)?.position,
                  case .onEdge(let ahead, let leaderHead)? = world.train(id: leader)?.position
            else { continue }
            following += 1
            let along = { (edge: TrackEdgeID, offset: Int64) in Int64(edge.number - 1) * 32_768 + offset }
            let tail = along(ahead.edge, leaderHead) - 1_024
            let firstHeld = tail % 1_024 == 0 ? tail - 1_024 : tail / 1_024 * 1_024
            XCTAssertGreaterThanOrEqual(firstHeld - along(traversal.edge, offset), 25_600 - 1_023, "second \(seconds)")
        }
        XCTAssertEqual(world.train(id: follower)?.execution, .waitingAtStop(1, cycle: 0), "arrived at N")

        // Stepping by minutes gives the same world.
        let minutesRun = Int(seconds / 60 + 1)
        var minutes = start
        minutes.setSpeed(.normal)
        try minutes.advance(ticks: minutesRun)
        minutes.setSpeed(.x10)
        var byTicks = start
        try byTicks.advance(ticks: minutesRun * 60)
        XCTAssertEqual(minutes, byTicks)
    }

    /// Stage U2: a train coming the other way along a service's route is
    /// never one to follow, even one that goes on from its stop there: the
    /// service would only run towards it. It waits for its whole route.
    func testAServiceNeverFollowsATrainComingTheOtherWay() throws {
        var (world, stations) = try makeFollowingWorld()
        let (a, m, n) = (stations[0], stations[1], stations[2])
        try world.setTrafficControl(true)
        // Oncoming stands at N's backward berth and runs west, calling at M
        // and going on to A.
        let oncoming = try stand(&world, cars: 2, at: backward(3), 32_768 - 14_336)
        try world.setTrainMovementRate(oncoming, to: 1_024)
        try world.setTrainTimetable(oncoming, to: [
            ScheduledStop(station: n, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 0)),
            ScheduledStop(station: m, arrival: GameTime(minutes: 10), departure: GameTime(minutes: 11)),
            ScheduledStop(station: a, arrival: GameTime(minutes: 20), departure: GameTime(minutes: 20)),
        ])
        // The service stands at A and runs east to N, past M.
        let service = try stand(&world, cars: 2, at: forward(1), 3_072)
        try world.setTrainMovementRate(service, to: 1_024)
        try world.setTrainTimetable(service, to: [
            ScheduledStop(station: a, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
            ScheduledStop(station: n, arrival: GameTime(minutes: 8), departure: GameTime(minutes: 8)),
        ])
        try world.startTrainService(oncoming)
        try world.startTrainService(service)
        // Oncoming leaves at 0:42 for M and holds the way there, which is
        // on the service's route; due at 1:00, the service waits for it.
        try world.advance(ticks: 2)
        XCTAssertEqual(world.train(id: oncoming)?.execution, .travellingToStop(1, cycle: 0))
        XCTAssertEqual(world.train(id: service)?.execution, .waitingAtStop(0, cycle: 0))
        XCTAssertEqual(world.trainHoldingRoute(of: service), oncoming)
        XCTAssertEqual(world.reservedResources(of: service), [])
    }

    /// A save from before Stage U may hold track its train has already
    /// passed (Stage T kept it until the route ended): it loads as it is,
    /// that track stays held, and the train lets it go when it next moves.
    func testTrackPassedInAnOlderSaveIsReleasedWhenTheTrainMoves() throws {
        var world = try makeLineWorld()
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 4_600))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 1_500)
        var json = try encoded(world)
        var trains = try XCTUnwrap(json["trains"] as? [[String: Any]])
        var reservation = try XCTUnwrap(trains[0]["reservation"] as? [[String: Any]])
        reservation.insert(["edge": 1, "start": 3_072, "end": 4_096], at: 1)
        trains[0]["reservation"] = reservation
        json["trains"] = trains
        var loaded = try decode(json)
        XCTAssertEqual(loaded.reservedResources(of: one), [node(2), span(1, 3_072, 4_096), span(1, 4_096, 5_120), span(2, 0, 1_000), span(2, 1_000, 2_000)])
        let two = try buy(&loaded)
        XCTAssertThrowsGameError(try loaded.placeTrain(two, at: .onEdge(backward(1), offset: 1_500)), .trackReserved(one))

        try loaded.setTrainMovementRate(one, to: 1_024)
        try loaded.advance(ticks: 1)
        XCTAssertEqual(loaded.reservedResources(of: one), [span(2, 0, 1_000), span(2, 1_000, 2_000)])
        // 5120 − 1500 = 3620 along e1, running back to n1.
        try loaded.placeTrain(two, at: .onEdge(backward(1), offset: 1_500))
        XCTAssertEqual(loaded.reservedResources(of: two), [node(1), span(1, 0, 1_024), span(1, 1_024, 2_048), span(1, 2_048, 3_072), span(1, 3_072, 4_096)])
    }

    // MARK: - Saves

    private func encoded(_ world: GameWorld) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(world)) as? [String: Any])
    }

    private func decode(_ json: [String: Any]) throws -> GameWorld {
        try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// Traffic control and reservations are saved only when used; they read
    /// back exactly.
    func testSavesKeepTrafficControlAndReservations() throws {
        var world = try makeLineWorld()
        let unused = try GameWorld(bounds: WorldBounds(width: 4_096, height: 4_096), economy: GameEconomy(balance: 1_000, costs: testCosts))
        XCTAssertNil(try encoded(unused)["trafficControl"])
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 4_600))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 1_500)
        let json = try encoded(world)
        XCTAssertEqual(json["trafficControl"] as? Bool, true)
        let trains = try XCTUnwrap(json["trains"] as? [[String: Any]])
        let saved = try XCTUnwrap(trains[0]["reservation"] as? [[String: Any]])
        XCTAssertEqual(saved.count, 4)
        XCTAssertEqual(saved[0]["node"] as? Int, 2)
        XCTAssertEqual(saved[1]["edge"] as? Int, 1)
        XCTAssertEqual(saved[1]["start"] as? Int, 4_096)
        XCTAssertEqual(try decode(json), world)
        // On its way, 504 along e2: only what is ahead of it.
        try world.setTrainMovementRate(one, to: 1_024)
        try world.advance(ticks: 1)
        let moved = try XCTUnwrap(try encoded(world)["trains"] as? [[String: Any]])
        let kept = try XCTUnwrap(moved[0]["reservation"] as? [[String: Any]])
        XCTAssertEqual(kept.map { $0["edge"] as? Int }, [2, 2])
        XCTAssertEqual(kept.map { $0["start"] as? Int }, [0, 1_000])
        XCTAssertEqual(try decode(try encoded(world)), world)
    }

    /// Saves that break a Stage T rule are refused, never repaired.
    func testBrokenTrafficSavesAreRefused() throws {
        var world = try makeLineWorld()
        // e2's platform cuts it at 100 and 1100: its spans are 0–100,
        // 100–1000, 1000–1100, 1100–2000 and 2000–3000.
        let station = try world.buildStation(named: "P", at: PlanPoint(x: 1_536, y: 3_584)).id
        try world.addTrackPlatform(station, on: .edge(2), from: 100, to: 1_100)
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 500))
        try world.setTrainContinuation(one, along: [], stoppingAt: 1_500)
        let two = try stand(&world, at: forward(1), 3_000)
        let json = try encoded(world)
        XCTAssertNoThrow(try decode(json))

        func mutated(_ change: (inout [String: Any], inout [[String: Any]]) -> Void) -> [String: Any] {
            var copy = json
            var trains = copy["trains"] as! [[String: Any]]
            change(&copy, &trains)
            copy["trains"] = trains
            return copy
        }
        let valid: [[String: Any]] = [["edge": 1, "start": 0, "end": 1_024], ["edge": 1, "start": 1_024, "end": 2_048]]
        let cases: [(String, [String: Any])] = [
            ("null flag", mutated { world, _ in world["trafficControl"] = NSNull() }),
            ("flag not a Bool", mutated { world, _ in world["trafficControl"] = "yes" }),
            ("reserved while off", mutated { world, _ in world["trafficControl"] = false }),
            ("null reservation", mutated { _, trains in trains[0]["reservation"] = NSNull() }),
            ("unsorted", mutated { _, trains in trains[0]["reservation"] = valid.reversed() }),
            ("repeated", mutated { _, trains in trains[0]["reservation"] = [valid[0], valid[0], valid[1]] }),
            ("start after end", mutated { _, trains in trains[0]["reservation"] = [["edge": 1, "start": 1_024, "end": 0], valid[1]] }),
            ("two tags", mutated { _, trains in trains[0]["reservation"] = [["edge": 1, "start": 0, "end": 1_024, "node": 1], valid[1]] }),
            ("no tag", mutated { _, trains in trains[0]["reservation"] = [[String: Any](), valid[1]] }),
            ("unknown edge", mutated { _, trains in trains[0]["reservation"] = valid + [["edge": 9, "start": 0, "end": 1_024]] }),
            ("unknown node", mutated { _, trains in trains[0]["reservation"] = [["node": 9]] + valid }),
            ("not a span of the edge", mutated { _, trains in trains[0]["reservation"] = [["edge": 1, "start": 0, "end": 2_048]] }),
            ("short of where it stands", mutated { _, trains in trains[0]["reservation"] = [valid[1]] }),
            ("over another train's track", mutated { _, trains in trains[0]["reservation"] = valid + [["edge": 1, "start": 2_048, "end": 3_072]] }),
            ("on a standing train", mutated { _, trains in trains[1]["reservation"] = [["edge": 1, "start": 2_048, "end": 3_072]] }),
            ("unplaced", mutated { _, trains in trains[1]["position"] = nil; trains[1]["movement"] = nil; trains[1]["reservation"] = [["node": 1]] }),
            ("link not neighbours", mutated { _, trains in trains[0]["reservation"] = [["link": [["x": 0, "y": 0], ["x": 2, "y": 0]]]] + valid }),
            ("the platform moved to e1, cutting it again", mutated { world, _ in
                var network = world["network"] as! [String: Any]
                network["platforms"] = [["station": station.rawValue, "edge": 1, "start": 700, "end": 900]]
                world["network"] = network
            }),
        ]
        for (name, broken) in cases {
            XCTAssertThrowsError(try decode(broken), name)
        }
        // Stage U2: holding where it stands and only part of the rest of
        // its route is a train following another (save version 7).
        let following = mutated { _, trains in trains[0]["reservation"] = [valid[0]] }
        XCTAssertEqual(try decode(following).reservedResources(of: one), [span(1, 0, 1_024)])
        // More than the route needs is a lock, not an error.
        let extra = mutated { _, trains in trains[0]["reservation"] = valid + [["edge": 2, "start": 2_000, "end": 3_000]] }
        XCTAssertEqual(try decode(extra).reservedResources(of: one), [span(1, 0, 1_024), span(1, 1_024, 2_048), span(2, 2_000, 3_000)])
        _ = two
    }
}

extension TrafficControlTests {
    /// Decision 57, hand arithmetic: 5120 left on e1 + 9216 to M's
    /// forward berth on e2 = 14336; the westbound default is also e2.
    /// Once the first train reserves it the second uses e6 → e5. Both continue
    /// across M and finish at the opposite terminal without intervention.
    func testOpposingServicesMeetOnDifferentPlatformsAndReachTheOtherEnd() throws {
        var world = try SingleTrackMeet.world()
        let eastbound = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let westbound = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.backward(3), offset: 3_072)
        for (id, east) in [(eastbound, true), (westbound, false)] {
            let path = try XCTUnwrap(world.path(from: world.train(id: id)!.position!, toStation: SingleTrackMeet.middle, length: 1_024))
            XCTAssertEqual(path.traversals.map(\.edge), [.edge(2)])
            XCTAssertEqual(path.distance, 14_336)
            try world.setTrainTimetable(id, to: SingleTrackMeet.timetable(eastbound: east))
            try world.startTrainService(id)
        }
        try world.setTrafficControl(true)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: eastbound)?.movement.edges, [.edge(2)])
        XCTAssertEqual(world.train(id: westbound)?.movement.edges, [.edge(6), .edge(5)])
        XCTAssertEqual(world.train(id: eastbound)?.times?.run?.length, 14_336)
        let exit = world.network.edge(.edge(6))!.length
        // Westbound stops at the near chainage end of the centred platform.
        XCTAssertEqual(world.train(id: westbound)?.times?.run?.length, 5_120 + exit + 5_120)
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
        try world.advance(ticks: 6)
        XCTAssertEqual(world.stationsStoppedAt(by: eastbound), [SingleTrackMeet.east])
        XCTAssertEqual(world.stationsStoppedAt(by: westbound), [SingleTrackMeet.west])
        XCTAssertNil(world.train(id: eastbound)?.execution)
        XCTAssertNil(world.train(id: westbound)?.execution)
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    func testAServiceUsesAnotherPlatformWhenTheNearestIsOccupied() throws {
        var world = try SingleTrackMeet.world()
        let service = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        _ = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(2), offset: 9_216)
        try world.setTrainTimetable(service, to: Array(SingleTrackMeet.timetable(eastbound: true).prefix(2)))
        try world.startTrainService(service)
        try world.setTrafficControl(true)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: service)?.movement.edges, [.edge(4), .edge(5)])
        try world.advance(ticks: 2)
        XCTAssertEqual(world.stationsStoppedAt(by: service), [SingleTrackMeet.middle])
    }

    func testAServiceWaitsWhenBothPlatformsAreOccupiedAndManualPathsStayExplicit() throws {
        var world = try SingleTrackMeet.world()
        let service = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let first = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(2), offset: 9_216)
        _ = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(5), offset: 5_120)
        try world.setTrafficControl(true)
        let before = world
        XCTAssertThrowsGameError(try world.setTrainContinuation(service, along: [SingleTrackMeet.forward(2)], stoppingAt: 9_216), .trackReserved(first))
        XCTAssertEqual(world, before)
        try world.setTrainTimetable(service, to: Array(SingleTrackMeet.timetable(eastbound: true).prefix(2)))
        try world.startTrainService(service)
        try world.advance(ticks: 3)
        XCTAssertEqual(world.train(id: service)?.execution, .waitingAtStop(0))
        XCTAssertEqual(world.train(id: service)?.position, .onEdge(SingleTrackMeet.forward(1), offset: 3_072))
        XCTAssertEqual(world.reservedResources(of: service), [])
    }

    func testTrafficControlOffKeepsTheDefaultPlatformForOpposingServices() throws {
        var world = try SingleTrackMeet.world()
        for east in [true, false] {
            let id = try SingleTrackMeet.stand(&world, edge: east ? SingleTrackMeet.forward(1) : SingleTrackMeet.backward(3), offset: 3_072)
            try world.setTrainTimetable(id, to: SingleTrackMeet.timetable(eastbound: east))
            try world.startTrainService(id)
        }
        try world.advance(ticks: 1)
        XCTAssertEqual(world.trains.map { $0.movement.edges }, [[.edge(2)], [.edge(2)]])
        XCTAssertTrue(world.trains.allSatisfy { $0.reservation.isEmpty })
    }
}

extension TrafficControlTests {
    func testALineIsReadyWhenOnlyTheAlternativePlatformCanBeReserved() throws {
        var world = try SingleTrackMeet.world()
        let service = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        _ = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(2), offset: 9_216)
        let line = try world.createLine(named: "L", stops: [SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.assignTrain(service, to: line)
        try world.setTrafficControl(true)
        XCTAssertNil(world.trainHoldingRoute(of: service), "an available alternate route is not a route wait")
        try world.advance(ticks: 1)
        XCTAssertEqual(world.line(id: line)?.lastDispatch, GameTime(seconds: 0))
        XCTAssertEqual(world.train(id: service)?.execution, .travellingToStop(1))
        XCTAssertEqual(world.train(id: service)?.movement.edges, [.edge(4), .edge(5)])
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }
}

extension TrafficControlTests {
    func testBlockedSearchCanStopBeforeABlockedPartOfTheSameEdge() throws {
        let world = try SingleTrackMeet.world()
        let start = TrainPosition.onEdge(SingleTrackMeet.forward(2), offset: 4_096)
        let blocked: Set<TrackResource> = [span(2, 12_288, 13_312)]
        // 9216 - 4096 = 5120, stopping before the blocked far end.
        let path = try XCTUnwrap(world.path(from: start, toStation: SingleTrackMeet.middle, length: 1_024, avoiding: blocked))
        XCTAssertEqual(path, TrainPath(traversals: [], end: 9_216, distance: 5_120))
    }

    func testBlockedSearchRejectsAFouledJunctionWithoutReachingIt() throws {
        let world = try SingleTrackMeet.world()
        let start = TrainPosition.onEdge(SingleTrackMeet.forward(4), offset: 500)
        // The head goes away from n2 and never touches it, but its first
        // interval lies inside n2's 1024-unit fouling zone on the branch.
        XCTAssertNotNil(world.path(from: start, toStation: SingleTrackMeet.middle, length: 0))
        XCTAssertNil(world.path(from: start, toStation: SingleTrackMeet.middle, length: 0, avoiding: [node(2)]))
    }

    func testBlockedSearchRetainsTheNearestBerthTieOrder() throws {
        var world = try SingleTrackMeet.world()
        try world.removeTrackPlatform(SingleTrackMeet.middle, on: .edge(5), from: 3_072)
        // e4 is 4732; 4732 + 4484 along e5 equals e2's 9216.
        // Both routes are 5120 + 9216 = 14336 from the head. At n2,
        // e2 comes before e4 and remains the default when neither is held.
        XCTAssertEqual(world.network.edge(.edge(4))?.length, 4_732)
        try world.addTrackPlatform(SingleTrackMeet.middle, on: .edge(5), from: 3_460, to: 4_484)
        let start = TrainPosition.onEdge(SingleTrackMeet.forward(1), offset: 3_072)
        let path = try XCTUnwrap(world.path(from: start, toStation: SingleTrackMeet.middle, length: 1_024, avoiding: [node(4)]))
        XCTAssertEqual(path.traversals, [SingleTrackMeet.forward(2)])
        XCTAssertEqual(path.distance, 14_336)
    }

    func testBlockedSearchAvoidsTrackThatFoulsAnotherSpan() throws {
        let world = try SingleTrackMeet.world()
        let start = TrainPosition.onEdge(SingleTrackMeet.forward(4), offset: 500)
        // The branch's early spans lie beside the main track as it parts;
        // resource identity alone would miss this F2b conflict.
        XCTAssertNil(world.path(from: start, toStation: SingleTrackMeet.middle, length: 0, avoiding: [span(2, 0, 1_024)]))
    }
}

extension TrafficControlTests {
    func testBatchedAdvanceWakesWhenAnAlternativePlatformFrees() throws {
        var world = try SingleTrackMeet.world()
        _ = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(2), offset: 9_216)
        let leader = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(5), offset: 5_120)
        let follower = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        try world.setTrainTimetable(leader, to: [
            ScheduledStop(station: SingleTrackMeet.middle, arrival: .init(seconds: 0), departure: .init(seconds: 0)),
            ScheduledStop(station: SingleTrackMeet.east, arrival: .init(seconds: 240), departure: .init(seconds: 240)),
        ])
        try world.setTrainTimetable(follower, to: Array(SingleTrackMeet.timetable(eastbound: true).prefix(2)))
        try world.startTrainService(leader)
        try world.startTrainService(follower)
        try world.setTrafficControl(true)
        var model = SingleTrackMeet.model()
        for (number, place) in [(2, Int64(9_216)), (5, 5_120), (1, 3_072)].enumerated() {
            let id = TrainID(rawValue: number + 1)
            XCTAssertNil(model.purchaseTrain(named: "T"))
            XCTAssertNil(model.setCars(id, 2))
            XCTAssertNil(model.placeTrain(id, at: .onEdge(SingleTrackMeet.forward(place.0), offset: place.1)))
            XCTAssertNil(model.setContinuation(id, along: [], stoppingAt: place.1))
            XCTAssertNil(model.setRate(id, 1_024))
        }
        for id in [leader, follower] {
            XCTAssertNil(model.setTimetable(id, world.train(id: id)!.timetable))
            XCTAssertNil(model.startService(id))
        }
        XCTAssertNil(model.setTrafficControl(true))
        var seconds = world
        seconds.setSpeed(.x1)
        // The alternate berth at 5120 touches the 5120–6144 span too.
        // The leader's 1024-long body frees that span only when its head
        // has gone strictly beyond 7168: 2048 on from its starting point.
        // Its route is 3072 + 4732 + 7168 = 14972, in 240 seconds.
        let curve = try XCTUnwrap(RunningCurve(length: 14_972, duration: 240_000, performance: .standard))
        let clear = try XCTUnwrap((1...120).first { curve.distance(at: Int64($0) * 1_000) > 2_048 })
        try world.advance(ticks: 3)
        for _ in 0..<180 { try seconds.advance(ticks: 10) }
        XCTAssertEqual(world.train(id: follower)?.times?.departure, GameTime(seconds: 42 + Int64(clear)))
        guard case .onEdge(let traversal, _)? = world.train(id: follower)?.position else { return XCTFail("follower must be on the passing loop") }
        XCTAssertEqual(traversal, SingleTrackMeet.forward(5))
        world.setSpeed(.x1)
        XCTAssertEqual(world, seconds)
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
        // Within this single reference advance the alternative is first
        // blocked, then freed. A cached failed route must be invalidated
        // when the leader releases the berth's span.
        XCTAssertNil(model.advance(ticks: 3))
        model.setSpeed(.x1)
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        for train in world.trains {
            XCTAssertEqual(world.reservedResources(of: train.id), model.reservedResources(of: train.id))
            XCTAssertEqual(world.heldResources(of: train.id), model.heldResources(of: train.id))
        }
    }
}

extension TrafficControlTests {
    func testAnAlternativeRouteDoesNotRunAgainstTheOpposingTrack() throws {
        var world = try DoubleTrackCrossover.world()
        let lead = try DoubleTrackCrossover.stand(&world, TrackTraversal(edge: .edge(2), direction: .forward), at: 13_312)
        let follower = try DoubleTrackCrossover.stand(&world, TrackTraversal(edge: .edge(1), direction: .forward), at: 3_072)
        let opposer = try DoubleTrackCrossover.stand(&world, TrackTraversal(edge: .edge(4), direction: .backward), at: 27_648 - 23_552)
        try world.setTrainTimetable(lead, to: DoubleTrackCrossover.calls([(DoubleTrackCrossover.middle, 180), (DoubleTrackCrossover.east, 420)]))
        try world.setTrainTimetable(follower, to: DoubleTrackCrossover.calls([(DoubleTrackCrossover.west, 0), (DoubleTrackCrossover.middle, 180), (DoubleTrackCrossover.east, 420)]))
        try world.setTrainTimetable(opposer, to: DoubleTrackCrossover.calls([(DoubleTrackCrossover.east, 60), (DoubleTrackCrossover.middle, 300), (DoubleTrackCrossover.west, 540)]))
        for id in [lead, follower, opposer] { try world.startTrainService(id) }
        try world.setTrafficControl(true)
        try world.advance(ticks: 1)
        XCTAssertNotEqual(world.train(id: follower)?.movement.edges, [.edge(5), .edge(4)], "eastbound service took westbound track B")
        try world.advance(ticks: 19)
        XCTAssertNil(world.train(id: opposer)?.execution, "the opposing service never finished")
        XCTAssertFalse(world.trainHoldingRoute(of: follower) == opposer && world.trainHoldingRoute(of: opposer) == follower, "circular wait")
    }

    func testAlternativeReadinessProtectsADueOpposingLineBeforeItIsDispatched() throws {
        var world = try DoubleTrackCrossover.world()
        var model = DoubleTrackCrossover.model()
        for (number, place) in [(SingleTrackMeet.forward(2), Int64(13_312)), (SingleTrackMeet.forward(1), 3_072), (SingleTrackMeet.backward(4), 4_096)].enumerated() {
            let id = try DoubleTrackCrossover.stand(&world, place.0, at: place.1)
            XCTAssertEqual(id.rawValue, number + 1)
            XCTAssertNil(model.purchaseTrain(named: "T"))
            XCTAssertNil(model.setCars(id, 2))
            XCTAssertNil(model.placeTrain(id, at: .onEdge(place.0, offset: place.1)))
            XCTAssertNil(model.setContinuation(id, along: [], stoppingAt: place.1))
            XCTAssertNil(model.setRate(id, 1_024))
        }
        let lead = TrainID(rawValue: 1)
        let calls = DoubleTrackCrossover.calls([(DoubleTrackCrossover.middle, 180), (DoubleTrackCrossover.east, 420)])
        try world.setTrainTimetable(lead, to: calls)
        try world.startTrainService(lead)
        XCTAssertNil(model.setTimetable(lead, calls))
        XCTAssertNil(model.startService(lead))
        // Eastbound readiness is examined first. The due westbound line
        // must protect its first leg before dispatch has given it a service.
        for (number, stops) in [[DoubleTrackCrossover.west, DoubleTrackCrossover.middle, DoubleTrackCrossover.east],
                                [DoubleTrackCrossover.east, DoubleTrackCrossover.middle, DoubleTrackCrossover.west]].enumerated() {
            let line = try world.createLine(named: "L", stops: stops).id
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
            try world.assignTrain(TrainID(rawValue: number + 2), to: line)
            XCTAssertNil(model.createLine(named: "L", stops: stops))
            XCTAssertNil(model.setLineWindow(line, .allDay))
            XCTAssertNil(model.setLineTrains(line, TrainsInService(peak: 1, offPeak: 1, low: 1)))
            XCTAssertNil(model.assign(TrainID(rawValue: number + 2), to: line))
        }
        try world.setTrafficControl(true)
        XCTAssertNil(model.setTrafficControl(true))
        try world.advance(ticks: 1)
        XCTAssertNil(model.advance(ticks: 1))
        XCTAssertNil(world.line(id: .init(rawValue: 1))?.lastDispatch)
        XCTAssertEqual(world.line(id: .init(rawValue: 2))?.lastDispatch, .init(seconds: 0))
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }
}


extension TrafficControlTests {
    func testAnOpposingServiceTwoLegsAwayStillCompletes() throws {
        var world = try DoubleTrackCrossover.world(extended: true)
        let lead = try DoubleTrackCrossover.stand(&world, SingleTrackMeet.forward(2), at: 13_312)
        let follower = try DoubleTrackCrossover.stand(&world, SingleTrackMeet.forward(1), at: 3_072)
        let opposer = try DoubleTrackCrossover.stand(&world, SingleTrackMeet.backward(7), at: 6_144)
        let calls = DoubleTrackCrossover.calls
        try world.setTrainTimetable(lead, to: calls([(DoubleTrackCrossover.middle, 180), (DoubleTrackCrossover.east, 420)]))
        try world.setTrainTimetable(follower, to: calls([(DoubleTrackCrossover.west, 0), (DoubleTrackCrossover.middle, 180), (DoubleTrackCrossover.east, 420)]))
        try world.setTrainTimetable(opposer, to: calls([(DoubleTrackCrossover.outer, 60), (DoubleTrackCrossover.east, 240), (DoubleTrackCrossover.middle, 420), (DoubleTrackCrossover.west, 660)]))
        for id in [lead, follower, opposer] { try world.startTrainService(id) }
        try world.setTrafficControl(true)
        try world.advance(ticks: 1)
        XCTAssertFalse(world.train(id: follower)!.movement.edges.contains(.edge(5)), "eastbound service borrowed track B before its opposing service reached E")
        try world.advance(ticks: 29)
        XCTAssertNil(world.train(id: opposer)?.execution, "the opposing service never finished")
        XCTAssertFalse(world.trainHoldingRoute(of: follower) == opposer && world.trainHoldingRoute(of: opposer) == follower, "circular wait")
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    func testAnOpposingLineProtectsItsRouteBeforeItsWindowOpens() throws {
        var world = try DoubleTrackCrossover.world(extended: true)
        let lead = try DoubleTrackCrossover.stand(&world, SingleTrackMeet.forward(2), at: 13_312)
        let follower = try DoubleTrackCrossover.stand(&world, SingleTrackMeet.forward(1), at: 3_072)
        let opposer = try DoubleTrackCrossover.stand(&world, SingleTrackMeet.backward(7), at: 6_144)
        try world.setTrainTimetable(lead, to: DoubleTrackCrossover.calls([(DoubleTrackCrossover.middle, 180), (DoubleTrackCrossover.east, 420)]))
        try world.setTrainTimetable(follower, to: DoubleTrackCrossover.calls([(DoubleTrackCrossover.west, 0), (DoubleTrackCrossover.middle, 180), (DoubleTrackCrossover.east, 420)]))
        for id in [lead, follower] { try world.startTrainService(id) }
        let line = try world.createLine(named: "B", stops: [DoubleTrackCrossover.outer, DoubleTrackCrossover.east, DoubleTrackCrossover.middle, DoubleTrackCrossover.west]).id
        try world.setLineServiceWindow(line, to: .hours(open: 2, close: 1_440))
        try world.setLineTrainsInService(line, to: .init(peak: 1, offPeak: 1, low: 1))
        try world.assignTrain(opposer, to: line)
        try world.setTrafficControl(true)
        try world.advance(ticks: 1)
        XCTAssertNil(world.line(id: line)?.lastDispatch)
        XCTAssertFalse(world.train(id: follower)!.movement.edges.contains(.edge(5)), "future opposing line was ignored")
        try world.advance(ticks: 29)
        XCTAssertNotNil(world.line(id: line)?.lastDispatch)
        XCTAssertFalse(world.trainHoldingRoute(of: follower) == opposer && world.trainHoldingRoute(of: opposer) == follower, "circular wait")
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }
}


extension TrafficControlTests {
    /// Decision 57 as fused for Stage V2: a line protects its whole plan
    /// only while a placed train is assigned to it, whatever its window;
    /// with none it is plan data that cannot run, and protects nothing.
    /// Assigning and unassigning between calls changes the protection.
    func testALineProtectsItsPlanOnlyWhileAPlacedTrainIsAssigned() throws {
        var world = try DoubleTrackCrossover.world(extended: true)
        var model = DoubleTrackCrossover.model(extended: true)
        let places = [(SingleTrackMeet.forward(2), Int64(13_312)), (SingleTrackMeet.forward(1), 3_072), (SingleTrackMeet.backward(7), 6_144)]
        for (number, place) in places.enumerated() {
            let id = try DoubleTrackCrossover.stand(&world, place.0, at: place.1)
            XCTAssertNil(model.purchaseTrain(named: "T"))
            XCTAssertNil(model.setCars(id, 2))
            XCTAssertNil(model.placeTrain(id, at: .onEdge(place.0, offset: place.1)))
            XCTAssertNil(model.setContinuation(id, along: [], stoppingAt: place.1))
            XCTAssertNil(model.setRate(id, 1_024))
            guard number < 2 else { continue }
            let stops: [(StationID, Int64)]
            if number == 0 { stops = [(DoubleTrackCrossover.middle, 180), (DoubleTrackCrossover.east, 420)] }
            else { stops = [(DoubleTrackCrossover.west, 0), (DoubleTrackCrossover.middle, 180), (DoubleTrackCrossover.east, 420)] }
            let calls = DoubleTrackCrossover.calls(stops)
            try world.setTrainTimetable(id, to: calls)
            try world.startTrainService(id)
            XCTAssertNil(model.setTimetable(id, calls))
            XCTAssertNil(model.startService(id))
        }
        let (follower, opposer) = (TrainID(rawValue: 2), TrainID(rawValue: 3))
        let stops = [DoubleTrackCrossover.outer, DoubleTrackCrossover.east, DoubleTrackCrossover.middle, DoubleTrackCrossover.west]
        let line = try world.createLine(named: "B", stops: stops).id
        XCTAssertNil(model.createLine(named: "B", stops: stops))
        // Westbound on track B is the line's way: an eastbound alternative
        // may not borrow e4 forwards while the line can run.
        let againstLine = TrackTraversal(edge: .edge(4), direction: .forward)
        func protected() -> Bool {
            var memo = GameWorld.DirectionMemo()
            return world.opposingServiceTraversals(for: world.train(id: follower)!, memo: &memo).contains(againstLine)
        }
        XCTAssertFalse(protected(), "a line with no train cannot run")
        try world.assignTrain(opposer, to: line)
        XCTAssertNil(model.assign(opposer, to: line))
        XCTAssertTrue(protected(), "its window is closed, but it has a train to send")
        try world.setTrafficControl(true)
        XCTAssertNil(model.setTrafficControl(true))
        try world.advance(ticks: 1)
        XCTAssertNil(model.advance(ticks: 1))
        XCTAssertNil(world.line(id: line)?.lastDispatch)
        XCTAssertFalse(world.train(id: follower)!.movement.edges.contains(.edge(5)))
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        try world.unassignTrain(opposer)
        XCTAssertNil(model.unassign(opposer))
        XCTAssertFalse(protected())
        try world.advance(ticks: 1)
        XCTAssertNil(model.advance(ticks: 1))
        XCTAssertTrue(world.train(id: follower)!.movement.edges.contains(.edge(5)))
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
        XCTAssertNil(WorldInvariants.roundTripProblem(of: world))
    }
}

/// Decision 57 as settled for Stage V2: following comes before another
/// platform, and an alternative is at most 400 m longer than the default
/// route.
extension TrafficControlTests {
    /// The same meeting station at eight times the size, so that a train
    /// can follow another 400 m behind. The leader leaves M's main platform
    /// for E as the follower is due at W: the follower follows it on the
    /// main track (U2) instead of taking the free loop (V1), and arrives
    /// at the main platform once the leader has gone.
    func testAServiceFollowsAMovingLeaderBeforeTakingAnotherPlatform() throws {
        var world = try SingleTrackMeet.world(scale: 8)
        var model = SingleTrackMeet.model(scale: 8)
        for (edge, offset) in [(2, Int64(9_216 * 8)), (1, 3_072 * 8)] {
            let id = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(edge), offset: offset)
            XCTAssertNil(model.purchaseTrain(named: "T"))
            XCTAssertNil(model.setCars(id, 2))
            XCTAssertNil(model.placeTrain(id, at: .onEdge(SingleTrackMeet.forward(edge), offset: offset)))
            XCTAssertNil(model.setContinuation(id, along: [], stoppingAt: offset))
            XCTAssertNil(model.setRate(id, 1_024))
        }
        let (leader, follower) = (TrainID(rawValue: 1), TrainID(rawValue: 2))
        let lead = [ScheduledStop(station: SingleTrackMeet.middle, arrival: .init(seconds: 0), departure: .init(seconds: 0)),
                    ScheduledStop(station: SingleTrackMeet.east, arrival: .init(seconds: 240), departure: .init(seconds: 240))]
        let follow = [ScheduledStop(station: SingleTrackMeet.west, arrival: .init(seconds: 0), departure: .init(seconds: 0)),
                      ScheduledStop(station: SingleTrackMeet.middle, arrival: .init(seconds: 240), departure: .init(seconds: 240))]
        for (id, stops) in [(leader, lead), (follower, follow)] {
            try world.setTrainTimetable(id, to: stops)
            try world.startTrainService(id)
            XCTAssertNil(model.setTimetable(id, stops))
            XCTAssertNil(model.startService(id))
        }
        try world.setTrafficControl(true)
        XCTAssertNil(model.setTrafficControl(true))
        // Both leave at 42 s, the leader first: the follower only follows
        // it, 400 m behind, while the leader's body is still at M.
        world.setSpeed(.x1)
        for _ in 0..<43 { try world.advance(ticks: 10) }
        XCTAssertEqual(world.train(id: follower)?.times?.departure, GameTime(seconds: 42))
        XCTAssertEqual(world.train(id: follower)?.movement.edges, [.edge(2)])
        XCTAssertTrue(world.isFollowing(world.train(id: follower)!))
        XCTAssertEqual(world.trainHoldingRoute(of: follower), leader)
        try world.advance(ticks: 3_170)
        XCTAssertNil(model.advance(ticks: 6))
        model.setSpeed(.x1)
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        // It arrived at the main platform, where its service ends.
        XCTAssertNil(world.train(id: follower)?.execution)
        XCTAssertEqual(world.stationsStoppedAt(by: follower), [SingleTrackMeet.middle])
        guard case .onEdge(let traversal, _)? = world.train(id: follower)?.position else { return XCTFail("placed") }
        XCTAssertEqual(traversal, SingleTrackMeet.forward(2))
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// The loop of the meeting station pulled 40000 units off the main
    /// track: the way through it is far more than 400 m longer than the
    /// main platform's, so the service waits for the train on the main
    /// platform instead of going round.
    func testAnAlternativeMoreThanTheDetourAllowanceLongerIsNotTaken() throws {
        var world = try SingleTrackMeet.world(loop: 40_000)
        let service = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        _ = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(2), offset: 9_216)
        let candidate = try XCTUnwrap(world.path(from: world.train(id: service)!.position!, toStation: SingleTrackMeet.middle, length: 2_048))
        let loop = try XCTUnwrap(world.path(from: world.train(id: service)!.position!, toStation: SingleTrackMeet.middle, length: 2_048,
                                            avoiding: [.span(world.trackSpans(of: .edge(2)).last { $0.start < 9_216 }!)]))
        XCTAssertEqual(loop.traversals.map(\.edge), [.edge(4), .edge(5)])
        XCTAssertGreaterThan(loop.distance - candidate.distance, GameWorld.detourAllowance)
        try world.setTrainTimetable(service, to: Array(SingleTrackMeet.timetable(eastbound: true).prefix(2)))
        try world.startTrainService(service)
        try world.setTrafficControl(true)
        try world.advance(ticks: 3)
        XCTAssertEqual(world.train(id: service)?.execution, .waitingAtStop(0))
        XCTAssertEqual(world.trainHoldingRoute(of: service), TrainID(rawValue: 2))
        // Within the allowance (the usual loop) it goes round.
        var near = try SingleTrackMeet.world()
        let other = try SingleTrackMeet.stand(&near, edge: SingleTrackMeet.forward(1), offset: 3_072)
        _ = try SingleTrackMeet.stand(&near, edge: SingleTrackMeet.forward(2), offset: 9_216)
        try near.setTrainTimetable(other, to: Array(SingleTrackMeet.timetable(eastbound: true).prefix(2)))
        try near.startTrainService(other)
        try near.setTrafficControl(true)
        try near.advance(ticks: 1)
        XCTAssertEqual(near.train(id: other)?.movement.edges, [.edge(4), .edge(5)])
    }
}

/// Decision 57 as fused for Stage V2: a running service protects only the
/// way it still goes, from where its train is, not every way its timetable
/// could start from.
extension TrafficControlTests {
    /// A stands on M's main platform, due to leave for E; B stands at E,
    /// due to leave for W. A waits for B's platform at E, B for A's at M.
    /// A goes east from the main platform, so the loop is not its way: B
    /// takes it (V1, 636 units longer) and both complete. Planning A's
    /// timetable from every berth of M as well, the loop's eastbound berth
    /// among them, would forbid the loop to B: neither could go, and no
    /// passing place would help.
    func testARunningServiceLeavesTheLoopItDoesNotUseToAnOpposingService() throws {
        var world = try SingleTrackMeet.world()
        var model = SingleTrackMeet.model()
        let (w, m, e) = (SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east)
        let plans: [(TrackTraversal, Int64, [ScheduledStop])] = [
            (SingleTrackMeet.forward(2), 9_216, DoubleTrackCrossover.calls([(m, 0), (e, 240)])),
            (SingleTrackMeet.backward(3), 3_072, DoubleTrackCrossover.calls([(e, 0), (w, 480)])),
        ]
        for (traversal, offset, calls) in plans {
            let id = try SingleTrackMeet.stand(&world, edge: traversal, offset: offset)
            XCTAssertNil(model.purchaseTrain(named: "T"))
            XCTAssertNil(model.setCars(id, 2))
            XCTAssertNil(model.placeTrain(id, at: .onEdge(traversal, offset: offset)))
            XCTAssertNil(model.setContinuation(id, along: [], stoppingAt: offset))
            XCTAssertNil(model.setRate(id, 1_024))
            try world.setTrainTimetable(id, to: calls)
            try world.startTrainService(id)
            XCTAssertNil(model.setTimetable(id, calls))
            XCTAssertNil(model.startService(id))
        }
        let (a, b) = (TrainID(rawValue: 1), TrainID(rawValue: 2))
        try world.setTrafficControl(true)
        XCTAssertNil(model.setTrafficControl(true))
        try world.advance(ticks: 1)
        XCTAssertNil(model.advance(ticks: 1))
        XCTAssertEqual(world.train(id: a)?.execution, .waitingAtStop(0))
        XCTAssertEqual(world.trainHoldingRoute(of: a), b)
        XCTAssertEqual(world.train(id: b)?.movement.edges, [.edge(6), .edge(5), .edge(4), .edge(1)])
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        for _ in 0..<12 where world.train(id: a)?.execution != nil || world.train(id: b)?.execution != nil {
            try world.advance(ticks: 1)
            XCTAssertNil(model.advance(ticks: 1))
            XCTAssertEqual(world.deadlockedTrains(), [])
            XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        }
        XCTAssertNil(world.train(id: a)?.execution)
        XCTAssertNil(world.train(id: b)?.execution)
        XCTAssertEqual(world.stationsStoppedAt(by: a), [e])
        XCTAssertEqual(world.stationsStoppedAt(by: b), [w])
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
        XCTAssertNil(WorldInvariants.roundTripProblem(of: world))
    }
}
