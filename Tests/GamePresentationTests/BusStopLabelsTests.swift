import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 424, C2: a bus stop carries its number and a name, the line a
/// round arrow every so often pointing at the station, the real bus stops
/// near it are drawn and tapped to, and the first line of the tool says the
/// stops, the kilometres and the minutes of the whole route.
@MainActor
final class BusStopLabelsTests: XCTestCase {
    private let frame = RealWorldFrame(anchor: GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!, bounds: .standard)
    private var projection: RealRoadCells.Projection { RealRoadCells.Projection(frame: frame) }
    private let metre = WorldCoordinate.unitsPerMetre

    private func plan(_ x: Double, _ y: Double) -> PlanPoint {
        PlanPoint(x: Int64((x * Double(metre)).rounded()), y: Int64((y * Double(metre)).rounded()))
    }

    // MARK: - Numbers

    func testNumbersCountFromTheStationInTheOrderTheyWereTapped() {
        XCTAssertEqual(BusStopLabel.numbers(count: 3, farthestFirst: false), [1, 2, 3])
        XCTAssertEqual(BusStopLabel.numbers(count: 3, farthestFirst: true), [3, 2, 1], "GameCore lists the farthest first")
        XCTAssertEqual(BusStopLabel.numbers(count: 0, farthestFirst: true), [])
    }

    private let cell = Land.cellLength

    /// A managed world with a station in cell (8, 5) and a road along row 8.
    private func makeSession() throws -> (GameSession, GameWorld, StationID) {
        var world = GameWorld(bounds: try WorldBounds(width: 64 * cell, height: 16 * cell), economy: GameEconomy(balance: 100_000_000, costs: testCosts))
        let station = try world.buildStation(named: "A", at: CellPosition(row: 8, column: 5).middle)
        world.setEconomyMode(.management)
        try world.setLand([LandCell(row: 8, column: 5, use: .residential, residents: 1_000, jobs: 0)]
            + (24...28).map { LandCell(row: 8, column: $0, use: .residential, residents: 200, jobs: 0) })
        world.setLandDemand(true)
        world.enableRoads()
        try world.setRoads((5...30).map { CellPosition(row: 8, column: $0) },
                           in: [LandBlock(row: 0, column: 0), LandBlock(row: 0, column: 1), LandBlock(row: 0, column: 2)])
        let session = GameSession(world: world)
        session.selectTool(.bus)
        return (session, world, station.id)
    }

    func testTheDraftAndASavedRouteNumberTheirStopsTheSameWay() throws {
        let (first, base, station) = try makeSession()
        var session = first, world = base
        let columns = [10, 18, 26]
        session.tapBusTool(at: CellPosition(row: 8, column: 5).middle, reach: cell)
        for column in columns { session.tapBusTool(at: CellPosition(row: 8, column: column).middle, reach: cell) }
        let draft = try XCTUnwrap(session.busMapOverlay?.draft)
        XCTAssertEqual(draft.labels.map(\.number), [1, 2, 3], "as the player tapped them")
        XCTAssertEqual(draft.stops, columns.map { CellPosition(row: 8, column: $0).middle }, "1 is the nearest the station")
        XCTAssertEqual(draft.labels.map(\.name), [nil, nil, nil], "no base map, no names")

        // The same route saved: GameCore lists the farthest first.
        try world.createBusRoute(to: station, stops: columns.reversed().map { CellPosition(row: 8, column: $0) }, service: .every(minutes: 10), buses: 0)
        session = GameSession(world: world)
        let route = try XCTUnwrap(session.busMapOverlay?.routes.first)
        XCTAssertEqual(route.stops, columns.reversed().map { CellPosition(row: 8, column: $0).middle })
        XCTAssertEqual(route.labels.map(\.number), [3, 2, 1], "the farthest stop is the last number")
    }

    // MARK: - Road names

