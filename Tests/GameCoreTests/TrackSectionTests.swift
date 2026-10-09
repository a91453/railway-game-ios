import Foundation
@testable import GameCore
import XCTest

/// Track over the ground (ARCHITECTURE decision 124, the design's second
/// step): every 16 m of an edge measured from the ground under its middle,
/// the automatic structure's sections, water that needs a bridge or a
/// tunnel, and earthwork and tall piers. Every number below is worked out
/// by hand; the track price is 100 a pricing length (`testCosts`).
final class TrackSectionTests: XCTestCase {
    /// 64 × 64 cells, 4 × 4 blocks of land.
    private static let bounds = try! WorldBounds(width: 262_144, height: 262_144)
    private static let side = GroundBlock.side
    /// The row the test track runs along: y = 2,048, in the first row of
    /// cells, whose two rows of corners stand alike.
    private static let row: Int64 = 2_048

    private func world() -> GameWorld {
        GameWorld(bounds: Self.bounds, economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal))
    }

    /// A world with ground whose block (0, 0) has corner column c at
    /// `columns[c]` metres (the last repeated past the list), every row
    /// alike.
    private func world(columns: [Int]) throws -> GameWorld {
        var world = world()
        let heights = (0..<Self.side).flatMap { _ in (0..<Self.side).map { Int16(columns[min($0, columns.count - 1)]) } }
        try world.setGround([GroundBlock(block: LandBlock(row: 0, column: 0), heights: heights)!])
        return world
    }

    /// Builds a straight edge along the test row from x = `from` to `to`, at
    /// `z` world units, and returns it and what it cost.
    @discardableResult
    private func build(
        _ world: inout GameWorld, from: Int64, to: Int64, z: Int64, structure: TrackStructure
    ) throws -> (edge: TrackEdge, cost: Int64) {
        let before = world.economy.balance.amount
        let a = try world.buildTrackNode(at: WorldCoordinate(x: from, y: Self.row, z: z))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: to, y: Self.row, z: z))
        let id = try world.buildTrackEdge(from: a, to: b, structure: structure)
        return (try XCTUnwrap(world.network.edge(id)), before - world.economy.balance.amount)
    }

    private func sections(_ runs: [(TrackSectionKind, Int)]) -> [TrackSection] {
        runs.map { TrackSection(kind: $0, lengths: $1) }
    }

    // MARK: - A world without ground

    /// Stage S4's rules and prices, untouched; the automatic structure on
    /// flat ground at 0 m.
    func testAWorldWithoutGroundKeepsStageS4AndTheAutomaticStructureReadsItsHeight() throws {
        var world = world()
        // 4,096 long: 4 lengths at 100, 3 × on a viaduct.
        XCTAssertEqual(try build(&world, from: 1_024, to: 5_120, z: 0, structure: .surface).cost, 400)
        XCTAssertEqual(try build(&world, from: 1_024, to: 5_120, z: 2_048, structure: .elevated).cost, 1_200, "no pier price without ground")
        XCTAssertThrowsError(try build(&world, from: 9_216, to: 13_312, z: 512, structure: .surface)) {
            XCTAssertEqual($0 as? GameError, .invalidTrackStructure)
        }

        // At 0 m the automatic edge is on the surface, at the surface price.
        var flat = self.world()
        let level = try build(&flat, from: 1_024, to: 5_120, z: 0, structure: .automatic)
        XCTAssertEqual(level.edge.sections, sections([(.surface, 4)]))
        XCTAssertEqual(level.cost, 400)
        // At 4 m, an embankment: h = 256 − 128 = 128 past the level, 7 · 128 ·
        // (1,280 + 384) = 1,490,944 a length, four of them 5,963,776, times
        // 100 over 3,276,800: 182 exactly.
        var raised = self.world()
        let fill = try build(&raised, from: 1_024, to: 5_120, z: 256, structure: .automatic)
        XCTAssertEqual(fill.edge.sections, sections([(.embankment, 4)]))
        XCTAssertEqual(fill.cost, 400 + 182)
        // At 16 m, a viaduct, its piers 64 past 15 m: 8 lengths, 8 · 3 · 100
        // and 512 · 100 / 640 = 80.
        var lifted = self.world()
        let high = try build(&lifted, from: 1_024, to: 9_216, z: 1_024, structure: .automatic)
        XCTAssertEqual(high.edge.sections, sections([(.viaduct, 8)]))
        XCTAssertEqual(high.cost, 2_400 + 80)
    }

    // MARK: - Ground

    /// A valley 20 m deep, its sides 64 m wide (corner columns 20, 20, 0, 0,
    /// 20 m), crossed by 16 lengths at 20 m from x = 1,024: the middles at
    /// 1,536 + 1,024 i stand 0, 0, 0, 160, 480, 800, 1,120, 1,280 (four
    /// times), 1,120, 800, 480, 160, 0 above the ground.
    func testAnAutomaticEdgeFollowsTheGroundAndAShortRunJoinsItsNeighbour() throws {
        var world = try world(columns: [20, 20, 0, 0, 20])
        let (edge, cost) = try build(&world, from: 1_024, to: 17_408, z: 1_280, structure: .automatic)
        // Surface 3, embankment 2, viaduct 8 (over 512), and the last three
        // on the ground, a run shorter than 4, join the viaduct beside them.
        XCTAssertEqual(edge.sections, sections([(.surface, 3), (.embankment, 2), (.viaduct, 11)]))
        // 3 + 2 + 11 · 3 = 38 prices; earthwork 7 · 32 · 1,376 + 7 · 352 ·
        // 2,336 = 6,064,128, · 100 / 3,276,800 = 185.06, 185; piers 160 +
        // 4 · 320 + 160 = 1,600, · 100 / 640 = 250.
        XCTAssertEqual(cost, 3_800 + 185 + 250)
        XCTAssertEqual(edge.sectionSpans.map(\.start), [0, 3_072, 5_120])
        XCTAssertEqual(edge.sectionSpans.last?.end, 16_384)

        // A renderer reads a platform on the surface section as on the
        // surface and one on the viaduct as elevated, in their order along
        // the edge.
        let station = try world.buildStation(named: "Valley", at: PlanPoint(x: 9_216, y: Self.row)).id
        try world.addTrackPlatform(station, on: edge.id, from: 8_192, to: 9_216)
        try world.addTrackPlatform(station, on: edge.id, from: 0, to: 1_024)
        XCTAssertEqual(world.railwaySnapshot().platforms.map(\.structure), [.surface, .elevated])
    }

    /// The edge's own ends stand on the ground; a node goes at most 64 m
    /// above or below the ground under it.
    func testANodeStaysWithin64MetresOfTheGround() throws {
        var world = try world(columns: [100])
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 1_024, y: Self.row)), 6_400)
        XCTAssertNoThrow(try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: Self.row, z: 6_400 + 4_096)))
        XCTAssertNoThrow(try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: Self.row, z: 6_400 - 4_096)))
        for z: Int64 in [6_400 + 4_097, 6_400 - 4_097, 0] {
            XCTAssertThrowsError(try world.buildTrackNode(at: WorldCoordinate(x: 3_072, y: Self.row, z: z))) {
                XCTAssertEqual($0 as? GameError, .invalidTrackGeometry)
            }
        }
        // Where no block has been read the ground is not known.
        XCTAssertThrowsError(try world.buildTrackNode(at: WorldCoordinate(x: 70_000, y: Self.row, z: 0))) {
            XCTAssertEqual($0 as? GameError, .groundNotLoaded)
        }
    }

    /// A hill 20 m high (corner columns 0, 0, 20, 20, 20, 20, 0) under track
    /// at 0 m from x = 1,024, 32 lengths: cut, then tunnel deeper than 11
    /// m, then cut again. A house over the tunnel stands; one over the open
    /// track comes down.
    func testATunnelPassesUnderAHouseAndTheOpenTrackClearsOne() throws {
        var world = try world(columns: [0, 0, 20, 20, 20, 20, 0])
        let over = try world.placeBuilding(.house, at: PlanPoint(x: 12_800, y: Self.row))
        let beside = try world.placeBuilding(.house, at: PlanPoint(x: 29_696, y: Self.row))
        let (edge, _) = try build(&world, from: 1_024, to: 33_792, z: 0, structure: .automatic)
        XCTAssertEqual(edge.sections, sections([(.surface, 3), (.cutting, 2), (.tunnel, 16), (.cutting, 2), (.surface, 9)]))
        XCTAssertEqual(world.placedBuildings.map(\.id), [over.id], "the house over the tunnel stands")
        XCTAssertNotEqual(over.id, beside.id)
        // The tunnel's portals lie inside the edge, where its sections change.
        let tunnel = try XCTUnwrap(edge.sectionSpans.first { $0.kind == .tunnel })
        XCTAssertEqual([tunnel.start, tunnel.end], [5_120, 21_504])
        XCTAssertFalse(world.network.isTunnelPortal(edge.from))

        // Split 8,192 along: the first part's last three tunnel lengths, a
        // run shorter than 4, become a cutting (the deepest is 20 m, as
        // deep as a cutting may go when it joins one); the second part
        // starts in the tunnel.
        let node = try world.splitTrackEdge(edge.id, at: 8_192)
        let parts = world.network.edges.filter { $0.from == node || $0.to == node }.sorted { $0.id < $1.id }
        XCTAssertEqual(parts.map(\.sections), [
            sections([(.surface, 3), (.cutting, 5)]),
            sections([(.tunnel, 13), (.cutting, 2), (.surface, 9)]),
        ])
        XCTAssertTrue(world.network.isTunnelPortal(node), "a cutting meets a tunnel at the new node")
    }

    // MARK: - Water

    /// A lake on cell column 2 of the first row; flat ground at 0 m. Track
    /// 16 lengths from x = 1,024 has lengths 7 to 10 over it.
    func testWaterNeedsABridgeOrATunnel() throws {
        var world = try world(columns: [0])
        try world.setWater([CellPosition(row: 0, column: 2)])
        for structure: TrackStructure in [.surface, .elevated, .automatic] {
            var attempt = world
            let z: Int64 = structure == .elevated ? 512 : 0
            XCTAssertThrowsError(try build(&attempt, from: 1_024, to: 17_408, z: z, structure: structure), "\(structure)") {
                XCTAssertEqual($0 as? GameError, .trackOverWater)
            }
        }
        // A bridge 3 m over the water is too low; 8 m is high enough.
        var low = world
        XCTAssertThrowsError(try build(&low, from: 1_024, to: 17_408, z: 192, structure: .automatic)) {
            XCTAssertEqual($0 as? GameError, .trackOverWater)
        }
        // At 8 m: embankments on land (h = 384, 7 · 384 · 2,432 = 6,537,216
        // a length, 12 of them · 100 / 3,276,800 = 2,394) and a bridge of
        // four over the lake (4 · 4 · 100).
        var automatic = world
        let (edge, cost) = try build(&automatic, from: 1_024, to: 17_408, z: 512, structure: .automatic)
        XCTAssertEqual(edge.sections, sections([(.embankment, 7), (.bridge, 4), (.embankment, 5)]))
        XCTAssertEqual(cost, 1_200 + 2_394 + 1_600)
        // A bridge the whole way, forced: 16 · 4 · 100.
        var bridge = world
        XCTAssertEqual(try build(&bridge, from: 1_024, to: 17_408, z: 512, structure: .bridge).cost, 6_400)
        // A station cannot stand on the lake, in a world with ground.
        XCTAssertThrowsError(try world.buildStation(named: "Lake", at: PlanPoint(x: 9_216, y: Self.row))) {
            XCTAssertEqual($0 as? GameError, .onWater(row: 0, column: 2))
        }
        XCTAssertNoThrow(try world.buildStation(named: "Shore", at: PlanPoint(x: 5_120, y: Self.row)))
        // Without ground the water does not count for track or stations.
        var flat = self.world()
        try flat.setWater([CellPosition(row: 0, column: 2)])
        XCTAssertNoThrow(try build(&flat, from: 1_024, to: 17_408, z: 0, structure: .surface))
        XCTAssertNoThrow(try flat.buildStation(named: "Lake", at: PlanPoint(x: 9_216, y: Self.row)))
    }

    /// A viaduct stands at most 64 m above the ground: across a dip 10 m
    /// deep (corner columns 0, −10, 0) track at 60 m stands 66.25 m above
    /// the second length's middle.
    func testAViaductStandsAtMost64MetresHigh() throws {
        let world = try world(columns: [0, -10, 0])
        for structure: TrackStructure in [.automatic, .elevated] {
            var attempt = world
            XCTAssertThrowsError(try build(&attempt, from: 1_024, to: 7_168, z: 3_840, structure: structure), "\(structure)") {
                XCTAssertEqual($0 as? GameError, .structureTooHigh)
            }
        }
    }

    // MARK: - Having ground

    func testAWorldIsGivenGroundBeforeItHasTrack() throws {
        var world = world()
        try world.mapGround()
        XCTAssertTrue(world.ground.isMapped)
        XCTAssertNil(world.groundHeight(at: PlanPoint(x: 1_024, y: 1_024)), "no block read yet")
        XCTAssertThrowsError(try world.mapGround()) { XCTAssertEqual($0 as? GameError, .invalidGround) }
        XCTAssertThrowsError(try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 1_024, z: 0))) {
            XCTAssertEqual($0 as? GameError, .groundNotLoaded)
        }
        XCTAssertEqual(world.missingGroundBlocks(under: [PlanPoint(x: 1_024, y: 1_024), PlanPoint(x: 70_000, y: 1_024)]),
                       [LandBlock(row: 0, column: 0), LandBlock(row: 0, column: 1)])

        var tracked = self.world()
        try tracked.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 1_024, z: 0))
        XCTAssertThrowsError(try tracked.mapGround(), "track on a flat world is not measured from ground that came later") {
            XCTAssertEqual($0 as? GameError, .invalidGround)
        }
        XCTAssertEqual(tracked.missingGroundBlocks(under: [PlanPoint(x: 1_024, y: 1_024)]), [], "a world without ground needs none")
    }

    // MARK: - Saving

    func testSectionsAndGroundAreSavedAndBadOnesRefused() throws {
        var world = try world(columns: [20, 20, 0, 0, 20])
        try build(&world, from: 1_024, to: 17_408, z: 1_280, structure: .automatic)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let network = try XCTUnwrap((object["world"] as? [String: Any])?["network"] as? [String: Any])
        let edge = try XCTUnwrap((network["edges"] as? [[String: Any]])?.first)
        XCTAssertEqual(edge["structure"] as? String, "automatic")
        XCTAssertEqual((edge["sections"] as? [[String: Any]])?.map { $0["kind"] as? String }, ["surface", "embankment", "viaduct"])

        // A world given ground with no block read saves that it has ground.
        var mapped = self.world()
        try mapped.mapGround()
        let saved = try JSONEncoder().encode(SavedGame(world: mapped))
        let ground = try XCTUnwrap(((JSONSerialization.jsonObject(with: saved) as? [String: Any])?["world"] as? [String: Any])?["ground"] as? [String: Any])
        XCTAssertEqual((ground["blocks"] as? [Any])?.count, 0)
        XCTAssertTrue(try JSONDecoder().decode(SavedGame.self, from: saved).world.ground.isMapped)

        // Sections that do not cover the edge, on an explicit edge, missing
        // on an automatic one, or that the ground does not allow.
        func edited(_ change: (inout [String: Any]) -> Void) throws -> Data {
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var savedWorld = try XCTUnwrap(root["world"] as? [String: Any])
            var savedNetwork = try XCTUnwrap(savedWorld["network"] as? [String: Any])
            var edges = try XCTUnwrap(savedNetwork["edges"] as? [[String: Any]])
            change(&edges[0])
            savedNetwork["edges"] = edges
            savedWorld["network"] = savedNetwork
            root["world"] = savedWorld
            return try JSONSerialization.data(withJSONObject: root)
        }
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: edited { _ in }).world, world)
        for bad: [(String, Int)] in [
            [("surface", 3), ("embankment", 2), ("viaduct", 10)],
            [("surface", 3), ("surface", 2), ("viaduct", 11)],
            [("surface", 16)],
            [("tunnel", 16)],
        ] {
            let sections = bad.map { ["kind": $0.0, "lengths": $0.1] as [String: Any] }
            XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0["sections"] = sections }), "\(bad)")
        }
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0["structure"] = "elevated" }), "sections on an explicit edge")
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0["sections"] = nil }), "no sections on an automatic edge")
    }

    // MARK: - Save version 28

    /// The version 27 world (sea, river, steep hillside, ground of blocks
    /// (0, 0), (0, 1) and (1, 0), block (r, c)'s corner (i, j) 100 r +
    /// 10 c + i + j metres) with two automatic edges: one along y = 20,480
    /// from x = 30,720 to 53,248 at 24 m, over the river (column 10) on a
    /// bridge, and one along y = 40,960 from x = 4,096 to 12,288 at 0 m,
    /// in a tunnel under ground 11 to 13 m high; run ten minutes more.
    static func terrainTrackWorld() throws -> GameWorld {
        var world = try GroundTests.groundWorld()
        for (y, from, to, z) in [(Int64(20_480), Int64(30_720), Int64(53_248), Int64(1_536)), (40_960, 4_096, 12_288, 0)] {
            let a = try world.buildTrackNode(at: WorldCoordinate(x: from, y: y, z: z))
            let b = try world.buildTrackNode(at: WorldCoordinate(x: to, y: y, z: z))
            try world.buildTrackEdge(from: a, to: b, structure: .automatic)
        }
        try world.advance(ticks: 10)
        return world
    }

    /// Version 28 (decision 124): automatic track and its sections. It
    /// saves byte for byte and is the world the build that wrote it makes.
    func testVersionTwentyEightKeepsTheAutomaticTrack() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v28-terrain-track.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["TERRAIN_TRACK_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: try Self.terrainTrackWorld())).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 28)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, try Self.terrainTrackWorld())
        XCTAssertTrue(world.ground.isMapped)
        let kinds = world.network.edges.map { Set($0.sections.map(\.kind)) }
        XCTAssertEqual(kinds.count, 2)
        XCTAssertTrue(kinds[0].contains(.bridge))
        XCTAssertEqual(kinds[1], [.tunnel])
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 28,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
