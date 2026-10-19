import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 289: the Jiji challenge played without a player, a few ways, as
/// `LiuMingchuanReportTests` plays the Liu Mingchuan challenge (decision
/// 153), printed as a Markdown table of the day each goal was met and how
/// the challenge ended. It asserts nothing and runs only on request:
///
///     JIJI_REPORT=1 swift test -c release -Xswiftc -enable-testing \
///       --filter JijiReportTests
///
/// `JIJI_PLAY` picks one way to play, `JIJI_TRACE=1` prints every day,
/// `JIJI_DAYS` stops early and `JIJI_RICH=1` starts with money to spare
/// (to measure what the line costs and earns). Every play lays the whole
/// line along the real one (the app's `tra_sched|JIJI`, ``RealRailways``)
/// on the first day, calling at its seven stations, with passing loops
/// where the real line has two tracks (Yuanquan, Zhuoshui, Longquan, Jiji,
/// Shuili). The map is flat, without the ground the app reads: a stretch
/// over the real water is a bridge (4 times the price), the rest on the
/// ground, so the app's embankments, cuttings and tunnels cost more than
/// here. The land is read round each station as the app reads it.
///
/// Every line runs a new line's hours (06:00 to midnight). Its costs are
/// mostly by the train-kilometre, not by the car (``GameWorld``'s hourly
/// settlement: $0.42 a train-km, $0.75 a departure), so a short train costs
/// nearly what a long one does.
///
/// - **Two cars**: one train of two standard cars, the flat $5 fare.
/// - **Four cars**: one train of four, the flat fare.
/// - **Fare $8**: one train of two, a flat $8 fare.
/// - **Two trains**: two trains of two, meeting at the loops.
/// - **Blue Train**: one Blue Train of two (a sightseeing train, decision
///   286), which adds half a star to Jiji Station and Checheng.
@MainActor
final class JijiReportTests: XCTestCase {
    enum Play: String, CaseIterable {
        case twoCars = "Two cars"
        case fourCars = "Four cars"
        case dearer = "Fare $8"
        case twoTrains = "Two trains"
        case blueTrain = "Blue Train"

        var cars: Int { self == .fourCars ? 4 : 2 }
        var fare: Money? { self == .dearer ? Money(800) : nil }
        var trains: Int { self == .twoTrains ? 2 : 1 }
        var type: TrainType? { self == .blueTrain ? .blueTrain : nil }
    }

    static let checkpoints: [Int64] = [7, 30, 60, 120, 180, 360, 720, 1_080]
    nonisolated static let stations = ["二水", "源泉", "濁水", "龍泉", "集集", "水里", "車埕"]
    nonisolated static let loops: Set<String> = ["源泉", "濁水", "龍泉", "集集", "水里"]

    func testTheJijiChallenge() throws {
        guard ProcessInfo.processInfo.environment["JIJI_REPORT"] != nil else {
            throw XCTSkip("set JIJI_REPORT=1 to print the Jiji challenge report")
        }
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let railways = try XCTUnwrap(data.railways), population = try XCTUnwrap(data.population)
        let plays = Play.allCases.filter { play in ProcessInfo.processInfo.environment["JIJI_PLAY"].map { $0 == "\(play)" } ?? true }
        let line = BranchLineChallenge.jiji
        let challenge = line.challenge
        let goals = challenge.goalsText(in: .english)
        var lines = [
            "### \(challenge.title(in: .english)): \(challenge.ratingsText(in: .english))",
            "",
            "| Play | Cost | " + goals.joined(separator: " | ") + " | Result | Riders a day / cash on day " + Self.checkpoints.map(String.init).joined(separator: ", ") + " | Net profit each year |",
            "| --- | --: |" + String(repeating: " --: |", count: goals.count) + " --- | --- | --- |",
        ]
        for play in plays {
            let started = Date()
            lines.append(try row(play, line: line, railways: railways, population: population, places: data.places, water: data.water))
            FileHandle.standardError.write(Data("\(lines.last!) (\(Int(Date().timeIntervalSince(started))) s)\n".utf8))
        }
        print(lines.joined(separator: "\n"))
    }

