import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 733: Hong Kong International Airport on the 3D map, from
/// OpenStreetMap as Taiwan's airports are (decisions 385 and 699): the
/// pack's airfield (`airfields.json`) and its land no one lives on
/// (`no_build.json`), read with Taiwan's.
@MainActor
final class HongKongAirportTests: XCTestCase {
    private static func pack() throws -> MapPack {
        try XCTUnwrap(HongKongRailwaysTests.pack(.hongKong))
    }

    private static let taiwanNoBuild = Result {
        try RealNoBuildLand(data: Data(contentsOf: Map3DTrenchTests.root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_no_build.json")))
    }

    /// The middle of Terminal 1, and of Taoyuan's Terminal 1.
    private static let terminal = (latitude: 22.3135, longitude: 113.9215)
    private static let taoyuan = (latitude: 25.0777, longitude: 121.2325)

    /// Metres between two places, near enough.
    private func metres(_ a: RealAirfields.Point, _ b: RealAirfields.Point) -> Double {
        let east = (a.longitude - b.longitude) * 111_320 * cos(a.latitude * .pi / 180), north = (a.latitude - b.latitude) * 110_574
        return (east * east + north * north).squareRoot()
    }

    // MARK: - The pack

    /// The airfield has its three runways, 3,800 m each (OpenStreetMap's
    /// lines from 3.4 to 3.7 km; 07C/25C too, which it tags as a displaced
    /// threshold its whole length), its stands, jet bridges, aprons,
    /// taxiways and tower.
    func testThePackHasTheAirfield() throws {
        let fields = try XCTUnwrap(Self.pack().airfields()).fields
        XCTAssertEqual(fields.map(\.iata), ["HKG"])
        let field = try XCTUnwrap(fields.first)
        XCTAssertEqual(Set(field.runways.map(\.ref)), ["07L/25R", "07C/25C", "07R/25L"])
        for runway in field.runways {
            XCTAssertGreaterThan(metres(runway.line[0], runway.line[runway.line.count - 1]), 3_300, runway.ref)
        }
        XCTAssertGreaterThan(field.stands.count, 150)
        XCTAssertGreaterThan(field.bridges.count, 100)
        XCTAssertFalse(field.aprons.isEmpty)
        XCTAssertGreaterThan(field.taxiways.count, 300)
        XCTAssertEqual(field.towers.count, 1)
        // The catalogue's airport stands by it.
        let place = try XCTUnwrap(AirportCatalog.overseasPlaces.first { $0.key == "hkg" })
        XCTAssertLessThan(metres(field.at, RealAirfields.Point(latitude: place.latitude, longitude: place.longitude)), 4_000)
    }

    /// The airport is no-build land, its terminals among its buildings.
    func testThePackHasTheAirportsLand() throws {
        let land = try XCTUnwrap(Self.pack().noBuildLand())
        XCTAssertEqual(land.kind(atLatitude: Self.terminal.latitude, longitude: Self.terminal.longitude), .airport)
        XCTAssertNil(land.kind(atLatitude: 22.2960, longitude: 114.1720), "Tsim Sha Tsui")
        XCTAssertGreaterThanOrEqual(land.buildings.filter { $0.use == .terminal }.count, 2)
        XCTAssertEqual(land.airfields?.fields.map(\.iata), ["HKG"])
        XCTAssertNil(try Self.pack().noBuildLand(airfields: false)?.airfields)
    }

    /// Taiwan's land and Hong Kong's read as one: each airport where it
    /// is, and their airfields together.
    func testTaiwansAndHongKongsLandAddUp() throws {
        var taiwan = try Self.taiwanNoBuild.get()
        taiwan.airfields = RealAirfields(fields: [])
        let both = taiwan.adding(try XCTUnwrap(Self.pack().noBuildLand()))
        XCTAssertEqual(both.kind(atLatitude: Self.terminal.latitude, longitude: Self.terminal.longitude), .airport)
        XCTAssertEqual(both.kind(atLatitude: Self.taoyuan.latitude, longitude: Self.taoyuan.longitude), .airport)
        XCTAssertEqual(both.areas.count, try Self.taiwanNoBuild.get().areas.count + XCTUnwrap(Self.pack().noBuildLand()).areas.count)
        XCTAssertEqual(both.airfields?.fields.map(\.iata), ["HKG"])
    }

    /// The real-world data reads Hong Kong's no-build land with Taiwan's,
    /// so a Hong Kong game's land puts no one on the airport.
    func testTheDataReadsTheAirportsLand() throws {
        let data = RealWorldData.load(overseas: [.hongKong], pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        let land = try XCTUnwrap(data.places?.noBuild)
        XCTAssertEqual(land.kind(atLatitude: Self.terminal.latitude, longitude: Self.terminal.longitude), .airport)
        XCTAssertEqual(land.kind(atLatitude: Self.taoyuan.latitude, longitude: Self.taoyuan.longitude), .airport)
        let taiwan = RealWorldData.load(overseas: [], file: RealWorldDataLoadTests.file)
        XCTAssertNil(taiwan.places?.noBuild?.kind(atLatitude: Self.terminal.latitude, longitude: Self.terminal.longitude), "no city asked for")
    }

    /// No one lives on the airport: WorldPop's people there move to the
    /// rest of their cells, as Taiwan's do (decision 385 (續)).
    func testNoOneLivesOnTheAirport() throws {
        let (world, open, closed, frame) = try land()
        _ = world
        func onAirport(_ cell: LandCell) throws -> Bool {
            let place = frame.coordinate(worldX: Double(cell.middle.x), worldY: Double(cell.middle.y))
            return try XCTUnwrap(Self.pack().noBuildLand(airfields: false)).kind(atLatitude: place.latitude, longitude: place.longitude) == .airport
        }
        XCTAssertGreaterThan(try open.filter(onAirport).reduce(Int64(0)) { $0 + $1.residents }, 1_000, "WorldPop puts people on the airport")
        XCTAssertEqual(try closed.filter(onAirport).reduce(Int64(0)) { $0 + $1.residents }, 0)
        XCTAssertEqual(closed.reduce(Int64(0)) { $0 + $1.residents }, open.reduce(Int64(0)) { $0 + $1.residents }, "everyone is kept")
    }

    /// A map round the airport whose land was read before the airport was
    /// no-build land (an older game's), and its land read both ways.
    private func land() throws -> (world: GameWorld, open: [LandCell], closed: [LandCell], frame: RealWorldFrame) {
        let ground = try HongKongMapTests.ground()
        let population = try XCTUnwrap(ground.population)
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 22.315, longitudeDegrees: 113.922))
        let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
        var places = try PlaceGrid(data: Data("""
        {"north":0.02,"west":0,"cellDegrees":0.01,"layers":{"shops":[],"offices":[],"schools":[],"attractions":[]}}
        """.utf8))
        let open = try XCTUnwrap(LandImport.cells(population: population, places: places, water: ground.water, frame: frame,
                                                  bounds: GameWorld.newGameBounds))
        places.noBuild = try Self.pack().noBuildLand(airfields: false)
        let closed = try XCTUnwrap(LandImport.cells(population: population, places: places, water: ground.water, frame: frame,
                                                    bounds: GameWorld.newGameBounds))
        return (GameWorld.newGame(anchor: anchor, land: open), open, closed, frame)
    }

    // MARK: - The scene

    /// The scene lays the airfield's runways in asphalt; an older game's
    /// lots on the airport tint no ground (the soft green patches of
    /// decision 720's yards), though off it they still do.
    func testTheSceneLaysTheAirfieldAndNoLotsGroundOnIt() throws {
        let (world, _, _, frame) = try land()
        let tiles = try BaseMapTiles(data: Data(contentsOf: Self.pack().root.appendingPathComponent("basemap.pmtiles"), options: .alwaysMapped))
        let land = try XCTUnwrap(Self.pack().noBuildLand())
        let bare = Map3DScene(world: world, baseMap: tiles)
        let scene = Map3DScene(world: world, baseMap: tiles, noBuild: land)
        typealias Paint = Map3DScene.Builder.Airfield
        func count(_ colours: Set<UInt32>, in scene: Map3DScene, where wanted: (Map3DVertex) -> Bool = { _ in true }) -> Int {
            let drawn = colours.union(colours.map(Map3DLook.colour))
            return scene.chunks.reduce(0) { $0 + $1.mesh.vertices.filter { drawn.contains($0.color) && wanted($0) }.count }
        }
        XCTAssertEqual(count([Paint.asphalt], in: bare), 0)
        XCTAssertGreaterThan(count([Paint.asphalt], in: scene), 300, "three runways")
        XCTAssertGreaterThan(count([Paint.yellow], in: scene), 300, "the taxiways' centre lines")
        // The lots' ground: the corners of the 64 m squares whose four
        // squares round them are all on the airport.
        let tinted = Map3DPalette.groundMixes.subtracting([Map3DPalette.ground])
        let cell = Double(Land.cellLength)
        var airportCorners = Set<Map3DScene.ChunkKey>()
        let noBuild = try XCTUnwrap(Self.pack().noBuildLand(airfields: false))
        func onAirport(row: Int, column: Int) -> Bool {
            let place = frame.coordinate(worldX: (Double(column) + 0.5) * cell, worldY: (Double(row) + 0.5) * cell)
            return noBuild.kind(atLatitude: place.latitude, longitude: place.longitude) == .airport
        }
        for lot in CitySkyline(world: world).lots(in: scene.region) where Map3DPalette.GroundKind(lot) != nil {
            for (row, column) in [(lot.row, lot.column), (lot.row, lot.column + 1), (lot.row + 1, lot.column), (lot.row + 1, lot.column + 1)]
                where [(row - 1, column - 1), (row - 1, column), (row, column - 1), (row, column)].allSatisfy({ onAirport(row: $0.0, column: $0.1) }) {
                airportCorners.insert(Map3DScene.ChunkKey(column: column, row: row))
            }
        }
        XCTAssertGreaterThan(airportCorners.count, 20, "the older game's lots on the airport")
        let corners = airportCorners.map { scene.point(worldX: Double($0.column) * cell, worldY: Double($0.row) * cell, height: 0) }
        func atACorner(_ vertex: Map3DVertex) -> Bool {
            corners.contains { abs($0.x - vertex.x) < 0.5 && abs($0.z - vertex.z) < 0.5 }
        }
        XCTAssertGreaterThan(count(tinted, in: bare, where: atACorner), 0, "tinted without the no-build land")
        XCTAssertEqual(count(tinted, in: scene, where: atACorner), 0, "plain on the airport")
        XCTAssertGreaterThan(count(tinted, in: scene), 0, "tinted off the airport")
    }
}
