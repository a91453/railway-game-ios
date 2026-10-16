import Foundation
import GameCore

/// GameSim's command line (decision 260): operations run one after another
/// on one game, joined by `then`, each answering with one line of JSON, a
/// receipt. An option an operation does not know is refused, with the ones
/// it does. `--state FILE` keeps the game between runs: read before the
/// first operation (unless it starts or loads a game) and written after the
/// last, as a save file the app reads.
///
///     swift run GameSim new-game --seed 1 then advance --days 3 then dump --sections economy,trains
///     swift run GameSim --state /tmp/game.json load report.json then apply report.json
///     swift run GameSim --state /tmp/game.json advance --days 30 then dump
@MainActor
public struct HeadlessCommandLine {
    /// One operation and what it takes.
    public struct Operation: Hashable, Sendable {
        public let name: String
        /// Its options, without the dashes, and whether each takes a value.
        public let options: [String: Bool]
        /// Whether it takes one file argument.
        public let takesFile: Bool
        public let summary: String
    }

    public static let operations: [Operation] = [
        Operation(name: "new-game", options: ["seed": true, "buys-map": false, "rules": true], takesFile: false, summary: "a new blank-map game; --seed N (1), --rules simple|realistic (simple, as the app), --buys-map"),
        Operation(name: "load", options: [:], takesFile: true, summary: "a save file, or a problem report's command log from its start"),
        Operation(name: "apply", options: [:], takesFile: true, summary: "a problem report's log, a list of log entries, or a list of commands"),
        Operation(name: "advance", options: ["days": true, "hours": true, "minutes": true, "seconds": true], takesFile: false, summary: "let game time run; --days, --hours, --minutes, --seconds add up"),
        Operation(name: "play", options: ["policy": true, "days": true, "seed": true], takesFile: false, summary: "play a way to play for --days N (policies: \(Policy.names.joined(separator: ", "))); --seed N for a loaded game's towns"),
        Operation(name: "dump", options: ["sections": true], takesFile: false, summary: "the world summed up; --sections \(HeadlessSummary.Section.allCases.map(\.rawValue).joined(separator: ","))"),
        Operation(name: "save", options: [:], takesFile: true, summary: "write the game as a save file"),
    ]

    /// The global options, before the first operation.
    public static let globalOptions = ["state": "keep the game in this save file between runs", "data": "the app's real-world data folder, for logs that read land"]

    /// A parsed operation.
    public struct Step: Hashable, Sendable {
        public var name: String
        public var options: [String: String] = [:]
        public var file: String?
    }

    /// Why the command line cannot run: what is wrong and what it takes.
    public struct UsageError: Error, CustomStringConvertible, Sendable {
        public let description: String
    }

    public var state: String?
    public var data: String?
    public var steps: [Step] = []

    /// Parses `arguments` (without the program's name).
    public init(arguments: [String]) throws(UsageError) {
        var rest = arguments[...]
        while let first = rest.first, first.hasPrefix("--") {
            let name = String(first.dropFirst(2))
            guard Self.globalOptions[name] != nil else {
                throw UsageError(description: "unknown option --\(name) before the first operation; known: \(Self.globalOptions.keys.sorted().map { "--\($0)" }.joined(separator: ", "))")
            }
            rest = rest.dropFirst()
            guard let value = rest.first else { throw UsageError(description: "--\(name) needs a value") }
            rest = rest.dropFirst()
            if name == "state" { state = value } else { data = value }
        }
        var groups: [[String]] = [[]]
        for word in rest {
            if word == "then" { groups.append([]) } else { groups[groups.count - 1].append(word) }
        }
        for group in groups {
            guard let name = group.first else { throw UsageError(description: "an empty operation (\"then\" twice, or at an end)\n" + Self.usage) }
            guard let operation = Self.operations.first(where: { $0.name == name }) else {
                throw UsageError(description: "unknown operation \(name); known: \(Self.operations.map(\.name).joined(separator: ", "))")
            }
            var step = Step(name: name)
            var words = group.dropFirst()[...]
            while let word = words.first {
                words = words.dropFirst()
                if word.hasPrefix("--") {
                    let option = String(word.dropFirst(2))
                    guard let takesValue = operation.options[option] else {
                        let known = operation.options.keys.sorted().map { "--\($0)" }.joined(separator: ", ")
                        throw UsageError(description: "\(name) does not take --\(option); it takes \(known.isEmpty ? "no options" : known)")
                    }
                    if takesValue {
                        guard let value = words.first else { throw UsageError(description: "\(name) --\(option) needs a value") }
                        words = words.dropFirst()
                        step.options[option] = value
                    } else {
                        step.options[option] = ""
                    }
                } else if operation.takesFile, step.file == nil {
                    step.file = word
                } else {
                    throw UsageError(description: "\(name) does not take \(word)")
                }
            }
            if operation.takesFile, step.file == nil { throw UsageError(description: "\(name) needs a file") }
            steps.append(step)
        }
    }

    /// What the program prints when asked how to use it.
    public static var usage: String {
        var lines = ["usage: GameSim [--state FILE] [--data DIR] OPERATION [OPTIONS] [then OPERATION [OPTIONS]]...", "", "operations:"]
        for operation in operations {
            lines.append("  \(operation.name)\(operation.takesFile ? " FILE" : "")  \(operation.summary)")
        }
        lines.append("")
        lines.append("options before the first operation:")
        for (name, text) in globalOptions.sorted(by: { $0.key < $1.key }) {
            lines.append("  --\(name)  \(text)")
        }
        lines.append("")
        lines.append("Each operation prints one line of JSON: {\"op\", \"ok\", \"result\" or \"error\"}. Money is in whole dollars.")
        return lines.joined(separator: "\n")
    }

