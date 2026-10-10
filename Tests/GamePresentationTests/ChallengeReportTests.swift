import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 145: the sandbox challenges played without a player on several
/// seeds, three ways each, printed as a Markdown table of the day each goal
/// was met and how the challenge ended, so the targets can be checked again
/// whenever a rule moves them (decision 86's were measured on a line that
/// decision 137 left losing money). It asserts nothing and runs only on
/// request:
///
///     CHALLENGE_REPORT=1 swift test -c release -Xswiftc -enable-testing \
///       --filter ChallengeReportTests
///
/// `CHALLENGE_REPORT` is the number of seeds (1 to 8). A grown network
/// plays a day in some 2 seconds, so a seed's three challenges take over an
/// hour; to run them side by side, `CHALLENGE_SEEDS` (such as `2,5`)
/// picks seeds, `CHALLENGE_ONLY` one challenge by ID and `CHALLENGE_PLAY`
/// one way to play (`linked`, `longTrains` or `grown`). `CHALLENGE_RUN_ON=1`
/// plays on to the deadline after a challenge ends, for the last column
/// (to tune a target); `CHALLENGE_TRACE=1` prints every day. The
/// ways to play:
///
/// - **Linked**: the least the first challenge asks, from day 1: a line
///   from the first town to the second and one from the first to the
///   third, one train of four cars each, never changed.
/// - **Long trains**: the same lines with trains of eight cars. Until
///   about day 120 the riders are the demand's; after it, the trains' room
///   (decision 145).
/// - **Grown**: long trains, and from day 30 a line from the second town
///   to the third and one from each town to the nearest edge of the map
///   (an outside connection, decision 137), each built as soon as the money
///   allows.
///
/// A line that would cross track already built runs on a viaduct one
/// clearance higher, as a player would build it; a station in a town is
/// shared by every line calling there.
final class ChallengeReportTests: XCTestCase {
    func testTheSandboxChallenges() throws {
        guard let value = ProcessInfo.processInfo.environment["CHALLENGE_REPORT"] else {
            throw XCTSkip("set CHALLENGE_REPORT=<seeds> to print the challenge report")
        }
        let environment = ProcessInfo.processInfo.environment
        let count = try XCTUnwrap(Int(value).flatMap { (1...8).contains($0) ? $0 : nil }, "CHALLENGE_REPORT is 1 to 8 seeds")
        let seeds = environment["CHALLENGE_SEEDS"].map { $0.split(separator: ",").compactMap { UInt32($0) } } ?? Array(1...UInt32(count))
        let challenges = Challenge.sandbox.filter { challenge in environment["CHALLENGE_ONLY"].map { $0 == challenge.id } ?? true }
        let plays = Play.allCases.filter { play in environment["CHALLENGE_PLAY"].map { $0 == "\(play)" } ?? true }
        let runOn = environment["CHALLENGE_RUN_ON"] != nil
        var lines: [String] = []
        for challenge in challenges {
            let goals = challenge.goalsText(in: .english)
            lines += [
                "### \(challenge.title(in: .english)): \(challenge.ratingsText(in: .english))",
                "",
                "| Seed | Play | " + goals.joined(separator: " | ") + " | Result | Riders a day / population / equity on day " + Self.checkpoints.map(String.init).joined(separator: ", ") + " |",
                "| --: | --- |" + String(repeating: " --: |", count: goals.count) + " --- | --- |",
            ]
            for seed in seeds {
                for play in plays {
                    let started = Date()
                    lines.append(try row(challenge, seed: seed, play: play, runOn: runOn))
                    // Each row as it comes: the longest take minutes.
                    FileHandle.standardError.write(Data("\(lines.last!) (\(Int(Date().timeIntervalSince(started))) s)\n".utf8))
                }
            }
            lines.append("")
        }
        print(lines.joined(separator: "\n"))
    }

    enum Play: String, CaseIterable {
        case linked = "Linked"
        case longTrains = "Long trains"
        case grown = "Grown"
    }

    /// The days whose riders, population and equity the last column shows.
    static let checkpoints: [Int64] = [30, 60, 120, 240, 360, 720, 1_080]

