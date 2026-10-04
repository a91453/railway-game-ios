import Foundation
@testable import GameCore
import XCTest

/// Stage F2 (ARCHITECTURE decision 52): edges at one level keep 256 units
/// (4 m) apart in plan, but at points within 32768 of each other along the
/// track, which are one junction's tracks parting; pairs built closer
/// before the rule stay exempt. Expected values worked out by hand from the
/// rule.
final class TrackSpacingTests: XCTestCase {
    /// A 32 × 32 map (32768 world units a side) with a large balance and
    /// track at 100 a tile.
    private func makeWorld() throws -> GameWorld {
        try GameWorld(
            bounds: WorldBounds(width: 32_768, height: 32_768), economy: GameEconomy(balance: 100_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 500)),
            clock: GameClock(speed: .normal)
        )
    }

    private func node(_ x: Int64, _ y: Int64, _ z: Int64 = 0, in world: inout GameWorld) throws -> TrackNodeID {
        try world.buildTrackNode(at: WorldCoordinate(x: x, y: y, z: z))
    }

    /// An edge from (x0, y0, z) to (x1, y1, z), straight unless `curve`.
    @discardableResult
    private func edge(
        _ x0: Int64, _ y0: Int64, _ x1: Int64, _ y1: Int64, z: Int64 = 0, curve: TrackCurve = .straight, in world: inout GameWorld
    ) throws -> TrackEdgeID {
        let from = try node(x0, y0, z, in: &world)
        let to = try node(x1, y1, z, in: &world)
        return try world.buildTrackEdge(from: from, to: to, curve: curve, structure: z == 0 ? .surface : .elevated)
    }

    private func refused(_ expected: GameError, in world: GameWorld, file: StaticString = #filePath, line: UInt = #line, _ body: (inout GameWorld) throws -> Void) {
        var copy = world
        do {
            try body(&copy)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? GameError, expected, file: file, line: line)
            XCTAssertEqual(copy, world, "a refused command changes nothing", file: file, line: line)
        }
    }

    /// A refused edge between two new nodes: the nodes are built, the edge
    /// is not, and nothing else changes.
    private func refusedEdge(
        _ expected: GameError, _ x0: Int64, _ y0: Int64, _ x1: Int64, _ y1: Int64, z: Int64 = 0, curve: TrackCurve = .straight,
        in world: inout GameWorld, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let from = try node(x0, y0, z, in: &world)
        let to = try node(x1, y1, z, in: &world)
        refused(expected, in: world, file: file, line: line) {
            _ = try $0.buildTrackEdge(from: from, to: to, curve: curve, structure: z == 0 ? .surface : .elevated)
        }
    }

    // MARK: - Side by side

    func testParallelTracksKeepFourMetresApart() throws {
        var world = try makeWorld()
        let a = try edge(2_048, 8_192, 14_336, 8_192, in: &world)
        // 255 beside it: too close, naming it; 256: exactly the spacing.
        try refusedEdge(.trackTooClose(a), 2_048, 8_447, 14_336, 8_447, in: &world)
        let b = try edge(2_048, 8_448, 14_336, 8_448, in: &world)
        // Between the two, 128 from each: the lower numbered is named.
        try refusedEdge(.trackTooClose(a), 4_096, 8_320, 12_288, 8_320, in: &world)
        // Beside only the second, on its far side.
        try refusedEdge(.trackTooClose(b), 4_096, 8_600, 12_288, 8_600, in: &world)
        // Beside it for a short stretch only: an edge running away at a
        // right angle from 100 beside its middle.
        try refusedEdge(.trackTooClose(a), 8_192, 8_092, 8_192, 2_048, in: &world)
        // End to end on one line without a shared node: a gap of 255 is too
        // close, 256 is not.
        try refusedEdge(.trackTooClose(a), 14_591, 8_192, 20_480, 8_192, in: &world)
        XCTAssertNoThrow(try edge(14_592, 8_192, 22_528, 8_192, in: &world))
        // Nothing built too close was charged for or given a number.
        XCTAssertEqual(world.network.edges.map(\.id), [a, b, .edge(3)])
        XCTAssertEqual(world.network.spacingExemptions, [])
    }

    func testTracksCloseInPlanMayPassOverEachOtherWithClearance() throws {
        var world = try makeWorld()
        let ground = try edge(2_048, 8_192, 14_336, 8_192, in: &world)
        // 128 beside it on a viaduct 511 up: too close; 512 up: the
        // clearance, so it passes beside and above.
        try refusedEdge(.trackTooClose(ground), 2_048, 8_320, 14_336, 8_320, z: 511, in: &world)
        let over = try edge(2_048, 8_320, 14_336, 8_320, z: 512, in: &world)
        // And beside that, 128 further and 511 up from the ground but only
        // 1 below the viaduct: too close to the viaduct.
        try refusedEdge(.trackTooClose(over), 2_048, 8_448, 14_336, 8_448, z: 511, in: &world)
    }

    // MARK: - Parting along the track

    func testAJunctionsTracksMayPartSlowly() throws {
        var world = try makeWorld()
        let b = try node(8_192, 16_384, in: &world)
        let m = try node(10_240, 16_384, in: &world)
        let c = try node(20_480, 16_384, in: &world)
        try world.buildTrackEdge(from: b, to: m)
        try world.buildTrackEdge(from: m, to: c)
        // A branch 1 in 16 off the line, a turnout at b: within 256 of the
        // line for its first 4100 or so, of the second edge of the line too,
        // with which it shares no node (a ladder: the line has a node m 2048
        // past the turnout). Along the track those points are at most about
        // 8200 apart. Allowed.
        let d = try node(20_480, 17_152, in: &world)
        XCTAssertNoThrow(try world.buildTrackEdge(from: b, to: d))
        // A second edge between b and c, 100 beside the line all the way:
        // no point of it is more than about 12288 from the line's point
        // beside it along the track. Allowed.
        let alongside = TrackCurve.cubic(PlanPoint(x: 12_288, y: 16_251), PlanPoint(x: 16_384, y: 16_251))
        XCTAssertNoThrow(try world.buildTrackEdge(from: b, to: c, curve: alongside))
        XCTAssertEqual(world.network.spacingExemptions, [])
    }

    func testAJunctionNearAnotherEdgeIsAPartingToo() throws {
        var world = try makeWorld()
        // network-construction.json's line and branch: the branch b–d is 1
        // in 16 off the line b–c, so c lies 4096 · 256 / 4104 ≈ 255.5 from
        // it. An edge on east from c shares no node with the branch, but c
        // is 4096 + about 4100 from the branch's point beside it along the
        // track: allowed.
        let b = try node(5_120, 1_024, in: &world)
        let c = try node(9_216, 1_024, in: &world)
        let d = try node(9_216, 1_280, in: &world)
        let e = try node(11_264, 1_024, in: &world)
        try world.buildTrackEdge(from: b, to: c)
        try world.buildTrackEdge(from: b, to: d)
        XCTAssertNoThrow(try world.buildTrackEdge(from: c, to: e))
    }

    func testTracksBesideEachOtherFarAlongTheTrackKeepTheSpacing() throws {
        var world = try makeWorld()
        // An edge 16284 long, a connector 200 down from its east end, and an
        // edge back west from there 200 beside the first, as long: the
        // farthest points beside each other, at the west ends, are 16284 +
        // 200 + 16284 = 32768 apart along the track, the reach: allowed.
        let a0 = try node(2_048, 4_096, in: &world)
        let a1 = try node(18_332, 4_096, in: &world)
        let b1 = try node(18_332, 4_296, in: &world)
        let b0 = try node(2_048, 4_296, in: &world)
        try world.buildTrackEdge(from: a0, to: a1)
        try world.buildTrackEdge(from: a1, to: b1)
        XCTAssertNoThrow(try world.buildTrackEdge(from: b1, to: b0))
        // With a connector 201 long the west ends are 32769 apart: refused,
        // naming the first edge.
        let c0 = try node(2_048, 12_288, in: &world)
        let c1 = try node(18_332, 12_288, in: &world)
        let d1 = try node(18_332, 12_489, in: &world)
        let d0 = try node(2_048, 12_489, in: &world)
        let first = try world.buildTrackEdge(from: c0, to: c1)
        try world.buildTrackEdge(from: c1, to: d1)
        refused(.trackTooClose(first), in: world) { _ = try $0.buildTrackEdge(from: d1, to: d0) }
        // Stopping 64 short of the west end is 128 nearer along the track:
        // allowed.
        let short = try node(2_112, 12_489, in: &world)
        XCTAssertNoThrow(try world.buildTrackEdge(from: d1, to: short))
    }

    func testAnEdgeTwoTracksPartByCannotBeRemoved() throws {
        var world = try makeWorld()
        // The ladder: a turnout at b, the line's node m 2048 past it, the
        // branch beside the line's second edge for about 2050.
        let b = try node(8_192, 16_384, in: &world)
        let m = try node(10_240, 16_384, in: &world)
        let c = try node(20_480, 16_384, in: &world)
        let d = try node(20_480, 17_152, in: &world)
        let first = try world.buildTrackEdge(from: b, to: m)
        let second = try world.buildTrackEdge(from: m, to: c)
        let branch = try world.buildTrackEdge(from: b, to: d)
        // Without the first edge the branch and the second edge are beside
        // each other with no track between them: refused, naming both.
        refused(.tracksWouldBeTooClose(second, branch), in: world) { try $0.removeTrackEdge(first) }
        // The branch goes first, then the edge.
        try world.removeTrackEdge(branch)
        XCTAssertNoThrow(try world.removeTrackEdge(first))
    }

    func testAnExemptPairJoinedWithinTheReachIsNoLongerExempt() throws {
        // Two edges 128 apart joined by nothing, from a save made before
        // the rule: exempt.
        var world = try JSONDecoder().decode(SavedGame.self, from: save(try closeWorldJSON(), version: 4)).world
        XCTAssertEqual(world.network.spacingExemptions, [TrackEdgePair(.edge(1), .edge(2))])
        // A track 128 long between their east ends joins them: every two
        // points beside each other are now at most 12288 + 128 + 12288 =
        // 24704 apart along the track, so the pair keeps the spacing.
        let connector = try world.buildTrackEdge(from: .node(2), to: .node(4))
        XCTAssertEqual(world.network.spacingExemptions, [])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGame(world: world))) as? [String: Any])
        XCTAssertNil(((object["world"] as? [String: Any])?["network"] as? [String: Any])?["spacingExemptions"])
        // And the pair does not become exempt again: the connector cannot be
        // removed while both are there.
        refused(.tracksWouldBeTooClose(.edge(1), .edge(2)), in: world) { try $0.removeTrackEdge(connector) }
    }

    func testClearanceIsCheckedBeforeSpacing() throws {
        var world = try makeWorld()
        let near = try edge(2_048, 8_192, 14_336, 8_192, in: &world)
        let across = try edge(16_384, 2_048, 16_384, 14_336, in: &world)
        XCTAssertLessThan(near, across)
        // Beside the first and across the second at one level: the crossing
        // is named, though the edge it runs beside is numbered lower.
        try refusedEdge(.trackConflict(across), 2_048, 8_300, 20_480, 8_300, in: &world)
    }

    // MARK: - Saves

    /// A world with two parallel edges 512 apart, saved, with the second
    /// moved to 128 beside the first: as only a build before Stage F2 could
    /// have made it.
    private func closeWorldJSON() throws -> [String: Any] {
        var world = try makeWorld()
        try edge(2_048, 8_192, 14_336, 8_192, in: &world)
        try edge(2_048, 8_704, 14_336, 8_704, in: &world)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        var network = try XCTUnwrap(object["network"] as? [String: Any])
        var nodes = try XCTUnwrap(network["nodes"] as? [[String: Any]])
        nodes[2]["y"] = 8_320
        nodes[3]["y"] = 8_320
        network["nodes"] = nodes
        object["network"] = network
        return object
    }

    private func save(_ world: [String: Any], version: Int) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["saveVersion": version, "world": world])
    }

    func testAnOldSaveKeepsItsCloseTracksAndListsThem() throws {
        let world = try closeWorldJSON()
        let pair = TrackEdgePair(.edge(1), .edge(2))
        // A world on its own, or in a version 5 save, must list them.
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: world))) { error in
            XCTAssertTrue("\(error)".contains("closer than the track spacing"), "\(error)")
        }
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: save(world, version: 5)))
        // A version 4 save loads with them exempt, and saves in the current
        // version (5 when Stage F2 came, 6 since Stage F3d) listing them.
        var loaded = try JSONDecoder().decode(SavedGame.self, from: save(world, version: 4)).world
        XCTAssertEqual(loaded.network.spacingExemptions, [pair])
        let again = try JSONEncoder().encode(SavedGame(world: loaded))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: again) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, SavedGame.currentVersion)
        let network = try XCTUnwrap((object["world"] as? [String: Any])?["network"] as? [String: Any])
        XCTAssertEqual(network["spacingExemptions"] as? [[Int]], [[1, 2]])
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: again).world, loaded)
        // Versions 1 to 3 read the same way.
        for version in 1...3 {
            XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: save(world, version: version)).world, loaded, "version \(version)")
        }

        // The exemption covers that pair only: a new edge may come no closer
        // to either.
        let from = try node(2_048, 8_448, in: &loaded)
        let to = try node(14_336, 8_448, in: &loaded)
        refused(.trackTooClose(.edge(2)), in: loaded) { _ = try $0.buildTrackEdge(from: from, to: to) }
        // Removing either edge removes the pair, and the save no longer
        // lists any.
        try loaded.removeTrackEdge(.edge(2))
        XCTAssertEqual(loaded.network.spacingExemptions, [])
        let cleared = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) as? [String: Any])
        XCTAssertNil((cleared["network"] as? [String: Any])?["spacingExemptions"])
    }

    func testSpacingExemptionsMustBeExactlyThePairsTooClose() throws {
        let world = try closeWorldJSON()
        func withExemptions(_ value: Any?, in world: [String: Any] = world) -> [String: Any] {
            var object = world
            var network = object["network"] as! [String: Any]
            network["spacingExemptions"] = value
            object["network"] = network
            return object
        }
        XCTAssertNoThrow(try JSONDecoder().decode(SavedGame.self, from: save(withExemptions([[1, 2]]), version: 5)))
        // A save made before the rule has none to list.
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: save(withExemptions([[1, 2]]), version: 4)))
        for (value, reason) in [
            ([[2, 1]], "the lower numbered first"),
            ([[1, 1]], "two different edges"),
            ([[1, 9]], "an edge that does not exist"),
            ([[1]], "a pair"),
            ([[1, 2], [1, 2]], "each once"),
            ([] as [[Int]], "the pair too close is missing"),
        ] as [([[Int]], String)] {
            XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: save(withExemptions(value), version: 5)), reason)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: save(withExemptions(NSNull()), version: 5)), "null")
        // Listing a pair that keeps the spacing is refused too: move the
        // second edge back to 512 away.
        var apart = world
        var network = apart["network"] as! [String: Any]
        var nodes = network["nodes"] as! [[String: Any]]
        nodes[2]["y"] = 8_704
        nodes[3]["y"] = 8_704
        network["nodes"] = nodes
        apart["network"] = network
        XCTAssertNoThrow(try JSONDecoder().decode(SavedGame.self, from: save(apart, version: 5)))
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: save(withExemptions([[1, 2]], in: apart), version: 5))) { error in
            XCTAssertTrue("\(error)".contains("keep the track spacing"), "\(error)")
        }
    }

    // MARK: - Fouling (Stage F2b)

    private func standing(_ name: String, on edge: TrackEdgeID, at offset: Int64, in world: inout GameWorld) throws -> TrainID {
        let id = try world.purchaseTrain(named: name).id
        try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: offset))
        try world.setTrainContinuation(id, along: [], stoppingAt: offset)
        return id
    }

    func testRemovingAnEdgeCannotMakeTwoTrainsFoul() throws {
        var world = try makeWorld()
        // Two short edges 200 apart, 150 long, joined at their west ends p
        // and q by a connector 200 long: their points are at most 150 + 200
        // + 150 = 500 apart along the track, so they do not foul. They are
        // also joined the long way round, along two edges 4096 west and a
        // second connector there (within the reach, so the spacing allows
        // removing the first connector).
        let p = try node(8_192, 8_192, in: &world)
        let q = try node(8_192, 8_392, in: &world)
        let connector = try world.buildTrackEdge(from: p, to: q)
        let east = try world.buildTrackEdge(from: p, to: try node(8_342, 8_192, in: &world))
        let eastBelow = try world.buildTrackEdge(from: q, to: try node(8_342, 8_392, in: &world))
        let w1 = try node(4_096, 8_192, in: &world)
        let w2 = try node(4_096, 8_392, in: &world)
        try world.buildTrackEdge(from: w1, to: p)
        try world.buildTrackEdge(from: w2, to: q)
        try world.buildTrackEdge(from: w1, to: w2)
        let first = try standing("One", on: east, at: 100, in: &world)
        _ = try standing("Two", on: eastBelow, at: 100, in: &world)
        try world.setTrafficControl(true)
        // Without the connector the two short edges are 150 + 4096 + 200 +
        // 4096 + 150 apart along the track at most: they foul, so the
        // connector cannot go while both trains are there.
        refused(.trackReserved(first), in: world) { try $0.removeTrackEdge(connector) }
        // Without traffic control it can.
        try world.setTrafficControl(false)
        XCTAssertNoThrow(try world.removeTrackEdge(connector))
        // And then traffic control cannot come on: the two need track that
        // fouls.
        refused(.trainsShareTrack(first, TrainID(rawValue: 2)), in: world) { try $0.setTrafficControl(true) }
    }

    func testTrainsOnAnExemptPairFoulEachOther() throws {
        // Two edges 128 apart joined by nothing, from a save made before the
        // spacing: a train on each fouls the other.
        var world = try JSONDecoder().decode(SavedGame.self, from: save(try closeWorldJSON(), version: 4)).world
        let one = try standing("One", on: .edge(1), at: 2_048, in: &world)
        let two = try standing("Two", on: .edge(2), at: 2_048, in: &world)
        refused(.trainsShareTrack(one, two), in: world) { try $0.setTrafficControl(true) }
        // Far apart along the edges they do not.
        try world.unplaceTrain(two)
        try world.placeTrain(two, at: .onEdge(TrackTraversal(edge: .edge(2), direction: .forward), offset: 10_240))
        try world.setTrainContinuation(two, along: [], stoppingAt: 10_240)
        XCTAssertNoThrow(try world.setTrafficControl(true))
    }
}
