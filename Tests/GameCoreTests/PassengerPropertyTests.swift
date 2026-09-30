import Foundation
import GameCore
import XCTest

/// G1a (ARCHITECTURE decision 34): station demand, release, queues and the
/// conservation audit, on GameCore and on ``ReferenceWorld`` side by side.
///
/// Every case builds three to six stations in a row, starting at a random
/// minute (before minute 0 too), and runs generated operations: demands of
/// every kind and size (up to the largest, and invalid ones), lines created,
/// re-stopped and removed, and time in short and long steps at every speed.
/// Passengers need no track, so every step of the clock is one GameCore may
/// skip as idle: the release of the skipped minutes is checked against the
/// reference, which steps every minute. After every operation the outcome,
/// every station's queue, counts and remainders, and every pair's trips must
/// agree; the world must keep every invariant (every passenger accounted
/// for) and survive a save exactly.
final class PassengerPropertyTests: XCTestCase {
    enum Operation {
        case demand(StationID, StationDemand?)
        case line([StationID])
        case removeLine(LineID)
        case stops(LineID, [StationID])
        case speed(GameSpeed)
        case advance(Int)
    }

    private static let costs = ConstructionCosts(track: 100, station: 1_000, train: 500)

    /// A world of this campaign's stations after `operations` generated
    /// operations; for the save mutation campaign.
    static func generateWorld(_ testCase: inout PropertyCase, operations: Int) throws -> GameWorld {
        var (world, _) = try begin(&testCase)
        for _ in 0..<operations {
            apply(operation(in: world, using: &testCase.random), to: &world)
        }
        return world
    }

    private static func begin(_ testCase: inout PropertyCase) throws -> (GameWorld, ReferenceWorld) {
        let base = testCase.random.element(of: [Int64(0), 419, 1_439, -1_500])
        let start = base + testCase.random.int64(in: 0...900)
        let count = 3 + testCase.random.below(4)
        testCase.note("\(count) stations, from minute \(start)")
        var world = try GameWorld(
            width: 2 * count + 1, height: 3, economy: GameEconomy(balance: 1_000_000, costs: costs),
            clock: GameClock(now: GameTime(minutes: start), speed: .normal)
        )
        var model = ReferenceWorld(width: 2 * count + 1, height: 3, balance: 1_000_000, costs: costs, minutes: start, speed: .normal)
        for index in 0..<count {
            let position = GridPosition(x: 2 * index + 1, y: 1)
            try world.buildStation(named: "S\(index + 1)", at: position)
            XCTAssertNil(model.buildStation(named: "S\(index + 1)", at: position))
        }
        return (world, model)
    }

    private static func stops(_ world: GameWorld, using random: inout SplitMix64) -> [StationID] {
        let ids = world.stations.map(\.id)
        var stops: [StationID] = []
        for _ in 0..<(2 + random.below(4)) {
            // Now and then a station twice in a row (refused), or one that
            // does not exist; otherwise any station, repeats allowed.
            if random.chance(1, in: 30) {
                stops.append(StationID(rawValue: 99))
            } else if random.chance(1, in: 25), let last = stops.last {
                stops.append(last)
            } else {
                var next = random.element(of: ids)
                while next == stops.last { next = random.element(of: ids) }
                stops.append(next)
            }
        }
        return stops
    }

    static func operation(in world: GameWorld, using random: inout SplitMix64) -> Operation {
        let station = random.chance(1, in: 20) ? StationID(rawValue: 99) : random.element(of: world.stations).id
        let line = world.lines.isEmpty || random.chance(1, in: 15) ? LineID(rawValue: 99) : random.element(of: world.lines).id
        switch random.below(20) {
        case 0..<6:
            guard !random.chance(1, in: 6) else { return .demand(station, nil) }
            let trips: Int64 = switch random.below(10) {
            case 0: 0
            case 1: StationDemand.maximumDailyTrips
            case 2: random.chance(1, in: 2) ? -1 : StationDemand.maximumDailyTrips + 1
            case 3, 4: random.int64(in: 1...40)
            case 5, 6: random.int64(in: 100...5_000)
            default: random.int64(in: 10_000...300_000)
            }
            return .demand(station, StationDemand(kind: random.element(of: StationDemandKind.allCases), dailyTrips: trips))
        case 6..<9:
            return .line(stops(world, using: &random))
        case 9:
            return .removeLine(line)
        case 10..<12:
            return .stops(line, stops(world, using: &random))
        case 12:
            return .speed(random.element(of: GameSpeed.allCases))
        case 13..<17:
            return .advance(1 + random.below(20))
        case 17, 18:
            return .advance(30 + random.below(200))
        default:
            return .advance(random.element(of: [720, 1_440]))
        }
    }

    @discardableResult
    static func apply(_ operation: Operation, to world: inout GameWorld) -> GameError? {
        do throws(GameError) {
            switch operation {
            case .demand(let id, let demand): try world.setStationDemand(id, to: demand)
            case .line(let stops): try world.createLine(named: "L", stops: stops)
            case .removeLine(let id): try world.removeLine(id)
            case .stops(let id, let stops): try world.setLineStops(id, to: stops)
            case .speed(let speed): world.setSpeed(speed)
            case .advance(let ticks): try world.advance(ticks: ticks)
            }
            return nil
        } catch {
            return error
        }
    }

