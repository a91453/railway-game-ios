import GameCore
import GamePresentation
import XCTest

/// Stage F1: stations at a point in the app. A tap picks the nearest
/// station within reach, by distance alone (Stage F3d: no tile under the
/// tap decides); the platform tool builds a station at the middle of its
/// first platform; and the train tool and the line draft use the selected
/// station.
final class FreeStationSessionTests: XCTestCase {
    func testATapSelectsTheNearestStationWithinReachByDistanceAlone() async throws {
        try await MainActor.run {
            var world = try makeWorld(width: 16_384, height: 8_192, balance: 100_000)
            let corner = try world.buildStation(named: "Corner", at: PlanPoint(x: 512, y: 512)).id
            let west = try world.buildStation(named: "West", at: PlanPoint(x: 4_000, y: 3_000)).id
            let twin = try world.buildStation(named: "Twin", at: PlanPoint(x: 4_500, y: 3_000)).id
            let close = try world.buildStation(named: "Close", at: PlanPoint(x: 900, y: 900)).id
            let session = GameSession(world: world)

            session.addSelectedStationToLineDraft()
            XCTAssertEqual(session.message?.kind, .failure, "nothing selected")
            // 141 from West, 412 from Twin.
            session.tapMap(at: PlanPoint(x: 4_100, y: 3_100), reach: 300)
            XCTAssertEqual(session.selectedStationID, west)
            XCTAssertEqual(session.selectedPoint, PlanPoint(x: 4_100, y: 3_100), "the tap's own point")
            XCTAssertNil(session.message)
            // 300 from West, 200 from Twin.
            session.tapMap(at: PlanPoint(x: 4_300, y: 3_000), reach: 300)
            XCTAssertEqual(session.selectedStationID, twin)
            // 707 from West: out of reach, though the grid once put both in
            // the tile (3, 2) and picked West.
            session.tapMap(at: PlanPoint(x: 3_500, y: 2_500), reach: 300)
            XCTAssertNil(session.selectedStationID)
            XCTAssertEqual(session.selectedPoint, PlanPoint(x: 3_500, y: 2_500))
            // Within half the reach: 141 from Close, 690 from Corner.
            session.tapMap(at: PlanPoint(x: 1_000, y: 1_000), reach: 300)
            XCTAssertEqual(session.selectedStationID, close)
            // The nearer: 361 from Close, 595 from Corner.
            session.tapMap(at: PlanPoint(x: 1_100, y: 600), reach: 640)
            XCTAssertEqual(session.selectedStationID, close)
            session.tapMap(at: PlanPoint(x: 1_100, y: 300), reach: 640)
            XCTAssertEqual(session.selectedStationID, corner, "625 from Corner, 632 from Close")
            // Empty land selects no station.
            session.tapMap(at: PlanPoint(x: 10_000, y: 6_000), reach: 300)
            XCTAssertNil(session.selectedStationID)
            XCTAssertNil(session.selectedStation)
            XCTAssertEqual(session.selectedPoint, PlanPoint(x: 10_000, y: 6_000))
            // Off the map: ignored.
            session.tapMap(at: PlanPoint(x: -1, y: 0), reach: 300)
            session.tapMap(at: PlanPoint(x: 16_384, y: 0), reach: 300)
            XCTAssertEqual(session.selectedPoint, PlanPoint(x: 10_000, y: 6_000))
        }
    }

    func testAStationIsSelectedByIDOrByATapAtItsPoint() async throws {
        try await MainActor.run {
            var world = try makeWorld(width: 16_384, height: 8_192, balance: 100_000)
            let corner = try world.buildStation(named: "Corner", at: PlanPoint(x: 512, y: 512)).id
            let west = try world.buildStation(named: "West", at: PlanPoint(x: 4_000, y: 3_000)).id
            let twin = try world.buildStation(named: "Twin", at: PlanPoint(x: 3_500, y: 2_500)).id
            let session = GameSession(world: world)

            session.selectStation(twin)
            XCTAssertEqual(session.selectedStation?.name, "Twin")
            XCTAssertEqual(session.selectedPoint, PlanPoint(x: 3_500, y: 2_500), "the station's own point")
            session.selectStation(StationID(rawValue: 99))
            XCTAssertEqual(session.selectedStationID, twin, "an unknown station is ignored")
            // As far from West as from Twin: the lower ID.
            session.tapMap(at: PlanPoint(x: 3_750, y: 2_750), reach: 1_000)
            XCTAssertEqual(session.selectedStationID, west)
            session.tapMap(at: PlanPoint(x: 512, y: 512), reach: 0)
            XCTAssertEqual(session.selectedStationID, corner, "a tap right on a station's point, with no reach")
            session.tapMap(at: PlanPoint(x: 513, y: 512), reach: 0)
            XCTAssertNil(session.selectedStationID, "one unit away, with no reach")
            session.clearSelection()
            XCTAssertNil(session.selectedPoint)
            XCTAssertNil(session.selectedStationID)
        }
    }

