import Foundation
@testable import GameCore
import GamePresentation
import XCTest

/// Decision 254: the baseline a simpler core loop is measured against. A
/// new player's usual opening on a new game, played without a player under
/// the new game's rules and under each rule taken off in turn, printed as
/// Markdown: when the first fare comes in, how the money goes, how long the
/// trains stand held for a route or a block, and how far the curves slow
/// them (docs/research/CORE_LOOP_2026-10-16.md §1). It asserts nothing and
/// runs only on request:
///
///     CORE_LOOP_REPORT=14 swift test -c release -Xswiftc -enable-testing \
///       --filter CoreLoopBaselineReportTests
///
/// `CORE_LOOP_REPORT` is the days to play (1 to 60). The opening, as the
/// tutorial and the run testers were asked to play ("first fare, then the
/// second town and a second train", NEXT_PRIORITIES §0) play it:
///
/// 1. Minute 0: one line from the first town to the second (seed 1), its
///    track one curved edge bowed sideways as a finger draws it, a station
///    at each end, one train of four cars running all day.
/// 2. Day 3: the track runs on from the first town's end to the third
///    town (on the far side of the first), curving on from the first
///    line's track, and a second line calls at all three with a train of
///    its own, so the two share the first line's single track.
final class CoreLoopBaselineReportTests: XCTestCase {
    func testANewPlayersOpening() throws {
        guard let value = ProcessInfo.processInfo.environment["CORE_LOOP_REPORT"] else {
            throw XCTSkip("set CORE_LOOP_REPORT=<days> to print the core loop baseline")
        }
        let days = try XCTUnwrap(Int64(value).flatMap { (1...60).contains($0) ? $0 : nil }, "CORE_LOOP_REPORT is 1 to 60 days")
        var rows = [
            "| Rules | Commands | First fare (game min / real s at 600×) | Fares day 1 | Balance day 1 / 3 / 7 / \(days) | Back to the starting balance | Held train-minutes (episodes) | Slowest curve limit | Trips day 2 / \(days) | Deadlocked at the end |",
            "| --- | --: | --- | --: | --- | --- | --- | --: | --- | --: |",
        ]
        for preset in Preset.allCases {
            let started = Date()
            rows.append(try row(preset, days: days))
            FileHandle.standardError.write(Data("\(rows.last!) (\(Int(Date().timeIntervalSince(started))) s)\n".utf8))
        }
        print("### A new player's opening (seed 1, \(days) days)\n\n" + rows.joined(separator: "\n"))
    }

    /// The rules the opening is played under: the new game's, and each
    /// rule a simpler default might take off.
    enum Preset: String, CaseIterable {
        case newGame = "New game (every rule on)"
        case noCurveLimits = "− curve limits (217)"
        case noBlockSections = "− block sections (212)"
        case noRealisticOperation = "− realistic operation (207)"
        case noFlexDispatch = "− flexible dispatch (172)"
        case simple = "Simple: − 207, 212, 217, 172, 169, 180"
        case noTrafficControl = "Simple and − traffic control (32)"
        /// Decision 256: the app's default, ``NewGameRules/simple``.
        case simpleRules = "Simple rules (256): − 207, 212, 217, 169, 180, 156, weather"

        func apply(to world: inout GameWorld) throws {
            switch self {
            case .newGame: break
            case .simpleRules: NewGameRules.simple.apply(to: &world)
            case .noCurveLimits: world.setCurveSpeedLimits(false)
            case .noBlockSections: world.setBlockSections(false)
            case .noRealisticOperation: world.setRealisticOperation(false)
            case .noFlexDispatch: world.setFlexDispatch(false)
            case .simple, .noTrafficControl:
                world.setRealisticOperation(false)
                world.setBlockSections(false)
                world.setCurveSpeedLimits(false)
                world.setFlexDispatch(false)
                world.setDoorCrowding(false)
                world.setRollingStockEconomics(false)
                if self == .noTrafficControl { try world.setTrafficControl(false) }
            }
        }
    }

