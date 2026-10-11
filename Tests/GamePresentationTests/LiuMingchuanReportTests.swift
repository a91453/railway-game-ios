import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 153: the Liu Mingchuan challenge played without a player, a few
/// ways, as `ChallengeReportTests` plays the sandbox challenges (decision
/// 145), printed as a Markdown table of the day each goal was met and how
/// the challenge ended. It asserts nothing and runs only on request:
///
///     LIU_REPORT=1 swift test -c release -Xswiftc -enable-testing \
///       --filter LiuMingchuanReportTests
///
/// `LIU_PLAY` picks one way to play; `LIU_TRACE=1` prints every day. Every
/// play lays the line along today's Western Trunk Line (the owner's
/// `Railway/` data, ``RealRailways``), Keelung to Taipei first and on to
/// Hsinchu as soon as the money allows, calling at the towns of Liu's day;
/// Liu's own line ran from Twatutia by Xinzhuang and the Guishan ridge,
/// which no data holds. The map is flat, without the ground the app reads:
/// a stretch of track over the real water is a bridge (4 times the price),
/// the rest on the ground, so the app's embankments, cuttings and tunnels
/// cost more than here. The land is read round each station as the app
/// reads it.
///
/// - **Short train**: one steam train of four cars a line: less than the
///   challenge asks; it loses money from the first day.
/// - **One train**: eight cars, the least that pays on the line to Taipei:
///   the challenge's least, played and waited out.
/// - **Long train**: sixteen cars, the most a train takes: one thing more.
/// - **Loan**: sixteen cars, the most the company may borrow ($5 million)
///   from the first day, and fares by distance (the reference's steps).
///
/// The line on to Hsinchu is a line of its own from Hsinchu to Taipei, its
/// train setting out from Hsinchu; Keelung, Songshan, Taipei, Banqiao,
/// Taoyuan, Yangmei and Hsinchu have passing loops (Taipei's lets both
/// lines stand there at once). `LIU_CARS` and `LIU_TRAINS` override a
/// play's cars and trains a line, `LIU_DAYS` stops early and
/// `LIU_RUN_ON=1` plays on to the deadline after the challenge ends.
@MainActor
final class LiuMingchuanReportTests: XCTestCase {
    enum Play: String, CaseIterable {
        case shortTrain = "Short train"
        case oneTrain = "One train"
        case longTrain = "Long train"
        case loan = "Loan"

        var cars: Int { ProcessInfo.processInfo.environment["LIU_CARS"].flatMap { Int($0) } ?? [.shortTrain: 4, .oneTrain: 8][self] ?? 16 }
        var trains: Int { ProcessInfo.processInfo.environment["LIU_TRAINS"].flatMap { Int($0) } ?? 1 }
    }

    static let checkpoints: [Int64] = [30, 60, 120, 240, 360, 720, 1_080, 1_440]

    func testTheLiuMingchuanChallenge() throws {
        guard ProcessInfo.processInfo.environment["LIU_REPORT"] != nil else {
            throw XCTSkip("set LIU_REPORT=1 to print the Liu Mingchuan challenge report")
        }
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let railways = try XCTUnwrap(data.railways), population = try XCTUnwrap(data.population)
        let plays = Play.allCases.filter { play in ProcessInfo.processInfo.environment["LIU_PLAY"].map { $0 == "\(play)" } ?? true }
        let challenge = Challenge.liuMingchuan
        let goals = challenge.goalsText(in: .english)
        var lines = [
            "### \(challenge.title(in: .english)): \(challenge.ratingsText(in: .english))",
            "",
            "| Play | " + goals.joined(separator: " | ") + " | Result | Riders a day / cash on day " + Self.checkpoints.map(String.init).joined(separator: ", ") + " | Net profit each year |",
            "| --- |" + String(repeating: " --: |", count: goals.count) + " --- | --- | --- |",
        ]
        for play in plays {
            let started = Date()
            lines.append(try row(play, railways: railways, population: population, places: data.places, water: data.water))
            FileHandle.standardError.write(Data("\(lines.last!) (\(Int(Date().timeIntervalSince(started))) s)\n".utf8))
        }
        print(lines.joined(separator: "\n"))
    }

