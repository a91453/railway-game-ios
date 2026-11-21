@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 912: what the station panel and the platform picker say about
/// changing lines, and that GameCore's island is the 3D map's (decision
/// 392).
///
/// Station S has three platform tracks running east: A, B 11 m north of it
/// (an island between), C 5 m south (too near for one). Lines West and
/// North name A and B, South names C.
final class StationTransfersTests: XCTestCase {
    private static let unit = WorldCoordinate.unitsPerMetre
    private static let y: Int64 = 8_192

    private struct Scene {
        var world: GameWorld
        let s: StationID
        let platforms: [TrackPlatform]
    }

    /// The tracks at the given offsets (metres) and their platforms at S.
    private static func scene(_ offsets: [Int64] = [0, 11, -5], extra: [Int64] = []) throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 200_704, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 6 * 60), speed: .normal)
        )
        func track(_ dy: Int64) throws -> TrackEdgeID {
            let from = try world.buildTrackNode(at: WorldCoordinate(x: 40_960, y: y + dy * unit, z: 0))
            let to = try world.buildTrackNode(at: WorldCoordinate(x: 61_440, y: y + dy * unit, z: 0))
            return try world.buildTrackEdge(from: from, to: to, structure: .surface)
        }
        let edges = try offsets.map(track)
        for dy in extra { _ = try track(dy) }
        let s = try world.buildStation(named: "S", at: PlanPoint(x: 51_200, y: y)).id
        for edge in edges {
            try world.addTrackPlatform(s, on: edge, from: 2_048, to: 12_288)
        }
        let platforms = world.trackPlatforms(of: s)
        return Scene(world: world, s: s, platforms: edges.map { edge in platforms.first { $0.edge == edge }! })
    }

    /// Lines West, North and South from S to stations of their own, each
    /// naming its platform at S.
    private static func lines(_ scene: inout Scene) throws -> [LineID] {
        var ids: [LineID] = []
        for (index, name) in ["West", "North", "South"].enumerated() {
            let far = try scene.world.buildStation(named: name, at: PlanPoint(x: 8_192 + Int64(index) * 60_000, y: 14_000)).id
            let line = try scene.world.createLine(named: name, stops: [far, scene.s]).id
            try scene.world.setLineRoutePreferences(line, to: [LineRoutePreference(from: 0, to: 1, platform: scene.platforms[index])])
            ids.append(line)
        }
        return ids
    }

    func testThePanelSaysHowEachChangeIsMade() throws {
        var scene = try Self.scene()
        let lines = try Self.lines(&scene)
        let transfers = StationTransfers(world: scene.world, station: scene.s)
        XCTAssertEqual(transfers.linesAt[scene.platforms[0]], [lines[0]])
        XCTAssertEqual(transfers.linesAt[scene.platforms[1]], [lines[1]])
        XCTAssertEqual(transfers.pairs.map(\.title), ["West ⇄ North", "West ⇄ South", "North ⇄ South"])
        XCTAssertEqual(transfers.pairs.map { $0.text(in: .traditionalChinese) }, ["對面換乘 1 分", "走天橋 2 分", "走天橋 2 分"])
        XCTAssertEqual(transfers.pairs[0].text(in: .english), "Across the platform, 1 min")
    }

    func testThePickerSaysWhatAPlatformMakesOfTheChanges() throws {
        var scene = try Self.scene()
        let lines = try Self.lines(&scene)
        XCTAssertEqual(StationTransfers.notes(world: scene.world, choosing: scene.platforms[0], for: lines[2], in: .traditionalChinese),
                       ["和West對面", "和North對面"], "C's line choosing A: at West's, across the island from North's")
        XCTAssertEqual(StationTransfers.notes(world: scene.world, choosing: scene.platforms[1], for: lines[0], in: .english),
                       ["Across from North", "Same level as South"])
    }

    func testALineNamingNoPlatformSaysSo() throws {
        var scene = try Self.scene()
        let lines = try Self.lines(&scene)
        try scene.world.setLineRoutePreferences(lines[2], to: [])
        let transfers = StationTransfers(world: scene.world, station: scene.s)
        XCTAssertEqual(transfers.pairs.last?.text(in: .traditionalChinese), "沒指定月台 2 分")
        XCTAssertEqual(StationTransfers.notes(world: scene.world, choosing: scene.platforms[0], for: lines[1], in: .english), ["Across from West"])
    }

    /// Decision 392's island is GameCore's: where the 3D map draws one
    /// platform between two tracks, the change is across it, and nowhere
    /// else.
    func testGameCoresIslandIsTheOneTheMapDraws() throws {
        for (offsets, extra) in [([Int64(0), 11, -5], [Int64]()), ([0, 11], [6]), ([0, 6], []), ([0, 14], [])] {
            let scene = try Self.scene(offsets, extra: extra)
            let world = scene.world
            let frame = Map3DScene.frame(world: world, focus: (x: 51_200, y: Double(Self.y)))
            var builder = Map3DScene.Builder(originX: frame.originX, originY: frame.originY, region: frame.region, world: world)
            let snapshot = world.railwaySnapshot()
            _ = builder.addTrack(snapshot)
            builder.addPlatforms(snapshot)
            let drawn = Set(builder.laidPlatforms.filter(\.island).map(\.edge))
            for platform in scene.platforms {
                let across = scene.platforms.contains { $0 != platform && world.platformChange(from: platform, to: $0)?.kind == .acrossPlatform }
                XCTAssertEqual(drawn.contains(platform.edge), across, "tracks \(offsets), \(extra) between: platform on \(platform.edge)")
            }
        }
    }
}