    /// Plays `challenge` on `seed` until it ends (or, `runOn`, until its
    /// deadline) and returns its row.
    private func row(_ challenge: Challenge, seed: UInt32, play: Play, runOn: Bool) throws -> String {
        var world = GameWorld.newGame(challenge: challenge, eventSeed: seed)
        let towns = Land.townCentres(seed: seed, in: world.bounds)
        let linked = [(towns[0], towns[1]), (towns[0], towns[2])]
        let grown = [(towns[1], towns[2])] + towns.map { ($0, Self.nearestEdge(to: $0, in: world.bounds)) }
        var pending: [(day: Int64, from: PlanPoint, to: PlanPoint, cars: Int)] = switch play {
        case .linked: linked.map { (0, $0.0, $0.1, 4) }
        case .longTrains: linked.map { (0, $0.0, $0.1, 8) }
        case .grown: linked.map { (0, $0.0, $0.1, 8) } + grown.map { (30, $0.0, $0.1, 8) }
        }
        var stations: [PlanPoint: StationID] = [:]
        try world.advance(ticks: 1)
        var day: Int64 = 0
        var checked: [String] = []
        let deadline = world.scenario?.scenario.deadlineDays ?? 0
        while world.scenario?.outcome == nil || (runOn && day < deadline) {
            // In order, each line whose day has come, as soon as it can be
            // paid for; a line refused for anything else is a broken script.
            while let next = pending.first, next.day <= day {
                var trial = world, known = stations
                do {
                    try Self.buildLine(&trial, from: next.from, to: next.to, cars: next.cars, stations: &known)
                } catch GameError.insufficientFunds {
                    break
                }
                world = trial
                stations = known
                pending.removeFirst()
            }
            let clock = Date()
            try world.advance(ticks: 1_440)
            day += 1
            if Self.checkpoints.contains(day) {
                checked.append("\(world.lastDayTrips() / 1_000)k / \(world.totalResidents() / 1_000)k / $\(world.balanceSheet().equity.amount / 100_000_000)M")
            }
            if ProcessInfo.processInfo.environment["CHALLENGE_TRACE"] != nil {
                FileHandle.standardError.write(Data("day \(day) \(Int(Date().timeIntervalSince(clock) * 1000)) ms trips \(world.lastDayTrips()) lines \(world.lines.count) cash \(world.economy.balance.amount / 100)\n".utf8))
            }
        }
        let state = try XCTUnwrap(world.scenario)
        // A goal met shows its day; one not met, how far it got.
        let met = zip(state.achieved, world.goalProgress(in: .english)).map { achieved, progress in
            achieved.map { "\(state.elapsedDays(through: $0))" } ?? "— (\(progress.detail))"
        }
        let result = switch state.outcome {
        case .completed(let end, let rating)?: "\(rating.displayName(in: .english)), day \(state.elapsedDays(through: end))"
        case .failed(let end, let reason)?: "failed (\(reason)), day \(state.elapsedDays(through: end))"
        case nil: "playing"
        }
        let unbuilt = pending.isEmpty ? "" : ", \(pending.count) lines never paid for"
        let column = checked.isEmpty ? "—" : checked.joined(separator: ", ")
        return "| \(seed) | \(play.rawValue) | " + met.joined(separator: " | ") + " | \(result)\(unbuilt) | \(column) |"
    }

    /// A point 40,000 units (625 m) inside the map's edge nearest `point`.
    private static func nearestEdge(to point: PlanPoint, in bounds: WorldBounds) -> PlanPoint {
        let inset: Int64 = 40_000
        let sides = [
            (point.x, PlanPoint(x: inset, y: point.y)),
            (bounds.width - point.x, PlanPoint(x: bounds.width - inset, y: point.y)),
            (point.y, PlanPoint(x: point.x, y: inset)),
            (bounds.height - point.y, PlanPoint(x: point.x, y: bounds.height - inset)),
        ]
        return sides.min { $0.0 < $1.0 }!.1
    }

    /// A straight line of one edge from `from` to `to`, with a station at
    /// each (an existing one there is shared), one train of `cars` cars and
    /// all-day service, like `newGameLine(through:)`: on the ground, or on
    /// a viaduct as low as clears the track already built.
    private static func buildLine(
        _ world: inout GameWorld, from: PlanPoint, to: PlanPoint, cars: Int, stations: inout [PlanPoint: StationID]
    ) throws {
        let platform = Int64(cars) * Train.carLength
        func beyond(_ a: PlanPoint, _ b: PlanPoint, z: Int64) -> WorldCoordinate {
            let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let span = (dx * dx + dy * dy).squareRoot()
            return WorldCoordinate(x: b.x + Int64(dx / span * Double(platform)), y: b.y + Int64(dy / span * Double(platform)), z: z)
        }
        var built: (GameWorld, TrackEdgeID)?
        for level in Int64(0)...7 {
            var trial = world
            let z = level * TrackStructure.clearance
            do {
                let start = try trial.buildTrackNode(at: beyond(to, from, z: z))
                let end = try trial.buildTrackNode(at: beyond(from, to, z: z))
                let edge = try trial.buildTrackEdge(from: start, to: end, structure: level == 0 ? .surface : .elevated)
                built = (trial, edge)
                break
            } catch GameError.trackConflict, GameError.trackTooClose {
                continue
            }
        }
        guard let (next, edge) = built else { throw GameError.invalidTrackGeometry }
        world = next
        let length = world.trackEdge(edge)?.length ?? 0
        var stops: [StationID] = []
        // Each stop's point and the middle of its platform along the edge,
        // which runs a platform beyond `from` and `to`.
        let calls = [(from, platform), (to, length - platform)]
        for (point, middle) in calls {
            let start = middle - platform / 2
            let station = try stations[point] ?? world.buildStation(named: "S\(stations.count)", at: point).id
            stations[point] = station
            try world.addTrackPlatform(station, on: edge, from: start, to: start + platform)
            stops.append(station)
        }
        let line = try world.createLine(named: "Line \(world.lines.count + 1)", stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "Train \(world.trains.count + 1)").id
        try world.setTrainCars(train, to: cars)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: platform + platform / 2))
        try world.setTrainContinuation(train, along: [], stoppingAt: platform + platform / 2)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
    }
}