    /// The stations each stretch calls at: Liu's towns by today's stations.
    nonisolated static let west = ["基隆", "八堵", "七堵", "五堵", "汐止", "南港", "松山", "臺北"]
    nonisolated static let south = ["臺北", "板橋", "樹林", "鶯歌", "桃園", "中壢", "楊梅", "湖口", "新豐", "新竹"]
    nonisolated static let loops: Set<String> = ["基隆", "松山", "臺北", "板橋", "桃園", "楊梅", "新竹"]

    private func row(_ play: Play, railways: RealRailways, population: PopulationGrid, places: PlaceGrid?, water: WaterGrid?) throws -> String {
        var world = LiuMingchuanChallenge.make()
        let route = Route(railways: railways, water: water, cars: play.cars)
        // What the stretch on to Hsinchu costs, built on a map with money
        // to spare: tried on the challenge's only once it can be paid for.
        var rich = GameWorld.newGame(anchor: LiuMingchuanChallenge.anchor, bounds: LiuMingchuanChallenge.bounds, balance: Money(100_000_000_000), land: [])
        var richPending: [Route.Pending] = []
        var richBuilt = try route.buildWest(in: &rich, trains: play.trains, cars: play.cars, pending: &richPending)
        let before = rich.economy.balance
        try route.buildSouth(in: &rich, after: &richBuilt, pending: &richPending)
        let southCost = before.amount - rich.economy.balance.amount
        FileHandle.standardError.write(Data("\(play.rawValue): Keelung–Taipei cost $\((100_000_000_000 - before.amount) / 100), on to Hsinchu $\(southCost / 100)\n".utf8))
        var pending: [Route.Pending] = []
        var built = try route.buildWest(in: &world, trains: play.trains, cars: play.cars, pending: &pending)
        if play == .loan {
            try world.borrow(CompanyAccounts.maximumLoan)
            try world.setFareRules(.distance(FareRules.standardBands(for: FareRules.standardFare)))
        }
        GameSession.readLand(roundStationsOf: &world, population: population, places: places, water: water)
        var extended = false
        try world.advance(ticks: 1)
        var day: Int64 = 0
        var checked: [String] = []
        let stopDay = ProcessInfo.processInfo.environment["LIU_DAYS"].flatMap { Int64($0) } ?? .max
        let runOn = ProcessInfo.processInfo.environment["LIU_RUN_ON"] != nil
        let deadline = world.scenario?.scenario.deadlineDays ?? 0
        while world.scenario?.outcome == nil || (runOn && day < deadline), day < stopDay {
            if !extended, world.economy.balance.amount >= southCost {
                var trial = world
                do {
                    try route.buildSouth(in: &trial, after: &built, pending: &pending)
                    GameSession.readLand(roundStationsOf: &trial, population: population, places: places, water: water)
                    world = trial
                    extended = true
                    FileHandle.standardError.write(Data("\(play.rawValue): extended to Hsinchu on day \(day + 1)\n".utf8))
                } catch GameError.insufficientFunds {}
            }
            // A second train waits for its first stop: tried every hour.
            for _ in 0..<24 {
                try Route.placePending(&pending, in: &world)
                try world.advance(ticks: 60)
            }
            day += 1
            if Self.checkpoints.contains(day) {
                checked.append("\(world.lastDayTrips()) / $\(world.economy.balance.amount / 100_000_000)M")
            }
            if ProcessInfo.processInfo.environment["LIU_TRACE"] != nil {
                let today = world.accounts.days.last
                FileHandle.standardError.write(Data("day \(day) trips \(world.lastDayTrips()) cash \(world.economy.balance.amount / 100) fares \((today?.fareRevenue.amount ?? 0) / 100) costs \((today?.totalCost.amount ?? 0) / 100) (operating \((today?.operatingCost.amount ?? 0) / 100), upkeep \((today?.maintenanceCost.amount ?? 0) / 100), energy \((today?.energyCost.amount ?? 0) / 100), staff \((today?.staffCost.amount ?? 0) / 100))\n".utf8))
            }
        }
        let state = try XCTUnwrap(world.scenario)
        let met = zip(state.achieved, world.goalProgress(in: .english)).map { achieved, progress in
            achieved.map { "\(state.elapsedDays(through: $0))" } ?? "— (\(progress.detail))"
        }
        let result = switch state.outcome {
        case .completed(let end, let rating)?: "\(rating.displayName(in: .english)), day \(state.elapsedDays(through: end))"
        case .failed(let end, let reason)?: "failed (\(reason)), day \(state.elapsedDays(through: end))"
        case nil: "playing"
        }
        let years = world.accounts.years.map { "$\($0.income.netProfit.amount / 100_000_000)M" }.joined(separator: ", ")
        return "| \(play.rawValue) | " + met.joined(separator: " | ") + " | \(result) | \(checked.isEmpty ? "—" : checked.joined(separator: ", ")) | \(years) |"
    }