    private func feature(_ kind: String, name: String?, english: String? = nil, _ points: [(x: Double, y: Double)], column: Int, row: Int,
                         brunnel: String? = nil) -> VectorTile.Feature {
        let (west, north, scale) = projection.place(column: column, row: row, extent: 4096)
        var properties: [String: VectorTile.Value] = ["class": .string(kind)]
        if let name { properties["name"] = .string(name) }
        if let english { properties["name_en"] = .string(english) }
        if let brunnel { properties["brunnel"] = .string(brunnel) }
        let part = points.map { VectorTile.Point(x: Int32((($0.x - west) / scale).rounded()), y: Int32((($0.y - north) / scale).rounded())) }
        return VectorTile.Feature(kind: .line, properties: properties, parts: [part])
    }

    func testAStopTakesTheNameOfTheNearestNamedRoadWithin30Metres() {
        let column = projection.column(8_192), row = projection.row(8_192)
        let (west, north, _) = projection.place(column: column, row: row, extent: 4096)
        let x0 = west + 500, y0 = north + 500
        let roads = BusRoadNames.roads(in: VectorTile.Layer(name: "transportation_name", extent: 4096, features: [
            feature("secondary", name: "忠孝東路", english: "Zhongxiao E. Rd.", [(x0, y0), (x0 + 400, y0)], column: column, row: row),
            feature("minor", name: "巷", [(x0, y0 + 100), (x0 + 400, y0 + 100)], column: column, row: row),
        ]), column: column, row: row, projection: projection)
        typealias Point = BusRoadNetwork.Point
        XCTAssertEqual(BusRoadNames.nearest(to: Point(x: x0 + 200, y: y0 + 10), in: roads)?.name, "忠孝東路")
        XCTAssertEqual(BusRoadNames.nearest(to: Point(x: x0 + 200, y: y0 + 10), in: roads)?.displayName(in: .english), "Zhongxiao E. Rd.")
        XCTAssertEqual(BusRoadNames.nearest(to: Point(x: x0 + 200, y: y0 + 10), in: roads)?.displayName(in: .traditionalChinese), "忠孝東路")
        XCTAssertEqual(BusRoadNames.nearest(to: Point(x: x0 + 200, y: y0 + 85), in: roads)?.name, "巷", "the nearer of two")
        XCTAssertNil(BusRoadNames.nearest(to: Point(x: x0 + 200, y: y0 + 50), in: roads), "30 m from neither: no name")
        XCTAssertNil(BusRoadNames.nearest(to: Point(x: x0 + 200, y: y0 - 31), in: roads), "31 m away")
        XCTAssertEqual(BusRoadNames.nearest(to: Point(x: x0 + 200, y: y0 - 29), in: roads)?.name, "忠孝東路")
        XCTAssertEqual(BusRoadNames.nearest(to: Point(x: x0 + 429, y: y0), in: roads)?.name, "忠孝東路", "past the end, within 30 m")
    }

    func testOnlyNamedRoadsABusTakesAreKept() {
        let column = projection.column(8_192), row = projection.row(8_192)
        let (west, north, _) = projection.place(column: column, row: row, extent: 4096)
        let line = [(x: west + 500, y: north + 500), (x: west + 600, y: north + 500)]
        let roads = BusRoadNames.roads(in: VectorTile.Layer(name: "transportation_name", extent: 4096, features: [
            feature("primary", name: nil, line, column: column, row: row),
            feature("motorway", name: "國道1號", line, column: column, row: row),
            feature("service", name: "巷道", line, column: column, row: row),
            feature("tertiary", name: "隧道路", line, column: column, row: row, brunnel: "tunnel"),
            feature("tertiary", name: "中山路", line, column: column, row: row, brunnel: "bridge"),
        ]), column: column, row: row, projection: projection)
        XCTAssertEqual(roads.map(\.name), ["中山路"])
    }

