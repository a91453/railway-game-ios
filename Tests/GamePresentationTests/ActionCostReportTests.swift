import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// PLAYER_FEEDBACK 82.1 (iPad, many stations): changing the speed,
/// choosing a building tool and buying a tile of the map stutter. Times
/// each of the three on the session of a real-world game round Miaoli with
/// four lines of eleven stations, played `ACTION_COST_REPORT` days, and
/// what the map reads of the session after each. Run on request:
///
///     ACTION_COST_REPORT=30 swift test -c release -Xswiftc -enable-testing \
///       --filter ActionCostReportTests
@MainActor
final class ActionCostReportTests: XCTestCase {
    func testWhatTheThreeActionsCost() throws {
        guard let value = ProcessInfo.processInfo.environment["ACTION_COST_REPORT"] else {
            throw XCTSkip("set ACTION_COST_REPORT=<days> to time the speed, the building tools and buying a tile")
        }
        let days = try XCTUnwrap(Int(value).flatMap { (0...1_000).contains($0) ? $0 : nil }, "ACTION_COST_REPORT is 0 to 1,000 days")
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        var world = try Self.miaoli(lines: 4, data: data)
        world.setSpeed(.fast)
        for _ in 0..<days { try world.advance(ticks: 144) }
        world.pause()
        let session = GameSession(world: world)
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.coverage = data.coverage
        session.railways = data.railways
        session.setSpeed(.x60)
        session.advance(realElapsed: GameSession.tickInterval)

        let clock = ContinuousClock()
        let waiting = session.world.passengers.reduce(Int64(0)) { $0 + $1.waiting.reduce(0) { $0 + $1.count } }
        var rows = [
            "stations \(session.world.stations.count), lines \(session.world.lines.count), trains \(session.world.trains.count), waiting \(waiting), tiles owned \(session.world.mapExpansion?.owned.count ?? 0)",
            "",
            "| Action | ms |", "| --- | --: |",
        ]
        func time(_ label: String, repeat count: Int = 10, _ action: () -> Void) {
            let spent = clock.measure { for _ in 0..<count { action() } }
            rows.append("| \(label) | \(LongGameCostReportTests.ms(spent, per: count)) |")
        }
        time("setSpeed x60 → fast → x60") {
            session.setSpeed(.fast)
            session.setSpeed(.x60)
        }
        time("pause → resume") {
            session.setSpeed(.paused)
            session.setSpeed(.x60)
        }
        time("selectTool network → select") {
            session.selectTool(.network)
            session.selectTool(.select)
        }
        time("selectTool building → select") {
            session.selectTool(.building)
            session.selectTool(.select)
        }
        session.selectTool(.network)
        time("networkOverlay with the network tool") { _ = session.networkOverlay }
        time("traceableRealLines") { _ = session.traceableRealLines }
        session.selectTool(.building)
        time("buildingOverlay with the building tool") { _ = session.buildingOverlay }
        session.selectTool(.select)
        let tile = try XCTUnwrap(session.world.mapTilesForSale().first)
        let area = session.world.mapArea(of: tile)
        let middle = PlanPoint(x: (area.minX + area.maxX) / 2, y: (area.minY + area.maxY) / 2)
        time("startChoosingMapTile → stopChoosingMapTile") {
            session.startChoosingMapTile()
            session.stopChoosingMapTile()
        }
        session.startChoosingMapTile()
        time("tapMapExpansion") { session.tapMapExpansion(at: middle) }
        time("chosenMapTileQuote") { _ = session.chosenMapTileQuote }
        time("chosenMapTileCaption") { _ = session.chosenMapTileCaption }
        time("mapExpansionOverlay while choosing") { _ = session.mapExpansionOverlay }
        time("buyChosenMapTile → undo", repeat: 3) {
            session.tapMapExpansion(at: middle)
            session.buyChosenMapTile()
            session.undo()
        }
        let start = session.world
        time("GameWorld.buyMapTile on a copy", repeat: 3) {
            var copy = start
            try? copy.buyMapTile(tile)
        }
        var bought = start
        try bought.buyMapTile(tile)
        time("world == the world after the buy") { _ = bought == start }
        time("readLand(roundStationsOf:) with nothing to read") {
            var copy = bought
            GameSession.readLand(roundStationsOf: &copy, population: data.population, places: data.places, water: data.water, coverage: data.coverage)
        }
        // The reading of the tile's land, in its two halves.
        let frame = try XCTUnwrap(RealWorldFrame(world: start))
        let blocks = Set(tile.landBlocks(in: start.bounds)).subtracting(start.landBlocks ?? [])
        let population = try XCTUnwrap(data.population)
        time("the tile's cells, water and slopes (GamePresentation)", repeat: 3) {
            _ = LandImport.cells(in: blocks, population: population, places: data.places, water: data.water, frame: frame, bounds: start.bounds)
            _ = data.water?.cells(frame: frame, bounds: start.bounds, in: blocks)
            _ = data.water?.steepCells(frame: frame, bounds: start.bounds, in: blocks)
        }
        var cells = LandImport.cells(in: blocks, population: population, places: data.places, water: data.water, frame: frame, bounds: start.bounds)
        if let coverage = data.coverage { cells = coverage.covering(cells, frame: frame) }
        let wet = data.water?.cells(frame: frame, bounds: start.bounds, in: blocks) ?? []
        let steep = data.water?.steepCells(frame: frame, bounds: start.bounds, in: blocks) ?? []
        time("the tile's coverage (GamePresentation)", repeat: 3) { _ = data.coverage?.covering(cells, frame: frame) }
        time("GameWorld.expandLand with the tile's land (GameCore)", repeat: 3) {
            var copy = bought
            try? copy.expandLand(blocks.sorted(), cells: cells, water: wet, steep: steep)
        }
        time("newlyMetNextSteps(since:)") { _ = session.newlyMetNextSteps(since: start) }
        time("buyChosenMapTile alone", repeat: 3) {
            session.tapMapExpansion(at: middle)
            session.buyChosenMapTile()
            session.undo()
        }
        var buys = Duration.zero, undos = Duration.zero
        for _ in 0..<3 {
            session.tapMapExpansion(at: middle)
            buys += clock.measure { session.buyChosenMapTile() }
            undos += clock.measure { session.undo() }
        }
        rows.append("| buyChosenMapTile | \(LongGameCostReportTests.ms(buys, per: 3)) |")
        rows.append("| undo of the buy | \(LongGameCostReportTests.ms(undos, per: 3)) |")
        session.stopChoosingMapTile()
        time("readLand(roundStationsOf:) on the world as it is") {
            var copy = start
            GameSession.readLand(roundStationsOf: &copy, population: data.population, places: data.places, water: data.water, coverage: data.coverage)
        }
        let owned = try XCTUnwrap(start.mapExpansion?.owned.first)
        let corner = WorldCoordinate(
            x: Int64(owned.column) * MapExpansion.tileLength + 300 * WorldCoordinate.unitsPerMetre,
            y: Int64(owned.row) * MapExpansion.tileLength + 300 * WorldCoordinate.unitsPerMetre
        )
        time("GameWorld.buildTrackNode on a copy") {
            var copy = start
            _ = try? copy.buildTrackNode(at: corner)
        }
        var built = start
        _ = try built.buildTrackNode(at: corner)
        time("world != the world after a node") { _ = built != start }
        session.selectTool(.network)
        time("performEdit(buildTrackNode) → undo") {
            _ = try? session.performEdit { world throws(GameError) in try world.buildTrackNode(at: corner) }
            session.undo()
        }
        var edits = Duration.zero
        for _ in 0..<10 {
            edits += clock.measure { _ = try? session.performEdit { world throws(GameError) in try world.buildTrackNode(at: corner) } }
            session.undo()
        }
        rows.append("| performEdit(buildTrackNode) | \(LongGameCostReportTests.ms(edits, per: 10)) |")
        time("refreshTransfers()") { session.refreshTransfers() }
        time("noteNextSteps(since:)") { session.noteNextSteps(since: start) }
        time("endFollowIfGone()") { session.endFollowIfGone() }
        time("refreshNightSkipOffer()") { session.refreshNightSkipOffer() }
        time("lookAgainForNightSkip()") { session.lookAgainForNightSkip() }
        time("readLandRoundStations()") { session.readLandRoundStations() }
        // What the map reads of the session the first time after an edit,
        // when what is kept for each command is worked out again.
        rows += ["", "| First read after an edit | ms |", "| --- | --: |"]
        let reads: [(String, () -> Void)] = [
            ("nextSteps", { _ = session.nextSteps }),
            ("trafficOverlay", { _ = session.trafficOverlay }),
            ("situationAlerts", { _ = session.situationAlerts }),
            ("cityRequestMarks", { _ = session.cityRequestMarks }),
            ("mapStopSuggestion", { _ = session.mapStopSuggestion }),
            ("realStationSuggestions", { _ = session.realStationSuggestions }),
            ("offersRealStations", { _ = session.offersRealStations }),
            ("buyableRealLines", { _ = session.buyableRealLines }),
            ("hasCityRequestOffers", { _ = session.hasCityRequestOffers }),
            ("cityRequestsButtonValue", { _ = session.cityRequestsButtonValue }),
            ("worstLosingLine", { _ = session.worstLosingLine }),
            ("stationMasterRefreshKey", { _ = session.stationMasterRefreshKey }),
            ("mapExpansionOverlay", { _ = session.mapExpansionOverlay }),
            ("showsMapExpansionButton", { _ = session.showsMapExpansionButton }),
            ("selectionText()", { _ = session.selectionText() }),
            ("lineMenuChoices", { _ = session.lineMenuChoices }),
            ("trainMenuChoices", { _ = session.trainMenuChoices }),
            ("networkOverlay", { _ = session.networkOverlay }),
            ("MapLayers.waitingPassengerCounts", { _ = MapLayers.waitingPassengerCounts(in: session.world) }),
            ("LineBadge.codes", { _ = LineBadge.codes(for: session.world.lines) }),
            ("depotRuns()", { _ = session.world.depotRuns() }),
        ]
        session.selectTool(.network)
        for (label, read) in reads {
            var spent = Duration.zero
            for _ in 0..<5 {
                _ = try? session.performEdit { world throws(GameError) in try world.buildTrackNode(at: corner) }
                spent += clock.measure { read() }
                session.undo()
            }
            rows.append("| \(label) | \(LongGameCostReportTests.ms(spent, per: 5)) |")
        }
        session.selectTool(.select)
        session.selectTool(.select)
        print(rows.joined(separator: "\n"))
    }