    /// The line's path and stops, in the challenge's world.
    struct Route {
        let path: WorldPath
        /// Stretches of the path, in distance along it, over water.
        let wet: [ClosedRange<Double>]
        let stops: [String: (point: WorldVector, at: Double)]
        let platformLength: Int64

        static let metre = Double(WorldCoordinate.unitsPerMetre)

        static func fail(_ why: String) -> Never {
            FileHandle.standardError.write(Data("FAILED: \(why)\n".utf8))
            exit(1)
        }
        static let runOn = 400 * metre
        static let loopReach = 250 * metre

        init(railways: RealRailways, water: WaterGrid?, cars: Int) {
            let frame = RealWorldFrame(anchor: LiuMingchuanChallenge.anchor, bounds: LiuMingchuanChallenge.bounds)
            let coordinates = railways.lines.filter { $0.name.hasPrefix("縱貫線北段") }.flatMap(\.points)
            // The path, and whether each 16 m along it is over water.
            var points: [WorldVector] = []
            var wetAt: [Double] = []
            var distance = 0.0
            for (a, b) in zip(coordinates, coordinates.dropFirst()) {
                let pa = WorldVector(frame.worldPosition(latitude: a.latitude, longitude: a.longitude))
                let pb = WorldVector(frame.worldPosition(latitude: b.latitude, longitude: b.longitude))
                let steps = max(1, Int((pb - pa).length / (16 * Self.metre)))
                for step in 0..<steps {
                    let t = Double(step) / Double(steps)
                    let latitude = a.latitude + (b.latitude - a.latitude) * t, longitude = a.longitude + (b.longitude - a.longitude) * t
                    let point = pa + (pb - pa) * t
                    if let last = points.last { distance += (point - last).length }
                    points.append(point)
                    if water?.isWater(latitude: latitude, longitude: longitude) == true { wetAt.append(distance) }
                }
            }
            // The surveyed line begins at Keelung's platform: it runs on
            // 600 m straight beyond it, where the harbour is, so Keelung
            // has room for a loop.
            if points.count > 1 {
                let back = (points[0] - points[min(20, points.count - 1)]).unit
                points.insert(points[0] + back * (600 * Self.metre), at: 0)
                wetAt = wetAt.map { $0 + 600 * Self.metre }
            }
            let full = WorldPath(points)
            path = full.smoothed()
            wet = wetAt.map { ($0 - 24 * Self.metre)...($0 + 24 * Self.metre) }
            var stops: [String: (WorldVector, Double)] = [:]
            for name in Set(LiuMingchuanReportTests.west + LiuMingchuanReportTests.south) {
                guard let station = railways.stations.first(where: { $0.id == "tra_sched|\(name)" }) else { preconditionFailure("no \(name)") }
                let point = WorldVector(frame.worldPosition(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude))
                stops[name] = (point, full.smoothed().project(point))
            }
            self.stops = stops
            platformLength = Int64(cars + 1) * Train.carLength
        }

        func zone(_ name: String, offset: Double) -> ClosedRange<Double> {
            let half = Double(platformLength) / 2
            let middle = max(stops[name]!.at - offset, half + 32 * Self.metre)
            return (middle - half)...(middle + half)
        }

        /// What has been built: the main track's last node and the stations.
        struct Built {
            var end: (node: TrackNodeID, point: PlanPoint, direction: WorldVector)
            var stations: [String: StationID]
            var line: LineID
            var trains: Int
            var cars: Int
        }

