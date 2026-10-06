import Foundation
import GameCore
import GamePresentation
import XCTest

/// The map's population and travel layers, ported from the `Ci/`
/// reference's `panel-poptravel`: their values, the population grid laid
/// out for drawing, the travel demand map and the follow bar's text.
final class PopTravelTests: XCTestCase {
    private static func bundled() throws -> PopulationGrid {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json")))
    }

    private static func fixture() throws -> PopulationGrid {
        try PopulationGrid(data: Data(#"{"north":1,"west":0,"cellDegrees":0.5,"runs":[{"r":0,"c":0,"p":[100,200]},{"r":1,"c":0,"p":[300,400]}]}"#.utf8))
    }

    private static func taipeiFrame() throws -> RealWorldFrame {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.047_882, longitudeDegrees: 121.517_219))
        return RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
    }

    // MARK: - The reference's values

    func testOpacityStartsAsTheReferenceAndStaysInItsRange() {
        XCTAssertEqual(PopTravel.baseOpacity(for: .population, compactWidth: false), 0.72)
        XCTAssertEqual(PopTravel.baseOpacity(for: .population, compactWidth: true), 0.72)
        XCTAssertEqual(PopTravel.baseOpacity(for: .travel, compactWidth: false), 0.85)
        XCTAssertEqual(PopTravel.baseOpacity(for: .movement, compactWidth: true), 1)
        XCTAssertEqual(PopTravel.clampedOpacity(0.05), 0.1)
        XCTAssertEqual(PopTravel.clampedOpacity(3), 1)
        XCTAssertEqual(PopTravel.clampedOpacity(0.5), 0.5)
        XCTAssertNil(PopTravel.clampedOpacity(.nan))
    }

    func testTheTimelineRunsFromZeroToTwentyThreeAndWraps() {
        XCTAssertEqual(PopTravel.defaultHour, 8)
        XCTAssertEqual(PopTravel.hourLabel(8), "08:00")
        XCTAssertEqual(PopTravel.hourLabel(23), "23:00")
        XCTAssertEqual(PopTravel.hourLabel(40), "23:00")
        XCTAssertEqual(PopTravel.nextHour(after: 22), 23)
        XCTAssertEqual(PopTravel.nextHour(after: 23), 0, "play starts the day again")
        XCTAssertEqual(PopTravel.playInterval, .milliseconds(1_200))
    }

    func testThePopulationGradientIsTheReferencesOneKilometreLegend() {
        XCTAssertEqual(PopTravel.populationColor(position: 0), PopTravel.RGB(hex: "#F7FBFF"))
        XCTAssertEqual(PopTravel.populationColor(position: 0.52), PopTravel.RGB(hex: "#4292C6"))
        XCTAssertEqual(PopTravel.populationColor(position: 1), PopTravel.RGB(hex: "#041F4A"))
        XCTAssertEqual(PopTravel.populationColor(position: 0.05), PopTravel.RGB(red: 0xEB, green: 0xF3, blue: 0xFB), "halfway between two stops")
        XCTAssertEqual(PopTravel.populationBand(people: 0), 0)
        XCTAssertEqual(PopTravel.populationBand(people: 249), 0)
        XCTAssertEqual(PopTravel.populationBand(people: 250), 1)
        XCTAssertEqual(PopTravel.populationBand(people: 9_999), 39)
        XCTAssertEqual(PopTravel.populationBand(people: 50_000), 39, "10000+ takes the last colour")
    }

