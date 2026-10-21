import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 328: what a tick and a frame cost as a real-world game grows
/// (PLAYER_FEEDBACK 78.1 and 79.1: with some thirty stations built, the 2D
/// map ran at about 5 fps and 60× reached only 29×, on an iPhone 15 Pro
/// Max). Plays a game on the real map round Miaoli, three lines of eleven
/// stations each, for `LONG_GAME_REPORT` days (1 to 1,000), and at the
/// days in ``checkpoints`` times GameCore's tick at 60× and 1,200×, what
/// the session does after it, and what the map reads of the session on
/// every render. Run on request:
///
///     LONG_GAME_REPORT=730 swift test -c release -Xswiftc -enable-testing \
///       --filter LongGameCostReportTests
@MainActor
final class LongGameCostReportTests: XCTestCase {
    static let checkpoints: [Int] = [1, 30, 180, 365, 730, 1_000]

    func testWhatATickAndAFrameCostAsTheGameGrows() throws {
        guard let value = ProcessInfo.processInfo.environment["LONG_GAME_REPORT"] else {
            throw XCTSkip("set LONG_GAME_REPORT=<days> to time a long real-world game")
        }
        let days = try XCTUnwrap(Int(value).flatMap { (1...1_000).contains($0) ? $0 : nil }, "LONG_GAME_REPORT is 1 to 1,000 days")
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let environment = ProcessInfo.processInfo.environment
        var world = try environment["LONG_GAME_LOAD"].map { try SaveLibrary.decode(Data(contentsOf: URL(fileURLWithPath: $0))) } ?? Self.miaoli(data: data)
        world.setSpeed(.fast)
        var rows: [String] = []
        var played = Int(world.clock.now.seconds / GameTime.secondsPerDay)
        for checkpoint in Self.checkpoints where checkpoint <= days {
            while played < checkpoint {
                try world.advance(ticks: 144)
                played += 1
            }
            rows.append(contentsOf: try Self.measure(world, day: played, data: data))
            FileHandle.standardError.write(Data("day \(played) measured\n".utf8))
        }
        if let path = environment["LONG_GAME_SAVE"] {
            try SaveLibrary.encode(world, at: Date(timeIntervalSince1970: 0)).write(to: URL(fileURLWithPath: path))
        }
        print((["| Day | What | ms |", "| --: | --- | --: |"] + rows).joined(separator: "\n"))
    }

    /// What the session's step after a tick spends, piece by piece, on the
    /// game saved in `LONG_GAME_LOAD`.
    func testWhatTheStepAfterATickSpends() async throws {
        guard let path = ProcessInfo.processInfo.environment["LONG_GAME_LOAD"] else {
            throw XCTSkip("set LONG_GAME_LOAD=<save> to split the step after a tick")
        }
        var world = try SaveLibrary.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        world.setSpeed(.x60)
        let session = GameSession(world: world)
        session.advance(realElapsed: GameSession.tickInterval)
        let clock = ContinuousClock()
        let before = session.world
        let after = try GameSession.advanced(before, by: 1, listening: false).world
        let count = 20
        var trips = TripLoads()
        _ = trips.step(from: before, to: after)
        var use = PlatformUse()
        use.record(before)
        let pieces: [(String, () -> Void)] = [
            ("StationFare.taken", { _ = StationFare.taken(from: before, to: after) }),
            ("TripLoads.step", { var copy = trips; _ = copy.step(from: before, to: after) }),
            ("GoalPulse.met", { _ = GoalPulse.met(from: before, to: after, in: .english) }),
            ("newlyMetNextSteps", { _ = session.newlyMetNextSteps(since: before) }),
            ("PlatformUse.record", { var copy = use; copy.record(after) }),
            ("noteIncome", { session.noteIncome(since: before.accounts.entries.last) }),
            ("observeNews", { session.observeNews(closedBefore: before.accounts.years.last?.year) }),
            ("SoundCue.arrivals", { _ = SoundCue.arrivals(in: after) }),
        ]
        var rows = ["| Piece | ms |", "| --- | --: |"]
        // The game loop's own way: the tick worked out off the main actor,
        // then put in place on it; the longest of each too.
        var worked = Duration.zero, finished = Duration.zero, longestWork = Duration.zero, longestFinish = Duration.zero
        let loopTicks = 200
        for _ in 0..<loopTicks {
            guard let tick = session.beginLoopTick() else { break }
            let start = clock.now
            let outcome = await tick.work()
            let work = clock.now - start
            let finish = clock.measure { session.finish(tick, with: outcome) }
            worked += work
            finished += finish
            longestWork = max(longestWork, work)
            longestFinish = max(longestFinish, finish)
        }
        rows.append("| loop tick worked out, off the main actor (longest) | \(Self.ms(worked, per: loopTicks)) (\(Self.ms(longestWork))) |")
        rows.append("| loop tick put in place on the main actor (longest) | \(Self.ms(finished, per: loopTicks)) (\(Self.ms(longestFinish))) |")
        for (label, piece) in pieces {
            let spent = clock.measure { for _ in 0..<count { piece() } }
            rows.append("| \(label) | \(Self.ms(spent, per: count)) |")
        }
        print(rows.joined(separator: "\n"))
    }