        /// Lays the stretch of path from `a` to `b` with stations at
        /// `names`, loops at those in ``loops``, from `start` if given.
        func lay(
            in world: inout GameWorld, from a: Double, to b: Double, names: [String], start: (node: TrackNodeID, point: PlanPoint, direction: WorldVector)?,
            stations: inout [String: StationID]
        ) throws -> (TrackNodeID, PlanPoint, WorldVector, RealWorldDemo.Track, [String: (TrackEdgeID, Int64)]) {
            var loopPlatforms: [String: (TrackEdgeID, Int64)] = [:]
            let sub = WorldPath(path.points(from: a, to: b))
            let new = names.filter { stations[$0] == nil }
            let zones = new.map { zone($0, offset: a) }
            let loopNames = new.filter { LiuMingchuanReportTests.loops.contains($0) }
            let loopEnds = loopNames.map { name in (stops[name]!.at - a - Self.loopReach, stops[name]!.at - a + Self.loopReach) }
            let plan = RealWorldDemo.TrackPlan(
                sub, forced: [0, sub.length] + loopEnds.flatMap { [$0.0, $0.1] }, avoiding: zones,
                start: start.map { ($0.point, $0.direction) }
            )
            let track = try build(plan, in: &world, from: a, start: start?.node)
            for (name, zone) in zip(new, zones) {
                let middle = sub.point(at: (zone.lowerBound + zone.upperBound) / 2)
                let id = try world.buildStation(named: name, at: middle.plan).id
                stations[name] = id
                let (edge, offset) = track.edge(at: zone.lowerBound, in: world)
                do {
                    try world.addTrackPlatform(id, on: edge, from: offset, to: offset + platformLength)
                } catch {
                    Self.fail("\(name): \(error) edge \(edge) length \(world.network.edge(edge)?.length ?? 0) offset \(offset) zone \(zone) nodes \(plan.distances.filter { $0 > zone.lowerBound - 2_000 && $0 < zone.upperBound + 2_000 })")
                }
            }
            for (name, ends) in zip(loopNames, loopEnds) {
                let loopPath = sub.offset(from: ends.0, to: ends.1, by: 6 * Self.metre, ramp: 100 * Self.metre)
                let middle = loopPath.length / 2, half = Double(platformLength) / 2
                guard let from = track.node(at: ends.0), let to = track.node(at: ends.1) else { preconditionFailure("loop ends") }
                let loopPlan = RealWorldDemo.TrackPlan(
                    loopPath, forced: [0, loopPath.length], avoiding: [(middle - half)...(middle + half)],
                    start: plan.node(at: ends.0), end: plan.node(at: ends.1)
                )
                let loop: RealWorldDemo.Track
                do {
                    loop = try loopPlan.build(in: &world, start: from, end: to)
                } catch {
                    Self.fail("loop \(name): \(error)")
                }
                let (edge, offset) = loop.edge(at: middle - half, in: world)
                loopPlatforms[name] = (edge, offset)
                try world.addTrackPlatform(stations[name]!, on: edge, from: offset, to: offset + platformLength)
            }
            let last = plan.nodes[plan.nodes.count - 1]
            return (track.nodes[track.nodes.count - 1], last.point, last.direction, track, loopPlatforms)
        }

        /// Builds `plan`'s edges, a bridge where one crosses water.
        func build(_ plan: RealWorldDemo.TrackPlan, in world: inout GameWorld, from a: Double, start: TrackNodeID?) throws -> RealWorldDemo.Track {
            var ids: [TrackNodeID] = []
            for (index, node) in plan.nodes.enumerated() {
                if index == 0, let start {
                    ids.append(start)
                } else {
                    ids.append(try world.buildTrackNode(at: WorldCoordinate(x: node.point.x, y: node.point.y, z: 0)))
                }
            }
            var edges: [TrackEdgeID] = []
            for (index, curve) in plan.curves.enumerated() {
                let span = (a + plan.distances[index])...(a + plan.distances[index + 1])
                let structure: TrackStructure = wet.contains { $0.overlaps(span) } ? .bridge : .surface
                edges.append(try world.buildTrackEdge(from: ids[index], to: ids[index + 1], curve: curve, structure: structure))
            }
            return RealWorldDemo.Track(plan: plan, nodes: ids, edges: edges)
        }

        func buildWest(in world: inout GameWorld, trains: Int, cars: Int, pending: inout [Pending]) throws -> Built {
            var stations: [String: StationID] = [:]
            // Keelung is where the surveyed line begins: the track starts
            // there, its platform a little way in.
            let a = max(0, stops["基隆"]!.at - Self.runOn), b = stops["臺北"]!.at + Self.runOn
            let (node, point, direction, track, loopPlatforms) = try lay(in: &world, from: a, to: b, names: LiuMingchuanReportTests.west, start: nil, stations: &stations)
            let line = try run(
                "Keelung–Taipei", calling: LiuMingchuanReportTests.west, stations: stations, on: track, from: a, forward: true, loop: loopPlatforms["基隆"], trains: trains, cars: cars,
                in: &world, pending: &pending
            )
            return Built(end: (node, point, direction), stations: stations, line: line, trains: trains, cars: cars)
        }