    private func row(_ preset: Preset, days: Int64) throws -> String {
        var world = GameWorld.newGame(eventSeed: 1)
        try preset.apply(to: &world)
        let start = world.economy.balance.amount
        let towns = Land.townCentres(seed: 1, in: world.bounds)
        var script = Script()
        try script.openFirstLine(&world, from: towns[0], to: towns[1])
        var firstFare: Int64?
        var balances: [Int64: Int64] = [:]
        var faresDayOne: Int64 = 0
        var backOn: Int64?
        var heldMinutes = 0, episodes = 0
        var held: Set<TrainID> = []
        var minute: Int64 = 0
        var tripsDayTwo: Int64 = 0
        while minute < days * 1_440 {
            if minute == 3 * 1_440 {
                try script.extend(&world, to: towns[2])
            }
            try world.advance(ticks: 1)
            minute += 1
            if firstFare == nil, world.financeReport(.day).current.fareRevenue.amount > 0 {
                firstFare = minute
            }
            let holding = Set(world.trains.map(\.id).filter { world.trainHoldingRoute(of: $0) != nil })
            heldMinutes += holding.count
            episodes += holding.subtracting(held).count
            held = holding
            if minute % 1_440 == 0 {
                let day = minute / 1_440
                balances[day] = world.economy.balance.amount
                if day == 1 { faresDayOne = world.financeReport(.day).previous.fareRevenue.amount }
                if day == 2 { tripsDayTwo = world.lastDayTrips() }
                if backOn == nil, world.economy.balance.amount >= start { backOn = day }
            }
        }
        let first = firstFare.map { "\($0) / " + String(format: "%.1f", Double($0) / 10) } ?? "none"
        let curve = script.slowestCurve(in: world).map { "\($0) km/h" } ?? "—"
        let shown = [1, 3, 7, days].map { balances[$0].map(dollars) ?? "—" }.joined(separator: " / ")
        return "| \(preset.rawValue) | \(script.commands) | \(first) | \(dollars(faresDayOne)) | \(shown) | "
            + "\(backOn.map { "day \($0)" } ?? "not by day \(days)") | \(heldMinutes) (\(episodes)) | \(curve) | \(tripsDayTwo) / \(world.lastDayTrips()) | \(world.deadlockedTrains().count) of \(world.trains.count) trains |"
    }

    /// The player's commands, counted: each call to the world a tap or a
    /// confirmation would make.
    private struct Script {
        var commands = 0
        var edges: [TrackEdgeID] = []
        var stations: [StationID] = []
        var firstEnd: (node: TrackNodeID, point: PlanPoint, heading: (Double, Double))?

        /// Four cars of the longest real car (25 m), so any type fits.
        static let platform: Int64 = 4 * 25 * WorldCoordinate.unitsPerMetre

        /// One curved edge from a platform beyond `from` to one beyond `to`,
        /// bowed sideways by a fifth of its span.
        mutating func openFirstLine(_ world: inout GameWorld, from: PlanPoint, to: PlanPoint) throws {
            let platform = Self.platform
            let (dx, dy) = unit(from, to)
            let a = PlanPoint(x: from.x - Int64(dx * Double(platform)), y: from.y - Int64(dy * Double(platform)))
            let b = PlanPoint(x: to.x + Int64(dx * Double(platform)), y: to.y + Int64(dy * Double(platform)))
            let span = distance(a, b), bow = span / 5
            let c1 = PlanPoint(x: a.x + Int64(dx * span / 3 - dy * bow), y: a.y + Int64(dy * span / 3 + dx * bow))
            let c2 = PlanPoint(x: a.x + Int64(dx * span * 2 / 3 - dy * bow), y: a.y + Int64(dy * span * 2 / 3 + dx * bow))
            let start = try command { try world.buildTrackNode(at: WorldCoordinate(x: a.x, y: a.y)) }
            let end = try command { try world.buildTrackNode(at: WorldCoordinate(x: b.x, y: b.y)) }
            let edge = try command { try world.buildTrackEdge(from: start, to: end, curve: .cubic(c1, c2)) }
            edges.append(edge)
            let length = world.trackEdge(edge)?.length ?? 0
            let first = try command { try world.buildStation(named: "S0", at: from).id }
            try command { try world.addTrackPlatform(first, on: edge, from: platform / 2, to: platform + platform / 2) }
            let second = try command { try world.buildStation(named: "S1", at: to).id }
            try command { try world.addTrackPlatform(second, on: edge, from: length - platform - platform / 2, to: length - platform / 2) }
            stations = [first, second]
            firstEnd = (start, a, unit(c1, a))
            try openLine(&world, stops: stations, on: TrackTraversal(edge: edge, direction: .forward))
        }