    private func row(
        _ play: Play, line: BranchLineChallenge, railways: RealRailways, population: PopulationGrid, places: PlaceGrid?, water: WaterGrid?
    ) throws -> String {
        let environment = ProcessInfo.processInfo.environment
        var world = line.make()
        if environment["JIJI_RICH"] != nil {
            try world.borrow(CompanyAccounts.maximumLoan)
        }
        let route = Route(line: line, railways: railways, water: water, cars: play.cars)
        let before = world.economy.balance.amount
        try route.build(in: &world, trains: play.trains, cars: play.cars, type: play.type)
        let cost = before - world.economy.balance.amount
        if let fare = play.fare {
            try world.setFareRules(.flat(fare))
        }
        GameSession.readLand(roundStationsOf: &world, population: population, places: places, water: water)
        try world.advance(ticks: 1)
        var day: Int64 = 0
        var checked: [String] = []
        let stopDay = environment["JIJI_DAYS"].flatMap { Int64($0) } ?? .max
        while world.scenario?.outcome == nil, day < stopDay {
            for _ in 0..<24 {
                try Route.placePending(in: &world)
                try world.advance(ticks: 60)
            }
            day += 1
            if Self.checkpoints.contains(day) {
                checked.append("\(world.lastDayTrips()) / $\(world.economy.balance.amount / 100_000_000)M")
            }
            if environment["JIJI_TRACE"] != nil {
                let today = world.accounts.days.last
                FileHandle.standardError.write(Data("day \(day) trips \(world.lastDayTrips()) cash \(world.economy.balance.amount / 100) fares \((today?.fareRevenue.amount ?? 0) / 100) costs \((today?.totalCost.amount ?? 0) / 100) (operating \((today?.operatingCost.amount ?? 0) / 100), upkeep \((today?.maintenanceCost.amount ?? 0) / 100), energy \((today?.energyCost.amount ?? 0) / 100), staff \((today?.staffCost.amount ?? 0) / 100)) tourists \(world.tourism?.attractions.map(\.yesterday) ?? [])\n".utf8))
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
        let years = world.accounts.years.map { "$\($0.income.netProfit.amount / 100_000)k" }.joined(separator: ", ")
        return "| \(play.rawValue) | $\(cost / 100_000)k | " + met.joined(separator: " | ") + " | \(result) | \(checked.isEmpty ? "—" : checked.joined(separator: ", ")) | \(years) |"
    }

    /// The line's path and stops, in the challenge's world.
    struct Route {
        let path: WorldPath
        /// Stretches of the path, in distance along it, over water.
        let wet: [ClosedRange<Double>]
        let stops: [String: Double]
        let platformLength: Int64

        static let metre = Double(WorldCoordinate.unitsPerMetre)
        static let runOn = 300 * metre
        static let loopReach = 250 * metre
        nonisolated(unsafe) static var pending: [(train: TrainID, line: LineID, position: TrainPosition, offset: Int64)] = []

        init(line: BranchLineChallenge, railways: RealRailways, water: WaterGrid?, cars: Int) {
            let frame = RealWorldFrame(anchor: line.anchor, bounds: line.bounds)
            let coordinates = railways.lines.filter { $0.name.hasPrefix("集集線") }.flatMap(\.points)
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
            var full = WorldPath(points).smoothed()
            // The surveyed line runs Ershui to Checheng; if it was drawn the
            // other way, turn it round.
            let ershui = Self.point(of: "二水", railways: railways, frame: frame)
            if (full.point(at: 0) - ershui).length > (full.point(at: full.length) - ershui).length {
                full = WorldPath(full.points(from: 0, to: full.length).reversed())
                wetAt = wetAt.map { distance - $0 }
            }
            path = full
            wet = wetAt.map { ($0 - 24 * Self.metre)...($0 + 24 * Self.metre) }
            var stops: [String: Double] = [:]
            for name in JijiReportTests.stations {
                stops[name] = full.project(Self.point(of: name, railways: railways, frame: frame))
            }
            self.stops = stops
            platformLength = Int64(cars + 1) * Train.carLength
        }

        static func point(of name: String, railways: RealRailways, frame: RealWorldFrame) -> WorldVector {
            guard let station = railways.stations.first(where: { $0.id == "tra_sched|\(name)" }) else { preconditionFailure("no \(name)") }
            return WorldVector(frame.worldPosition(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude))
        }

        func zone(_ name: String) -> ClosedRange<Double> {
            let half = Double(platformLength) / 2
            let middle = min(max(stops[name]!, half + 32 * Self.metre), path.length - half - 32 * Self.metre)
            return (middle - half)...(middle + half)
        }

        /// Lays the whole line with its stations and loops, and a line
        /// calling at every station with `trains` trains of `cars` cars.
        func build(in world: inout GameWorld, trains: Int, cars: Int, type: TrainType?) throws {
            let names = JijiReportTests.stations
            let zones = names.map(zone)
            let loopNames = names.filter { JijiReportTests.loops.contains($0) }
            let loopEnds = loopNames.map { (stops[$0]! - Self.loopReach, stops[$0]! + Self.loopReach) }
            let plan = RealWorldDemo.TrackPlan(path, forced: [0, path.length] + loopEnds.flatMap { [$0.0, $0.1] }, avoiding: zones, start: nil)
            var ids: [TrackNodeID] = []
            for node in plan.nodes {
                ids.append(try world.buildTrackNode(at: WorldCoordinate(x: node.point.x, y: node.point.y, z: 0)))
            }
            var edges: [TrackEdgeID] = []
            for (index, curve) in plan.curves.enumerated() {
                let span = plan.distances[index]...plan.distances[index + 1]
                let structure: TrackStructure = wet.contains { $0.overlaps(span) } ? .bridge : .surface
                edges.append(try world.buildTrackEdge(from: ids[index], to: ids[index + 1], curve: curve, structure: structure))
            }
            let track = RealWorldDemo.Track(plan: plan, nodes: ids, edges: edges)
            var stations: [String: StationID] = [:]
            for (name, zone) in zip(names, zones) {
                let middle = path.point(at: (zone.lowerBound + zone.upperBound) / 2)
                let id = try world.buildStation(named: name, at: middle.plan).id
                stations[name] = id
                let (edge, offset) = track.edge(at: zone.lowerBound, in: world)
                try world.addTrackPlatform(id, on: edge, from: offset, to: offset + platformLength)
            }
            for (name, ends) in zip(loopNames, loopEnds) {
                let loopPath = path.offset(from: ends.0, to: ends.1, by: 6 * Self.metre, ramp: 100 * Self.metre)
                let middle = loopPath.length / 2, half = Double(platformLength) / 2
                guard let from = track.node(at: ends.0), let to = track.node(at: ends.1) else { preconditionFailure("loop ends") }
                let loopPlan = RealWorldDemo.TrackPlan(
                    loopPath, forced: [0, loopPath.length], avoiding: [(middle - half)...(middle + half)],
                    start: plan.node(at: ends.0), end: plan.node(at: ends.1)
                )
                let loop = try loopPlan.build(in: &world, start: from, end: to)
                let (edge, offset) = loop.edge(at: middle - half, in: world)
                try world.addTrackPlatform(stations[name]!, on: edge, from: offset, to: offset + platformLength)
            }
            let line = try world.createLine(named: "Jiji", stops: names.map { stations[$0]! }).id
            try world.setLineServiceWindow(line, to: .standard)
            let (edge, start) = track.edge(at: zones[0].lowerBound, in: world)
            let offset = start + platformLength
            let position = TrainPosition.onEdge(TrackTraversal(edge: edge, direction: .forward), offset: offset)
            Self.pending = []
            for number in 0..<trains {
                let train = try (type.map { try world.purchaseTrain(named: "Jiji \(number + 1)", as: $0) } ?? world.purchaseTrain(named: "Jiji \(number + 1)")).id
                try world.setTrainCars(train, to: cars)
                Self.pending.append((train, line, position, offset))
            }
            try Self.placePending(in: &world)
            try world.setLineTrainsInService(line, to: TrainsInService(peak: trains, offPeak: trains, low: trains))
        }

        /// Places each pending train whose first stop is free now.
        static func placePending(in world: inout GameWorld) throws {
            var waiting: [(train: TrainID, line: LineID, position: TrainPosition, offset: Int64)] = []
            for next in pending {
                var trial = world
                do {
                    try trial.placeTrain(next.train, at: next.position)
                    try trial.setTrainContinuation(next.train, along: [], stoppingAt: next.offset)
                    try trial.setTrainMovementRate(next.train, to: 512)
                    try trial.assignTrain(next.train, to: next.line)
                    world = trial
                } catch GameError.trackReserved {
                    waiting.append(next)
                }
            }
            pending = waiting
        }
    }
}