    func testTwoRoadsAsNearGiveTheNameThatSortsFirstWhateverTheirOrder() {
        let column = projection.column(8_192), row = projection.row(8_192)
        let (west, north, _) = projection.place(column: column, row: row, extent: 4096)
        let x0 = west + 500, y0 = north + 500
        let a = NamedRoad(name: "Beta Rd", english: nil, points: [.init(x: x0, y: y0 - 10), .init(x: x0 + 100, y: y0 - 10)])
        let b = NamedRoad(name: "Alpha Rd", english: nil, points: [.init(x: x0, y: y0 + 10), .init(x: x0 + 100, y: y0 + 10)])
        let here = BusRoadNetwork.Point(x: x0 + 50, y: y0)
        XCTAssertEqual(BusRoadNames.nearest(to: here, in: [a, b])?.name, "Alpha Rd")
        XCTAssertEqual(BusRoadNames.nearest(to: here, in: [b, a])?.name, "Alpha Rd")
    }

    // MARK: - Arrows

    func testArrowsAreOnTheLinePointAtTheStationAndAreTheSameEachTime() {
        // 1,000 m east along y = 50 m, farthest stop first.
        let line = [plan(0, 50), plan(400, 50), plan(1_000, 50)]
        let arrows = BusArrows.arrows(along: line, every: 200)
        XCTAssertEqual(arrows.count, 5)
        XCTAssertEqual(arrows, BusArrows.arrows(along: line, every: 200))
        for arrow in arrows {
            XCTAssertEqual(arrow.point.y, plan(0, 50).y)
            XCTAssertEqual(arrow.dx, 1, accuracy: 1e-9)
            XCTAssertEqual(arrow.dy, 0, accuracy: 1e-9)
        }
        XCTAssertEqual(arrows.map { Double($0.point.x) / Double(metre) }, [100, 300, 500, 700, 900])
        // Run the other way, they point the other way.
        XCTAssertEqual(BusArrows.arrows(along: line.reversed(), every: 200).map(\.dx), [-1, -1, -1, -1, -1].map { Double($0) })
    }

    func testArrowsFollowACornerAndStayOnTheLine() {
        // 300 m east, then 300 m south.
        let line = [plan(0, 0), plan(300, 0), plan(300, 300)]
        let arrows = BusArrows.arrows(along: line, every: 100)
        XCTAssertEqual(arrows.count, 6)
        for arrow in arrows {
            let x = Double(arrow.point.x) / Double(metre), y = Double(arrow.point.y) / Double(metre)
            XCTAssertTrue(abs(y) < 1e-6 && (0...300).contains(x) || abs(x - 300) < 1e-6 && (0...300).contains(y), "\(x), \(y)")
            XCTAssertEqual(hypot(arrow.dx, arrow.dy), 1, accuracy: 1e-9)
        }
        XCTAssertEqual(arrows.first.map { [$0.dx, $0.dy] }, [1, 0])
        XCTAssertEqual(arrows.last.map { [$0.dx, $0.dy] }, [0, 1])
    }

    func testAShortLineHasOneArrowInTheMiddleOrNoneUnder40Metres() {
        let short = BusArrows.arrows(along: [plan(0, 0), plan(60, 0)], every: 200)
        XCTAssertEqual(short.count, 1)
        XCTAssertEqual(short.first?.point, plan(30, 0))
        XCTAssertEqual(BusArrows.arrows(along: [plan(0, 0), plan(39, 0)], every: 200), [])
        XCTAssertEqual(BusArrows.arrows(along: [plan(5, 5)], every: 200), [])
        XCTAssertEqual(BusArrows.arrows(along: [], every: 200), [])
    }

    func testTheGapIs200MetresOr120PointsWhicheverIsFarther() {
        XCTAssertEqual(BusArrows.spacing(pointsPerMetre: 2), 200, "zoomed in: 200 m")
        XCTAssertEqual(BusArrows.spacing(pointsPerMetre: 0.1), 1_200, "zoomed out: 120 points")
        XCTAssertEqual(BusArrows.spacing(pointsPerMetre: 0), 200)
    }

