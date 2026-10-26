import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 424's sequel: the base map's bus roads and the real bus stops
/// round a station are read off the main actor as soon as the bus tool has
/// the station, and a tap gets the same stops, lines and names whether the
/// read is done or not.
@MainActor
final class BusReadAheadTests: XCTestCase {
    private static let taipei = (latitude: 25.0478, longitude: 121.5170)
    private let metre = WorldCoordinate.unitsPerMetre

    /// Taipei with a station a cell north of Taipei Station and another
    /// 3 km east, the land round the first read with its roads, and the
    /// bus tool open. `library` is what the session's real stops are.
    private func game(library: RealBusLibrary? = nil) throws -> (GameSession, PlanPoint, PlanPoint) {
        var world = GameWorld.newWholeTaiwanGame()
        let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)
        let position = frame.worldPosition(latitude: Self.taipei.latitude, longitude: Self.taipei.longitude)
        let taipei = PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()) - Land.cellLength)
        let east = PlanPoint(x: taipei.x + 3_000 * Int64(metre), y: taipei.y)
        try world.buildStation(named: "Taipei", at: taipei)
        try world.buildStation(named: "East", at: east)
        let session = GameSession(world: world)
        try CommandLogReplay.realWorld.install(
            RealWorldDataSet(population: true, places: true, water: true, heights: true, coverage: true, baseMap: true), in: session
        )
        session.readLand(within: WholeTaiwan.landReach, of: taipei)
        session.realBuses = library
        session.selectTool(.bus)
        return (session, taipei, east)
    }

    /// Where a tap puts a stop: road points round `station` the cells know,
    /// at least 300 m apart.
    private func roadTaps(_ session: GameSession, round station: PlanPoint, count: Int) throws -> [PlanPoint] {
        let roads = try XCTUnwrap(session.busRoads)
        let cells = try XCTUnwrap(session.world.roads).cells
        var taps: [PlanPoint] = []
        for (dx, dy) in [(400, -300), (-500, 350), (700, 600), (-300, -700), (900, -100)] {
            let tap = PlanPoint(x: station.x + Int64(dx) * metre, y: station.y + Int64(dy) * metre)
            guard let pin = roads.place(near: tap, within: 40, accepting: { cells.contains(CellPosition(containing: $0)) }) else { continue }
            taps.append(pin)
            if taps.count == count { break }
        }
        XCTAssertEqual(taps.count, count, "road points to tap")
        return taps
    }

    /// A library with a real stop where the road point `pin` is, and one 300 m north.
    private func library(at pin: PlanPoint, in session: GameSession) throws -> RealBusLibrary {
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        let here = frame.coordinate(worldX: Double(pin.x), worldY: Double(pin.y))
        let files = try BusStopLabelsTests.busFiles([("測試站", here.latitude, here.longitude), ("北站", here.latitude + 0.003, here.longitude)])
        return try RealBusLibrary(index: files.index, file: files.file)
    }

    /// Everything the player sees of the draft, but for the identity of the real stops.
    private struct Seen: Equatable {
        let draft: BusRouteDraft
        let path: [PlanPoint]
        let preview: BusRoutePreview?
        let overlay: BusMapOverlay.Draft?
        let realStops: [RealBusStops.Stop]?
    }

    private func seen(_ session: GameSession) -> Seen {
        let overlay = session.busMapOverlay
        return Seen(
            draft: session.busDraft, path: session.busDraftPath, preview: session.busPreview,
            overlay: overlay?.draft, realStops: overlay?.realStops?.stops
        )
    }

    // MARK: - Read once the station is picked

    func testTheStopsAndRoadsRoundAStationAreReadOnceItIsPicked() async throws {
        let (probe, taipei, _) = try game()
        let tap = try roadTaps(probe, round: taipei, count: 1)[0]
        let (session, station, _) = try game(library: library(at: tap, in: probe))
        XCTAssertNil(session.busReadAhead, "nothing is read before a station is picked")
        XCTAssertEqual(session.realBusStopsMemo.count, 0)

        session.tapBusTool(at: station, reach: Land.cellLength)
        XCTAssertNotNil(session.busDraft.station)
        let started = try XCTUnwrap(session.busReadAhead)
        XCTAssertEqual(started.station, station)
        await started.task.value

        let stops = try XCTUnwrap(session.realBusStopsMemo[station], "the real stops are in the memo")
        XCTAssertEqual(stops.stops.map(\.name).sorted(), ["北站", "測試站"].sorted())
        let kept = try XCTUnwrap(session.busRoads).kept
        XCTAssertGreaterThanOrEqual(kept.regions, 1, "the network round the station is built")
        XCTAssertGreaterThan(kept.tiles, 12, "the tiles round it are read")

        // Asking again hands out the memo, and picking the same station again starts nothing.
        XCTAssertTrue(session.realBusStops(around: station) === stops)
        session.refreshBusPreview()
        XCTAssertEqual(session.busReadAhead?.serial, started.serial)
    }

    func testAnEditedRouteAndANewRouteFromTheStationPanelStartTheReadToo() async throws {
        let (session, station, _) = try game()
        let id = try XCTUnwrap(session.world.station(near: station, within: Land.cellLength)).id
        session.startBusRoute(from: id)
        let started = try XCTUnwrap(session.busReadAhead)
        XCTAssertEqual(started.station, station)
        await started.task.value
        XCTAssertEqual(session.busRoads?.kept.regions, 1)
    }

    func testTheSameTapsGiveTheSameResultWhetherTheReadIsDoneOrNot() async throws {
        let (probe, taipei, _) = try game()
        let taps = try roadTaps(probe, round: taipei, count: 3)
        let library = try library(at: taps[0], in: probe)

        /// The taps played on a session whose read ahead is `done`, waited
        /// for, or `never` (the main actor does everything).
        func play(waiting: Bool) async throws -> [Seen] {
            let (session, station, _) = try game(library: library)
            if !waiting {
                // A read already "started" for the station: none is started.
                session.busReadAhead = BusReadAhead(station: station, serial: -1, task: Task {})
            }
            var states: [Seen] = []
            session.tapBusTool(at: station, reach: Land.cellLength)
            if waiting { await session.busReadAhead?.task.value }
            XCTAssertEqual(session.realBusStopsMemo[station] != nil, waiting)
            states.append(seen(session))
            for tap in taps {
                session.tapBusTool(at: PlanPoint(x: tap.x + 8 * Int64(metre), y: tap.y - 6 * Int64(metre)), reach: Land.cellLength)
                XCTAssertNil(session.message, session.message?.text ?? "")
                states.append(seen(session))
            }
            return states
        }
        let done = try await play(waiting: true)
        let notDone = try await play(waiting: false)
        XCTAssertEqual(done.count, 4)
        XCTAssertEqual(done.last?.draft.stops.count, 3)
        XCTAssertEqual(done.last?.overlay?.labels.first?.name, "測試站", "the real stop's name")
        XCTAssertEqual(done, notDone)
    }

    // MARK: - A read that was replaced

    func testAStationPickedAfterwardsKeepsTheEarlierStationsResultOut() async throws {
        let (probe, taipei, _) = try game()
        let library = try library(at: try roadTaps(probe, round: taipei, count: 1)[0], in: probe)
        let (session, first, second) = try game(library: library)
        session.tapBusTool(at: first, reach: Land.cellLength)
        let earlier = try XCTUnwrap(session.busReadAhead)
        // The main actor does not yield before the other station is
        // picked, so the earlier read finishes after it.
        session.startBusRoute(from: try XCTUnwrap(session.world.station(near: second, within: Land.cellLength)).id)
        let later = try XCTUnwrap(session.busReadAhead)
        XCTAssertEqual(later.station, second)
        XCTAssertNotEqual(later.serial, earlier.serial)
        await earlier.task.value
        await later.task.value
        XCTAssertNil(session.realBusStopsMemo[first], "the earlier station's result is thrown away")
        XCTAssertNotNil(session.realBusStopsMemo[second])
        XCTAssertEqual(session.busReadAhead?.serial, later.serial)
    }

    func testNewRealStopsOrANewBaseMapThrowTheReadInProgressAway() async throws {
        let (probe, taipei, _) = try game()
        let library = try library(at: try roadTaps(probe, round: taipei, count: 1)[0], in: probe)
        let (session, station, _) = try game(library: library)
        session.tapBusTool(at: station, reach: Land.cellLength)
        let started = try XCTUnwrap(session.busReadAhead)
        session.realBuses = nil
        XCTAssertNil(session.busReadAhead)
        await started.task.value
        XCTAssertEqual(session.realBusStopsMemo.count, 0, "the stops it read are not kept")

        // The same for a base map that is replaced.
        session.realBuses = library
        session.refreshBusPreview()
        let again = try XCTUnwrap(session.busReadAhead)
        let baseMap = session.baseMap
        session.baseMap = baseMap
        XCTAssertNil(session.busReadAhead)
        await again.task.value
        XCTAssertEqual(session.realBusStopsMemo.count, 0)
    }

    // MARK: - Where nothing is read

    func testAMapWithoutABaseMapReadsNothing() throws {
        var world = GameWorld(bounds: try WorldBounds(width: 64 * Land.cellLength, height: 16 * Land.cellLength), economy: GameEconomy(balance: 100_000_000, costs: testCosts))
        let station = try world.buildStation(named: "A", at: CellPosition(row: 8, column: 5).middle)
        world.enableRoads()
        try world.setRoads((5...30).map { CellPosition(row: 8, column: $0) }, in: [LandBlock(row: 0, column: 0), LandBlock(row: 0, column: 1)])
        let session = GameSession(world: world)
        session.selectTool(.bus)
        session.startBusRoute(from: station.id)
        XCTAssertNil(session.busReadAhead)
    }
}