    /// The first platform builds a station at its middle;
    /// a platform on a parallel track beside it joins the same station, and
    /// the station's platforms tell its size.
    func testThePlatformToolBuildsAStationAtAPoint() async throws {
        var world = try makeLineWorld()
        let south = (
            try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 3_584)),
            try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 3_584))
        )
        try world.buildTrackEdge(from: south.0, to: south.1)
        try await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            session.tapNetwork(at: PlanPoint(x: 4_024, y: 3_000), reach: 256)
            session.addNetworkPlatform()
            let station = try XCTUnwrap(session.world.station(id: StationID(rawValue: 1)))
            XCTAssertEqual(station.point, PlanPoint(x: 4_024, y: 3_072))
            XCTAssertEqual(session.message?.text, "Built station “Station 1” with a 64 m platform on edge #1.")

            // 512 south, within 2048 (32 m).
            session.tapNetwork(at: PlanPoint(x: 4_024, y: 3_600), reach: 256)
            XCTAssertEqual(session.networkEdgePoint?.edge, .edge(2))
            XCTAssertEqual(session.platformStationID, station.id)
            session.addNetworkPlatform()
            XCTAssertEqual(session.message?.text, "Added a 64 m platform to Station 1 on edge #2.")
            XCTAssertEqual(session.world.trackPlatforms(of: station.id).count, 2)
            XCTAssertEqual(session.world.stations.count, 1)

            XCTAssertEqual(session.world.stationSummary(station.id, in: .english), "Station · Station 1 · 2 platforms, 128 m")
            XCTAssertEqual(session.world.stationSummary(station.id, in: .traditionalChinese), "車站 · Station 1 · 2 座月台，共 128 公尺")
            XCTAssertEqual(station.placeText(in: .english), "x 63 m, y 48 m")
            XCTAssertEqual(station.placeText(in: .traditionalChinese), "x 63 公尺, y 48 公尺")

            session.selectTool(.select)
            XCTAssertNil(session.selectionText())
            session.tapMap(at: PlanPoint(x: 4_000, y: 3_100), reach: 256)
            XCTAssertEqual(session.selectionText(), "Station · Station 1 · 2 platforms, 128 m")
        }
    }

    /// Decision 46: a managed company's city gives a new station its
    /// ridership; in free play the player sets it.
    func testAManagedCompanysNewStationHasTheCitysRidership() async throws {
        var world = try makeLineWorld()
        world.setEconomyMode(.management)
        try await MainActor.run { [world] in
            for managed in [true, false] {
                let session = GameSession(world: world)
                if !managed { session.setEconomyMode(.free) }
                session.selectTool(.network)
                session.setNetworkMode(.platform)
                session.tapNetwork(at: PlanPoint(x: 4_024, y: 3_000), reach: 256)
                session.addNetworkPlatform()
                let station = try XCTUnwrap(session.world.stations.first)
                XCTAssertEqual(session.world.stationDemand(of: station.id), managed ? .cityDefault : nil)
            }
        }
    }

    func testTheTrainToolAndTheLineDraftUseTheSelectedStation() async throws {
        var world = try makeLineWorld()
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 2_048, y: 3_072)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 7_168, y: 3_072)).id
        let bare = try world.buildStation(named: "Bare", at: PlanPoint(x: 5_000, y: 5_000)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 1_024, to: 3_072)
        try world.addTrackPlatform(east, on: .edge(1), from: 6_144, to: 8_192)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectTool(.train)
            session.purchaseTrain()
            XCTAssertEqual(session.message?.text, "Bought Train 1. Select a station to place it.")
            let train = session.selectedTrainID!

            session.selectStation(bare)
            session.applyTool()
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Bare has no platform yet. Add one with the network tool."))
            XCTAssertNil(session.world.train(id: train)?.position)

            session.selectStation(west)
            session.applyTool()
            XCTAssertEqual(session.message?.text, "Placed Train 1 at West, on edge #1 going forward.")
            XCTAssertEqual(session.world.train(id: train)?.position, .onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 3_072))

            session.selectStation(east)
            session.applyTool()
            XCTAssertEqual(session.message?.text, "Sent Train 1 to East, 5120 units along the track.")
            XCTAssertNil(session.world.train(id: train)?.movement.end, "the far end of East's platform is the end of the edge")

            session.selectStation(west)
            session.addSelectedStationToLineDraft()
            session.selectStation(east)
            session.addSelectedStationToLineDraft()
            XCTAssertEqual(session.lineDraft, [west, east])
            session.createLineFromDraft()
            XCTAssertEqual(session.selectedLine?.stops, [west, east])
        }
    }

    func testTheAppOffersOnlyTheNetworkTools() {
        XCTAssertEqual(ConstructionTool.networkTools, [.select, .network, .train])
    }
}

/// One straight edge, 8192 long, along y = 3072.
private func makeLineWorld() throws -> GameWorld {
    var world = try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000)
    let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 3_072))
    let east = try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 3_072))
    try world.buildTrackEdge(from: west, to: east)
    return world
}
