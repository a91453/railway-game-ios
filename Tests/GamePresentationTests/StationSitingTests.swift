import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 108: choosing where a station goes. With a place
/// on track picked for a platform, the session says who lives and works
/// within a station's catchment of it: the land GameCore's station demand
/// draws on, so a cell past 800 m does not count.
@MainActor
final class StationSitingTests: XCTestCase {
    /// A straight track 480 m long west to east; homes and jobs in a cell
    /// beside its middle, and more homes some 3.6 km away.
    private func makeSession() throws -> GameSession {
        var world = try makeWorld(width: 262_144, height: 16_384, balance: 10_000_000, speed: .paused)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 31_744, y: 8_192))
        try world.buildTrackEdge(from: west, to: east)
        try world.setLand([
            LandCell(row: 2, column: 4, use: .residential, residents: 1_200, jobs: 300),
            LandCell(row: 2, column: 60, use: .residential, residents: 9_000, jobs: 0),
        ])
        return GameSession(world: world, language: .english)
    }

    func testThePickedSiteCountsWhoLivesAndWorksWithin800Metres() throws {
        let session = try makeSession()
        XCTAssertNil(session.platformSiteCatchment, "nothing picked")
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 512)
        let site = try XCTUnwrap(session.platformSitePlanPoint)
        XCTAssertEqual(site.y, 8_192, "on the track")
        let catchment = try XCTUnwrap(session.platformSiteCatchment)
        XCTAssertEqual(catchment, session.world.land.totals(within: Land.catchmentRadius, of: site))
        XCTAssertEqual(catchment.residents, 1_200, "the far cell is past 800 m")
        XCTAssertEqual(catchment.jobs, 300)
        XCTAssertEqual(session.catchmentText(catchment), "Within 800 m: 1,200 residents · 300 jobs")

        session.setNetworkMode(.build)
        XCTAssertNil(session.platformSitePlanPoint, "only while choosing where a platform goes")
    }
}
