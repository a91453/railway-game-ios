import Foundation
import GameCore
import XCTest

/// A problem report's command log (ARCHITECTURE decision 193) made into a
/// replay fixture (`ReplayFixtures/README.md`): the save it starts from,
/// and its commands in GameCore's own terms (``ReplayCommand``), with the
/// checksums of ``ReplayFixture/checksums(from:applying:every:problem:)``.
///
/// Only a report from a world that reads nothing from the app's data (a
/// blank map, the challenges) can be one: on the real map the land and the
/// ground come from the bundled files, which only the session's replay in
/// `Tests/GamePresentationTests/CommandLogReplay.swift` reads. And only one
/// whose commands the fixtures can say: a track's profile and structure,
/// an edge split for a turnout, Undo and Redo are not among their commands,
/// and conversion refuses a report with them, saying why.
///
/// To convert a report:
/// `PROBLEM_REPORT=<report.json> REPLAY_RECORD="$PWD/ReplayFixtures" swift test --filter ProblemReportFixtureTests/testConvertingAReport`.
final class ProblemReportFixtureTests: XCTestCase {
    /// The example report, from `CommandLogTests` in GamePresentationTests.
    static var example: URL {
        ReplayFixture.directory.appendingPathComponent("Reports/blank-map.json")
    }

