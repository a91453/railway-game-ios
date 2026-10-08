import GameCore
@testable import GamePresentation
import XCTest

/// Station names on a zoomed-out map (decision 89): MapBuilder's line
/// levels by station spacing, each named above its zoom.
final class StationLabelsTests: XCTestCase {
    private let kilometre = 1_000 * WorldCoordinate.unitsPerMetre

    func testALinesLevelIsTheFirstWhoseSpacingItIsBelow() {
        XCTAssertEqual(MapLineLevel.level(averageSpacing: 0.8), .local)
        XCTAssertEqual(MapLineLevel.level(averageSpacing: 1.999), .local)
        XCTAssertEqual(MapLineLevel.level(averageSpacing: 2), .regional, "below the threshold, not at it")
        XCTAssertEqual(MapLineLevel.level(averageSpacing: 9.9), .regional)
        XCTAssertEqual(MapLineLevel.level(averageSpacing: 29), .long)
        XCTAssertEqual(MapLineLevel.level(averageSpacing: 50), .extraLong)
        XCTAssertEqual(MapLineLevel.allCases.map(\.zoomThreshold), [9.5, 7, 3.5, 1.1])
    }

    /// The zoom is MapLibre's: at zoom 0 the Earth's equator is 512 points
    /// wide.
    func testTheZoomIsMapLibres() {
        let earth = 2 * Double.pi * 6_378_137.0
        let zero = 512 / earth / Double(WorldCoordinate.unitsPerMetre)
        XCTAssertEqual(StationLabels.zoom(pointsPerUnit: zero), 0, accuracy: 1e-9)
        XCTAssertEqual(StationLabels.zoom(pointsPerUnit: zero * 1_024), 10, accuracy: 1e-9)
        XCTAssertEqual(StationLabels.zoom(pointsPerUnit: zero, latitude: 60), -1, accuracy: 1e-9, "half as many metres round the Earth at 60°")
        // The whole of Taiwan, 286 km across a 390-point phone: about 6.6,
        // so the long lines' stations are named and the regional ones not.
        let taiwan = 390 / Double(WholeTaiwan.bounds.width)
        XCTAssertEqual(StationLabels.zoom(pointsPerUnit: taiwan, latitude: WholeTaiwan.anchor.latitudeDegrees), 6.6, accuracy: 0.1)
    }

    /// A station takes its widest line's level; the higher levels come
    /// first, then the stations more lines stop at, then lower IDs.
    func testStationsAreNamedByTheirWidestLine() throws {
        var world = GameWorld(bounds: .maximum, economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 1, station: 1, train: 1)))
        func station(_ name: String, km x: Int64) throws -> StationID {
            try world.buildStation(named: name, at: PlanPoint(x: 1_000_000 + x * kilometre, y: 1_000_000)).id
        }
        let a = try station("A", km: 0), b = try station("B", km: 1), c = try station("C", km: 2)
        let far = try station("Far", km: 32), lone = try station("Lone", km: 100)
        _ = try world.createLine(named: "Metro", stops: [a, b, c])
        _ = try world.createLine(named: "Express", stops: [c, far])
        let labels = StationLabels(world: world)
        XCTAssertEqual(labels.ranked.map(\.station), [c, far, a, b, lone])
        XCTAssertEqual(labels.ranked.map(\.level), [.long, .long, .local, .local, .local])
        XCTAssertEqual(labels.ranked.map(\.lines), [2, 1, 1, 1, 0])
        XCTAssertEqual(labels.named(atZoom: 3).map(\.station), [])
        XCTAssertEqual(labels.named(atZoom: 6.6).map(\.station), [c, far])
        XCTAssertEqual(labels.named(atZoom: 9.6).map(\.station), [c, far, a, b, lone])
    }

    /// A ring's last stop counts its way back to the first.
    func testARingCountsItsWayBackToItsFirstStop() throws {
        var world = GameWorld(bounds: .maximum, economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 1, station: 1, train: 1)))
        let corners = [(0, 0), (1, 0), (1, 1)].map { PlanPoint(x: 1_000_000 + Int64($0.0) * 3 * kilometre, y: 1_000_000 + Int64($0.1) * 3 * kilometre) }
        let ids = try corners.enumerated().map { try world.buildStation(named: "S\($0.offset)", at: $0.element).id }
        let line = try world.createLine(named: "Ring", stops: ids)
        // 3, 3 km open: regional; closed, 3, 3 and 4.24 km: still regional.
        XCTAssertEqual(StationLabels.level(of: try XCTUnwrap(world.line(id: line.id)), points: Dictionary(uniqueKeysWithValues: world.stations.map { ($0.id, $0.location) })), .regional)
        try world.setLineRing(line.id, to: true)
        XCTAssertEqual(StationLabels(world: world).ranked.map(\.level), [.regional, .regional, .regional])
    }
}
