import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 84: the lines along the track their trains take,
/// side by side where they share it (MapBuilder's interline segments and
/// offsets), and transfer groups linked through their stations.
final class LineMapTests: XCTestCase {
    // One straight edge east along y = 3072, from 1024 to 15360 (14336
    // long): West's platform at 1024…5120 along it, Middle's at
    // 5632…7680, East's at 9216…13312.
    private static let edge = TrackEdgeID.edge(1)

    private func makeWorld() throws -> (GameWorld, west: StationID, middle: StationID, east: StationID) {
        var world = try GamePresentationTests.makeWorld(width: 16_384, height: 6_144, balance: 1_000_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 3_072))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 15_360, y: 3_072))
        try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 2_560, y: 3_584)).id
        let middle = try world.buildStation(named: "Middle", at: PlanPoint(x: 7_168, y: 3_584)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 12_800, y: 3_584)).id
        try world.addTrackPlatform(west, on: Self.edge, from: 1_024, to: 5_120)
        try world.addTrackPlatform(middle, on: Self.edge, from: 5_632, to: 7_680)
        try world.addTrackPlatform(east, on: Self.edge, from: 9_216, to: 13_312)
        return (world, west, middle, east)
    }

    /// MapBuilder's offsets: an odd number of lines has one on the track,
    /// an even number none, and the rest go out either side in turn.
    func testOffsetsFollowMapBuilder() {
        XCTAssertEqual(LineMap.offsets(count: 0), [])
        XCTAssertEqual(LineMap.offsets(count: 1), [0])
        XCTAssertEqual(LineMap.offsets(count: 2), [0.5, -0.5])
        XCTAssertEqual(LineMap.offsets(count: 3), [0, -1, 1])
        XCTAssertEqual(LineMap.offsets(count: 4), [0.5, -0.5, 1.5, -1.5])
        XCTAssertEqual(LineMap.offsets(count: 5), [0, -1, 1, -2, 2])
    }

    /// A line alone is on the track, over the stretch its trains drive:
    /// from its first call's berth to its last call's and back.
    func testALineAloneRunsOnTheTrack() throws {
        var (world, west, _, east) = try makeWorld()
        let line = try world.createLine(named: "Shuttle", stops: [west, east]).id
        let map = LineMap(world: world)
        XCTAssertFalse(map.stretches.isEmpty)
        XCTAssertTrue(map.stretches.allSatisfy { $0.line == line && $0.edge == Self.edge && $0.offset == 0 && $0.color == nil })
        // One stretch: the ways out and back join up.
        XCTAssertEqual(map.stretches.count, 1)
        let stretch = try XCTUnwrap(map.stretches.first)
        XCTAssertGreaterThanOrEqual(stretch.start, 1_024)
        XCTAssertLessThanOrEqual(stretch.start, 5_120, "starts at West's platform")
        XCTAssertGreaterThanOrEqual(stretch.end, 9_216)
        XCTAssertLessThanOrEqual(stretch.end, 13_312, "ends at East's platform")
        XCTAssertEqual(map.transfers, [])
    }

    /// Where a second line shares the track, the two are drawn half a
    /// width out either side, the lower ID first; where the first runs
    /// alone it stays on the track.
    func testLinesSharingTrackGoSideBySide() throws {
        var (world, west, middle, east) = try makeWorld()
        let long = try world.createLine(named: "Long", stops: [west, east]).id
        let short = try world.createLine(named: "Short", stops: [middle, east]).id
        let color = try XCTUnwrap(LineColor(rgb: 0x123456))
        try world.setLineColor(short, to: color)
        let map = LineMap(world: world)

        let shorts = map.stretches.filter { $0.line == short }
        XCTAssertEqual(shorts.count, 1)
        let shared = try XCTUnwrap(shorts.first)
        XCTAssertEqual(shared.offset, -0.5)
        XCTAssertEqual(shared.color, color)

        let longs = map.stretches.filter { $0.line == long }
        XCTAssertEqual(longs.map(\.offset), [0, 0.5], "alone, then beside Short")
        XCTAssertEqual(longs[0].end, longs[1].start)
        XCTAssertEqual(longs[1].start, shared.start)
        XCTAssertEqual(longs[1].end, shared.end)
    }

    /// A transfer group is linked through its stations in the group's
    /// order; a station left alone is not.
    func testTransferGroupsAreLinkedThroughTheirStations() throws {
        var (world, west, middle, east) = try makeWorld()
        _ = try world.linkTransfer(east, west)
        let positions = [west, east].compactMap { world.station(id: $0)?.location }
        XCTAssertEqual(LineMap(world: world).transfers, [positions])

        _ = try world.linkTransfer(middle, west)
        let three = [west, middle, east].compactMap { world.station(id: $0)?.location }
        XCTAssertEqual(LineMap(world: world).transfers, [three])
    }

    /// On the demo map, with its two lines and its ring, every line is
    /// drawn, each stretch within its edge, and where lines share track
    /// they take MapBuilder's offsets.
    func testTheDemoMapDrawsEveryLine() throws {
        let world = DemoWorld.make(in: .english)
        let map = LineMap(world: world)
        XCTAssertEqual(Set(map.stretches.map(\.line)), Set(world.lines.map(\.id)))
        for stretch in map.stretches {
            let edge = try XCTUnwrap(world.network.edge(stretch.edge))
            XCTAssertTrue(0 <= stretch.start && stretch.start < stretch.end && stretch.end <= edge.length, "\(stretch)")
        }
        // Stretches of one edge that overlap are drawn side by side.
        for (edge, stretches) in Dictionary(grouping: map.stretches, by: \.edge) {
            for a in stretches {
                let over = stretches.filter { $0.start < a.end && a.start < $0.end }
                XCTAssertEqual(Set(over.map(\.offset)).count, over.count, "\(edge): no two lines on top of each other")
            }
        }
    }
}
