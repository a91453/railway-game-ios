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
    private func makeSession(
        land: [LandCell] = [
            LandCell(row: 2, column: 4, use: .residential, residents: 1_200, jobs: 300),
            LandCell(row: 2, column: 60, use: .residential, residents: 9_000, jobs: 0),
        ],
        language: DisplayLanguage = .english,
        outsideConnections: Bool = false
    ) throws -> GameSession {
        var world = try makeWorld(width: 262_144, height: 16_384, balance: 10_000_000, speed: .paused)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 31_744, y: 8_192))
        try world.buildTrackEdge(from: west, to: east)
        if !land.isEmpty {
            try world.setLand(land)
        }
        if outsideConnections {
            try world.setFareBaseline(FareRules.standardFare)
            world.setOutsideConnections(true)
        }
        return GameSession(world: world, language: language)
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

    /// Decision 128: a new station says, as it opens, who it reaches, or
    /// that no one lives or works near it yet; without land it says
    /// neither.
    func testANewStationSaysWhoItReachesAsItOpens() throws {
        let cases: [(land: [LandCell], language: DisplayLanguage, ending: String?)] = [
            (
                [LandCell(row: 2, column: 4, use: .residential, residents: 1_200, jobs: 300)], .english,
                " Within 800 m: 1,200 residents · 300 jobs. Serve it well and the town round it grows."
            ),
            (
                [LandCell(row: 2, column: 4, use: .residential, residents: 1_200, jobs: 300)], .traditionalChinese,
                "800 公尺內：居民 1,200 · 工作 300。服務好，附近的城市就會長大。"
            ),
            (
                [LandCell(row: 2, column: 60, use: .residential, residents: 9_000, jobs: 0)], .english,
                " No one lives or works within 800 m yet: it will see few passengers."
            ),
            ([], .english, nil),
        ]
        for (land, language, ending) in cases {
            let session = try makeSession(land: land, language: language)
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 512)
            session.addNetworkPlatform()
            XCTAssertEqual(session.world.stations.count, 1)
            let text = try XCTUnwrap(session.message?.text)
            if let ending {
                XCTAssertTrue(text.hasSuffix(ending), text)
            } else {
                XCTAssertTrue(text.hasSuffix("."), text)
                XCTAssertFalse(text.contains("800 m"), text)
            }
        }
    }

    /// Decision 137: by the map's edge (the whole of this 256 m high world
    /// is within 1 km of it) the site says a station there is an outside
    /// connection, and the station says so as it opens.
    func testAStationByTheEdgeSaysItIsAnOutsideConnection() throws {
        for (language, caption, ending) in [
            (DisplayLanguage.english, "Within 800 m: 1,200 residents · 300 jobs\nOutside connection: +$ 5 a trip",
             " Outside connection: travellers from beyond the map's edge ride from here, paying $ 5 more a trip."),
            (.traditionalChinese, "800 公尺內：居民 1,200 · 工作 300\n外地連絡站：每趟多收 $ 5", "外地連絡站：地圖外的旅客由這裡進出，每趟多付 $ 5。"),
        ] {
            let session = try makeSession(language: language, outsideConnections: true)
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 512)
            let site = try XCTUnwrap(session.platformSitePlanPoint)
            XCTAssertEqual(session.platformSiteCaption(try XCTUnwrap(session.platformSiteCatchment), at: site), caption)
            session.addNetworkPlatform()
            let text = try XCTUnwrap(session.message?.text)
            XCTAssertTrue(text.hasSuffix(ending), text)
        }

        // Without the outside connections the caption is the catchment alone.
        let session = try makeSession()
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 512)
        let site = try XCTUnwrap(session.platformSitePlanPoint)
        XCTAssertEqual(session.platformSiteCaption(try XCTUnwrap(session.platformSiteCatchment), at: site), "Within 800 m: 1,200 residents · 300 jobs")
    }
}