    // MARK: - Real bus stops

    private func stops(_ list: [(String, Double, Double)]) -> RealBusStops {
        RealBusStops(stops: list.map { RealBusStops.Stop(name: $0.0, point: plan($0.1, $0.2)) })
    }

    func testTheSameNameAndPlaceIsOneStop() {
        let merged = stops([("忠孝新生", 100, 100), ("忠孝新生", 105, 100), ("忠孝新生", 300, 100), ("善導寺", 100, 103), ("忠孝新生", 100, 109)])
        XCTAssertEqual(merged.stops.count, 3, "two of 忠孝新生 within 10 m merge; the one 200 m away and 善導寺 stay")
        XCTAssertEqual(merged.stops.filter { $0.name == "忠孝新生" }.count, 2)
        XCTAssertEqual(merged.stops, merged.stops.sorted { ($0.point.x, $0.point.y, $0.name) < ($1.point.x, $1.point.y, $1.name) })
        XCTAssertEqual(RealBusStops(stops: merged.stops.reversed()).stops, merged.stops, "the order given does not matter")
    }

    func testATapWithin25MetresIsNearAStopAndBeyondIsNot() {
        let real = stops([("A站", 100, 100), ("B站", 400, 100)])
        XCTAssertEqual(real.nearest(to: plan(120, 100))?.name, "A站")
        XCTAssertEqual(real.nearest(to: plan(100, 124))?.name, "A站")
        XCTAssertNil(real.nearest(to: plan(131, 100)))
        XCTAssertNil(real.nearest(to: plan(100, 126)))
        XCTAssertEqual(real.nearest(to: plan(380, 100))?.name, "B站")
        XCTAssertNil(stops([]).nearest(to: plan(0, 0)))
        // The nearer of two; of two as near, the name that sorts first.
        XCTAssertEqual(stops([("Beta", 90, 100), ("Alpha", 115, 100)]).nearest(to: plan(100, 100))?.name, "Beta")
        XCTAssertEqual(stops([("Beta", 90, 100), ("Alpha", 110, 100)]).nearest(to: plan(100, 100))?.name, "Alpha")
    }

    func testStopsInViewAreThoseInsideTheRegion() {
        let real = stops([("A", 100, 100), ("B", 400, 100), ("C", 400, 900)])
        let region = WorldRegion(minX: Double(plan(300, 0).x), minY: Double(plan(300, 0).y), maxX: Double(plan(500, 200).x), maxY: Double(plan(500, 200).y))
        XCTAssertEqual(real.stops(in: region).map(\.name), ["B"])
    }

