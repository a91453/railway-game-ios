import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Player feedback of 0.6.0 (152), 2026-11-27 (iPhone 17): a real map
/// built from Pingtung to Tainan "runs slowly", and with the 2D map that
/// large the game no longer reaches 60× and below, taps answer late and
/// the picture stutters. A game on the real map round Pingtung, its tiles
/// bought up to Tainan, with Taiwan Railway's stations from Pingtung to
/// Tainan as one line and Kaohsiung Metro's red line as a second, played
/// `SOUTH_MAP_REPORT` days; then what a tick costs at 60× and 600× and
/// what the 2D map reads and redraws, as ``LongGameCostReportTests`` and
/// ``MapFrameCostReportTests`` measure them. It asserts nothing and runs
/// only on request:
///
///     SOUTH_MAP_REPORT=3 swift test -c release -Xswiftc -enable-testing \
///       --filter SouthernMapCostReportTests
///
/// `SOUTH_MAP_SAVE=<path>` also writes the game it played.
@MainActor
final class SouthernMapCostReportTests: XCTestCase {
    /// Taiwan Railway from Pingtung to Tainan (the West Coast and Pingtung
    /// lines), in order.
    static let traStations = [
        "屏東", "六塊厝", "九曲堂", "後庄", "鳳山", "正義", "科工館", "民族", "高雄", "三塊厝", "鼓山", "內惟", "美術館",
        "左營(舊城)", "新左營", "楠梓", "橋頭", "岡山", "路竹", "大湖", "中洲", "保安", "仁德", "臺南",
    ]

    func testWhatASouthernMapCosts() async throws {
        guard let value = ProcessInfo.processInfo.environment["SOUTH_MAP_REPORT"] else {
            throw XCTSkip("set SOUTH_MAP_REPORT=<days> to time a real map from Pingtung to Tainan")
        }
        let days = try XCTUnwrap(Int(value).flatMap { (0...365).contains($0) ? $0 : nil }, "SOUTH_MAP_REPORT is 0 to 365 days")
        let data = RealWorldData.load(pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        let clock = ContinuousClock()
        var world = try Self.southernMap(data: data)
        FileHandle.standardError.write(Data("built: stations \(world.stations.count), tiles \(world.mapExpansion?.owned.count ?? 0), land cells \(world.land.cells.count)\n".utf8))
        world.setSpeed(.fast)
        let played = try clock.measure { for _ in 0..<days { try world.advance(ticks: 144) } }
        FileHandle.standardError.write(Data("played \(days) days in \(LongGameCostReportTests.ms(played)) ms\n".utf8))
        if let path = ProcessInfo.processInfo.environment["SOUTH_MAP_SAVE"] {
            try SaveLibrary.encode(world, at: Date(timeIntervalSince1970: 0)).write(to: URL(fileURLWithPath: path))
        }
        var rows = ["| Day | What | ms |", "| --: | --- | --: |"]
        rows += try LongGameCostReportTests.measure(world, day: days, data: data)
        // The game loop's own way at 60×: worked out off the main actor,
        // put in place on it.
        let session = GameSession(world: world, language: .traditionalChinese)
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.coverage = data.coverage
        session.railways = data.railways
        session.setSpeed(.x60)
        session.advance(realElapsed: GameSession.tickInterval)
        var worked = Duration.zero, finished = Duration.zero, longestWork = Duration.zero, longestFinish = Duration.zero
        let loopTicks = 100
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
        rows.append("| \(days) | loop tick at x60 off the main actor, mean (longest) | \(LongGameCostReportTests.ms(worked, per: loopTicks)) (\(LongGameCostReportTests.ms(longestWork))) |")
        rows.append("| \(days) | loop tick at x60 on the main actor, mean (longest) | \(LongGameCostReportTests.ms(finished, per: loopTicks)) (\(LongGameCostReportTests.ms(longestFinish))) |")
        // What the 2D map redraws a second at 60×.
        let count = try await MapRedrawCount.run(session, ticks: 100)
        rows += ["", "| Canvas at x60 | redrawn a second |", "| --- | --: |"]
        rows += MapRedrawCount.Canvas.allCases.map { "| \($0.rawValue) | \(count.perSecond($0, over: 10)) |" }
        rows += ["", "Inputs that changed (of 100 ticks at x60):"]
        rows += count.reasons.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value)" }
        rows += ["", "The railway canvas, the whole map in view:", ""]
        rows += MapFrameCostReportTests.railwayPoints(of: session.world)
        print(rows.joined(separator: "\n"))
    }

