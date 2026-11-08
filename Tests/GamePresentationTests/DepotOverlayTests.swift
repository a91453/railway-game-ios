import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 630: a depot is where trains rest, not a station. Its platforms
/// show no "Packed", the map draws no 800 m ring around it, the coverage
/// layer counts no one it reaches, and the ring switch turned off leaves no
/// ring at all.
@MainActor
final class DepotOverlayTests: XCTestCase {
    /// West (a depot) and East (a station) on one track, a train standing
    /// at West's platform.
    private func world() throws -> (world: GameWorld, depot: StationID, station: StationID, train: TrainID) {
        var world = GameWorld(
            bounds: try WorldBounds(width: 65_536, height: 16_384), economy: GameEconomy(balance: 10_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .paused)
        )
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_704)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 12_288, y: 8_704)).id
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 5_120)
        try world.addTrackPlatform(east, on: edge, from: 9_216, to: 13_312)
        let first = try world.splitTrackEdge(edge, at: 5_120)
        let into = try XCTUnwrap(world.network.edges.first { $0.to == first }).id
        let train = try world.purchaseTrain(named: "T1").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: into, direction: .forward), offset: 5_120))
        try world.setStationDepot(west, to: true)
        return (world, west, east, train)
    }

    func testADepotsPlatformsShowNoBusynessWhileAStationsDo() throws {
        var (world, depot, _, _) = try world()
        var use = PlatformUse()
        for _ in 0..<30 {
            try world.advance(ticks: 1)
            use.record(world)
        }
        let page = StationOperations(world: world, station: depot, use: use)
        XCTAssertFalse(page.platforms.isEmpty)
        for row in page.platforms {
            XCTAssertNil(row.busyPercent)
            XCTAssertNil(row.busyness)
            XCTAssertNil(row.busyText(in: .traditionalChinese))
        }
    }

    func testTheRingsGoToStationsOnlyAndNoneWhenOff() throws {
        let (world, depot, station, _) = try world()
        let on = MapLayers.catchmentStations(in: world, layers: MapLayerPreferences())
        XCTAssertEqual(on.map(\.id), [station])
        XCTAssertFalse(on.contains { $0.id == depot })
        XCTAssertTrue(MapLayers.catchmentStations(in: world, layers: MapLayerPreferences(showsCatchmentRings: false)).isEmpty)
    }

    func testADepotCoversNoLand() throws {
        let (world, depot, _, _) = try world()
        // The depot alone reaches no cell; the station beside it does.
        let rows = Land.rows(in: world.bounds), columns = Land.columns(in: world.bounds)
        let covered = CityMap.coveredCells(of: world, rows: rows, columns: columns)
        let point = try XCTUnwrap(world.station(id: depot)).location
        let length = Land.cellLength
        let cell = CellPosition(row: Int(point.y / length), column: Int(point.x / length))
        XCTAssertFalse(covered.contains(cell) && Self.distance(cell, to: world, from: depot))
    }

    private static func distance(_ cell: CellPosition, to world: GameWorld, from depot: StationID) -> Bool {
        // The cell is covered only by a non-depot station within reach.
        let length = Land.cellLength, radius = Land.catchmentRadius
        let middleX = Int64(cell.column) * length + length / 2, middleY = Int64(cell.row) * length + length / 2
        return !world.stations.contains { station in
            let dx = middleX - station.location.x, dy = middleY - station.location.y
            return !station.isDepot && dx * dx + dy * dy < radius * radius
        }
    }

    func testTurningTheRingsOffPutsTheCoverageShortcutAway() {
        var shortcut = BuildingLayerShortcut()
        shortcut.choose(.coverage)
        shortcut.buildingBegan(autoShows: true)
        XCTAssertEqual(shortcut.layer(over: nil), .coverage)
        shortcut.catchmentRingsSwitched(on: true)
        XCTAssertEqual(shortcut.layer(over: nil), .coverage)
        shortcut.catchmentRingsSwitched(on: false)
        XCTAssertNil(shortcut.layer(over: nil))
        // Where people are is not the rings' business.
        var people = BuildingLayerShortcut()
        people.buildingBegan(autoShows: true)
        people.catchmentRingsSwitched(on: false)
        XCTAssertEqual(people.layer(over: nil), .potential)
    }
}
