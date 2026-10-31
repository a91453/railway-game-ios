import GameCore
@testable import GamePresentation
import XCTest

/// Decision 519 (the owner's play-test, 2026-10-31): at Taipei on the
/// real-world map a player drew a freight track beside the station and
/// tapped it in the Station mode, but the platform went to a new station,
/// not to Taipei, which stands at the middle of its 300 m platform: a
/// station was chosen only within 32 m of that middle. Now a station is
/// chosen when the place is near one of its platforms too, and the
/// station menu lists the stations nearest the place first.
@MainActor
final class PlatformStationJoinTests: XCTestCase {
    private let metre = WorldCoordinate.unitsPerMetre
    private static let reach: Int64 = 512

    /// A 300 m station platform along y = 40 m, "Taipei" at its middle
    /// (x = 200 m), and the player's own track 40 m south of it, from
    /// beside its east end (x = 330 m) on east to x = 600 m, joined to
    /// nothing; a station "Far" 900 m east.
    private func taipei() throws -> (world: GameWorld, taipei: StationID, far: StationID) {
        var world = try makeWorld(width: 1_200 * metre, height: 400 * metre, balance: 1_000_000)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 50 * metre, y: 40 * metre))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 350 * metre, y: 40 * metre))
        let main = try world.buildTrackEdge(from: west, to: east)
        let taipei = try world.buildStation(named: "Taipei", at: PlanPoint(x: 200 * metre, y: 40 * metre))
        try world.addTrackPlatform(taipei.id, on: main, from: 0, to: 300 * metre)
        let far = try world.buildStation(named: "Far", at: PlanPoint(x: 1_100 * metre, y: 300 * metre))
        let start = try world.buildTrackNode(at: WorldCoordinate(x: 330 * metre, y: 80 * metre))
        let end = try world.buildTrackNode(at: WorldCoordinate(x: 600 * metre, y: 80 * metre))
        try world.buildTrackEdge(from: start, to: end)
        return (world, taipei.id, far.id)
    }

    /// Tapped where it runs beside the platform's end, 40 m from it and
    /// 130 m from the station's middle, the player's track gets a
    /// platform of Taipei, not of a new station.
    func testAPlatformBesideAStationsPlatformJoinsIt() throws {
        let (world, taipei, _) = try taipei()
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        session.platformCars = 2
        session.tapNetwork(at: PlanPoint(x: 340 * metre, y: 80 * metre), reach: Self.reach)
        XCTAssertNotNil(session.networkEdgePoint)
        XCTAssertEqual(session.platformStationID, taipei, "the station whose platform is 40 m away")

        session.addNetworkPlatform()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.stations.count, 2, "no new station")
        XCTAssertEqual(session.world.trackPlatforms(of: taipei).count, 2)
    }

    /// Far from every station's platforms, or out past a platform's end
    /// (the next station along the line, 64 m on in the first lesson), the
    /// place still gets a new station, as before.
    func testAPlaceNotBesideAPlatformGetsANewStation() throws {
        let (world, _, _) = try taipei()
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        session.platformCars = 2
        for x: Int64 in [590, 380] {
            session.tapNetwork(at: PlanPoint(x: x * metre, y: 80 * metre), reach: Self.reach)
            XCTAssertNotNil(session.networkEdgePoint)
            XCTAssertNil(session.platformStationID, "\(x) m")
        }
    }

    /// The station menu lists the stations nearest the place first, each
    /// with how far it stands.
    func testTheStationMenuListsTheNearestStationsFirst() throws {
        var (world, taipei, far) = try taipei()
        let other = try world.buildStation(named: "Other", at: PlanPoint(x: 20 * metre, y: 380 * metre))
        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        session.platformCars = 2
        session.tapNetwork(at: PlanPoint(x: 590 * metre, y: 80 * metre), reach: Self.reach)
        let choices = session.platformStationMenuChoices
        XCTAssertEqual(choices.map(\.id), [taipei, far, other.id], "\(choices.map(\.title))")
        XCTAssertEqual(choices.map(\.title), ["Taipei · 392 公尺", "Far · 555 公尺", "Other · 644 公尺"])
    }

    /// The station panel's platforms say how a track of the player's own
    /// gets a platform of the station.
    func testThePanelSaysHowAnOwnTrackCallsHere() throws {
        let (world, taipei, _) = try taipei()
        let session = GameSession(world: world, language: .traditionalChinese)
        let station = try XCTUnwrap(world.station(id: taipei))
        XCTAssertEqual(session.ownTrackPlatformHelp(for: station), "要讓自己拉的軌道停這站：用路網工具的「車站」點那條軌道，車站選「Taipei」。")
    }
}
