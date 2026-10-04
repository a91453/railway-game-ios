import Foundation
import GameCore
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
    /// to where the path stops; held for the trip and released when the
    /// head gets there.
    func testAPathTakesPartsOfItsFirstAndLastEdges() throws {
        var world = try makeLineWorld()
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 4_600))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 1_500)
        let route = [node(2), span(1, 4_096, 5_120), span(2, 0, 1_000), span(2, 1_000, 2_000)]
        XCTAssertEqual(world.reservedResources(of: one), route)
        try world.setTrainMovementRate(one, to: 1_024)
        // 520 to n2, then 504 along e2.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(2), offset: 504))
        XCTAssertEqual(world.reservedResources(of: one), route)
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
        // it: chainage 1024.
        XCTAssertEqual(world.reservedResources(of: one), [
            node(2), span(1, 1_024, 2_048), span(1, 2_048, 3_072), span(1, 3_072, 4_096), span(1, 4_096, 5_120), span(1, 5_120, 6_144),
            span(1, 6_144, 7_168), span(1, 7_168, 8_192), span(1, 0, 1_024),
            span(2, 0, 1_024), span(2, 1_024, 2_048), span(2, 2_048, 3_072), span(2, 3_072, 4_096), span(2, 4_096, 5_120),
            span(2, 5_120, 6_144), span(2, 6_144, 7_168), span(2, 7_168, 8_192),
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
    /// gets to the end of its path.
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
        XCTAssertEqual(world.reservedResources(of: one), westToEast)

        try world.stopTrainService(one)
        XCTAssertEqual(world.reservedResources(of: one), westToEast)
        // Without its service it goes on at its rate: 3072 + 7168 = 10240
        // units at most, ten minutes.
        try world.advance(ticks: 10)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(2), offset: 7_168))
        XCTAssertEqual(world.reservedResources(of: one), [])
    }

    /// `testALineWaitsToSendATrainOut`: a line does not send out a train
    /// whose first route another train holds: no dispatch, no timetable, no
    /// service; it goes at the first step the route is free.
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
        XCTAssertEqual(world.reservedResources(of: one), westToEast)
        XCTAssertNil(world.trainHoldingRoute(of: one))
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
    /// back exactly, including track a train has passed but still holds.
    func testSavesKeepTrafficControlAndReservations() throws {
        var world = try makeLineWorld()
        let unused = try GameWorld(bounds: WorldBounds(width: 4_096, height: 4_096), economy: GameEconomy(balance: 1_000, costs: testCosts))
        XCTAssertNil(try encoded(unused)["trafficControl"])
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 4_600))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 1_500)
        try world.setTrainMovementRate(one, to: 1_024)
        try world.advance(ticks: 1)
        let json = try encoded(world)
        XCTAssertEqual(json["trafficControl"] as? Bool, true)
        let trains = try XCTUnwrap(json["trains"] as? [[String: Any]])
        let saved = try XCTUnwrap(trains[0]["reservation"] as? [[String: Any]])
        XCTAssertEqual(saved.count, 4)
        XCTAssertEqual(saved[0]["node"] as? Int, 2)
        XCTAssertEqual(saved[1]["edge"] as? Int, 1)
        XCTAssertEqual(saved[1]["start"] as? Int, 4_096)
        XCTAssertEqual(try decode(json), world)
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
            ("short of the route", mutated { _, trains in trains[0]["reservation"] = [valid[0]] }),
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
        // More than the route needs is a lock, not an error.
        let extra = mutated { _, trains in trains[0]["reservation"] = valid + [["edge": 2, "start": 2_000, "end": 3_000]] }
        XCTAssertEqual(try decode(extra).reservedResources(of: one), [span(1, 0, 1_024), span(1, 1_024, 2_048), span(2, 2_000, 3_000)])
        _ = two
    }
}
