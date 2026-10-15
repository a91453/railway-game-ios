import Foundation
import GameCore
import GamePresentation
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
}
