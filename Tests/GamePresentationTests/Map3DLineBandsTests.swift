import GameCore
@testable import GamePresentation
import XCTest

/// Decision 314: a thin band in each line's colour beside the track it
/// runs on; where lines share track, only the one the 2D map draws on top.
final class Map3DLineBandsTests: XCTestCase {
    // One straight edge east along y = 3072, as LineMapTests's.
    private func makeWorld() throws -> (GameWorld, west: StationID, middle: StationID, east: StationID) {
        var world = try GamePresentationTests.makeWorld(width: 16_384, height: 6_144, balance: 1_000_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 3_072))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 15_360, y: 3_072))
        try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 2_560, y: 3_584)).id
        let middle = try world.buildStation(named: "Middle", at: PlanPoint(x: 7_168, y: 3_584)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 12_800, y: 3_584)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 1_024, to: 5_120)
        try world.addTrackPlatform(middle, on: .edge(1), from: 5_632, to: 7_680)
        try world.addTrackPlatform(east, on: .edge(1), from: 9_216, to: 13_312)
        return (world, west, middle, east)
    }

    /// Where Short shares Long's track, Short's band (the larger ID, on top
    /// on the 2D map); where Long runs alone, Long's.
    func testTheTopLineWinsWhereLinesShareTrack() throws {
        var (world, west, middle, east) = try makeWorld()
        let long = try world.createLine(named: "Long", stops: [west, east]).id
        let short = try world.createLine(named: "Short", stops: [middle, east]).id
        XCTAssertLessThan(long, short)
        try world.setLineColor(long, to: try XCTUnwrap(LineColor(rgb: 0x112233)))
        try world.setLineColor(short, to: try XCTUnwrap(LineColor(rgb: 0x445566)))

        let bands = Map3DLineBands(world: world, palette: .standard).bands
        XCTAssertEqual(bands.map(\.rgb), [0x112233, 0x445566], "Long alone, then Short over the shared stretch")
        XCTAssertEqual(bands[0].end, bands[1].start)
        XCTAssertTrue(bands.allSatisfy { $0.edge == .edge(1) && $0.start < $0.end })
        let shared = try XCTUnwrap(LineMap(world: world).stretches.first { $0.line == short })
        XCTAssertEqual(bands[1].start, shared.start)
        XCTAssertEqual(bands[1].end, shared.end)
    }

    /// A line with no colour of its own gets its automatic one (decision
    /// 216), and the colour-blind-safe palette changes it as the 2D map's.
    func testTheBandsColourIsTheOneThe2DMapDraws() throws {
        var (world, west, _, east) = try makeWorld()
        let line = try world.createLine(named: "Shuttle", stops: [west, east]).id
        let automatic = LineBadge.automaticColor(of: line)
        XCTAssertEqual(Map3DLineBands(world: world, palette: .standard).bands.map(\.rgb), [automatic])
        XCTAssertEqual(Map3DLineBands(world: world, palette: .colourBlindSafe).bands.map(\.rgb),
                       [LinePalette.colourBlindSafe.color(for: automatic)])
        XCTAssertEqual(Map3DLineBands(world: try makeWorld().0, palette: .standard).bands, [], "no line, no band")
    }

    /// The scene is built again when a line's track or colour changes,
    /// not when its trains run.
    func testTheSignatureChangesWithTheLinesTrackAndColourOnly() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        let before = Map3DLineBands.Signature(world: world)
        try world.advance(ticks: 600)
        XCTAssertEqual(Map3DLineBands.Signature(world: world), before, "trains sent out and running")
        let line = try XCTUnwrap(world.lines.first).id
        try world.setLineColor(line, to: try XCTUnwrap(LineColor(rgb: 0x123456)))
        XCTAssertNotEqual(Map3DLineBands.Signature(world: world), before)
    }

    /// The bands are only in the near meshes, in the line's colour, beside
    /// the rails on the ballast's shoulder; the far view is unchanged.
    func testTheSceneDrawsTheBandsBesideTheTrackCloseUp() throws {
        var (world, west, _, east) = try makeWorld()
        let line = try world.createLine(named: "Shuttle", stops: [west, east]).id
        try world.setLineColor(line, to: try XCTUnwrap(LineColor(rgb: 0x123456)))
        let bands = Map3DLineBands(world: world, palette: .standard)
        let plain = Map3DScene(world: world), banded = Map3DScene(world: world, lineBands: bands)
        XCTAssertGreaterThan(banded.triangleCount, plain.triangleCount)
        XCTAssertEqual(banded.chunks.map(\.far.vertices), plain.chunks.map(\.far.vertices))
        XCTAssertEqual(banded.chunks.map(\.close.vertices), plain.chunks.map(\.close.vertices))

        let colour = Map3DColor.rgb(0x123456)
        let painted = banded.chunks.flatMap(\.mesh.vertices).filter { $0.color == colour }
        XCTAssertFalse(painted.isEmpty)
        XCTAssertTrue(plain.chunks.flatMap(\.mesh.vertices).allSatisfy { $0.color != colour })
        // The track runs east, so the band lies a fixed way north or south
        // of its middle, beside the rails (1.067 m apart), on the bed.
        let middle = banded.point(WorldCoordinate(x: 8_000, y: 3_072)).z
        let across = Set(painted.map { abs($0.z - middle) })
        let offset = Map3DLineBands.offset(on: .surface)
        XCTAssertTrue(across.allSatisfy { abs($0 - offset) <= Map3DLineBands.width / 2 + 0.01 }, "\(across)")
        XCTAssertGreaterThan(offset - Map3DLineBands.width / 2, 1.067 / 2 + 0.1, "outside the rails")
    }
}