    func testGradesAreOneToTenOfTheLargest() {
        XCTAssertEqual(PopTravel.grade(0, maximum: 100), 0)
        XCTAssertEqual(PopTravel.grade(1, maximum: 100), 1)
        XCTAssertEqual(PopTravel.grade(10, maximum: 100), 1)
        XCTAssertEqual(PopTravel.grade(11, maximum: 100), 2)
        XCTAssertEqual(PopTravel.grade(100, maximum: 100), 10)
        XCTAssertEqual(PopTravel.grade(5, maximum: 0), 0)
        XCTAssertEqual(PopTravel.travelColors.count, 10)
        XCTAssertEqual(PopTravel.travelColors.first, PopTravel.RGB(hex: "#000088"))
        XCTAssertEqual(PopTravel.travelColors.last, PopTravel.RGB(hex: "#FF1100"))
        XCTAssertEqual(PopTravel.decreaseColors.last, PopTravel.RGB(hex: "#002668"))
        XCTAssertEqual(PopTravel.increaseColors.last, PopTravel.RGB(hex: "#9E1010"))
    }

    func testOnlyOneLayerShowsAtATime() {
        var layers = MapLayerPreferences()
        XCTAssertNil(layers.popTravelMode)
        layers.showsPopulationHeatmap = true
        XCTAssertEqual(layers.popTravelMode, .population)
        layers.setShows(.travel, true)
        XCTAssertEqual(layers.popTravelMode, .travel)
        XCTAssertFalse(layers.showsPopulationHeatmap)
        layers.showsPopulationHeatmap = false
        XCTAssertEqual(layers.popTravelMode, .travel, "turning off a layer not shown changes nothing")
        layers.setShows(.travel, false)
        XCTAssertNil(layers.popTravelMode)
    }

    // MARK: - The population grid on the map

    func testTilesAreTheGridsCellsInView() throws {
        let grid = try Self.bundled()
        let frame = try Self.taipeiFrame()
        let heatmap = PopulationHeatmap(grid: grid, frame: frame)
        let northWest = frame.worldPosition(latitude: 25.10, longitude: 121.45)
        let southEast = frame.worldPosition(latitude: 25.00, longitude: 121.55)
        let region = WorldRegion(minX: northWest.x, minY: northWest.y, maxX: southEast.x, maxY: southEast.y)
        let tiles = heatmap.tiles(in: region)
        let cells = grid.cells(north: 25.10, south: 25.00, west: 121.45, east: 121.55)
        XCTAssertFalse(tiles.isEmpty)
        // One cell more on each side than the old query, never fewer.
        XCTAssertGreaterThanOrEqual(tiles.count, cells.count)
        XCTAssertTrue(tiles.allSatisfy { $0.cells == 1 && $0.people > 0 && $0.minX < $0.maxX && $0.minY < $0.maxY })
        let inside = tiles.filter { $0.maxX > region.minX && $0.minX < region.maxX && $0.maxY > region.minY && $0.minY < region.maxY }
        XCTAssertEqual(inside.map(\.people).reduce(0, +), cells.map(\.count).reduce(0, +), "the same people as the cells in view")
        XCTAssertEqual(heatmap.tiles(in: region), tiles, "the same tiles every time")
    }

    func testBlocksMergeCellsWhenZoomedOut() throws {
        let grid = try Self.bundled()
        let frame = try Self.taipeiFrame()
        let heatmap = PopulationHeatmap(grid: grid, frame: frame)
        // A cell is about 1 km (64,000 units): at 1 point a kilometre a
        // block of 8 is the first at least 6 points wide.
        XCTAssertEqual(heatmap.blockSize(pointsPerUnit: 1.0 / 64_000), 8)
        XCTAssertEqual(heatmap.blockSize(pointsPerUnit: 1.0 / 640), 1)
        let northWest = frame.worldPosition(latitude: 25.30, longitude: 121.30)
        let southEast = frame.worldPosition(latitude: 24.80, longitude: 121.80)
        let region = WorldRegion(minX: northWest.x, minY: northWest.y, maxX: southEast.x, maxY: southEast.y)
        let cells = heatmap.tiles(in: region, blockSize: 1)
        let blocks = heatmap.tiles(in: region, blockSize: 4)
        XCTAssertLessThan(blocks.count, cells.count)
        XCTAssertEqual(blocks.map(\.people).reduce(0, +), cells.map(\.people).reduce(0, +), "merging keeps everyone")
        XCTAssertTrue(blocks.allSatisfy { $0.cells == 16 })
        let whole = WorldRegion(minX: -1e12, minY: -1e12, maxX: 1e12, maxY: 1e12)
        XCTAssertEqual(heatmap.tiles(in: whole, blockSize: 1).map(\.people).reduce(0, +), grid.total, "all of Taiwan")
    }

