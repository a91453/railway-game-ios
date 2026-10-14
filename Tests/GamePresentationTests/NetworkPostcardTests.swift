import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 215: the network postcard's words, its map's region and its
/// layout; v2: at most three figures and no zeros, the layout framed to the
/// network, the route map's strokes, dots and names, and the sea.
final class NetworkPostcardTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The high-speed demo, as the owner saw it on a device (decision 170).
    private static let highSpeed: Result<GameWorld, Error> = Result {
        try HighSpeedDemo.make(in: .traditionalChinese, railways: HighSpeedDemoTests.railways())
    }

    // MARK: - What it says

    func testTheDemoNetworkPostcardSaysWhatTheCompanyHas() {
        let world = DemoWorld.make(in: .traditionalChinese)
        let postcard = NetworkPostcard(world: world, companyName: "  沿線鐵道 ", in: .traditionalChinese)
        let figures = CompanyFigures(world: world)

        XCTAssertEqual(postcard.title, "沿線鐵道")
        XCTAssertEqual(postcard.wordmark, "沿線")
        XCTAssertEqual(
            postcard.subtitle,
            "\(world.clock.now.date.text(in: .traditionalChinese)) ・ \(CompanyRank(world: world).title.title(in: .traditionalChinese))"
        )
        XCTAssertEqual(postcard.figures, NetworkPostcard.figures(lines: world.lines.count, figures: figures, in: .traditionalChinese))
        XCTAssertLessThanOrEqual(postcard.figures.count, NetworkPostcard.figureLimit)
        // The demo map is the game's own: no base map, no real railways.
        XCTAssertEqual(postcard.credit, "")
    }

    func testAtMostThreeFiguresAndNoneThatIsZero() {
        let figures = CompanyFigures(yesterdayRiders: 12_345, trackMetres: 3_400, stations: 5)
        let all = NetworkPostcard.figures(lines: 1, figures: figures, in: .english)
        XCTAssertEqual(all.map(\.label), ["riders yesterday", "of track", "stations"])
        XCTAssertEqual(all.map(\.value), ["12,345", "3.4 km", "5"])

        // A new network: no riders yet, so the track, stations and lines.
        let opening = NetworkPostcard.figures(lines: 3, figures: CompanyFigures(yesterdayRiders: 0, trackMetres: 730_600, stations: 12), in: .traditionalChinese)
        XCTAssertEqual(opening.map(\.label), ["路網長度", "座車站", "條路線"])
        XCTAssertEqual(opening.map(\.value), ["730.6 km", "12", "3"])

        let one = NetworkPostcard.figures(lines: 1, figures: CompanyFigures(yesterdayRiders: 0, trackMetres: 0, stations: 1), in: .english)
        XCTAssertEqual(one.map(\.label), ["station", "line"])
        XCTAssertEqual(NetworkPostcard.figures(lines: 0, figures: CompanyFigures(yesterdayRiders: 0, trackMetres: 0, stations: 0), in: .english), [])
    }

    func testTheCompanyNameIsTrimmedCutAndNeverEmpty() {
        XCTAssertEqual(NetworkPostcard.companyName(" \n ", in: .traditionalChinese), "我的鐵道")
        XCTAssertEqual(NetworkPostcard.companyName("", in: .english), "My Railway")
        XCTAssertEqual(NetworkPostcard.companyName("北海\n岸線", in: .english), "北海 岸線")
        let long = String(repeating: "鐵", count: 30)
        XCTAssertEqual(NetworkPostcard.companyName(long, in: .english).count, NetworkPostcard.nameLimit)
    }

    func testARealWorldMapCreditsItsRailways() {
        let world = LiuMingchuanChallenge.make()
        XCTAssertNotNil(world.geoAnchor)
        let postcard = NetworkPostcard(world: world, companyName: "", in: .english)
        XCTAssertEqual(postcard.credit, DataSourceCredits.mapCorner(baseMap: false, railways: true, in: .english))
    }

    func testTheLegendListsTwoOrMoreLinesWithTheirBadges() throws {
        let world = try Self.highSpeed.get()
        let postcard = NetworkPostcard(world: world, companyName: "", in: .traditionalChinese)
        let codes = LineBadge.codes(for: world.lines)
        XCTAssertEqual(postcard.legend.map(\.name), world.lines.map(\.name))
        XCTAssertEqual(postcard.legend.map(\.code), world.lines.map { codes[$0.id] ?? "" })
        XCTAssertEqual(postcard.legendEntries(slots: 3), postcard.legend.map(NetworkPostcard.LegendEntry.line))
        XCTAssertEqual(postcard.legendEntries(slots: 2), [.line(postcard.legend[0]), .more(2)])
        XCTAssertEqual(postcard.legendEntries(slots: 0), [])
    }

    // MARK: - The map's region

    func testTheMapShowsTheNetworkWithRoomRoundIt() throws {
        let world = DemoWorld.make(in: .english)
        let built = try XCTUnwrap(WorldRegion.built(in: world))
        let postcard = NetworkPostcard(world: world, companyName: "", in: .english)
        let region = postcard.region
        XCTAssertLessThan(region.minX, built.minX)
        XCTAssertLessThan(region.minY, built.minY)
        XCTAssertGreaterThan(region.maxX, built.maxX)
        XCTAssertGreaterThan(region.maxY, built.maxY)
        // Fitted into the postcard's map, the whole network is in view.
        let frame = PostcardLayout.parts(of: postcard).map
        let projection = PostcardProjection(region: region, size: ScreenSize(width: frame.width, height: frame.height))
        for station in world.stations {
            let point = projection.screenPoint(of: station.location)
            XCTAssertTrue((0...frame.width).contains(point.x) && (0...frame.height).contains(point.y), station.name)
        }
    }

    func testANewMapShowsTheWholeMap() throws {
        let world = GameWorld(bounds: try WorldBounds(width: 131_072, height: 98_304), economy: GameEconomy(balance: 1_000, costs: ConstructionCosts(track: 1, station: 1, train: 1)))
        XCTAssertEqual(NetworkPostcard(world: world, companyName: "", in: .english).region, WorldRegion(bounds: world.bounds))
    }

    func testTheProjectionIsNoCloserThanTheMapsClosestZoom() {
        let tiny = WorldRegion(minX: 0, minY: 0, maxX: 10, maxY: 10)
        let projection = PostcardProjection(region: tiny, size: ScreenSize(width: 380, height: 296))
        XCTAssertEqual(projection.referenceSize, MapScale.largestSize, accuracy: 1e-9)
        let middle = projection.screenPoint(worldX: 5, worldY: 5)
        XCTAssertEqual(middle.x, 190, accuracy: 1e-9)
        XCTAssertEqual(middle.y, 148, accuracy: 1e-9)
        let back = projection.worldPosition(at: middle)
        XCTAssertEqual(back.x, 5, accuracy: 1e-9)
        XCTAssertEqual(back.y, 5, accuracy: 1e-9)
    }

    // MARK: - The layout

    func testThePartsStayOnTheCardAndApart() {
        let card = PostcardLayout.Frame(
            x: PostcardLayout.border, y: PostcardLayout.border,
            width: PostcardLayout.size.width - 2 * PostcardLayout.border,
            height: PostcardLayout.size.height - 2 * PostcardLayout.border
        )
        let header = [PostcardLayout.stationMaster, PostcardLayout.title, PostcardLayout.subtitle]
        let footer = [PostcardLayout.credit, PostcardLayout.wordmark]
        for shape in [NetworkPostcard.Shape.tall, .wide] {
            for aspect in [0.2, 0.5, 0.8, 1.5, 4] {
                for legend in [0, 2, 3, 12] {
                    for figures in 0...3 {
                        let parts = PostcardLayout.parts(shape: shape, aspect: aspect, legend: legend, figures: figures)
                        let all = header + footer + [parts.map] + parts.legend + parts.figures
                        let context = "\(shape) \(aspect) \(legend) \(figures)"
                        XCTAssertEqual(parts.figures.count, figures, context)
                        XCTAssertLessThanOrEqual(parts.legend.count, legend, context)
                        if legend > 0 { XCTAssertGreaterThan(parts.legend.count, 0, context) }
                        for (index, part) in all.enumerated() {
                            XCTAssertTrue(card.contains(part), "\(context): \(part)")
                            for other in all[(index + 1)...] {
                                XCTAssertFalse(part.intersects(other), "\(context): \(part) \(other)")
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(PostcardLayout.size.width * PostcardLayout.scale, 1_200)
        XCTAssertEqual(PostcardLayout.size.height * PostcardLayout.scale, 1_500)
    }

    func testATallNetworksMapIsAsNarrowAsItNeedsAndAWideOneFillsTheWidth() {
        let tall = PostcardLayout.parts(shape: .tall, aspect: 0.55, legend: 3, figures: 3)
        XCTAssertEqual(tall.map.width, PostcardLayout.body.height * 0.55, accuracy: 1e-9)
        XCTAssertEqual(tall.map.height, PostcardLayout.body.height)
        // The legend at the top of the column beside it, the figures at
        // its foot.
        XCTAssertEqual(tall.legend.count, 3)
        XCTAssertEqual(tall.legend[0].y, PostcardLayout.body.y + PostcardLayout.gap)
        XCTAssertEqual(tall.figures.last?.maxY, PostcardLayout.body.maxY)
        XCTAssertTrue(tall.figures.allSatisfy { $0.x > tall.map.maxX })

        // A wide one: the map from under the title to the legend's row,
        // the figures along the foot.
        let wide = PostcardLayout.parts(shape: .wide, aspect: 3, legend: 0, figures: 3)
        XCTAssertEqual(wide.map.width, PostcardLayout.body.width)
        XCTAssertEqual(wide.map.y, PostcardLayout.body.y)
        XCTAssertEqual(wide.figures.first?.maxY, PostcardLayout.body.maxY)
        let keyed = PostcardLayout.parts(shape: .wide, aspect: 3, legend: 2, figures: 3)
        XCTAssertLessThan(keyed.map.height, wide.map.height)
        XCTAssertTrue(keyed.legend.allSatisfy { $0.y >= keyed.map.maxY && $0.maxY <= keyed.figures[0].y })
        XCTAssertEqual(PostcardLayout.parts(shape: .wide, aspect: 3, legend: 9, figures: 3).legend.count, PostcardLayout.wideLegendLimit)
    }

    // MARK: - The route map

    func testTheDemoNetworksNamesStayOnTheMapApartAndNearTheirStations() throws {
        let world = DemoWorld.make(in: .traditionalChinese)
        try checkNames(of: world)
    }

    func testTheHighSpeedDemoStandsTallWithItsThreeLinesSideBySide() throws {
        let world = try Self.highSpeed.get()
        let postcard = NetworkPostcard(world: world, companyName: "", in: .traditionalChinese)
        XCTAssertEqual(postcard.shape, .tall)
        XCTAssertEqual(postcard.figures.map(\.label), ["路網長度", "座車站", "條路線"])
        let (network, _) = map(of: world, postcard)
        XCTAssertEqual(network.lineWidth, PostcardNetwork.sharedLineWidth)
        // Halfway between Taichung and Changhua, all three lines pass, a
        // stroke's width and more apart, never on top of one another.
        let stations = Dictionary(uniqueKeysWithValues: world.stations.map { ($0.name, $0) })
        let projection = self.projection(postcard)
        let taichung = projection.screenPoint(of: try XCTUnwrap(stations["台中"]).location)
        let changhua = projection.screenPoint(of: try XCTUnwrap(stations["彰化"]).location)
        let middle = ScreenPoint(x: (taichung.x + changhua.x) / 2, y: (taichung.y + changhua.y) / 2)
        var nearest: [LineID: ScreenPoint] = [:]
        for line in world.lines {
            nearest[line.id] = PostcardNetwork.nearest(to: middle, on: network.strokes.filter { $0.line == line.id }.map(\.points))?.0
        }
        let points = Array(nearest.values)
        XCTAssertEqual(points.count, 3)
        for (index, a) in points.enumerated() {
            for b in points[(index + 1)...] {
                XCTAssertGreaterThan(hypot(a.x - b.x, a.y - b.y), PostcardNetwork.sharedLineWidth, "\(a) \(b)")
            }
        }
        try checkNames(of: world)
    }

    func testTaipeiStandsLeftOfNangangAndBanqiaoUnderTheLine() throws {
        // The owner, 2026-10-14, on the high-speed demo's postcard.
        let world = try Self.highSpeed.get()
        let postcard = NetworkPostcard(world: world, companyName: "", in: .traditionalChinese)
        let (network, _) = map(of: world, postcard)
        let labels = Dictionary(uniqueKeysWithValues: network.labels.map { ($0.name, $0) })
        let nangang = try XCTUnwrap(labels["南港"]), taipei = try XCTUnwrap(labels["台北"]), banqiao = try XCTUnwrap(labels["板橋"])
        XCTAssertLessThanOrEqual(taipei.frame.maxX, nangang.frame.x)
        XCTAssertEqual(taipei.frame.y, nangang.frame.y, accuracy: 1)
        let station = try XCTUnwrap(world.stations.first { $0.name == "板橋" })
        let dot = projection(postcard).screenPoint(of: station.location)
        XCTAssertGreaterThan(banqiao.frame.y, dot.y)
        XCTAssertNil(banqiao.leader)
    }

    func testTheHighSpeedDemosSeaIsOffTheCoastAndNoStationIsInIt() throws {
        let world = try Self.highSpeed.get()
        let postcard = NetworkPostcard(world: world, companyName: "", in: .traditionalChinese)
        let water = try WaterGrid(data: Data(contentsOf: Self.root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_water.json")))
        let frame = PostcardLayout.parts(of: postcard).map
        let size = ScreenSize(width: frame.width, height: frame.height)
        let sea = PostcardSea(water: water, frame: try XCTUnwrap(RealWorldFrame(world: world)), projection: projection(postcard), size: size)
        let cells = sea.runs.reduce(0) { $0 + $1.columns.count }
        let all = Int((size.width / sea.cell).rounded(.up)) * Int((size.height / sea.cell).rounded(.up))
        // The Taiwan Strait to the west, the Pacific to the east: a good
        // part of the map, but far from all of it.
        XCTAssertGreaterThan(cells, all / 5)
        XCTAssertLessThan(cells, all * 4 / 5)
        for station in world.stations {
            let point = projection(postcard).screenPoint(of: station.location)
            let row = Int(point.y / sea.cell), column = Int(point.x / sea.cell)
            XCTAssertFalse(sea.runs.contains { $0.row == row && $0.columns.contains(column) }, station.name)
        }
    }

    func testOnlyWaterReachingTheEdgeIsSea() {
        // A lake in the middle of land, the sea along the left.
        let wet: [Bool] = [
            true, false, false, false, false,
            true, false, true, false, false,
            true, false, false, false, false,
        ]
        let sea = PostcardSea.sea(wet, rows: 3, columns: 5)
        XCTAssertEqual(PostcardSea.runs(of: sea, rows: 3, columns: 5), (0..<3).map { PostcardSea.Run(row: $0, columns: 0..<1) })
    }

    func testAStrokeMovesToItsLeft() {
        // Going east, left is north: up the screen.
        let moved = PostcardNetwork.offset([ScreenPoint(x: 0, y: 0), ScreenPoint(x: 10, y: 0)], by: 2)
        XCTAssertEqual(moved[0].y, -2, accuracy: 1e-9)
        XCTAssertEqual(moved[1].y, -2, accuracy: 1e-9)
    }

    // MARK: - Helpers

    private func projection(_ postcard: NetworkPostcard) -> PostcardProjection {
        let frame = PostcardLayout.parts(of: postcard).map
        return PostcardProjection(region: postcard.region, size: ScreenSize(width: frame.width, height: frame.height))
    }

    private func map(of world: GameWorld, _ postcard: NetworkPostcard) -> (PostcardNetwork, ScreenSize) {
        let frame = PostcardLayout.parts(of: postcard).map
        let size = ScreenSize(width: frame.width, height: frame.height)
        return (PostcardNetwork(world: world, lines: LineMap(world: world), projection: projection(postcard), size: size), size)
    }

    /// Every name on the map, none over another, each nearer its own
    /// station than any other.
    private func checkNames(of world: GameWorld, file: StaticString = #filePath, line: UInt = #line) throws {
        let postcard = NetworkPostcard(world: world, companyName: "", in: .traditionalChinese)
        let (network, size) = map(of: world, postcard)
        let projection = self.projection(postcard)
        XCTAssertEqual(network.labels.count, world.stations.count, file: file, line: line)
        XCTAssertEqual(network.dots.count, world.stations.count, file: file, line: line)
        let card = PostcardLayout.Frame(x: 0, y: 0, width: size.width, height: size.height)
        let points = world.stations.map { projection.screenPoint(of: $0.location) }
        for (index, label) in network.labels.enumerated() {
            XCTAssertTrue(card.contains(label.frame), "\(label.name) \(label.frame)", file: file, line: line)
            for other in network.labels[(index + 1)...] {
                XCTAssertFalse(label.frame.intersects(other.frame), "\(label.name) \(other.name)", file: file, line: line)
            }
            let box = PostcardNetwork.Box(minX: label.frame.x, minY: label.frame.y, maxX: label.frame.maxX, maxY: label.frame.maxY)
            let own = box.distance(to: points[index])
            for (other, point) in points.enumerated() where other != index {
                XCTAssertGreaterThanOrEqual(box.distance(to: point), own - 0.5, "\(label.name) nearer \(world.stations[other].name)", file: file, line: line)
            }
        }
    }
}