        /// On from the first edge's start to a platform beyond `town`,
        /// leaving the way the first edge runs there and curving round to
        /// it; a second line calling at every station with a train of its
        /// own, from the far end.
        mutating func extend(_ world: inout GameWorld, to town: PlanPoint) throws {
            let platform = Self.platform
            guard let (node, point, heading) = firstEnd else { return }
            let (dx, dy) = unit(point, town)
            let b = PlanPoint(x: town.x + Int64(dx * Double(platform)), y: town.y + Int64(dy * Double(platform)))
            let span = distance(point, b)
            let c1 = PlanPoint(x: point.x + Int64(heading.0 * span / 3), y: point.y + Int64(heading.1 * span / 3))
            let c2 = PlanPoint(x: b.x - Int64(dx * span / 3), y: b.y - Int64(dy * span / 3))
            let end = try command { try world.buildTrackNode(at: WorldCoordinate(x: b.x, y: b.y)) }
            let edge = try command { try world.buildTrackEdge(from: node, to: end, curve: .cubic(c1, c2)) }
            edges.append(edge)
            let length = world.trackEdge(edge)?.length ?? 0
            let third = try command { try world.buildStation(named: "S2", at: town).id }
            try command { try world.addTrackPlatform(third, on: edge, from: length - platform - platform / 2, to: length - platform / 2) }
            stations.append(third)
            try openLine(&world, stops: [third, stations[0], stations[1]], on: TrackTraversal(edge: edge, direction: .backward))
        }

        /// A line calling at `stops`, all day, one train of four cars whose
        /// head is at the far end of the first stop's platform on `traversal`.
        mutating func openLine(_ world: inout GameWorld, stops: [StationID], on traversal: TrackTraversal) throws {
            let platform = Self.platform
            let line = try command { try world.createLine(named: "Line \(world.lines.count + 1)", stops: stops).id }
            try command { try world.setLineServiceWindow(line, to: .allDay) }
            try command { try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1)) }
            let train = try command { try world.purchaseTrain(named: "Train \(world.trains.count + 1)").id }
            try command { try world.setTrainCars(train, to: 4) }
            try command { try world.placeTrain(train, at: .onEdge(traversal, offset: platform + platform / 2)) }
            try command { try world.setTrainContinuation(train, along: [], stoppingAt: platform + platform / 2) }
            try command { try world.setTrainMovementRate(train, to: 512) }
            try command { try world.assignTrain(train, to: line) }
        }

        /// The lowest curve limit posted on the script's track, in km/h.
        func slowestCurve(in world: GameWorld) -> Int64? {
            edges.compactMap { world.trackEdge($0) }.flatMap { $0.speedLimits(going: .forward) }.map(\.speed).min()
        }

        @discardableResult
        mutating func command<T>(_ body: () throws -> T) throws -> T {
            commands += 1
            return try body()
        }

        func unit(_ from: PlanPoint, _ to: PlanPoint) -> (Double, Double) {
            let span = distance(from, to)
            return (Double(to.x - from.x) / span, Double(to.y - from.y) / span)
        }

        func distance(_ a: PlanPoint, _ b: PlanPoint) -> Double {
            let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            return (dx * dx + dy * dy).squareRoot()
        }
    }
}

private func dollars(_ cents: Int64) -> String {
    "$\(cents / 100)"
}
