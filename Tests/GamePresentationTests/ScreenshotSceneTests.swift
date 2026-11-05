import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The website's screenshot scenes (decision 165) are worlds the game's own
/// commands build; each must still build, and show what its screenshots
/// are taken for, or the screenshot run would photograph something else.
@MainActor
final class ScreenshotSceneTests: XCTestCase {
    /// The freight scene, on the second morning: both yards hold goods,
    /// the freight train is full, the city's stations are drawn from
    /// as before, and the first midnight left stations short of building
    /// materials, so the map shows its bubble.
    func testTheFreightSceneShowsFreightAndMaterials() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        await launcher.openScreenshotScene(.freight).value
        let world = try XCTUnwrap(launcher.session?.world, "the launcher plays the scene")
        XCTAssertEqual(world.clock.speed, .paused)
        XCTAssertEqual(world.clock.now, GameTime(seconds: 32 * 3_600 + 30))
        let freight = try XCTUnwrap(world.freight)
        XCTAssertEqual(freight.facilities.count, 2)
        let line = try XCTUnwrap(world.lines.first(where: \.isFreight))
        XCTAssertEqual(line.name, "貨運線")
        let train = try XCTUnwrap(line.assignedTrains.first)
        let load = try XCTUnwrap(world.trainLoadInfo(of: train))
        XCTAssertTrue(load.isFreight)
        XCTAssertEqual(load.percentage, 100, "the freight train leaves full: \(load)")
        XCTAssertTrue(world.stations.allSatisfy { world.freightFacility(at: $0.id).map { $0.stock > 0 } ?? true }, "both yards hold goods")
        XCTAssertGreaterThan(freight.delivered, 0, "goods have been delivered")
        XCTAssertTrue(world.stations.contains { world.isShortOfMaterials($0.id) }, "a station is short of building materials")
        XCTAssertTrue(world.lines.filter { !$0.isFreight }.allSatisfy { !$0.assignedTrains.isEmpty }, "the demo's lines still run")
    }

    /// Decision 574: the Maokong scene, at 10:00 of its second day: the
    /// gondola built with its real 4,033 m, its first day settled.
    func testTheMaokongSceneHasTheGondolaRunning() throws {
        let world = ScreenshotScene.maokong.make(in: .traditionalChinese)
        XCTAssertEqual(world.clock.speed, .paused)
        XCTAssertEqual(world.clock.now.seconds / 3_600, 34)
        let gondola = try XCTUnwrap(world.cableways.first)
        XCTAssertEqual(world.cableways.count, 1)
        XCTAssertEqual(gondola.metres, 4_033)
        XCTAssertEqual(gondola.stops.filter(\.boards).count, 4)
        XCTAssertTrue(world.cablewayIsOpen(gondola.id, onDay: 1) || world.weather(onDay: 1) == .thunderstorm)
        XCTAssertEqual(gondola.days.map(\.day), [0], "the first day is settled")
        // The map opens on the gondola: its stops are what is built.
        let opening = try XCTUnwrap(WorldRegion.opening(in: world))
        for stop in gondola.stops {
            XCTAssertTrue(opening.contains(WorldCoordinate(x: stop.cell.middle.x, y: stop.cell.middle.y)))
        }
        XCTAssertLessThan(opening.width, Double(Land.cellLength) * 40, "only the gondola, not the whole map")
    }

    /// Decision 585: the Tamsui–Bali ferry on a new game of Tamsui, its
    /// first day settled, and the map opening on its piers.
    func testTamsuiFerrySceneOpensTheRealFerry() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let water = try WaterGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_water.json")))
        let world = ScreenshotScene.tamsuiFerry.make(in: .traditionalChinese, water: water)
        XCTAssertEqual(world.clock.speed, .paused)
        XCTAssertEqual(world.clock.now.seconds / 3_600, 34)
        let ferry = try XCTUnwrap(world.ferryRoutes.first, "the real map has water at the river mouth")
        XCTAssertEqual(world.ferryRoutes.count, 1)
        XCTAssertEqual(ferry.piers.count, 2)
        XCTAssertEqual(ferry.boats, 2)
        XCTAssertEqual(ferry.metres, RealFerry.tamsuiBali.legMetres.reduce(0, +))
        XCTAssertEqual(ferry.days.map(\.day), [0], "the first day is settled")
        let opening = try XCTUnwrap(WorldRegion.opening(in: world))
        for pier in ferry.piers {
            XCTAssertTrue(opening.contains(WorldCoordinate(x: pier.middle.x, y: pier.middle.y)))
        }
        XCTAssertLessThan(opening.width, Double(Land.cellLength) * 40, "only the ferry, not the whole map")
    }

    /// Decision 585 PR-3 (FERRY3): the Gushan–Cijin scenes open the real
    /// ferry with the double-ended boat, at 10:00 and 18:30 of the second
    /// day, each pier facing the water, a boat to point the camera at;
    /// and the Tamsui–Bali scene draws the passenger boat.
    func testTheFerryScenesLayBoatsAndPiersIn3D() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let water = try WaterGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_water.json")))
        for (scene, hours, boat) in [(ScreenshotScene.gushanFerry, 34.0, Map3DFerry.Boat.cijin), (.gushanFerryEvening, 42.5, .cijin),
                                     (.tamsuiFerry, 34.0, .tamsui), (.tamsuiFerryCrossing, 34.05, .tamsui)] {
            XCTAssertTrue(scene.needsWater)
            let world = scene.make(in: .traditionalChinese, water: water)
            XCTAssertEqual(Double(world.clock.now.seconds) / 3_600, hours, accuracy: 0.001, "\(scene)")
            let ferry = try XCTUnwrap(world.ferryRoutes.first, "\(scene)")
            XCTAssertEqual(ferry.boats, 2)
            let laid = Map3DFerries(world: world, scene: Map3DScene(world: world))
            let line = try XCTUnwrap(laid.lines.first)
            XCTAssertEqual(line.boat, boat, "\(scene)")
            for (cell, other) in zip(ferry.piers, ferry.piers.reversed()) {
                let side = Map3DFerries.waterSide(of: cell, toward: other, in: world)
                XCTAssertTrue(world.terrain.isWater(row: cell.row + side.row, column: cell.column + side.column), "\(scene) \(cell)")
            }
            XCTAssertNotNil(laid.firstBoat(second: Double(world.clock.now.seconds)))
            if scene == .tamsuiFerryCrossing {
                // The boat followed is out on the river, the other far off.
                let followed = try XCTUnwrap(world.ferryBoatMidCrossing(on: ferry.id))
                let boats = laid.laid(line, second: Double(world.clock.now.seconds), following: followed.number)
                let mine = try XCTUnwrap(boats.first { $0.number == followed.number })
                guard case .sailing(_, let share, _)? = mine.sailing?.stage else { return XCTFail("not sailing") }
                XCTAssertEqual(share, 0.5, accuracy: 0.1)
                for other in boats where other.number != followed.number { XCTAssertGreaterThan((other.point - mine.point).length, 200) }
            }
            if scene == .gushanFerryEvening {
                XCTAssertFalse(Map3DFerries.sailings(of: ferry, atSecond: Double(world.clock.now.seconds)) { _ in true }.isEmpty)
            }
        }
    }

    /// Decision 585 PR-3: on the real map, each pier of the two real
    /// ferries stands at the shore as drawn: its shelter on the land, its
    /// boats' berth on the water (run 41906144682 drew Gushan's boat on
    /// land; the base map's water areas alone put its shelter on the water).
    /// With the real buildings the app draws, no building stands over the
    /// berth, the boat's turning circle or the landing (run 41927167376:
    /// Gushan's boat cut through the ferry terminal, which stands on the
    /// water drawn), and the crossing between the berths is open water.
    func testTheRealFerryPiersStandAtTheDrawnShore() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let water = try WaterGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_water.json")))
        let tiles = try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                                options: .alwaysMapped))
        let footprints = try FootprintTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles"),
                                                       options: .alwaysMapped))
        let city = CityTileArea.areas(in: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/city"))
        for shot in [ScreenshotScene.gushanFerry, .tamsuiFerry] {
            let world = shot.make(in: .traditionalChinese, water: water)
            let route = try XCTUnwrap(world.ferryRoutes.first)
            for (index, cell) in route.piers.enumerated() {
                let scene = Map3DScene(world: world, focus: (Double(cell.middle.x), Double(cell.middle.y)), baseMap: tiles, cityTiles: city,
                                       footprints: footprints)
                let line = try XCTUnwrap(Map3DFerries(world: world, scene: scene).lines.first)
                let pier = line.piers[index]
                let drawn = scene.drawnWater(round: pier.origin, radius: 160)
                let shelter = pier.origin - pier.out * 13
                XCTAssertFalse(drawn.isWater(x: shelter.x, z: shelter.z), "\(shot) pier \(index): the shelter on the land")
                XCTAssertFalse(drawn.isBuilt(x: shelter.x, z: shelter.z), "\(shot) pier \(index): the shelter clear of the buildings")
                XCTAssertTrue(drawn.isOpenWater(x: pier.origin.x, z: pier.origin.z), "\(shot) pier \(index): the pontoon on the water")
                XCTAssertTrue(drawn.isOpenWater(x: pier.berth.x, z: pier.berth.z), "\(shot) pier \(index): the berth on the water")
                let swing = (line.boat.length * line.boat.length + line.boat.beam * line.boat.beam).squareRoot() / 2
                for turn in 0..<16 {
                    let angle = Float(turn) * .pi / 8
                    let p = pier.berth + Map3DPoint(cos(angle), 0, sin(angle)) * swing
                    XCTAssertTrue(drawn.isOpenWater(x: p.x, z: p.z), "\(shot) pier \(index): the boat clear of the buildings, \(turn)")
                }
                // And its boats leave toward the other pier over water,
                // not over a quay (run 41919543916).
                let other = route.piers[index == 0 ? 1 : 0].middle
                let to = scene.point(worldX: Double(other.x), worldY: Double(other.y), height: 0)
                let leave = try XCTUnwrap(Map3DPoint(to.x - pier.berth.x, 0, to.z - pier.berth.z).normalized)
                for s in stride(from: Float(0), through: Map3DFerries.clearWay, by: 4) {
                    let p = pier.berth + leave * s
                    XCTAssertTrue(drawn.isOpenWater(x: p.x, z: p.z), "\(shot) pier \(index): water \(s) m out")
                }
            }
            // The straight crossing between the berths over open water.
            let scene = Map3DScene(world: world, focus: (Double(route.piers[0].middle.x), Double(route.piers[0].middle.y)), baseMap: tiles,
                                   cityTiles: city, footprints: footprints)
            let piers = try XCTUnwrap(Map3DFerries(world: world, scene: scene).lines.first).piers
            let (a, b) = (piers[0].berth, piers[1].berth)
            let drawn = scene.drawnWater(round: a, radius: (b - a).length + 20)
            for s in stride(from: Float(0), through: 1, by: 4 / (b - a).length) {
                let p = a + (b - a) * s
                XCTAssertTrue(drawn.isOpenWater(x: p.x, z: p.z), "\(shot): the crossing over water \(s)")
            }
        }
    }

    /// Decision 580 (FOLLOWBUS): the follow-a-bus scene has a feeder route
    /// with buses out at half past nine, and following its route follows one.
    func testTheFollowBusSceneHasABusOutToFollow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        await launcher.openScreenshotScene(.followBus).value
        let session = try XCTUnwrap(launcher.session, "the launcher plays the scene")
        XCTAssertEqual(session.world.clock.now.seconds, ScreenshotScene.followBusRunSeconds)
        XCTAssertEqual(session.world.clock.speed, .paused)
        let route = try XCTUnwrap(session.world.busRoutes.last, "the scene's route")
        XCTAssertGreaterThan(route.buses, 0)
        XCTAssertTrue(session.hasBusToFollow(onRoute: route.id))
        session.followBus(onRoute: route.id)
        XCTAssertNotNil(session.followedBus)
    }

    /// Decision 506 續二: the expansion scene, on its fourth morning: West
    /// expanded once (its mark beside its name), and Central past the
    /// people its first expansion needs but full on three of the last seven
    /// days, so its card says how many full days it still wants.
    func testTheExpansionSceneShowsAMarkAndACardShortOfFullDays() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        await launcher.openScreenshotScene(.expansion).value
        let world = try XCTUnwrap(launcher.session?.world, "the launcher plays the scene")
        XCTAssertEqual(world.clock.speed, .paused)
        XCTAssertEqual(world.clock.now, GameTime(seconds: ScreenshotScene.expansionRunSeconds))
        XCTAssertEqual(world.stations.map(\.expansion), [.concourse, nil, nil, nil, nil])
        let central = world.stations[1]
        XCTAssertEqual(central.name, "中央")
        let card = try XCTUnwrap(StationExpansionCard(station: central.id, in: world))
        let offer = try XCTUnwrap(card.offer)
        XCTAssertTrue(offer.open, "past the people a day it needs: \(card.people)")
        XCTAssertFalse(offer.full)
        XCTAssertTrue((1...3).contains(card.fullDays), "full on \(card.fullDays) days")
        XCTAssertEqual(card.offerText(in: .traditionalChinese), "最近 7 天裡要有 4 天客滿、有旅客進不來，才能擴建（目前 \(card.fullDays) 天）。")
    }

    /// The depots scene: the demo map with two depots, Line 1 keeping its
    /// trains at the west one, so the line panel lists both, nearest first,
    /// and ticks the west one.
    func testTheDepotsSceneGivesLineOneTwoDepotsToTick() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        await launcher.openScreenshotScene(.depots).value
        let session = try XCTUnwrap(launcher.session, "the launcher plays the scene")
        XCTAssertEqual(session.world.clock.speed, .paused)
        let depots = session.world.stations.filter(\.isDepot)
        XCTAssertEqual(depots.map(\.name), ["西機廠", "東機廠"])
        let line = try XCTUnwrap(session.world.lines.first)
        XCTAssertEqual(line.depots, [depots[0].id])
        session.selectLine(line.id)
        let row = try XCTUnwrap(session.selectedLineDepotRow)
        XCTAssertEqual(row.choices.map(\.name), ["西機廠", "東機廠"])
        XCTAssertEqual(row.choices.map(\.isChosen), [true, false])
        XCTAssertTrue(session.world.lines.allSatisfy { !$0.assignedTrains.isEmpty }, "the demo's lines still run")
    }

    /// Decision 514: the zoning scene shows every outlook the zoning layer
    /// marks.
    func testTheZoningSceneShowsEveryOutlook() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        await launcher.openScreenshotScene(.zoning).value
        let world = try XCTUnwrap(launcher.session?.world, "the launcher plays the scene")
        XCTAssertEqual(world.clock.speed, .paused)
        let counts = ZoningOutlook(world: world).counts(in: world)
        for outlook in ZoneOutlook.allCases {
            XCTAssertGreaterThan(counts[outlook] ?? 0, 0, "\(outlook) shows")
        }

        // Decision 522: the drag held for its screenshot shows cells in
        // reach and grey ones past it, zoning the use the city wants most.
        let session = try XCTUnwrap(launcher.session)
        session.holdScreenshotZoningDrag()
        XCTAssertTrue(session.isChosen(.zoning))
        XCTAssertEqual(session.zoningZone, session.suggestedZoningZone)
        let drag = try XCTUnwrap(session.zoneDrag)
        let overlay = try XCTUnwrap(session.buildingOverlay)
        let grey = session.cellsOutOfReach(in: drag).reduce(0) { $0 + $1.count }
        XCTAssertFalse(overlay.zoneDragOutOfReach.isEmpty)
        XCTAssertGreaterThan(grey, 0)
        XCTAssertLessThan(grey, drag.count, "some in reach")
        XCTAssertEqual(session.world.zones, world.zones, "nothing zoned")
    }

    /// Decision 533: the commute scene's first station brings students
    /// and patients on its second morning, a school day.
    func testTheCommuteSceneBringsStudentsAndPatients() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        await launcher.openScreenshotScene(.commute).value
        let world = try XCTUnwrap(launcher.session?.world, "the launcher plays the scene")
        XCTAssertEqual(world.clock.speed, .paused)
        XCTAssertEqual(world.clock.now, GameTime(seconds: 31 * 3_600 + 30 * 60))
        let station = try XCTUnwrap(world.stations.first)
        let riders = world.stationRidership(of: station.id).civic
        XCTAssertEqual(riders.map(\.kind), [.school, .hospital], "\(riders)")
        XCTAssertTrue(riders.allSatisfy { $0.riders > 0 })
    }
}