    @discardableResult
    static func apply(_ operation: Operation, to model: inout ReferenceWorld) -> GameError? {
        switch operation {
        case .demand(let id, let demand): return model.setStationDemand(id, demand)
        case .line(let stops): return model.createLine(named: "L", stops: stops)
        case .removeLine(let id): return model.removeLine(id)
        case .stops(let id, let stops): return model.setLineStops(id, stops)
        case .speed(let speed):
            model.setSpeed(speed)
            return nil
        case .advance(let ticks): return model.advance(ticks: ticks)
        }
    }

    /// How GameCore and the reference differ, if they do.
    private static func differences(_ world: GameWorld, _ model: ReferenceWorld) -> [String] {
        var problems: [String] = []
        if world.clock.now.minutes != model.minutes { problems.append("minute \(world.clock.now.minutes) vs \(model.minutes)") }
        let summaries = world.passengers.filter { $0.demand != nil || $0.released > 0 }.map(PassengerSummary.init)
        if summaries != model.passengerSummaries { problems.append("passengers \(summaries) vs reference \(model.passengerSummaries)") }
        var remainders: [Int: [Int: Int64]] = [:]
        for record in world.passengers where !record.remainders.isEmpty {
            remainders[record.station.rawValue] = Dictionary(uniqueKeysWithValues: record.remainders.map { ($0.destination.rawValue, $0.value) })
        }
        if remainders != model.passengers.fraction { problems.append("remainders \(remainders) vs reference \(model.passengers.fraction)") }
        for origin in world.stations.map(\.id) {
            for destination in world.stations.map(\.id) {
                let trip = world.passengerTrip(from: origin, to: destination)
                let expected = model.passengerTrip(from: origin.rawValue, to: destination.rawValue)
                if trip?.line.rawValue != expected?.line || (trip.map { $0.direction == .outbound }) != expected?.outbound {
                    problems.append("trip \(origin.rawValue)→\(destination.rawValue) \(String(describing: trip)) vs \(String(describing: expected))")
                }
                if world.hourlyDemand(from: origin, to: destination) != model.hourlyTrips(from: origin.rawValue, to: destination.rawValue) {
                    problems.append("hourly trips \(origin.rawValue)→\(destination.rawValue) differ")
                }
            }
        }
        return problems
    }

    func testPassengersMatchTheReferenceAtEveryStep() throws {
        var digest = Digest()
        var tally: [String: Int] = [:]
        var operations = 0
        let ran = try runCampaign("passenger.differential", cases: 20) { testCase in
            var (world, model) = try Self.begin(&testCase)
            for step in 0..<50 {
                let operation = Self.operation(in: world, using: &testCase.random)
                testCase.note("\(step): \(operation)")
                let before = world
                let outcome = Self.apply(operation, to: &world)
                let expected = Self.apply(operation, to: &model)
                operations += 1
                guard outcome == expected else {
                    return testCase.fail("\(operation): \(String(describing: outcome)) vs reference \(String(describing: expected))")
                }
                if outcome != nil, world != before { return testCase.fail("refused \(operation) but changed the world") }
                let name = "\(operation)".components(separatedBy: "(")[0]
                tally["\(outcome.map { "\($0)".components(separatedBy: "(")[0] } ?? "ok") \(name)", default: 0] += 1
                for (old, new) in zip(before.stations.map { before.passengerLedger(of: $0.id) }, world.stations.map { world.passengerLedger(of: $0.id) }) {
                    if new.released > old.released { tally["stations releasing", default: 0] += 1 }
                    if new.overflowed > old.overflowed { tally["stations overflowing", default: 0] += 1 }
                    if new.abandoned > old.abandoned { tally["stations abandoning", default: 0] += 1 }
                }
                let problems = Self.differences(world, model) + WorldInvariants.violations(in: world)
                guard problems.isEmpty else { return testCase.fail(problems.joined(separator: "\n")) }
                if let problem = WorldInvariants.roundTripProblem(of: world) { return testCase.fail(problem) }
            }
            tally["passengers released", default: 0] += Int(world.passengers.reduce(0) { $0 + $1.released })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            digest.add(String(decoding: try encoder.encode(world), as: UTF8.self))
        }
        let summary = tally.keys.sorted().map { "\($0) \(tally[$0]!)" }.joined(separator: ", ")
        print("[digest] passenger.differential \(digest.hex) (\(summary))")
        print("[volume] passenger.differential \(ran) cases, \(operations) operations")
        assertVolume(ran == 20 * PropertySeeds.active.count, "every case ran")
        assertVolume(tally["stations releasing", default: 0] > 600, "stations release passengers")
        assertVolume(tally["stations overflowing", default: 0] > 200, "full stations turn passengers away")
        assertVolume(tally["stations abandoning", default: 0] > 50, "passengers lose their lines")
        assertVolume(tally["invalidStationDemand demand", default: 0] > 20, "invalid demands are refused")
        assertVolume(tally["unknownStation demand", default: 0] > 20, "demands for missing stations are refused")
        assertVolume(tally["ok removeLine", default: 0] > 20, "lines are removed")
        assertVolume(tally["ok stops", default: 0] > 50, "lines are re-stopped")
    }
}
