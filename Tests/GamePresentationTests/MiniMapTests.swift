import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 116: the whole map, small, with the track, the
/// lines through their stops and the stations, a frame round what the map
/// view shows, and a tap that goes there.
final class MiniMapTests: XCTestCase {
    private static let alpha = StationID(rawValue: 1)
    private static let beta = StationID(rawValue: 2)

    func testAnEmptyWorldIsJustItsGround() throws {
        let world = try makeWorld(width: 8_192, height: 4_096)
        let map = MiniMap(world: world)
        XCTAssertEqual(map.region, WorldRegion(minX: 0, minY: 0, maxX: 8_192, maxY: 4_096))
        XCTAssertEqual(map.track, [])
        XCTAssertEqual(map.lines, [])
        XCTAssertEqual(map.stations, [])
    }

    func testTheTrackTheStationsAndALineThroughItsStops() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 100_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        try world.createLine(named: "Main", stops: [Self.beta, Self.alpha])
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 512, y: 1_536))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 1_536, y: 1_536))
        _ = try world.buildTrackEdge(from: west, to: east)
        let map = MiniMap(world: world)
        XCTAssertEqual(map.track, [MiniMap.Segment(from: .init(x: 512, y: 1_536), to: .init(x: 1_536, y: 1_536))])
        let points = [Self.alpha, Self.beta].map { id -> MiniMap.WorldPoint in
            let location = world.station(id: id)!.location
            return MiniMap.WorldPoint(x: Double(location.x), y: Double(location.y))
        }
        XCTAssertEqual(map.stations, points)
        XCTAssertEqual(map.lines, [MiniMap.Line(id: LineID(rawValue: 1), color: nil, stops: [points[1], points[0]])])
    }

    func testARingGoesBackToItsFirstStop() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 100_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        let line = try world.createLine(named: "Loop", stops: [Self.alpha, Self.beta, StationID(rawValue: 3)])
        try world.setLineRing(line.id, to: true)
        let stops = try XCTUnwrap(MiniMap(world: world).lines.first?.stops)
        XCTAssertEqual(stops.count, 4)
        XCTAssertEqual(stops.first, stops.last)
    }

    func testTheSizeKeepsTheMapsShapeAndATappableWidth() {
        let wide = WorldRegion(minX: 0, minY: 0, maxX: 2_000, maxY: 1_000)
        XCTAssertEqual(MiniMap.size(of: wide, longestSide: 120), ScreenSize(width: 120, height: 60))
        let tall = WorldRegion(minX: 0, minY: 0, maxX: 1_000, maxY: 2_000)
        XCTAssertEqual(MiniMap.size(of: tall, longestSide: 120), ScreenSize(width: 60, height: 120))
        // Taiwan-like: ten times as tall as wide.
        let thin = WorldRegion(minX: 0, minY: 0, maxX: 100, maxY: 1_000)
        XCTAssertEqual(MiniMap.size(of: thin, longestSide: 120), ScreenSize(width: MiniMap.shortestSide, height: 120))
    }

    func testTheProjectionFitsTheMapAndATapGoesBack() {
        // A 2:1 map in a square: half a side of margin above and below.
        let region = WorldRegion(minX: 1_000, minY: 0, maxX: 5_000, maxY: 2_000)
        let projection = MiniMapProjection(region: region, size: ScreenSize(width: 100, height: 100))
        XCTAssertEqual(projection.scale, 0.025)
        XCTAssertEqual(projection.origin, ScreenPoint(x: 0, y: 25))
        XCTAssertEqual(projection.screenPoint(of: .init(x: 3_000, y: 1_000)), ScreenPoint(x: 50, y: 50))
        XCTAssertEqual(projection.worldPoint(at: ScreenPoint(x: 50, y: 50)), .init(x: 3_000, y: 1_000))
        // In the margin: to the map's nearest edge.
        XCTAssertEqual(projection.worldPoint(at: ScreenPoint(x: 10, y: 5)), .init(x: 1_400, y: 0))
    }

    func testTheFrameIsCutToTheMap() throws {
        let region = WorldRegion(minX: 0, minY: 0, maxX: 4_000, maxY: 4_000)
        let projection = MiniMapProjection(region: region, size: ScreenSize(width: 100, height: 100))
        let inside = try XCTUnwrap(projection.frame(of: WorldRegion(minX: 1_000, minY: 1_000, maxX: 2_000, maxY: 3_000)))
        XCTAssertEqual(inside.topLeft, ScreenPoint(x: 25, y: 25))
        XCTAssertEqual(inside.bottomRight, ScreenPoint(x: 50, y: 75))
        let overhanging = try XCTUnwrap(projection.frame(of: WorldRegion(minX: -1_000, minY: 3_000, maxX: 1_000, maxY: 6_000)))
        XCTAssertEqual(overhanging.topLeft, ScreenPoint(x: 0, y: 75))
        XCTAssertEqual(overhanging.bottomRight, ScreenPoint(x: 25, y: 100))
        XCTAssertNil(projection.frame(of: WorldRegion(minX: 5_000, minY: 0, maxX: 6_000, maxY: 1_000)))
    }
}