    /// Runs the steps, giving each receipt to `print`; whether every step
    /// went through. `read` and `write` reach files (the program's are
    /// the disk; tests give their own).
    public func run(
        print: (String) -> Void, read: (String) throws -> Data, write: (String, Data) throws -> Void
    ) -> Bool {
        var game: HeadlessGame?
        let realWorld = data.map { RealWorldFiles(folder: URL(fileURLWithPath: $0)) }
        if let state, steps.first.map({ $0.name != "new-game" && $0.name != "load" }) ?? true, let saved = try? read(state) {
            game = try? HeadlessGame.load(saved)
        }
        for step in steps {
            do {
                let result = try Self.run(step, on: &game, realWorld: realWorld, read: read, write: write)
                print(Self.receipt(step.name, result: result))
            } catch {
                print(Self.receipt(step.name, error: "\(error)"))
                return false
            }
        }
        if let state, let game {
            do {
                try write(state, try game.saveFile())
            } catch {
                print(Self.receipt("state", error: "\(error)"))
                return false
            }
        }
        return true
    }

    private static func run(
        _ step: Step, on game: inout HeadlessGame?, realWorld: RealWorldFiles?,
        read: (String) throws -> Data, write: (String, Data) throws -> Void
    ) throws -> any Encodable {
        switch step.name {
        case "new-game":
            let seed = try step.options["seed"].map { try number($0, "seed", UInt32.self) } ?? 1
            var rules = NewGameRules.simple
            if let name = step.options["rules"] {
                guard let chosen = NewGameRules(rawValue: name) else {
                    throw HeadlessGameError("unknown rules \(name); known: \(NewGameRules.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                rules = chosen
            }
            let started = HeadlessGame.newGame(seed: seed, buysMap: step.options["buys-map"] != nil, rules: rules)
            game = started
            return started.summary([.economy])
        case "load":
            let loaded = try HeadlessGame.load(read(step.file!))
            game = loaded
            return loaded.summary([.economy])
        default:
            break
        }
        guard let game else { throw HeadlessGameError("no game: start with new-game or load, or give --state a game") }
        switch step.name {
        case "apply":
            return try game.apply(read(step.file!), realWorld: realWorld)
        case "advance":
            var seconds: Int64 = 0
            for (option, unit) in [("days", GameTime.secondsPerDay), ("hours", GameTime.secondsPerHour), ("minutes", GameTime.secondsPerMinute), ("seconds", 1)] {
                if let value = step.options[option] { seconds += try number(value, option, Int64.self) * unit }
            }
            guard seconds > 0 else { throw HeadlessGameError("advance needs --days, --hours, --minutes or --seconds above 0") }
            return game.advance(seconds: seconds)
        case "play":
            guard let name = step.options["policy"] else { throw HeadlessGameError("play needs --policy; known: \(Policy.names.joined(separator: ", "))") }
            guard let seed = try step.options["seed"].map({ try number($0, "seed", UInt32.self) }) ?? game.seed else {
                throw HeadlessGameError("play needs --seed: a loaded game does not say which towns it drew")
            }
            guard let policy = Policy.named(name, seed: seed, bounds: game.world.bounds) else {
                throw HeadlessGameError("unknown policy \(name); known: \(Policy.names.joined(separator: ", "))")
            }
            let days = try step.options["days"].map { try number($0, "days", Int64.self) } ?? 0
            guard days > 0 else { throw HeadlessGameError("play needs --days above 0") }
            return try game.play(policy, days: days)
        case "dump":
            var sections = Set(HeadlessSummary.Section.allCases)
            if let list = step.options["sections"] {
                sections = []
                for name in list.split(separator: ",") {
                    guard let section = HeadlessSummary.Section(rawValue: String(name)) else {
                        throw HeadlessGameError("unknown section \(name); known: \(HeadlessSummary.Section.allCases.map(\.rawValue).joined(separator: ", "))")
                    }
                    sections.insert(section)
                }
            }
            return game.summary(sections)
        case "save":
            try write(step.file!, game.saveFile())
            return game.summary([])
        default:
            throw HeadlessGameError("unknown operation \(step.name)")
        }
    }

    private static func number<T: FixedWidthInteger>(_ text: String, _ option: String, _: T.Type) throws -> T {
        guard let value = T(text), value >= 0 else { throw HeadlessGameError("--\(option) takes a whole number from 0, not \(text)") }
        return value
    }

    // MARK: - Receipts

    private struct Receipt<Result: Encodable>: Encodable {
        let op: String
        let ok: Bool
        let result: Result?
        let error: String?
    }

    private struct AnyResult: Encodable {
        let value: any Encodable
        func encode(to encoder: any Encoder) throws { try value.encode(to: encoder) }
    }

    static func receipt(_ op: String, result: any Encodable) -> String {
        line(Receipt(op: op, ok: true, result: AnyResult(value: result), error: nil))
    }

    static func receipt(_ op: String, error: String) -> String {
        line(Receipt<AnyResult>(op: op, ok: false, result: nil, error: error))
    }

    private static func line(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return #"{"ok":false,"error":"the receipt could not be written"}"# }
        return String(decoding: data, as: UTF8.self)
    }
}
