import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// A seeded campaign of player edits and time on the world a player
/// actually gets: `GameWorld.newGame()`, with every switch the app's new
/// game turns on (traffic control, network routing, flexible dispatch, door
/// crowding, rolling-stock economics, tourism, the city ...), which the
/// GameCore property campaigns, on worlds with them off, do not reach
/// (docs/research/GAP_RESEARCH_2026-10-12.md, 4.2).
///
/// Every edit either succeeds or throws and leaves the world as it was;
/// after each the world saves and loads back equal; and every stretch of
/// time is the same advanced at once, in random pieces, and after a save
/// and load. `NEW_GAME_CAMPAIGN=<steps>` runs longer cases than CI's,
/// `NEW_GAME_CAMPAIGN_SEEDS=<n>` n more seeds.
final class NewGameCampaignTests: XCTestCase {
    private struct Generator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func below(_ bound: Int) -> Int {
            Int(next() % UInt64(bound))
        }

        mutating func element<T>(of array: [T]) -> T? {
            array.isEmpty ? nil : array[below(array.count)]
        }
    }

    private static let seeds: [UInt64] = [0x5EED_B001, 0x5EED_B002]

    func testEditsAndTimeOnANewGame() throws {
        let steps = ProcessInfo.processInfo.environment["NEW_GAME_CAMPAIGN"].flatMap(Int.init) ?? 24
        let extra = ProcessInfo.processInfo.environment["NEW_GAME_CAMPAIGN_SEEDS"].flatMap(Int.init) ?? 0
        var derive = Generator(state: 0x5EED_B0B0)
        let base = try Self.world()
        for seed in Self.seeds + (0..<max(0, extra)).map({ _ in derive.next() }) {
            var generator = Generator(state: seed)
            var world = base
            for step in 0..<steps {
                let label = "seed \(String(seed, radix: 16)) step \(step)"
                if generator.below(3) == 0 {
                    try checkTime(&world, minutes: 1 + generator.below(240), generator: &generator, label: label)
                } else {
                    try edit(&world, generator: &generator, label: label)
                }
            }
        }
    }

    /// Two lines of the balance report's year with every switch on, and a
    /// third train on the first.
    private static func world() throws -> GameWorld {
        let bounds = GameWorld.newGameBounds
        let towns = Land.townCentres(seed: 1, in: bounds)
        let first = towns[0], second = towns[1]
        let edgeX = second.x > first.x ? 40_000 : bounds.width - 40_000
        let edge = PlanPoint(x: edgeX, y: first.y + (first.y - second.y) * (edgeX - first.x) / (first.x - second.x))
        var world = try newGameLine(through: [first, second])
        let shifted = PlanPoint(x: first.x, y: first.y + 6_144)
        world = try newGameLine(through: [shifted, PlanPoint(x: edge.x, y: edge.y + 6_144)], in: world)
        try world.advance(ticks: 1)
        return world
    }

    private func checkTime(_ world: inout GameWorld, minutes: Int, generator: inout Generator, label: String) throws {
        var whole = world
        try whole.advance(ticks: minutes)
        var pieces = world
        var left = minutes
        while left > 0 {
            let piece = 1 + generator.below(min(left, 30))
            try pieces.advance(ticks: piece)
            left -= piece
        }
        var loaded = try roundTrip(world, label: label)
        try loaded.advance(ticks: minutes)
        XCTAssert(pieces == whole, "\(label): \(minutes) minutes in pieces are the same as at once: \(Self.differences(pieces, whole))")
        XCTAssert(loaded == whole, "\(label): \(minutes) minutes after a save and load are the same: \(Self.differences(loaded, whole))")
        world = whole
    }

    /// The top-level keys of the two worlds' saves that differ.
    private static func differences(_ a: GameWorld, _ b: GameWorld) -> [String] {
        func object(_ world: GameWorld) -> [String: Any] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return (try? JSONSerialization.jsonObject(with: encoder.encode(world))) as? [String: Any] ?? [:]
        }
        let x = object(a), y = object(b)
        func data(_ value: Any?) -> Data? {
            try? JSONSerialization.data(withJSONObject: [value ?? NSNull()], options: .sortedKeys)
        }
        return Set(x.keys).union(y.keys).sorted().filter { data(x[$0]) != data(y[$0]) }
    }

    private func roundTrip(_ world: GameWorld, label: String) throws -> GameWorld {
        let decoded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
        XCTAssert(decoded == world, "\(label): saves and loads back equal: \(Self.differences(decoded, world))")
        return decoded
    }

    private func edit(_ world: inout GameWorld, generator: inout Generator, label: String) throws {
        let before = world
        let line = generator.element(of: world.lines)
        let train = generator.element(of: world.trains)
        var name = ""
        do {
            switch generator.below(15) {
            case 0:
                name = "reverse"
                if let line { try world.reverseLineStops(line.id) }
            case 1:
                name = "trains in service"
                let count = generator.below(4)
                if let line { try world.setLineTrainsInService(line.id, to: TrainsInService(peak: count, offPeak: count, low: max(0, count - 1))) }
            case 2:
                name = "assign"
                if let line, let train {
                    if world.lines.contains(where: { $0.assignedTrains.contains(train.id) }) { try world.unassignTrain(train.id) }
                    let unassigned = world
                    do {
                        try world.assignTrain(train.id, to: line.id)
                    } catch {
                        XCTAssert(world == unassigned, "\(label): a refused assignment leaves the world as it was: \(Self.differences(world, unassigned))")
                        world = unassigned
                    }
                }
            case 3:
                name = "stops"
                if let line {
                    var stops = line.stops
                    if stops.count > 2, generator.below(2) == 0 {
                        stops.remove(at: generator.below(stops.count))
                    } else if let station = generator.element(of: world.stations), !stops.contains(station.id) {
                        stops.insert(station.id, at: generator.below(stops.count + 1))
                    }
                    try world.setLineStops(line.id, to: stops)
                }
            case 4:
                name = "pattern"
                if let line, line.stops.count > 2 {
                    _ = try world.addLinePattern(line.id, calling: [0, line.stops.count - 1])
                }
            case 5:
                name = "remove pattern"
                if let line, !line.patterns.isEmpty { try world.removeLinePattern(line.id, at: 0) }
            case 6:
                name = "remove edge"
                if let edge = generator.element(of: world.network.edges.map(\.id)) { try world.removeTrackEdge(edge) }
            case 7:
                name = "remove station"
                if let station = generator.element(of: world.stations) { try world.removeStation(station.id) }
            case 8:
                name = "type"
                if let train { try world.setTrainType(train.id, to: generator.element(of: Array(TrainType.allCases.prefix(5)))) }
            case 9:
                name = "cars"
                if let train { try world.setTrainCars(train.id, to: 1 + generator.below(6)) }
            case 10:
                name = "stop and sell"
                if let train {
                    try world.unplaceTrain(train.id)
                    let unplaced = world
                    do {
                        try world.sellTrain(train.id)
                    } catch {
                        XCTAssert(world == unplaced, "\(label): a refused sale leaves the world as it was: \(Self.differences(world, unplaced))")
                        world = unplaced
                    }
                }
            case 11:
                name = "ring"
                if let line { try world.setLineRing(line.id, to: !line.isRing) }
            case 12:
                name = "window"
                if let line { try world.setLineServiceWindow(line.id, to: generator.below(2) == 0 ? .allDay : .hours(open: 6 * 60, close: 22 * 60)) }
            case 13:
                name = "stop service"
                if let train { try world.stopTrainService(train.id) }
            default:
                name = "unassign"
                if let train { try world.unassignTrain(train.id) }
            }
        } catch {
            XCTAssert(world == before, "\(label): a refused \(name) (\(error)) leaves the world as it was: \(Self.differences(world, before))")
            world = before
            return
        }
        _ = try roundTrip(world, label: "\(label) after \(name)")
    }
}
