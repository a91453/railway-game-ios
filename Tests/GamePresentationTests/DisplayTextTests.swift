import GameCore
import GamePresentation
import XCTest

final class DisplayTextTests: XCTestCase {
    func testTrackShapeNames() {
        XCTAssertEqual(TrackConnections().shapeName, "No connections")
        XCTAssertEqual(TrackConnections.south.shapeName, "Dead end")
        XCTAssertEqual(TrackConnections([.north, .south]).shapeName, "Straight")
        XCTAssertEqual(TrackConnections([.east, .west]).shapeName, "Straight")
        XCTAssertEqual(TrackConnections([.north, .east]).shapeName, "Curve")
        XCTAssertEqual(TrackConnections([.south, .west]).shapeName, "Curve")
        XCTAssertEqual(TrackConnections([.north, .east, .west]).shapeName, "T-junction")
        XCTAssertEqual(TrackConnections([.north, .east, .south, .west]).shapeName, "Crossing")
    }

    func testTrackSummaryListsDirectionsInCompassOrder() {
        XCTAssertEqual(TrackConnections([.west, .north]).summary, "Curve N–W")
        XCTAssertEqual(TrackConnections([.south, .north]).summary, "Straight N–S")
        XCTAssertEqual(TrackConnections().summary, "No connections")
    }

    func testTileSummaries() throws {
        var world = try makeWorld()
        try world.buildTrack(at: GridPosition(x: 1, y: 0), connections: [.east, .west])
        try world.buildStation(named: "Central", at: GridPosition(x: 2, y: 0))

        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 0, y: 0)), "Empty")
        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 1, y: 0)), "Track · Straight E–W")
        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 2, y: 0)), "Station · Central")
        XCTAssertEqual(world.tileSummary(at: GridPosition(x: 99, y: 0)), "Outside the map")
    }
}