        /// A line calling at `names`, with `trains` trains of `cars` cars:
        /// the first at the first stop's platform facing `forward` along the
        /// path, the others (a line sends trains out only from its first
        /// stop) to stand there as soon as it is free (``placePending``).
        func run(
            _ name: String, calling names: [String], stations: [String: StationID], on track: RealWorldDemo.Track, from a: Double,
            forward: Bool, loop: (TrackEdgeID, Int64)?, trains: Int, cars: Int, in world: inout GameWorld, pending: inout [Pending]
        ) throws -> LineID {
            let line = try world.createLine(named: name, stops: names.map { stations[$0]! }).id
            try world.setLineServiceWindow(line, to: .allDay)
            let zone = zone(names[0], offset: a)
            let (edge, start) = track.edge(at: zone.lowerBound, in: world)
            let length = world.network.edge(edge)?.length ?? 0
            let offset = forward ? start + platformLength : length - start
            let position = TrainPosition.onEdge(TrackTraversal(edge: edge, direction: forward ? .forward : .backward), offset: offset)
            for number in 0..<trains {
                let train = try world.purchaseTrain(named: "\(name) \(number + 1)").id
                try world.setTrainCars(train, to: cars)
                if number == 0 {
                    try Self.place(train, at: position, offset: offset, on: line, in: &world)
                } else if let (loopEdge, loopStart) = loop {
                    // The first stop's loop platform, so the first train
                    // finds its own free when it comes back.
                    let loopLength = world.network.edge(loopEdge)?.length ?? 0
                    let loopOffset = forward ? loopStart + platformLength : loopLength - loopStart
                    let at = TrainPosition.onEdge(TrackTraversal(edge: loopEdge, direction: forward ? .forward : .backward), offset: loopOffset)
                    pending.append(Pending(train: train, line: line, position: at, offset: loopOffset))
                } else {
                    pending.append(Pending(train: train, line: line, position: position, offset: offset))
                }
            }
            try world.setLineTrainsInService(line, to: TrainsInService(peak: trains, offPeak: trains, low: trains))
            return line
        }

        /// A train still to stand at its line's first stop.
        struct Pending {
            let train: TrainID
            let line: LineID
            let position: TrainPosition
            let offset: Int64
        }

        static func place(_ train: TrainID, at position: TrainPosition, offset: Int64, on line: LineID, in world: inout GameWorld) throws {
            try world.placeTrain(train, at: position)
            try world.setTrainContinuation(train, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(train, to: 512)
            try world.assignTrain(train, to: line)
        }

        /// Places each pending train whose first stop is free now.
        static func placePending(_ pending: inout [Pending], in world: inout GameWorld) throws {
            var waiting: [Pending] = []
            for next in pending {
                var trial = world
                do {
                    try place(next.train, at: next.position, offset: next.offset, on: next.line, in: &trial)
                    world = trial
                } catch GameError.trackReserved {
                    waiting.append(next)
                }
            }
            pending = waiting
        }

        /// The line on from Taipei to Hsinchu: a line of its own, sharing
        /// Taipei's station (on its loop's platform when the train finds the
        /// main one taken), its trains setting out from Hsinchu.
        func buildSouth(in world: inout GameWorld, after built: inout Built, pending: inout [Pending]) throws {
            let a = stops["臺北"]!.at + Self.runOn, b = stops["新竹"]!.at + Self.runOn
            var stations = built.stations
            let (_, _, _, track, loopPlatforms) = try lay(in: &world, from: a, to: b, names: LiuMingchuanReportTests.south, start: built.end, stations: &stations)
            built.stations = stations
            _ = try run(
                "Hsinchu–Taipei", calling: LiuMingchuanReportTests.south.reversed(), stations: stations, on: track, from: a, forward: false,
                loop: loopPlatforms["新竹"], trains: built.trains, cars: built.cars, in: &world, pending: &pending
            )
        }
    }
}
