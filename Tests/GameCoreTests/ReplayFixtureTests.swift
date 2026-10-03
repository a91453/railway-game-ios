import Foundation
import GameCore
import XCTest

/// Recorded command streams replayed against GameCore, the way the Railway
/// reference replays a desync recording (Stage F3b; reference
/// `docs/desync.md` §2.2, §3.1 and §3.2, and `01_MIGRATION_MAP.md`,
/// "Determinism / debugging"). Each fixture in `ReplayFixtures/` holds:
///
/// - a starting world;
/// - the commands a campaign generated on it;
/// - a checksum of the world's state before the first command, after every
///   `interval` commands, and at the end.
///
/// Replaying must give every checksum again. The first checksum that
/// differs names the stretch of commands where the worlds part, as the
/// reference's replay narrows a desync down between two saves. Every
/// world on the way must also keep the invariants: the reference checks
/// its caches every tick (§2.1); these are ours.
///
/// The checksum is taken over a description of the game (time, money, the
/// track network, stations, trains, lines, passengers and accounts; see
/// ``ReplayState``), not over the save's bytes. So a change to how a world
/// is saved that keeps every value leaves the checksums alone, and a
/// changed checksum is a change of behavior. Like a golden value, a
/// checksum is never updated to make the test pass; a fixture is recorded
/// again only for a behavior change the pull request justifies (see
/// `ReplayFixtures/README.md`).
final class ReplayFixtureTests: XCTestCase {
    func testEveryRecordedStreamReplaysToTheSameStates() throws {
        let urls = try ReplayFixture.urls()
        XCTAssertFalse(urls.isEmpty, "No fixtures in \(ReplayFixture.directory.path)")
        for url in urls {
            let name = url.lastPathComponent
            let fixture = try JSONDecoder().decode(ReplayFixture.self, from: Data(contentsOf: url))
            XCTAssertEqual(fixture.schemaVersion, ReplayFixture.schemaVersion, name)
            let operations = try fixture.commands.enumerated().map { index, command in
                try XCTUnwrap(command.operation, "\(name): command \(index) does not decode to a command")
            }
            let replayed = try ReplayFixture.checksums(from: fixture.startWorld(), applying: operations, every: fixture.interval) { index, problem in
                XCTFail("\(name): command \(index) \(operations[index]): \(problem)")
            }
            XCTAssertEqual(replayed.count, fixture.checksums.count, "\(name): \(replayed.count) checksums, the fixture has \(fixture.checksums.count)")
            if let first = Self.firstDifference(replayed, fixture.checksums) {
                let from = max(0, (first - 1) * fixture.interval)
                let to = min(operations.count, first * fixture.interval)
                XCTFail("\(name): checksum \(first) differs, so the states part between commands \(from) and \(to): \(operations[from..<to].map(\.description))")
            }
            // A stream worth replaying: its states keep changing.
            XCTAssertGreaterThan(Set(fixture.checksums).count, fixture.checksums.count / 2, "\(name): the state hardly changes")
        }
    }

    /// The index of the first checksum that differs, if any.
    static func firstDifference(_ a: [String], _ b: [String]) -> Int? {
        zip(a, b).enumerated().first { $0.element.0 != $0.element.1 }?.offset
    }

    /// The replay itself finds a divergence, in the stretch where it is:
    /// an advance that moved the clock, made a minute longer, parts the
    /// states in its own interval.
    func testADifferentCommandIsCaughtInItsStretch() throws {
        let fixture = try JSONDecoder().decode(ReplayFixture.self, from: Data(contentsOf: ReplayFixture.directory.appendingPathComponent("kernel.json")))
        var operations = fixture.commands.compactMap(\.operation)
        XCTAssertEqual(operations.count, fixture.commands.count)
        var world = try fixture.startWorld()
        var found: (index: Int, ticks: Int)?
        for (index, operation) in operations.enumerated() {
            let before = world.clock.now
            _ = KernelDifferentialTests.apply(operation, to: &world)
            if index >= 25, case .advance(let ticks) = operation, world.clock.now != before {
                found = (index, ticks)
                break
            }
        }
        let (index, ticks) = try XCTUnwrap(found, "no advance after command 25 moves the clock")
        operations[index] = .advance(ticks + 1)
        let replayed = ReplayFixture.checksums(from: try fixture.startWorld(), applying: operations, every: fixture.interval) { _, _ in }
        XCTAssertEqual(Self.firstDifference(replayed, fixture.checksums), index / fixture.interval + 1)
        // And every recorded command keeps its form through a round trip.
        for command in fixture.commands {
            let operation = try XCTUnwrap(command.operation)
            let again = try XCTUnwrap(ReplayCommand(operation))
            XCTAssertEqual(again.operation, operation)
        }
    }