    /// A real bus file of one route through `points` (name, latitude,
    /// longitude), the way the tool writes it: degrees in 1e-5, the shape
    /// after the first point as steps.
    static func busFiles(_ points: [(String, Double, Double)]) throws -> (index: Data, file: @Sendable (String, String) throws -> Data) {
        let units = points.map { (Int(($0.2 * 1e5).rounded()), Int(($0.1 * 1e5).rounded())) }
        var shape: [Int] = []
        var previous = (0, 0)
        for point in units {
            shape += [point.0 - previous.0, point.1 - previous.1]
            previous = point
        }
        let coordinates = points.map { RealRailways.Coordinate(latitude: $0.1, longitude: $0.2) }
        var run = 0.0
        var stopMetres: [Int] = [0]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            run += a.distance(to: b)
            stopMetres.append(Int(run.rounded()))
        }
        let route: [String: Any] = [
            "key": "T_0", "route": "T", "name": "1", "subRoute": "", "direction": 0, "headway": 10, "headwayEstimated": false,
            "metres": stopMetres.last!, "shape": shape, "stopNames": points.map(\.0), "stopMetres": stopMetres,
        ]
        let city = try JSONSerialization.data(withJSONObject: ["schema": 1, "city": "Taipei", "routes": [route]], options: [.sortedKeys])
        let index = try JSONSerialization.data(withJSONObject: [
            "schema": 1, "scale": 100_000,
            "places": [[
                "bounds": [units.map(\.0).min()! - 100, units.map(\.1).min()! - 100, units.map(\.0).max()! + 100, units.map(\.1).max()! + 100],
                "city": "Taipei", "estimatedHeadways": 0, "file": "real_buses_Taipei.json", "name": "臺北市", "routes": 1, "source": "tdx",
            ]],
        ] as [String: Any], options: [.sortedKeys])
        return (index, { name, ext in
            switch "\(name).\(ext)" {
            case "real_buses_Taipei.json": return city
            default: throw RealBusError.malformed("no file \(name).\(ext)")
            }
        })
    }

    func testTheLibraryReadsTheCityFilesOfTheStopsRoundAStation() throws {
        let station = RealRailways.Coordinate(latitude: 25.0478, longitude: 121.5170)
        let files = try Self.busFiles([("近站", 25.0480, 121.5172), ("遠站", 25.0600, 121.5170), ("很遠站", 25.2000, 121.5170)])
        let library = try RealBusLibrary(index: files.index, file: files.file)
        let position = frame.worldPosition(latitude: station.latitude, longitude: station.longitude)
        let here = PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
        let stops = library.stops(around: here, frame: frame, within: 6_000)
        XCTAssertEqual(stops.stops.map(\.name).sorted(), ["近站", "遠站"].sorted(), "the stop 17 km off is out of reach")
        let near = try XCTUnwrap(stops.stops.first { $0.name == "近站" })
        let there = frame.worldPosition(latitude: 25.0480, longitude: 121.5172)
        XCTAssertEqual(Double(near.point.x), there.x, accuracy: Double(metre) * 2)
        XCTAssertEqual(Double(near.point.y), there.y, accuracy: Double(metre) * 2)
        // A map that does not reach the city reads nothing.
        let faraway = RealWorldFrame(anchor: GeoAnchor(latitudeDegrees: 22.6, longitudeDegrees: 120.3)!, bounds: .standard)
        let none = library.stops(around: PlanPoint(x: 0, y: 0), frame: faraway, within: 6_000)
        XCTAssertEqual(none.stops, [])
    }

    func testTheLibraryLeavesOutACityFileItCannotRead() throws {
        let files = try Self.busFiles([("站", 25.0480, 121.5172), ("站二", 25.0482, 121.5172)])
        let library = try RealBusLibrary(index: files.index, file: { _, _ in throw RealBusError.malformed("gone") })
        let position = frame.worldPosition(latitude: 25.0478, longitude: 121.5170)
        XCTAssertEqual(library.stops(around: PlanPoint(x: Int64(position.x), y: Int64(position.y)), frame: frame, within: 6_000).stops, [])
        XCTAssertThrowsError(try RealBusLibrary(index: Data("{}".utf8), file: files.file))
    }

    // MARK: - The summary line

    private func preview(metres: Int64) -> BusRoutePreview {
        BusRoutePreview(
            price: .zero, metres: metres, headway: 10, departures: 0, dailyCost: .zero, riders: 0, minutes: 0,
            problem: nil, brokenLeg: [], isUnchanged: false
        )
    }

    func testTheFirstLineSaysStopsKilometresAndMinutes() {
        var draft = BusRouteDraft()
        draft.stops = (0..<3).map { CellPosition(row: 8, column: 10 + $0) }
        draft.legMetres = [1_000, 500, 1_500]
        let shown = preview(metres: 3_000)
        XCTAssertEqual(shown.lines(for: draft, in: .english).first, "3 stops · 3.0 km · about 10 min")
        XCTAssertEqual(shown.lines(for: draft, in: .traditionalChinese).first, "3 個站牌 · 3.0 公里 · 約 10 分")
        draft.stops = [draft.stops[0]]
        XCTAssertEqual(shown.lines(for: draft, in: .english).first, "1 stop · 3.0 km · about 10 min")
    }

    func testMinutesAreTheWholeRouteAt18KilometresAnHourRounded() {
        XCTAssertEqual(BusRoutePreview.rideMinutes(metres: 3_000), 10)
        XCTAssertEqual(BusRoutePreview.rideMinutes(metres: 3_150), 11, "10.5 rounds up")
        XCTAssertEqual(BusRoutePreview.rideMinutes(metres: 3_149), 10)
        XCTAssertEqual(BusRoutePreview.rideMinutes(metres: 600), 2)
        var draft = BusRouteDraft()
        draft.stops = [CellPosition(row: 8, column: 10)]
        draft.legMetres = [2_000, 1_000]
        // The legs' total, not the route's metres, when the way was drawn.
        XCTAssertEqual(preview(metres: 9_000).lines(for: draft, in: .english).first, "1 stop · 9.0 km · about 10 min")
        draft.legMetres = nil
        XCTAssertEqual(preview(metres: 9_000).lines(for: draft, in: .english).first, "1 stop · 9.0 km · about 30 min")
    }
}