    /// A new real-world game at Pingtung station (unlimited funds), with
    /// the tiles bought that Taiwan Railway's stations to Tainan and
    /// Kaohsiung Metro's red line stand on, one line along each, and the
    /// land read round their stations.
    static func southernMap(data: RealWorldData) throws -> GameWorld {
        // ``LineBuilder/line(through:in:carLength:)`` through as many of
        // `points` in order as its straight edges can be laid through
        // (a stop whose edge would cross or touch the track is left out).
        func line(through points: [PlanPoint], in world: GameWorld, named name: String) throws -> GameWorld {
            var kept: [PlanPoint] = []
            for point in points {
                let trial = kept + [point]
                if trial.count < 2 || (try? LineBuilder.line(through: trial, in: world)) != nil {
                    kept = trial
                } else {
                    FileHandle.standardError.write(Data("\(name): a stop left out\n".utf8))
                }
            }
            FileHandle.standardError.write(Data("\(name): \(kept.count) of \(points.count) stops\n".utf8))
            return try LineBuilder.line(through: kept, in: world)
        }
        let railways = try XCTUnwrap(data.railways)
        func station(_ system: String, _ name: String) throws -> RealRailways.Station {
            try XCTUnwrap(railways.stations.first { $0.system.id == system && $0.chinese == name }, "\(system) \(name)")
        }
        let pingtung = try station("tra_sched", "屏東")
        var options = NewGameOptions()
        options.funds = .unlimited
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: pingtung.coordinate.latitude, longitudeDegrees: pingtung.coordinate.longitude))
        var world = GameLauncher.newWorld(
            at: anchor, options: options,
            data: .init(population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: nil)
        )
        let frame = RealWorldFrame(anchor: try XCTUnwrap(world.geoAnchor), bounds: world.bounds)
        func point(_ station: RealRailways.Station) -> PlanPoint {
            let position = frame.worldPosition(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude)
            return PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
        }
        let tra = traStations.compactMap { name -> PlanPoint? in
            guard let found = railways.stations.first(where: { $0.system.id == "tra_sched" && $0.chinese == name }) else {
                FileHandle.standardError.write(Data("no station \(name)\n".utf8))
                return nil
            }
            return point(found)
        }
        let red = railways.stations.filter { $0.system.id == "krtc" && $0.palette == railways.stations.first(where: { $0.system.id == "krtc" && $0.chinese == "美麗島" })?.palette }
        // Kaohsiung Metro's red line, south to north.
        let redPoints = red.sorted { $0.coordinate.latitude < $1.coordinate.latitude }.map(point)
        // Every tile in the box round them, bought outwards from the first.
        let all = tra + redPoints
        let tiles = all.map(MapExpansion.tile(at:))
        let rows = (tiles.map(\.row).min()!...tiles.map(\.row).max()!), columns = (tiles.map(\.column).min()!...tiles.map(\.column).max()!)
        var wanted = Set(rows.flatMap { row in columns.map { MapTile(row: row, column: $0) } })
        wanted.subtract(world.mapExpansion?.owned ?? [])
        while !wanted.isEmpty {
            let owned = world.mapExpansion?.owned ?? []
            guard let next = wanted.sorted().first(where: { tile in tile.neighbours.contains(where: owned.contains) }) else { break }
            try world.buyMapTile(next, passingMilestone: true)
            wanted.remove(next)
        }
        world = try line(through: tra, in: world, named: "TRA")
        if let red = try? line(through: redPoints, in: world, named: "red line") { world = red }
        GameSession.readLand(roundStationsOf: &world, population: data.population, places: data.places, water: data.water)
        return world
    }

    /// The same, on the whole of Taiwan with the real lines of the south
    /// bought (`SOUTH_BUY`, a comma-separated list of parts of the lines'
    /// ids; the Pingtung line, the West Coast line's southern half, the
    /// Shalun line and Kaohsiung Metro by default), played to
    /// `SOUTH_BOUGHT_REPORT` (the minute of the first day, 420 for 07:00),
    /// then timed at 60×:
    ///
    ///     SOUTH_BOUGHT_REPORT=420 swift test -c release -Xswiftc -enable-testing \
    ///       --filter SouthernMapCostReportTests/testWhatTheSouthsRealLinesCost
    func testWhatTheSouthsRealLinesCost() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let value = environment["SOUTH_BOUGHT_REPORT"] else {
            throw XCTSkip("set SOUTH_BOUGHT_REPORT=<minute of the day> to time the south's real lines at 60×")
        }
        let minute = try XCTUnwrap(Int64(value).flatMap { (0..<1_440).contains($0) ? $0 : nil }, "SOUTH_BOUGHT_REPORT is a minute of the day")
        let parts = (environment["SOUTH_BUY"] ?? "屏東線,縱貫線南段,SHALUN,krtc").split(separator: ",").map(String.init)
        let clock = ContinuousClock()
        let session = try BoughtWorldSaveTests.wholeTaiwan(rules: environment["SOUTH_RULES"] == "realistic" ? .realistic : .simple)
        FileHandle.standardError.write(Data(("on sale: " + session.realLineBundles.map { $0.lines.map(\.id).joined(separator: "+") }.joined(separator: ", ") + "\n").utf8))
        var bought: [String] = []
        let buying = clock.measure {
            for bundle in session.realLineBundles where bundle.lines.contains(where: { line in parts.contains { line.id.contains($0) } }) {
                let offer = session.realLineBundleOffer(for: bundle)
                if session.acquireRealLines(offer) {
                    bought += bundle.lines.map(\.id)
                } else {
                    FileHandle.standardError.write(Data("not bought: \(bundle.lines.map(\.id))\n".utf8))
                }
            }
        }
        var world = session.world
        FileHandle.standardError.write(Data("bought \(bought) in \(LongGameCostReportTests.ms(buying)) ms: stations \(world.stations.count), lines \(world.lines.count), trains \(world.trains.count), edges \(world.network.edges.count)\n".utf8))
        if let path = environment["SOUTH_MAP_SAVE"] {
            try SaveLibrary.encode(world, at: Date(timeIntervalSince1970: 0)).write(to: URL(fileURLWithPath: path))
        }
        world.setSpeed(.fast)
        let played = try clock.measure {
            while MapFrameCostReportTests.minuteOfDay(world.clock.now) + 10 <= minute { try world.advance(ticks: 1) }
            world.setSpeed(.x60)
            while MapFrameCostReportTests.minuteOfDay(world.clock.now) < minute { try world.advance(ticks: 10) }
        }
        FileHandle.standardError.write(Data("played to minute \(minute) in \(LongGameCostReportTests.ms(played)) ms\n".utf8))
        let data = RealWorldData.load(pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        var rows = ["| Minute | What | ms |", "| --: | --- | --: |"]
        rows += try LongGameCostReportTests.measure(world, day: Int(minute), data: data)
        let playing = GameSession(world: world, language: .traditionalChinese)
        playing.population = session.population
        playing.places = session.places
        playing.water = session.water
        playing.coverage = session.coverage
        playing.railways = session.railways
        playing.heights = session.heights
        playing.setSpeed(.x60)
        playing.advance(realElapsed: GameSession.tickInterval)
        var worked: [Duration] = [], finished: [Duration] = []
        for _ in 0..<300 {
            guard let tick = playing.beginLoopTick() else { break }
            let start = clock.now
            let outcome = await tick.work()
            worked.append(clock.now - start)
            finished.append(clock.measure { playing.finish(tick, with: outcome) })
        }
        func summary(_ times: [Duration]) -> String {
            let sorted = times.sorted()
            guard !sorted.isEmpty else { return "–" }
            let total = sorted.reduce(Duration.zero, +)
            return "mean \(LongGameCostReportTests.ms(total, per: sorted.count)), p90 \(LongGameCostReportTests.ms(sorted[sorted.count * 9 / 10])), longest \(LongGameCostReportTests.ms(sorted.last!)); over 100 ms: \(sorted.filter { $0 > .milliseconds(100) }.count) of \(sorted.count)"
        }
        rows.append("| \(minute) | 300 loop ticks at x60, off the main actor | \(summary(worked)) |")
        rows.append("| \(minute) | 300 loop ticks at x60, on the main actor | \(summary(finished)) |")
        let count = try await MapRedrawCount.run(playing, ticks: 100)
        rows += ["", "| Canvas at x60 | redrawn a second |", "| --- | --: |"]
        rows += MapRedrawCount.Canvas.allCases.map { "| \($0.rawValue) | \(count.perSecond($0, over: 10)) |" }
        rows += ["", "Inputs that changed (of 100 ticks at x60):"]
        rows += count.reasons.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value)" }
        rows += ["", "The railway canvas, the whole network in view:", ""]
        rows += MapFrameCostReportTests.railwayPoints(of: playing.world)
        print(rows.joined(separator: "\n"))
    }
}