    /// The fixtures are recorded from campaign cases, and only on request:
    /// `REPLAY_RECORD=<directory>` writes them there. Recording again is a
    /// behavior change to justify, never a way to make the replay pass.
    func testRecordingTheFixtures() throws {
        guard let directory = ProcessInfo.processInfo.environment["REPLAY_RECORD"] else {
            throw XCTSkip("set REPLAY_RECORD=<directory> to record the replay fixtures")
        }
        for recipe in ReplayFixture.recipes {
            // The first case from the recipe's on whose clock time passes:
            // neither at the end of time nor paused.
            var index = recipe.index
            var generated: (KernelDifferentialTests.Setup, [KernelDifferentialTests.Operation])
            repeat {
                var testCase = PropertyCase(suite: recipe.suite, seed: recipe.seed, index: index)
                generated = try recipe.generate(&testCase)
                index += 1
            } while generated.0.seconds > 1_000_000_000 || generated.0.speed == .paused
            let (setup, operations) = generated
            let start = try setup.build().0
            let commands = try operations.map { operation in
                try XCTUnwrap(ReplayCommand(operation), "\(recipe.name): \(operation) has no recorded form")
            }
            let checksums = ReplayFixture.checksums(from: start, applying: operations, every: ReplayFixture.interval) { index, problem in
                XCTFail("\(recipe.name): command \(index): \(problem)")
            }
            let fixture = try ReplayFixture(
                schemaVersion: ReplayFixture.schemaVersion, description: recipe.description,
                source: "\(recipe.suite) seed \(String(recipe.seed, radix: 16, uppercase: true)) case \(index - 1)",
                start: start, interval: ReplayFixture.interval, commands: commands, checksums: checksums
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            try encoder.encode(fixture).write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(recipe.name).json"))
        }
    }
}

// MARK: - The fixture

struct ReplayFixture: Codable {
    static let schemaVersion = 1
    static let interval = 10

    let schemaVersion: Int
    let description: String
    /// The campaign case it was recorded from.
    let source: String
    /// The starting world, saved as GameCore saves a world.
    let start: JSONValue
    let interval: Int
    let commands: [ReplayCommand]
    /// Before the first command, after every `interval` commands, and after
    /// the last.
    let checksums: [String]

    init(schemaVersion: Int, description: String, source: String, start: GameWorld, interval: Int, commands: [ReplayCommand], checksums: [String]) throws {
        self.schemaVersion = schemaVersion
        self.description = description
        self.source = source
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.start = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(start))
        self.interval = interval
        self.commands = commands
        self.checksums = checksums
    }

    func startWorld() throws -> GameWorld {
        try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(start))
    }

    /// The checksums of `world` before `operations`, after every `interval`
    /// of them and after the last. `problem` hears of a refused command that
    /// changed the world and of a broken invariant, with the command's index.
    static func checksums(
        from world: GameWorld, applying operations: [KernelDifferentialTests.Operation], every interval: Int,
        problem: (Int, String) -> Void
    ) -> [String] {
        var world = world
        var checksums = [ReplayState.checksum(of: world)]
        for (index, operation) in operations.enumerated() {
            let before = world
            if KernelDifferentialTests.apply(operation, to: &world) != nil, world != before {
                problem(index, "refused, but changed the world")
            }
            let broken = WorldInvariants.violations(in: world)
            if !broken.isEmpty { problem(index, "\(broken)") }
            if (index + 1) % interval == 0 || index + 1 == operations.count {
                checksums.append(ReplayState.checksum(of: world))
            }
        }
        return checksums
    }

    /// `ReplayFixtures/` at the repository root, found from this source file.
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ReplayFixtures", isDirectory: true)
    }

    static func urls() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The campaign cases the fixtures are recorded from: one of each
    /// network campaign of the kernel's family, long enough to run
    /// services, lines, passengers and accounts for a while.
    struct Recipe {
        let name: String
        let description: String
        let suite: String
        let seed: UInt64
        let index: Int
        let generate: (inout PropertyCase) throws -> (KernelDifferentialTests.Setup, [KernelDifferentialTests.Operation])
    }

    static var recipes: [Recipe] { [
        Recipe(
            name: "kernel", description: "The kernel campaign: track, stations, platforms and trains moved by hand, on a generated network.",
            suite: "kernel.differential", seed: 0x5EED_A001, index: 3
        ) { try KernelDifferentialTests.generate(&$0, operations: 120) },
        Recipe(
            name: "repeating-services", description: "Timetables that turn trains round and repeat, among the kernel's commands.",
            suite: "service.repeating", seed: 0x5EED_A001, index: 5
        ) { try ServicePropertyTests.generate(&$0, operations: 120, repeating: true) },
        Recipe(
            name: "line-dispatch", description: "Lines that send their trains out, with targets, windows, service days and rings.",
            suite: "line.dispatch", seed: 0x5EED_A001, index: 2
        ) { try LineDispatchPropertyTests.generate(&$0, operations: 120) },
        Recipe(
            name: "line-patterns", description: "Lines with patterns: short workings and expresses, and the loads on each stretch.",
            suite: "line.patterns", seed: 0x5EED_A001, index: 4
        ) { try LinePatternPropertyTests.generate(&$0, operations: 120) },
        Recipe(
            name: "economy", description: "Passengers boarding lines' trains, fares, and the accounts over hours and days.",
            suite: "economy.differential", seed: 0x5EED_A001, index: 1
        ) { try EconomyPropertyTests.generate(&$0, operations: 160) },
    ] }
}

/// Any JSON value, kept as it was read: the fixture's starting world.
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case integer(Int64)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