    /// A new game on the real map round Miaoli station, as the app starts
    /// one (unlimited funds), with three straight lines of eleven stations
    /// 700 m apart, 2 km from each other, and the land read round them.
    static func miaoli(data: RealWorldData) throws -> GameWorld {
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
        for line in 0..<3 {
            let y = minY + length / 2 + Int64(line - 1) * 2_000 * metre
            let points = (0..<11).map { PlanPoint(x: minX + 1_200 * metre + Int64($0) * 700 * metre, y: y) }
            world = try LineBuilder.line(through: points, in: world)
        }
        GameSession.readLand(roundStationsOf: &world, population: data.population, places: data.places, water: data.water)
        return world
    }

    static func ms(_ duration: Duration, per count: Int = 1) -> String {
        String(format: "%.3f", (Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15) / Double(count))
    }

    static func measure(_ world: GameWorld, day: Int, data: RealWorldData) throws -> [String] {
        let clock = ContinuousClock()
        var rows: [String] = []
        let waiting = world.passengers.reduce(Int64(0)) { $0 + $1.waiting.reduce(0) { $0 + $1.count } }
        rows.append("| \(day) | stations \(world.stations.count), trains \(world.trains.count), passenger records \(world.passengers.count), waiting \(waiting), ledger entries \(world.accounts.entries.count), days \(world.accounts.days.count), land cells \(world.land.cells.count) | |")
        let ticks = 40
        for speed in [GameSpeed.x60, .double] {
            var stepped = world
            stepped.setSpeed(speed)
            let spent = try clock.measure {
                for _ in 0..<ticks { stepped = try GameSession.advanced(stepped, by: 1, listening: false).world }
            }
            rows.append("| \(day) | GameCore tick at \(speed) | \(ms(spent, per: ticks)) |")
            let reading = clock.measure { for _ in 0..<5 { _ = TrafficReading(world: stepped, train: nil, in: .english, previous: nil) } }
            rows.append("| \(day) | TrafficReading at \(speed) | \(ms(reading, per: 5)) |")
        }
        // The session: GameCore's tick and what follows it on the main actor.
        let session = GameSession(world: world)
        session.population = data.population
        session.railways = data.railways
        session.setSpeed(.x60)
        session.advance(realElapsed: GameSession.tickInterval)
        var core = Duration.zero, total = Duration.zero
        for _ in 0..<ticks {
            let before = session.world
            core += try clock.measure { _ = try GameSession.advanced(before, by: 1, listening: false) }
            total += clock.measure { session.advance(realElapsed: GameSession.tickInterval) }
        }
        rows.append("| \(day) | session tick at x60, after the step | \(ms(total - core, per: ticks)) |")
        // What the map reads of the session on a render after a tick.
        let now = session.world
        var next = now
        try next.advance(ticks: 1)
        let renders = 20
        let reads: [(String, () -> Void)] = [
            ("MapLayers.waitingPassengerCounts", { _ = MapLayers.waitingPassengerCounts(in: now) }),
            ("StationLabels(world:)", { _ = StationLabels(world: now) }),
            ("LineMap(world:)", { _ = LineMap(world: now) }),
            ("LineBadge.codes", { _ = LineBadge.codes(for: now.lines) }),
            ("depotRuns()", { _ = now.depotRuns() }),
            ("TrainMotion(world:)", { _ = TrainMotion(world: now, time: 0) }),
            ("MapWeather(world:)", { _ = MapWeather(world: now) }),
            ("RidershipInputs(world:)", { _ = RidershipInputs(world: now) }),
            ("stations == after a tick", { _ = now.stations == next.stations }),
            ("trains == after a tick", { _ = now.trains == next.trains }),
            ("land == after a tick", { _ = now.land == next.land }),
            ("network == after a tick", { _ = now.network == next.network }),
            ("lines == after a tick", { _ = now.lines == next.lines }),
            ("session.trafficOverlay", { _ = session.trafficOverlay }),
            ("session.viewingSpeed", { _ = session.viewingSpeed }),
            ("session.nextSteps", { _ = session.nextSteps }),
            ("session.situationAlerts", { _ = session.situationAlerts }),
            ("session.cityRequestMarks", { _ = session.cityRequestMarks }),
            ("session.mapStopSuggestion", { _ = session.mapStopSuggestion }),
            ("session.realStationSuggestions", { _ = session.realStationSuggestions }),
            ("session.offersRealStations", { _ = session.offersRealStations }),
            ("session.buyableRealLines", { _ = session.buyableRealLines }),
            ("session.hasCityRequestOffers", { _ = session.hasCityRequestOffers }),
            ("session.cityRequestsButtonValue", { _ = session.cityRequestsButtonValue }),
            ("session.worstLosingLine", { _ = session.worstLosingLine }),
            ("session.stationMasterRefreshKey", { _ = session.stationMasterRefreshKey }),
            ("session.offersCoverageShortcut", { _ = session.offersCoverageShortcut }),
            ("session.mapExpansionOverlay", { _ = session.mapExpansionOverlay }),
            ("session.showsMapExpansionButton", { _ = session.showsMapExpansionButton }),
            ("session.isFreePlayLocked", { _ = session.isFreePlayLocked }),
            ("session.runsLinesForThePlayer", { _ = session.runsLinesForThePlayer }),
            ("session.selectionText()", { _ = session.selectionText() }),
            ("session.lineMenuChoices", { _ = session.lineMenuChoices }),
            ("session.trainMenuChoices", { _ = session.trainMenuChoices }),
            ("world.todaySymbol()", { _ = now.todaySymbol() }),
            ("world.forecast()", { _ = now.forecast() }),
        ]
        for (label, read) in reads {
            let spent = clock.measure { for _ in 0..<renders { read() } }
            rows.append("| \(day) | \(label) | \(ms(spent, per: renders)) |")
        }
        return rows
    }
}