    /// The example report converts to the fixture committed from it, which
    /// `ReplayFixtureTests` replays with the others.
    func testTheExampleReportConvertsToItsFixture() throws {
        let converted = try Self.fixture(fromReport: Data(contentsOf: Self.example), source: "Reports/blank-map.json")
        let committed = try JSONDecoder().decode(
            ReplayFixture.self, from: Data(contentsOf: ReplayFixture.directory.appendingPathComponent("problem-report-blank-map.json"))
        )
        XCTAssertEqual(converted.checksums, committed.checksums)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(converted.commands), try encoder.encode(committed.commands))
        XCTAssertEqual(converted.start, committed.start)
        XCTAssertGreaterThan(converted.commands.count, 20)
    }

    /// What it cannot say, it refuses, saying why.
    func testAReportItCannotSayIsRefused() throws {
        let example = try Data(contentsOf: Self.example)
        func refusal(_ change: (inout [String: JSONValue]) -> Void) throws -> String? {
            guard case .object(var report) = try JSONDecoder().decode(JSONValue.self, from: example) else { return "not an object" }
            change(&report)
            do {
                _ = try Self.fixture(fromReport: JSONEncoder().encode(JSONValue.object(report)), source: "")
                return nil
            } catch let refused as Refusal {
                return refused.reason
            }
        }
        XCTAssertNil(try refusal { _ in })
        XCTAssertEqual(try refusal { $0["startData"] = .object(["population": .bool(true)]) }, "it reads the app's data: replay it with CommandLogReplay")
        XCTAssertEqual(try refusal { report in
            guard case .array(var entries) = report["entries"] else { return }
            entries.append(.object(["time": .integer(0), "action": .string("undo")]))
            report["entries"] = .array(entries)
        }, "entry \(try Self.entryCount(example)): undo is not among the fixtures' commands")
    }

    /// Converts the report `PROBLEM_REPORT` names into `REPLAY_RECORD`.
    func testConvertingAReport() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["PROBLEM_REPORT"], let directory = environment["REPLAY_RECORD"] else {
            throw XCTSkip("set PROBLEM_REPORT=<report.json> and REPLAY_RECORD=<directory> to convert a problem report")
        }
        let url = URL(fileURLWithPath: path)
        let fixture = try Self.fixture(fromReport: Data(contentsOf: url), source: url.lastPathComponent)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let name = "problem-report-\(url.deletingPathExtension().lastPathComponent).json"
        try encoder.encode(fixture).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }

    // MARK: - Converting

    struct Refusal: Error {
        let reason: String
    }

    static func entryCount(_ data: Data) throws -> Int {
        try JSONDecoder().decode(Report.self, from: data).entries.count
    }

    /// The fixture `data`, a problem report, makes: its commands as GameCore
    /// runs them, each checked against the world as it goes, and the end
    /// against the report's.
    static func fixture(fromReport data: Data, source: String) throws -> ReplayFixture {
        let report = try JSONDecoder().decode(Report.self, from: data)
        guard report.schemaVersion == 1 else { throw Refusal(reason: "report schema \(report.schemaVersion)") }
        guard !report.startData.values.contains(true) else { throw Refusal(reason: "it reads the app's data: replay it with CommandLogReplay") }
        let start = report.start.world
        var world = start
        var operations: [KernelDifferentialTests.Operation] = []
        for (index, entry) in report.entries.enumerated() {
            func refuse(_ reason: String) -> Refusal { Refusal(reason: "entry \(index): \(reason)") }
            // A refused command changed nothing.
            guard !entry.refused else { continue }
            func run(_ operation: KernelDifferentialTests.Operation) throws {
                if let error = KernelDifferentialTests.apply(operation, to: &world) {
                    throw refuse("\(operation) is refused here (\(error)), not on the device")
                }
                operations.append(operation)
            }
            switch entry.action {
            case "advance": try run(.advance(entry.ticks ?? 0))
            case "setSpeed":
                guard let speed = entry.speed.flatMap(GameSpeed.init(rawValue:)) else { throw refuse("no speed") }
                try run(.setSpeed(speed))
            case "pause": try run(.pause)
            case "resume": try run(.resume)
            case "readLandRoundStations":
                guard !(entry.data?.values.contains(true) ?? false) else { throw refuse("it reads the app's data: replay it with CommandLogReplay") }
            case "command":
                guard let command = entry.command else { throw refuse("no command") }
                try convert(command, run: run, world: { world }, refuse: refuse)
            default:
                throw refuse("\(entry.action) is not among the fixtures' commands")
            }
        }
        let end = Report.Summary(
            time: world.clock.now.seconds, balance: world.economy.balance.amount, nodes: world.network.nodes.count,
            edges: world.network.edges.count, stations: world.stations.count, lines: world.lines.count, trains: world.trains.count
        )
        guard end == report.end else { throw Refusal(reason: "it ends at \(end), the device at \(report.end)") }
        let checksums = ReplayFixture.checksums(from: start, applying: operations, every: ReplayFixture.interval) { index, problem in
            XCTFail("\(source): command \(index): \(problem)")
        }
        return try ReplayFixture(
            schemaVersion: ReplayFixture.schemaVersion,
            description: "A problem report's command log (decision 193), from app \(report.version) (\(report.build)).",
            source: "problem report \(source)", start: start, interval: ReplayFixture.interval,
            commands: operations.map(ReplayCommand.init), checksums: checksums
        )
    }

    /// `command` as the fixtures' commands, run one by one on the world
    /// `world` reads.
    private static func convert(
        _ command: Report.Command, run: (KernelDifferentialTests.Operation) throws -> Void, world: () -> GameWorld,
        refuse: (String) -> Refusal
    ) throws {
        func points(_ values: [Int64]?) -> [PlanPoint] {
            guard let values else { return [] }
            return stride(from: 0, to: values.count - 1, by: 2).map { PlanPoint(x: values[$0], y: values[$0 + 1]) }
        }
        switch command.kind {
        case "buildTrack":
            guard command.transitions == [0, 0] else { throw refuse("a track with vertical curves") }
            guard command.structure == TrackStructure.surface.rawValue else { throw refuse("a \(command.structure ?? "") track") }
            func node(_ anchor: Report.Anchor?, at values: [Int64]?) throws -> TrackNodeID {
                switch anchor?.kind {
                case "node": return .node(anchor?.node ?? 0)
                case "point":
                    guard let values, values.count == 3 else { throw refuse("a point with no coordinate") }
                    try run(.buildNode(WorldCoordinate(x: values[0], y: values[1], z: values[2])))
                    guard let last = world().network.nodes.last?.id else { throw refuse("no node built") }
                    return last
                default: throw refuse("an edge split for a turnout")
                }
            }
            let first = try node(command.start, at: command.from)
            let last = try node(command.end, at: command.to)
            let controls = points(command.controls)
            try run(.buildEdge(first, last, controls.count == 2 ? .cubic(controls[0], controls[1]) : .straight))
        case "addPlatform":
            guard let edge = command.edge, let start = command.startDistance, let end = command.endDistance else { throw refuse("a platform with no place") }
            let station: StationID
            if let existing = command.station {
                station = StationID(rawValue: existing)
            } else {
                guard let name = command.name, let point = points(command.point).first, let demand = command.demand,
                      let kind = StationDemandKind(rawValue: demand.kind) else { throw refuse("a new station with no name, point or demand") }
                try run(.buildStationAt(name, point))
                guard let built = world().stations.last?.id else { throw refuse("no station built") }
                station = built
                if world().accounts.mode == .management, !world().landDemand {
                    guard demand.hinterland == 0 else { throw refuse("a demand with a hinterland") }
                    try run(.setStationDemand(station, StationDemand(kind: kind, dailyTrips: demand.dailyTrips)))
                }
            }
            try run(.addPlatform(station, .edge(edge), start, end))
        case "removePlatform":
            guard let station = command.station, let edge = command.edge, let start = command.startDistance else { throw refuse("a platform with no place") }
            try run(.removePlatform(StationID(rawValue: station), .edge(edge), start))
        case "removeTrack":
            guard let number = command.edge, let edge = world().network.edge(.edge(number)) else { throw refuse("no edge") }
            try run(.removeEdge(.edge(number)))
            for node in Set([edge.from, edge.to]).sorted() where world().network.node(node)?.ends.isEmpty == true {
                try run(.removeNode(node))
            }
        default:
            throw refuse("\(command.kind) is not among the fixtures' commands")
        }
    }

    /// A problem report as GamePresentation writes it (`CommandLogReport`),
    /// read as plain values: GameCore's tests do not see GamePresentation.
    struct Report: Decodable {
        struct Anchor: Decodable {
            var kind: String
            var node: Int?
            var point: [Int64]?
            var edge: Int?
            var distance: Int64?
        }

        struct Demand: Decodable {
            var kind: String
            var dailyTrips: Int64
            var hinterland: Int64
        }

        struct Command: Decodable {
            var kind: String
            var start: Anchor?
            var end: Anchor?
            var from: [Int64]?
            var to: [Int64]?
            var controls: [Int64]?
            var transitions: [Int64]?
            var structure: String?
            var edge: Int?
            var station: Int?
            var name: String?
            var point: [Int64]?
            var demand: Demand?
            var startDistance: Int64?
            var endDistance: Int64?
        }

        struct Entry: Decodable {
            var time: Int64
            var action: String
            var refused: Bool = false
            var command: Command?
            var ticks: Int?
            var speed: String?
            var data: [String: Bool]?

            private enum CodingKeys: String, CodingKey {
                case time, action, refused, command, ticks, speed, data
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                time = try container.decode(Int64.self, forKey: .time)
                action = try container.decode(String.self, forKey: .action)
                refused = try container.decodeIfPresent(Bool.self, forKey: .refused) ?? false
                command = try container.decodeIfPresent(Command.self, forKey: .command)
                ticks = try container.decodeIfPresent(Int.self, forKey: .ticks)
                speed = try container.decodeIfPresent(String.self, forKey: .speed)
                data = try container.decodeIfPresent([String: Bool].self, forKey: .data)
            }
        }

        struct Summary: Decodable, Equatable, CustomStringConvertible {
            var time: Int64
            var balance: Int64
            var nodes: Int
            var edges: Int
            var stations: Int
            var lines: Int
            var trains: Int

            var description: String {
                "\(time) s, $\(balance), \(nodes) nodes, \(edges) edges, \(stations) stations, \(lines) lines, \(trains) trains"
            }
        }

        var schemaVersion: Int
        var version: String
        var build: String
        var start: SavedGame
        var startData: [String: Bool]
        var entries: [Entry]
        var end: Summary
    }
}
