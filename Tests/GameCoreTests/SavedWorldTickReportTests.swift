import Foundation
@testable import GameCore
import XCTest

/// Decision 876 (TICK-REAL): what a tick costs in a saved game, GameCore
/// alone, and a checksum of the world it ends in. A report, run only on
/// request; it asserts nothing about speed and changes no rule:
///
///     SAVED_WORLD=/tmp/worlds/hk-all-simple.json swift test --skip-build \
///       --filter SavedWorldTickReportTests
///
/// The save is any ``SavedGame`` (`BoughtWorldSaveTests` writes the maps
/// with every line on sale bought; `DEPOT_RETURN_SAVE` writes a report's
/// world part way through). GameCoreTests builds in a minute after a
/// change to GameCore, where the reports of GamePresentationTests lay
/// their lines again each time, so two builds are told apart in minutes:
/// the same checksums mean the change left the world bit for bit as it
/// was, tick by tick.
///
/// - `SAVED_WORLD_TICKS`: the ticks timed (default 1,440: a game day at a
///   minute a tick).
/// - `SAVED_WORLD_SPEED`: the ``GameSpeed`` played at (default `normal`,
///   a minute a tick; `fast` is ten).
/// - `SAVED_WORLD_SKIP`: ticks played first, not timed (default 0).
/// - `SAVED_WORLD_CHECK`: a checksum every so many ticks (default 60;
///   0 for the last one only). Each is FNV-1a of the world's JSON, keys
///   sorted, as `DEPOT_RETURN_CHECKSUM`'s (decision 805); the line
///   `SAVED_WORLD checksums` is one over all of them.
/// - `SAVED_WORLD_HOLD=<seconds>`: keeps stepping a copy of the world so
///   long before the timed ticks and prints the process ID, for a sampler.
/// - `SAVED_WORLD_HOURS=1`: a line of times for each hour of the clock.
/// - `SAVED_WORLD_EACH=1`: every checksum, with its time.
/// - `SAVED_WORLD_AUDIT=1`: every answer a memo gives again (a run's trip,
///   a line's plans, the trains in the way, the due runs that cannot
///   leave, ``GameWorld/AnswerAudit``) and every set of holders changed in
///   place (``GameWorld/HolderAudit``) is checked against working it out
///   again, and the test traps on the first that differs. Several times
///   slower: for a proof, not for times.
final class SavedWorldTickReportTests: XCTestCase {
    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    static func checksum(of world: GameWorld) throws -> UInt64 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var checksum: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in try encoder.encode(world) { checksum = (checksum ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return checksum
    }

    private static func clockText(_ seconds: Int64) -> String {
        let minutes = seconds % GameTime.secondsPerDay / 60
        return String(format: "day %lld %02lld:%02lld", seconds / GameTime.secondsPerDay, minutes / 60, minutes % 60)
    }

    func testWhatASavedWorldCostsATick() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["SAVED_WORLD"] else {
            throw XCTSkip("Set SAVED_WORLD=<save> to time its ticks (decision 876).")
        }
        guard environment["SAVED_WORLD_AUDIT"] != nil else { return try report(environment, path) }
        let answers = GameWorld.AnswerAudit(), holders = GameWorld.HolderAudit()
        try GameWorld.$answerAudit.withValue(answers) {
            try GameWorld.$holderAudit.withValue(holders) { try report(environment, path) }
        }
        let text = "SAVED_WORLD audit: \(answers.checked) answers given again were the answers worked out again; "
            + "\(holders.updates) holders changed in place were the holders worked out again (\(holders.rebuilds) worked out)\n"
        FileHandle.standardError.write(Data(text.utf8))
    }

