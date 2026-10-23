import Foundation
import GameCore

/// What a problem report can carry besides its note (ARCHITECTURE decision
/// 193), if the player chooses: the game's command log (``CommandLog``)
/// with the save it starts from, so the problem can be replayed on Linux.
/// Nothing else: the app's version and build, and a digest of each data
/// file the replay needs to read the same land and ground. No device
/// identifier and no account; the save holds where a real-world map
/// starts (its latitude and longitude, ``GameWorld/geoAnchor``), and the
/// player is told so and sees the names in the save (``typedNames``) before
/// choosing, and sends it where they choose.
public struct CommandLogReport: Codable, Sendable {
    public static let schemaVersion = 1
    /// The file's name in the share sheet.
    public static let fileName = "command-log.json"

    public let schemaVersion: Int
    /// The app's version (`CFBundleShortVersionString`) and build
    /// (`CFBundleVersion`), as the note says them (``ProblemReport``).
    public let version: String
    public let build: String
    /// A digest of each of ``dataFiles`` the app read (``digest(of:)``),
    /// by file name; a replay warns when its own differ.
    public let data: [String: String]
    /// The world the log starts from, saved as a save is.
    public let start: SavedGame
    /// The real-world data the session had then.
    public let startData: RealWorldDataSet
    public let entries: [CommandLog.Entry]
    /// What the world came to, for a replay to compare.
    public let end: Summary

    public init(log: CommandLog, world: GameWorld, version: String, build: String, data: [String: String]) {
        self.schemaVersion = Self.schemaVersion
        self.version = version
        self.build = build
        self.data = data
        self.start = SavedGame(world: log.start)
        self.startData = log.startData
        self.entries = log.entries
        self.end = Summary(world)
    }

    /// The bundled files whose contents the world reads (decision 88, 124,
    /// 147): the land's people, places and water, the ground's heights and
    /// the coverage of the land data.
    public static let dataFiles = [
        "taiwan_population.json", "taiwan_places.json", "taiwan_water.json", "taiwan_heights.dat", "taiwan_coverage.dat",
    ]

    /// A digest of a data file: its FNV-1a 64-bit hash, in hexadecimal. It
    /// tells two versions of a file apart, nothing more.
    public static func digest(of data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// The digest of each of ``dataFiles`` `file` reads (by its name), and
    /// none of one it cannot.
    public static func digests(reading file: (String) throws -> Data) -> [String: String] {
        var digests: [String: String] = [:]
        for name in dataFiles {
            if let data = try? file(name) { digests[name] = digest(of: data) }
        }
        return digests
    }

    /// The report as a file: JSON, its keys sorted.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// The names in it the player may have typed, for them to see before
    /// they send it: the stations', lines' and trains' in the save it
    /// starts from and those its commands give; each once, in order.
    public var typedNames: [String] {
        let world = start.world
        var names = world.stations.map(\.name) + world.lines.map(\.name) + world.trains.map(\.name)
        for entry in entries {
            if case .command(.addPlatform(let addition)) = entry.action, case .new(let name, _, _) = addition.station {
                names.append(name)
            }
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    /// What the player is told is attached, before they choose to send it:
    /// the save, how many entries, the version, and the names they may have
    /// typed (at most `shown` of them, then how many more).
    public func attachmentText(in language: DisplayLanguage, shown: Int = 20) -> String {
        var text = language.text(
            "Attached: \(Self.fileName), with the save this game started from, the \(entries.count) things done since (commands, game time, Undo and Redo) and the version \(version) (\(build)). A real-world map's save holds the latitude and longitude of where it starts; nothing about your account or device.",
            "會附上 \(Self.fileName)：這局開始時的存檔、之後做的 \(entries.count) 件事（指令、遊戲時間、復原與重做），以及版本 \(version) (\(build))。實景地圖的存檔含這局起點的經緯度；不含帳號或裝置的資料。"
        )
        let names = typedNames
        if !names.isEmpty {
            let listed = names.prefix(shown).joined(separator: language.text(", ", "、"))
            let more = names.count > shown
                ? language.text(" and \(names.count - shown) more", " 等 \(names.count) 個")
                : ""
            text += language.text(" Names in it: \(listed)\(more).", "裡面的名稱：\(listed)\(more)。")
        }
        return text
    }

    /// What a world came to: the time, the money and how much is built.
    /// Plain counts, so a replay on another system compares the same.
    public struct Summary: Codable, Hashable, Sendable {
        public let time: Int64
        public let balance: Int64
        public let nodes: Int
        public let edges: Int
        public let stations: Int
        public let lines: Int
        public let trains: Int

        public init(_ world: GameWorld) {
            time = world.clock.now.seconds
            balance = world.economy.balance.amount
            nodes = world.network.nodes.count
            edges = world.network.edges.count
            stations = world.stations.count
            lines = world.lines.count
            trains = world.trains.count
        }
    }
}

extension GameSession {
    /// The command log as a problem report carries it (decision 193), with
    /// the app's `version` and `build` and the digests of the data files it
    /// read (``CommandLogReport/digest(of:)``).
    public func commandLogReport(version: String, build: String, data: [String: String]) -> CommandLogReport {
        CommandLogReport(log: commandLog, world: world, version: version, build: build, data: data)
    }
}
