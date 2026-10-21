import GameCore
import GamePresentation
import XCTest

/// The locks on the tiles not bought yet (ARCHITECTURE decision 167,
/// later): a new blank game of 5 × 5 tiles owning the middle one, so the
/// four tiles beside it are for sale and carry a lock; a tap on one opens
/// its card.
@MainActor
final class MapLockTests: XCTestCase {
    private let length = Double(MapExpansion.tileLength)
    private let viewport = ScreenSize(width: 400, height: 400)

    /// A camera on the middle three tiles each way.
    private func camera(_ world: GameWorld) -> PlanCamera {
        PlanCamera(bounds: world.bounds, viewport: viewport, showing: WorldRegion(minX: length, minY: length, maxX: 4 * length, maxY: 4 * length))
    }

    private func middle(of tile: MapTile, _ camera: PlanCamera) -> ScreenPoint {
        camera.screenPoint(worldX: (Double(tile.column) + 0.5) * length, worldY: (Double(tile.row) + 0.5) * length)
    }

    func testTheTilesForSaleCarryALockInTheirMiddle() {
        let session = GameSession(world: GameWorld.newGame(eventSeed: 9, buysMap: true), language: .english)
        XCTAssertTrue(session.showsMapLocks)
        let camera = camera(session.world)
        let locks = session.mapLocks(on: camera, viewport: viewport)
        XCTAssertEqual(locks.map(\.tile), session.world.mapTilesForSale())
        XCTAssertEqual(locks.count, 4)
        for lock in locks {
            XCTAssertEqual(lock.at.x, middle(of: lock.tile, camera).x, accuracy: 0.001)
            XCTAssertEqual(lock.at.y, middle(of: lock.tile, camera).y, accuracy: 0.001)
            // Management: shut until the best day unlocks the tile.
            XCTAssertFalse(lock.isUnlocked)
        }
        // The corner tiles, not beside the land owned, are only shaded.
        XCTAssertFalse(locks.contains { $0.tile == MapTile(row: 1, column: 1) })
    }

    func testFreePlaysLocksAreOpen() {
        var world = GameWorld.newGame(eventSeed: 9, buysMap: true)
        world.setEconomyMode(.free)
        let session = GameSession(world: world, language: .english)
        let locks = session.mapLocks(on: camera(world), viewport: viewport)
        XCTAssertEqual(locks.count, 4)
        XCTAssertTrue(locks.allSatisfy(\.isUnlocked))
    }

    /// A tile zoomed out to a few points, or a sliver under the controls,
    /// gets no lock; a tile half under them gets its lock in the part in
    /// view.
    func testALockNeedsRoomInView() {
        let session = GameSession(world: GameWorld.newGame(eventSeed: 9, buysMap: true), language: .english)
        let whole = PlanCamera(bounds: session.world.bounds, viewport: ScreenSize(width: 120, height: 120))
        XCTAssertEqual(session.mapLocks(on: whole, viewport: ScreenSize(width: 120, height: 120)), [])

        let camera = camera(session.world)
        let east = MapTile(row: 2, column: 3), north = MapTile(row: 1, column: 2)
        let eastEdge = camera.screenPoint(worldX: 3 * length, worldY: 0).x
        let northTop = camera.screenPoint(worldX: 0, worldY: length).y
        let northBottom = camera.screenPoint(worldX: 0, worldY: 2 * length).y
        let insets = ScreenInsets(top: (northTop + northBottom) / 2, trailing: viewport.width - eastEdge - 20)
        let locks = session.mapLocks(on: camera, viewport: viewport, clearOf: insets)
        XCTAssertFalse(locks.contains { $0.tile == east })
        let northLock = try? XCTUnwrap(locks.first { $0.tile == north })
        XCTAssertEqual(northLock?.at.y ?? 0, (insets.top + northBottom) / 2, accuracy: 0.001)
        XCTAssertEqual(locks.count, 3)
    }

    func testTappingALockOpensItsCard() throws {
        let session = GameSession(world: GameWorld.newGame(eventSeed: 9, buysMap: true), language: .english)
        // A tile not for sale opens nothing.
        XCTAssertFalse(session.openMapLock(MapTile(row: 0, column: 0)))
        XCTAssertFalse(session.isChoosingMapTile)

        let east = MapTile(row: 2, column: 3)
        XCTAssertTrue(session.openMapLock(east))
        XCTAssertTrue(session.isChoosingMapTile)
        XCTAssertEqual(session.chosenMapTile, east)
        XCTAssertEqual(try XCTUnwrap(session.chosenMapTileQuote).tile, east)
        XCTAssertNil(session.message)
        // While choosing, the tiles for sale show their prices instead.
        XCTAssertFalse(session.showsMapLocks)
        XCTAssertEqual(session.mapLocks(on: camera(session.world), viewport: viewport), [])
        session.stopChoosingMapTile()
        XCTAssertTrue(session.showsMapLocks)
    }

    func testNoLocksWhileBuildingInTheTutorialOrOnAMapNotBought() {
        let session = GameSession(world: GameWorld.newGame(eventSeed: 9, buysMap: true), language: .english)
        session.selectTool(.network)
        XCTAssertFalse(session.showsMapLocks)
        XCTAssertFalse(session.openMapLock(MapTile(row: 2, column: 3)))
        session.selectTool(.select)
        session.startTutorial()
        XCTAssertFalse(session.showsMapLocks)
        let usual = GameSession(world: GameWorld.newGame(eventSeed: 9), language: .english)
        XCTAssertFalse(usual.showsMapLocks)
        XCTAssertEqual(usual.mapLocks(on: PlanCamera(bounds: usual.world.bounds, viewport: viewport), viewport: viewport), [])
    }

    /// What `MapLockUITests` leans on: from the camera a blank game opens
    /// with, on a phone on its side, the zoom-out button reaches the locks
    /// before it reaches its farthest (run 39545597750 gave up after four).
    func testZoomingOutFromTheOpeningReachesTheLocks() {
        let session = GameSession(world: GameWorld.newGame(eventSeed: 9, buysMap: true), language: .english)
        let phone = ScreenSize(width: 874, height: 402)
        let clear = ScreenInsets(top: 100, leading: 150, bottom: 40, trailing: 140)
        var camera = PlanCamera.opening(
            bounds: session.world.bounds, viewport: phone, showing: WorldRegion.opening(in: session.world), keeping: [], clearOf: clear
        )
        var taps = 0
        while session.mapLocks(on: camera, viewport: phone, clearOf: clear).isEmpty, taps < 12 {
            camera = camera.zoomedOut()
            taps += 1
        }
        XCTAssertFalse(session.mapLocks(on: camera, viewport: phone, clearOf: clear).isEmpty)
        XCTAssertGreaterThan(taps, 4, "The opening is closer than the UI test once thought")
        XCTAssertLessThanOrEqual(taps, 9)
    }
}
