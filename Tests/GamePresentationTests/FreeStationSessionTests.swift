import GameCore
import GamePresentation
import XCTest

/// Stage F1: stations at a point in the app. A tap picks the nearest
/// station within reach, or the station on the tile under it; the platform
/// tool builds a station at the middle of its first platform; and the train
/// tool and the line draft use the selected station, not the tile.
final class FreeStationSessionTests: XCTestCase {
    func testATapSelectsTheNearestStationWithinReachOrTheOneOnTheTile() async throws {
        try await MainActor.run {
            var world = try makeWorld(width: 16, height: 8, balance: 100_000)
            let tile = try world.buildStation(named: "Tile", at: GridPosition(x: 0, y: 0)).id
            let west = try world.buildStation(named: "West", at: PlanPoint(x: 4_000, y: 3_000)).id
            let twin = try world.buildStation(named: "Twin", at: PlanPoint(x: 4_500, y: 3_000)).id
            let close = try world.buildStation(named: "Close", at: PlanPoint(x: 900, y: 900)).id
            let session = GameSession(world: world)

            session.addSelectedStationToLineDraft()
            XCTAssertEqual(session.message?.kind, .failure, "nothing selected")
            // 141 from West, 412 from Twin.
            session.tapMap(at: PlanPoint(x: 4_100, y: 3_100), reach: 300)
            XCTAssertEqual(session.selectedStationID, west)
            XCTAssertEqual(session.selection, GridPosition(x: 4, y: 3), "the tile under the tap")
            XCTAssertNil(session.message)
            // 300 from West, 200 from Twin.
            session.tapMap(at: PlanPoint(x: 4_300, y: 3_000), reach: 300)
            XCTAssertEqual(session.selectedStationID, twin)
            // 707 from West, out of reach, but West stands in the tile (3, 2).
            session.tapMap(at: PlanPoint(x: 3_500, y: 2_500), reach: 300)
            XCTAssertEqual(session.selectedStationID, west)
            XCTAssertEqual(session.selection, GridPosition(x: 3, y: 2))
            // A station on tiles takes its tile, even with Close nearer.
            session.tapMap(at: PlanPoint(x: 1_000, y: 1_000), reach: 300)
            XCTAssertEqual(session.selectedStationID, tile)
            // Beside it, the nearer: 361 from Close, 595 from Tile's centre.
            session.tapMap(at: PlanPoint(x: 1_100, y: 600), reach: 640)
            XCTAssertEqual(session.selectedStationID, close)
            session.tapMap(at: PlanPoint(x: 1_100, y: 300), reach: 640)
            XCTAssertEqual(session.selectedStationID, tile, "625 from Tile's centre, 632 from Close")
            // Empty land selects no station.
            session.tapMap(at: PlanPoint(x: 10_000, y: 6_000), reach: 300)
            XCTAssertNil(session.selectedStationID)
            XCTAssertNil(session.selectedStation)
            XCTAssertEqual(session.selection, GridPosition(x: 9, y: 5))
            // Off the map: ignored.
            session.tapMap(at: PlanPoint(x: -1, y: 0), reach: 300)
            session.tapMap(at: PlanPoint(x: 16_384, y: 0), reach: 300)
            XCTAssertEqual(session.selection, GridPosition(x: 9, y: 5))
        }
    }

    func testAStationIsSelectedByNameOrByTheTileItStandsIn() async throws {
        try await MainActor.run {
            var world = try makeWorld(width: 16, height: 8, balance: 100_000)
            let tile = try world.buildStation(named: "Tile", at: GridPosition(x: 0, y: 0)).id
            let west = try world.buildStation(named: "West", at: PlanPoint(x: 4_000, y: 3_000)).id
            let twin = try world.buildStation(named: "Twin", at: PlanPoint(x: 3_500, y: 2_500)).id
            let session = GameSession(world: world)

            session.selectStation(twin)
            XCTAssertEqual(session.selectedStation?.name, "Twin")
            XCTAssertEqual(session.selection, GridPosition(x: 3, y: 2), "the tile under its point")
            session.selectStation(StationID(rawValue: 99))
            XCTAssertEqual(session.selectedStationID, twin, "an unknown station is ignored")
            // The tile (3, 2) holds West and Twin: the lower ID.
            session.select(GridPosition(x: 3, y: 2))
            XCTAssertEqual(session.selectedStationID, west)
            session.select(GridPosition(x: 0, y: 0))
            XCTAssertEqual(session.selectedStationID, tile)
            session.moveSelection(.east)
            XCTAssertNil(session.selectedStationID)
            session.clearSelection()
            XCTAssertNil(session.selection)
            XCTAssertNil(session.selectedStationID)
        }
    }

    /// The first platform builds a station at its middle, taking no tile;
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
            XCTAssertEqual(station.tiles, [])
            XCTAssertEqual(session.world.map.tile(at: GridPosition(x: 3, y: 3))?.type, .empty)
            XCTAssertEqual(session.message?.text, "Built station “Station 1” with a 64 m platform on edge #1.")

            // 512 south, within two tiles.
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
            XCTAssertEqual(session.message?.text, "Sent Train 1 to East, 5120 units along the track. Set a rate to start.")
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
    var world = try makeWorld(width: 16, height: 8, balance: 1_000_000)
    let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 3_072))
    let east = try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 3_072))
    try world.buildTrackEdge(from: west, to: east)
    return world
}