    func testATappedCellShowsItsPeopleAndDensity() throws {
        let grid = try Self.bundled()
        let frame = try Self.taipeiFrame()
        let heatmap = PopulationHeatmap(grid: grid, frame: frame)
        let info = try XCTUnwrap(heatmap.cellInfo(atX: frame.middleX, y: frame.middleY))
        XCTAssertGreaterThan(info.people, 0)
        XCTAssertEqual(info.squareKilometres, 0.77, accuracy: 0.02, "a cell of 30″ is about 0.92 km by 0.84 km at Taipei")
        XCTAssertEqual(info.density, Double(info.people) / info.squareKilometres)
        let lines = info.lines(in: .english)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasPrefix("Estimated people: "))
        XCTAssertTrue(lines[1].hasPrefix("Population density (people/km²): "))
        XCTAssertTrue(info.lines(in: .traditionalChinese)[0].hasPrefix("估算人口："))
        // Out at sea no one lives.
        let sea = frame.worldPosition(latitude: 24.0, longitude: 123.5)
        XCTAssertNil(heatmap.cellInfo(atX: sea.x, y: sea.y))
    }

    func testTheFixtureGridLaysOutAsUprightRectangles() throws {
        let grid = try Self.fixture()
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 0.5, longitudeDegrees: 0.5))
        let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
        let heatmap = PopulationHeatmap(grid: grid, frame: frame)
        let tiles = heatmap.tiles(in: WorldRegion(minX: -1e12, minY: -1e12, maxX: 1e12, maxY: 1e12))
        XCTAssertEqual(tiles.map(\.people), [100, 200, 300, 400], "north to south, west to east")
        XCTAssertEqual(tiles[0].maxX, tiles[1].minX, accuracy: 1e-6)
        XCTAssertEqual(tiles[0].maxY, tiles[2].minY, accuracy: 1e-6)
        XCTAssertEqual(heatmap.tiles(in: WorldRegion(minX: -1e12, minY: -1e12, maxX: 1e12, maxY: 1e12), blockSize: 2).map(\.people), [1_000])
        XCTAssertTrue(heatmap.tiles(in: WorldRegion(minX: .nan, minY: 0, maxX: 1, maxY: 1)).isEmpty)
    }

    // MARK: - Travel demand

    func testTravelDemandGathersEachStationsTripsByHour() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .paused)
        let line = TestLine(tiles: 7, row: 1)
        try line.build(in: &world)
        let alpha = try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let gamma = try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        try world.setStationDemand(alpha, to: StationDemand(kind: .residential, dailyTrips: 2_400))
        try world.setStationDemand(gamma, to: StationDemand(kind: .office, dailyTrips: 1_200))

        let map = world.travelDemandMap()
        let flowAlpha = try XCTUnwrap(world.stationFlow(of: alpha)).entries
        let flowGamma = try XCTUnwrap(world.stationFlow(of: gamma)).entries
        // Both stations stand in the first 1 km square.
        XCTAssertEqual(map.trips.count, 1)
        let cell = TravelDemandMap.Cell(column: 0, row: 0)
        for hour in 0..<24 {
            XCTAssertEqual(map.trips(in: cell, at: hour), flowAlpha[hour] + flowGamma[hour])
        }
        let hours = (0..<24).map { map.trips(in: cell, at: $0) }
        XCTAssertEqual(map.busiest, hours.max())
        XCTAssertEqual(map.change(in: cell, at: 8), hours[8] - hours[7])
        XCTAssertEqual(map.change(in: cell, at: 0), hours[0] - hours[23], "hour 0 against hour 23")

        let peak = StationFlow.peakHour(of: hours)
        let travel = map.tiles(for: .travel, at: peak)
        XCTAssertEqual(travel.count, 1)
        XCTAssertEqual(travel[0].color, PopTravel.travelColors[9], "the busiest hour takes the top grade")
        XCTAssertEqual(travel[0].maxX - travel[0].minX, Double(TravelDemandMap.cellUnits))
        XCTAssertTrue(map.tiles(for: .population, at: peak).isEmpty)

        let movement = map.tiles(for: .movement, at: peak)
        if let tile = movement.first {
            XCTAssertEqual(tile.value, map.change(in: cell, at: peak))
            XCTAssertTrue((tile.value > 0 ? PopTravel.increaseColors : PopTravel.decreaseColors).contains(tile.color))
        }
        XCTAssertEqual(TravelDemandMap(trips: [:]).tiles(for: .travel, at: 8), [])
        XCTAssertEqual(TravelDemandMap.cell(atX: -1, y: 64_000), TravelDemandMap.Cell(column: -1, row: 1))
    }

    // MARK: - The follow bar

    func testTheFollowBarNamesTheRunsEndsAndTimes() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .normal)
        let line = TestLine(tiles: 7, row: 1)
        try line.build(in: &world)
        let alpha = try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let beta = try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        let gamma = try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let main = try world.createLine(named: "Main", stops: [alpha, beta, gamma]).id
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1")
        XCTAssertEqual(world.followBarInfo(of: train.id, in: .english)?.detail(in: .english), "", "a train with no service has only its name")
        try world.placeTrain(train.id, at: line.at(1, facingEast: true))
        try world.setTrainMovementRate(train.id, to: 1_024)
        try world.assignTrain(train.id, to: main)
        let waiting = try XCTUnwrap(world.followBarInfo(of: train.id, in: .english))
        XCTAssertEqual(waiting.line, main)
        XCTAssertEqual(waiting.status, .notDeparted)
        XCTAssertEqual(waiting.detail(in: .traditionalChinese).hasSuffix("· 尚未發車"), true)

        for _ in 0..<120 where world.train(id: train.id)?.execution == nil {
            try world.advance(ticks: 1)
        }
        for _ in 0..<60 {
            guard case .waitingAtStop(0, _)? = world.train(id: train.id)?.execution else { break }
            try world.advance(ticks: 1)
        }
        let running = try XCTUnwrap(world.followBarInfo(of: train.id, in: .english))
        let timetable = try XCTUnwrap(world.train(id: train.id)?.timetable)
        XCTAssertGreaterThan(timetable.count, 1)
        XCTAssertEqual(running.name, "T1")
        XCTAssertEqual(running.kind, "Main")
        XCTAssertEqual(running.origin, world.station(id: timetable[0].station)?.name)
        XCTAssertEqual(running.terminus, world.station(id: timetable[timetable.count - 1].station)?.name)
        XCTAssertEqual(running.departure, timetable[0].departure.clockText)
        XCTAssertEqual(running.arrival, timetable[timetable.count - 1].arrival.clockText)
        let detail = running.detail(in: .english)
        XCTAssertTrue(detail.hasPrefix("Main　\(running.origin ?? "")→\(running.terminus ?? "")　"), detail)
        XCTAssertNil(world.followBarInfo(of: TrainID(rawValue: 99), in: .english))
    }

    func testFollowStatusTexts() {
        XCTAssertEqual(FollowBarInfo.Status.notDeparted.text(in: .english), "Not departed")
        XCTAssertEqual(FollowBarInfo.Status.arrived.text(in: .traditionalChinese), "已抵達")
        XCTAssertNil(FollowBarInfo.Status.running.text(in: .english))
        let info = FollowBarInfo(name: "T", line: nil, kind: "K", origin: "A", terminus: "B", departure: "08:00", arrival: "08:30", status: .arrived)
        XCTAssertEqual(info.detail(in: .english), "K　A→B　08:00–08:30　· Arrived")
    }
}