    /// Fifty edits of one track node on the same world, and three readings
    /// of a bought tile's land, for a profiler
    /// (`ACTION_COST_PROFILE=1`).
    func testFiftyEditsForAProfiler() throws {
        guard ProcessInfo.processInfo.environment["ACTION_COST_PROFILE"] != nil else {
            throw XCTSkip("set ACTION_COST_PROFILE=1 to run fifty edits under a profiler")
        }
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let world = try Self.miaoli(lines: 4, data: data)
        let session = GameSession(world: world)
        session.population = data.population
        session.railways = data.railways
        session.selectTool(.network)
        let owned = try XCTUnwrap(world.mapExpansion?.owned.first)
        let corner = WorldCoordinate(
            x: Int64(owned.column) * MapExpansion.tileLength + 300 * WorldCoordinate.unitsPerMetre,
            y: Int64(owned.row) * MapExpansion.tileLength + 300 * WorldCoordinate.unitsPerMetre
        )
        for _ in 0..<50 {
            _ = try? session.performEdit { world throws(GameError) in try world.buildTrackNode(at: corner) }
            session.undo()
        }
        // And the land of a tile bought, read three times.
        var bought = world
        try bought.buyMapTile(try XCTUnwrap(world.mapTilesForSale().first))
        for _ in 0..<3 {
            var copy = bought
            GameSession.readLand(roundStationsOf: &copy, population: data.population, places: data.places, water: data.water, coverage: data.coverage)
        }
    }

    /// ``LongGameCostReportTests/miaoli(data:)`` with `lines` lines.
    static func miaoli(lines: Int, data: RealWorldData) throws -> GameWorld {
        var options = NewGameOptions()
        options.funds = .unlimited
        let anchor = try XCTUnwrap(GeoAnchor(latitude: 245_692_340, longitude: 1_208_222_820))
        var world = GameLauncher.newWorld(
            at: anchor, options: options,
            data: .init(population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: nil)
        )
        let tile = try XCTUnwrap(world.mapExpansion?.owned.first)
        let metre = WorldCoordinate.unitsPerMetre, length = MapExpansion.tileLength
        let minX = Int64(tile.column) * length, minY = Int64(tile.row) * length
        for line in 0..<lines {
            let y = minY + length / 2 + Int64(line - lines / 2) * 1_500 * metre
            let points = (0..<11).map { PlanPoint(x: minX + 1_200 * metre + Int64($0) * 700 * metre, y: y) }
            world = try LineBuilder.line(through: points, in: world)
        }
        GameSession.readLand(roundStationsOf: &world, population: data.population, places: data.places, water: data.water)
        return world
    }
}