    private func report(_ environment: [String: String], _ path: String) throws {
        let ticks = Int(environment["SAVED_WORLD_TICKS"] ?? "") ?? 1_440
        let skip = Int(environment["SAVED_WORLD_SKIP"] ?? "") ?? 0
        let every = Int(environment["SAVED_WORLD_CHECK"] ?? "") ?? 60
        let speed = environment["SAVED_WORLD_SPEED"].flatMap(GameSpeed.init(rawValue:)) ?? .normal
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent + " \(speed.rawValue)"
        var world = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: URL(fileURLWithPath: path))).world
        world.setSpeed(speed)
        func say(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
        say("SAVED_WORLD \(name): \(world.stations.count) stations, \(world.lines.count) lines, \(world.trains.count) trains, "
            + "\(world.network.edges.count) edges, traffic control \(world.isTrafficControlEnabled), block sections \(world.blockSections), "
            + "from \(Self.clockText(world.clock.now.seconds))")
        if skip > 0 { try world.advance(ticks: skip) }
        if let hold = environment["SAVED_WORLD_HOLD"].flatMap(Double.init) {
            say("SAVED_WORLD \(name): pid \(ProcessInfo.processInfo.processIdentifier), holding \(Int(hold)) s")
            let until = Date().addingTimeInterval(hold)
            var copy = world
            while Date() < until { try copy.advance(ticks: 1) }
        }
        let clock = ContinuousClock()
        var costs: [Double] = [], clocks: [Int64] = []
        var hours: [Int64: [Double]] = [:]
        var all: UInt64 = 0xcbf2_9ce4_8422_2325
        var deadlocked = 0, deadlockedTicks = 0, deadlockedAt: Int64 = 0
        for tick in 1...max(1, ticks) {
            let before = world.clock.now.seconds
            let cost = Self.ms(try clock.measure { try world.advance(ticks: 1) })
            costs.append(cost)
            clocks.append(before)
            hours[before / 3_600, default: []].append(cost)
            let stuck = world.deadlockedTrains().count
            if stuck > 0 { deadlockedTicks += 1 }
            if stuck > deadlocked { (deadlocked, deadlockedAt) = (stuck, world.clock.now.seconds) }
            if tick == ticks || (every > 0 && tick % every == 0) {
                let checksum = try Self.checksum(of: world)
                for shift in stride(from: 0, to: 64, by: 8) { all = (all ^ (checksum >> UInt64(shift) & 0xff)) &* 0x100_0000_01b3 }
                if environment["SAVED_WORLD_EACH"] != nil {
                    say("SAVED_WORLD \(name) checksum \(String(checksum, radix: 16)) at \(Self.clockText(world.clock.now.seconds))")
                }
            }
        }
        func line(_ label: String, _ values: [Double]) -> String {
            let sorted = values.sorted()
            return String(
                format: "SAVED_WORLD %@ %@: %d ticks, total %.1f s, mean %.2f ms, median %.2f ms, p95 %.2f ms, longest %.2f ms",
                name, label, sorted.count, sorted.reduce(0, +) / 1_000, sorted.reduce(0, +) / Double(max(1, sorted.count)),
                sorted[sorted.count / 2], sorted[min(sorted.count - 1, sorted.count * 95 / 100)], sorted.last ?? 0
            )
        }
        for hour in hours.keys.sorted() where environment["SAVED_WORLD_HOURS"] != nil {
            say(line(String(format: "hour %02lld", hour % 24), hours[hour] ?? []))
        }
        for index in costs.indices.sorted(by: { costs[$0] > costs[$1] }).prefix(8) {
            say(String(format: "SAVED_WORLD %@ costliest: %@ %.1f ms", name, Self.clockText(clocks[index]), costs[index]))
        }
        say(line("every tick", costs))
        say("SAVED_WORLD \(name) deadlocked: most \(deadlocked)\(deadlocked > 0 ? " at \(Self.clockText(deadlockedAt))" : ""), in \(deadlockedTicks) ticks")
        say("SAVED_WORLD \(name) checksums \(String(all, radix: 16)), last \(String(try Self.checksum(of: world), radix: 16)) at \(Self.clockText(world.clock.now.seconds))")
    }
}