/// Decision 424, C2 on the app's own base map: round Taipei Station the
/// road names are the map's, a real stop within 25 m of a tap is where the
/// stop goes, and the stop carries its name.
@MainActor
final class BusStopLabelsRealMapTests: XCTestCase {
    private static let taipei = (latitude: 25.0478, longitude: 121.5170)

    /// As `BusRoadsRealMapTests`: Taipei, a station a cell north of Taipei
    /// Station, its land read with the roads, and the bus tool open.
    private func game() throws -> (GameSession, PlanPoint) {
        var world = GameWorld.newWholeTaiwanGame()
        let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)
        let position = frame.worldPosition(latitude: Self.taipei.latitude, longitude: Self.taipei.longitude)
        let taipei = PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()) - Land.cellLength)
        try world.buildStation(named: "Taipei", at: taipei)
        let session = GameSession(world: world)
        try CommandLogReplay.realWorld.install(
            RealWorldDataSet(population: true, places: true, water: true, heights: true, coverage: true, baseMap: true), in: session
        )
        session.readLand(within: WholeTaiwan.landReach, of: taipei)
        session.selectTool(.bus)
        return (session, taipei)
    }

    private let metre = WorldCoordinate.unitsPerMetre

    func testRoadsRoundTaipeiStationHaveTheirNamesAndTheSameNameEachTime() throws {
        let (session, taipei) = try game()
        let roads = try XCTUnwrap(session.busRoads)
        var names = Set<String>(), unnamed = 0
        for dy in stride(from: -600, through: 600, by: 60) {
            for dx in stride(from: -600, through: 600, by: 60) {
                let tap = PlanPoint(x: taipei.x + Int64(dx) * metre, y: taipei.y + Int64(dy) * metre)
                guard let pin = roads.place(near: tap, within: 25) else { continue }
                let name = roads.roadName(near: pin, in: .traditionalChinese)
                XCTAssertEqual(name, roads.roadName(near: pin, in: .traditionalChinese), "the same name each time")
                if let name { names.insert(name) } else { unnamed += 1 }
            }
        }
        print("BusStopLabels: names round Taipei Station:", names.sorted().prefix(12), "unnamed:", unnamed)
        XCTAssertGreaterThan(names.count, 3, "the base map names the main roads")
        XCTAssertTrue(names.contains { $0.hasSuffix("路") || $0.hasSuffix("街") || $0.hasSuffix("道") }, "\(names)")
    }

    func testARealStopWithin25MetresIsWhereTheStopGoesAndGivesItsName() throws {
        let (session, taipei) = try game()
        let roads = try XCTUnwrap(session.busRoads)
        let cells = try XCTUnwrap(session.world.roads).cells
        let reach = Land.cellLength
        session.tapBusTool(at: taipei, reach: reach)
        XCTAssertNotNil(session.busDraft.station)

        // A road point 600 to 900 m off, where a tap puts a stop.
        var start: PlanPoint?
        search: for dy in stride(from: -600, through: -900, by: -17) {
            for dx in stride(from: 300, through: 700, by: 13) {
                let tap = PlanPoint(x: taipei.x + Int64(dx) * metre, y: taipei.y + Int64(dy) * metre)
                if roads.place(near: tap, within: 20, accepting: { cells.contains(CellPosition(containing: $0)) }) != nil {
                    start = tap
                    break search
                }
            }
        }
        let tap = try XCTUnwrap(start)
        func put(_ point: PlanPoint) throws -> PlanPoint {
            session.tapBusTool(at: point, reach: reach)
            XCTAssertEqual(session.busDraft.stops.count, 1, session.message?.text ?? "")
            let pin = try XCTUnwrap(session.busDraft.stopPoints.first)
            session.removeLastBusStop()
            return pin
        }
        let real = try put(tap)

        // Which way a tap 20 m from it is put elsewhere, without a real stop.
        var chosen: (near: PlanPoint, far: PlanPoint, nearPin: PlanPoint, farPin: PlanPoint)?
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let near = PlanPoint(x: real.x + Int64(dx * 20) * metre, y: real.y + Int64(dy * 20) * metre)
            let far = PlanPoint(x: real.x + Int64(dx * 40) * metre, y: real.y + Int64(dy * 40) * metre)
            let nearPin = try put(near), farPin = try put(far)
            if hypot(Double(nearPin.x - real.x), Double(nearPin.y - real.y)) / Double(metre) > 3 {
                chosen = (near, far, nearPin, farPin)
                break
            }
        }
        let picked = try XCTUnwrap(chosen, "a tap 20 m off a road point is put elsewhere in some direction")

        // The real stop, and one 300 m away.
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        let here = frame.coordinate(worldX: Double(real.x), worldY: Double(real.y))
        let files = try BusStopLabelsTests.busFiles([("測試站", here.latitude, here.longitude), ("別站", here.latitude + 0.003, here.longitude)])
        session.realBuses = try RealBusLibrary(index: files.index, file: files.file)

        // 20 m from it: the stop is where the real one is, with its name.
        session.tapBusTool(at: picked.near, reach: reach)
        XCTAssertEqual(session.busDraft.stops.count, 1, session.message?.text ?? "")
        let pin = try XCTUnwrap(session.busDraft.stopPoints.first)
        XCTAssertEqual(hypot(Double(pin.x - real.x), Double(pin.y - real.y)) / Double(metre), 0, accuracy: 1.5)
        XCTAssertTrue(cells.contains(session.busDraft.stops[0]))
        let draft = try XCTUnwrap(session.busMapOverlay?.draft)
        XCTAssertEqual(draft.labels, [BusStopLabel(number: 1, name: "測試站")])
        XCTAssertEqual(session.busMapOverlay?.realStops?.stops.map(\.name).sorted(), ["別站", "測試站"].sorted())
        XCTAssertTrue(session.busMapOverlay?.showsLabels == true)
        session.removeLastBusStop()

        // 40 m from it: put on the road as before.
        session.tapBusTool(at: picked.far, reach: reach)
        XCTAssertEqual(session.busDraft.stopPoints.first, picked.farPin)
        session.removeLastBusStop()

        // Without the real stops the stop is put as before, and a tap on
        // the stop just put takes it away.
        session.realBuses = nil
        session.tapBusTool(at: picked.near, reach: reach)
        XCTAssertEqual(session.busDraft.stopPoints.first, picked.nearPin)
        XCTAssertNil(session.busMapOverlay?.realStops)
    }
}
