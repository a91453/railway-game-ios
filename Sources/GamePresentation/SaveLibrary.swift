import Foundation
import GameCore

// The app's saves (Stage C4), after the `Ci/` reference's local saves
// (`buildLocalSavePayload`: `{app, version, exportedAt, data}`; the draft it
// keeps while the player builds; slots, export and import): JSON files in a
// folder, the world in GameCore's versioned `SavedGame`. Foundation is used
// here and nowhere else in GamePresentation, for JSON and files only; it is
// part of the Swift toolchain on Linux too, so all of this is tested there.

/// The saves in one folder: the autosave, `autosave.json`, and the
/// player's own saves, one file each.
///
/// A file is `{"app": "RailwayGame", "savedAt": "…", "summary": {…},
/// "game": {"saveVersion": 2, "world": {…}}}`. The summary repeats a few
/// facts of the world so a list of saves reads without decoding every
/// world; `game` is GameCore's ``SavedGame`` and alone decides what loads.
public struct SaveLibrary: Sendable {
    /// What a save is: the one the app writes by itself, or one the player
    /// made.
    public enum Kind: Hashable, Sendable {
        case autosave
        case manual
    }

    /// A save in the folder, as listed. An unreadable file is listed too,
    /// with the reason, so the player can delete it.
    public struct Entry: Identifiable, Hashable, Sendable {
        /// The file's name.
        public let id: String
        public let kind: Kind
        public let savedAt: Date?
        public let summary: SaveSummary?
        /// Why the file cannot be loaded, or `nil` when it can be tried.
        public let problem: SaveError?
        /// The name the player gave it (decision 184), or `nil`: the list
        /// then names it by when it was saved. Kept beside the file, never
        /// in the game.
        public let name: String?

        init(id: String, kind: Kind, savedAt: Date?, summary: SaveSummary?, problem: SaveError?, name: String? = nil) {
            self.id = id
            self.kind = kind
            self.savedAt = savedAt
            self.summary = summary
            self.problem = problem
            self.name = name
        }
    }

    /// How a list of saves is ordered (decision 184).
    public enum Order: String, CaseIterable, Hashable, Sendable {
        /// The latest saved first: ``entries()``'s order.
        case newest
        case oldest
        /// By the player's name, then the date's, alphabetically.
        case name

        public func displayName(in language: DisplayLanguage) -> String {
            switch self {
            case .newest: language.text("Newest first", "最新的在前")
            case .oldest: language.text("Oldest first", "最舊的在前")
            case .name: language.text("By name", "依名稱")
            }
        }
    }

    /// The longest name a save keeps; a longer one is cut.
    public static let maximumNameLength = 60

    /// The `"app"` every save names. Keep this identifier for save compatibility.
    public static let appName = "RailwayGame"
    static let autosaveFile = "autosave.json"
    /// What a save's news log's file name ends with: `autosave.json`'s is
    /// `autosave.news.json`.
    static let newsSuffix = ".news.json"
    /// What the file holding a save's name ends with (decision 184):
    /// `save-….json`'s is `save-….name`, plain UTF-8 text. Not `.json`, so
    /// no build lists it as a save.
    static let nameSuffix = ".name"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The saves in the app's Application Support folder, `Saves/`.
    public static func standard() throws -> SaveLibrary {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return SaveLibrary(directory: support.appendingPathComponent("Saves", isDirectory: true))
    }

    // MARK: - Listing

    /// Every save in the folder: the autosave first, then the player's own,
    /// the newest first; files that cannot be read last, by name. An empty
    /// list when the folder does not exist yet.
    public func entries() -> [Entry] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        // A save's news log (decision 175) lies beside it and is no save.
        let entries = names.filter { $0.hasSuffix(".json") && !$0.hasSuffix(Self.newsSuffix) }.map(entry(named:))
        return entries.sorted { lhs, rhs in
            if (lhs.kind == .autosave) != (rhs.kind == .autosave) { return lhs.kind == .autosave }
            switch (lhs.savedAt, rhs.savedAt) {
            case let (left?, right?) where left != right: return left > right
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.id < rhs.id
            }
        }
    }

    private func entry(named name: String) -> Entry {
        let kind: Kind = name == Self.autosaveFile ? .autosave : .manual
        guard let data = try? Data(contentsOf: url(of: name)) else {
            return Entry(id: name, kind: kind, savedAt: nil, summary: nil, problem: .fileSystem)
        }
        let given = playerName(of: name)
        switch Self.header(of: data) {
        case .success(let header):
            return Entry(id: name, kind: kind, savedAt: header.savedAt, summary: header.summary, problem: nil, name: given)
        case .failure(let problem):
            return Entry(id: name, kind: kind, savedAt: nil, summary: nil, problem: problem, name: given)
        }
    }

    /// `entries` in `order`: the autosave always first, unreadable files
    /// last, as ``entries()`` puts them.
    public static func sorted(_ entries: [Entry], by order: Order) -> [Entry] {
        func group(_ entry: Entry) -> Int {
            entry.kind == .autosave ? 0 : (entry.savedAt == nil ? 2 : 1)
        }
        return entries.enumerated().sorted { lhs, rhs in
            let (left, right) = (lhs.element, rhs.element)
            if group(left) != group(right) { return group(left) < group(right) }
            switch order {
            case .newest:
                break
            case .oldest:
                if let a = left.savedAt, let b = right.savedAt, a != b { return a < b }
            case .name:
                let a = left.name ?? "", b = right.name ?? ""
                // Named saves first, by name; then the rest, newest first.
                if a.isEmpty != b.isEmpty { return !a.isEmpty }
                let order = a.localizedStandardCompare(b)
                if order != .orderedSame { return order == .orderedAscending }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    // MARK: - Names

    /// The name kept beside save file `file`, or `nil`.
    private func playerName(of file: String) -> String? {
        guard let data = try? Data(contentsOf: url(of: Self.nameFile(of: file))),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return Self.cleanName(text)
    }

    /// `text` as a save's name: on one line, trimmed, at most
    /// ``maximumNameLength`` characters; `nil` when nothing is left.
    public static func cleanName(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        return String(line.prefix(maximumNameLength))
    }

    /// Names `entry` `name` (decision 184), or takes its name away when
    /// `name` is empty, so the list names it by its date again. Only the
    /// player's own saves: the autosave is written over. The save itself
    /// is not touched.
    @discardableResult
    public func rename(_ entry: Entry, to name: String) throws(SaveError) -> Entry {
        guard entry.kind == .manual else { throw .fileSystem }
        let file = url(of: Self.nameFile(of: entry.id))
        let cleaned = Self.cleanName(name)
        do {
            if let cleaned {
                try Data(cleaned.utf8).write(to: file, options: .atomic)
            } else if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            throw .fileSystem
        }
        return Entry(id: entry.id, kind: entry.kind, savedAt: entry.savedAt, summary: entry.summary, problem: entry.problem, name: cleaned)
    }

    /// The file name of the name of save file `name`.
    static func nameFile(of name: String) -> String {
        (name.hasSuffix(".json") ? String(name.dropLast(".json".count)) : name) + nameSuffix
    }

    // MARK: - Loading and saving

    /// The world in `entry`, as GameCore reads it.
    public func load(_ entry: Entry) throws(SaveError) -> GameWorld {
        let data: Data
        do {
            data = try Data(contentsOf: url(of: entry.id))
        } catch {
            throw .fileSystem
        }
        return try Self.decode(data)
    }

    /// Writes `world` as the autosave, over the last one, or as a new save
    /// of the player's own, saved at `date`. The file is replaced whole or
    /// not at all.
    @discardableResult
    public func save(_ world: GameWorld, news: NewsLog? = nil, as kind: Kind, at date: Date, named playerName: String? = nil) throws(SaveError) -> Entry {
        let data = try Self.encode(world, at: date)
        let name = kind == .autosave ? Self.autosaveFile : freeName(for: date)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(of: name), options: .atomic)
        } catch {
            throw .fileSystem
        }
        // The news log is a convenience: failing to keep it never fails the
        // save.
        if let news, let log = try? JSONEncoder().encode(news) {
            try? log.write(to: url(of: Self.newsFile(of: name)), options: .atomic)
        }
        let entry = Entry(id: name, kind: kind, savedAt: date, summary: SaveSummary(world: world), problem: nil)
        // So is its name (decision 184); the autosave has none.
        guard kind == .manual, let playerName else { return entry }
        return (try? rename(entry, to: playerName)) ?? entry
    }

    /// Keeps the autosave as a save of the player's own before another game
    /// starts and writes over it, as the reference archives the current
    /// draft before a fresh start (`archiveMetroAppCurrentDraftBeforeFreshStart`).
    /// Does nothing when there is no autosave.
    public func archiveAutosave() throws(SaveError) {
        let autosave = url(of: Self.autosaveFile)
        guard FileManager.default.fileExists(atPath: autosave.path) else { return }
        let savedAt = (try? Data(contentsOf: autosave)).flatMap { try? Self.header(of: $0).get().savedAt } ?? Date()
        let name = freeName(for: savedAt)
        do {
            try FileManager.default.moveItem(at: autosave, to: url(of: name))
        } catch {
            throw .fileSystem
        }
        // Its news log goes with it.
        try? FileManager.default.moveItem(at: url(of: Self.newsFile(of: Self.autosaveFile)), to: url(of: Self.newsFile(of: name)))
    }

    /// The news log kept beside `entry` (decision 175), or an empty one
    /// when there is none or it cannot be read.
    public func news(for entry: Entry) -> NewsLog {
        guard let data = try? Data(contentsOf: url(of: Self.newsFile(of: entry.id))),
              let log = try? JSONDecoder().decode(NewsLog.self, from: data) else { return NewsLog() }
        return log
    }

    /// The file name of the news log of save file `name`.
    static func newsFile(of name: String) -> String {
        (name.hasSuffix(".json") ? String(name.dropLast(".json".count)) : name) + newsSuffix
    }

    public func delete(_ entry: Entry) throws(SaveError) {
        do {
            try FileManager.default.removeItem(at: url(of: entry.id))
        } catch {
            throw .fileSystem
        }
        try? FileManager.default.removeItem(at: url(of: Self.newsFile(of: entry.id)))
        try? FileManager.default.removeItem(at: url(of: Self.nameFile(of: entry.id)))
    }

    /// `world` saved at `date` as a file to share, named after the app and
    /// the date, in the temporary folder (the reference's "导出本地存档").
    public static func exportFile(for world: GameWorld, at date: Date) throws(SaveError) -> URL {
        let data = try encode(world, at: date)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        let url = folder.appendingPathComponent("Along the Line \(stamp(date)).json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw .fileSystem
        }
        return url
    }

    // MARK: - The file

    /// The file for `world` saved at `date`.
    public static func encode(_ world: GameWorld, at date: Date) throws(SaveError) -> Data {
        let file = SaveFile(app: appName, savedAt: date, summary: SaveSummary(world: world), game: SavedGame(world: world))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(file)
        } catch {
            throw .damaged
        }
    }

    /// The world in a save file: one this app wrote, of a version this
    /// build reads, that GameCore accepts.
    public static func decode(_ data: Data) throws(SaveError) -> GameWorld {
        _ = try header(of: data).get()
        do {
            return try decoder.decode(SaveFile.self, from: data).game.world
        } catch {
            throw .damaged
        }
    }

    /// The file's header, after checking it is this app's and of a version
    /// this build reads.
    private static func header(of data: Data) -> Result<Header, SaveError> {
        guard let header = try? decoder.decode(Header.self, from: data), header.app == appName else {
            return .failure(.notASave)
        }
        guard header.game.saveVersion <= SavedGame.currentVersion else {
            return .failure(.newerVersion(header.game.saveVersion))
        }
        return .success(header)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func url(of name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// `save-<stamp>.json`, or with `-2`, `-3`… when that is taken.
    private func freeName(for date: Date) -> String {
        let stem = "save-\(Self.stamp(date))"
        var name = "\(stem).json"
        var number = 2
        while FileManager.default.fileExists(atPath: url(of: name).path) {
            name = "\(stem)-\(number).json"
            number += 1
        }
        return name
    }

    /// The date as `yyyy-MM-dd HHmmss` in UTC, so names sort by date and
    /// never depend on the device's settings.
    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return formatter.string(from: date)
    }
}

/// What a list of saves shows of one without loading it: game time, cash
/// and how much has been built.
public struct SaveSummary: Codable, Hashable, Sendable {
    /// Game time, in seconds since the start.
    public let seconds: Int64
    /// The balance, in cents.
    public let balance: Int64
    public let stations: Int
    public let lines: Int
    public let trains: Int
    /// `true` for a real-world map (Stage E2); absent for a blank one, and
    /// in every summary written before E2.
    public let realWorld: Bool?

    public init(world: GameWorld) {
        seconds = world.clock.now.seconds
        balance = world.economy.balance.amount
        stations = world.stations.count
        lines = world.lines.count
        trains = world.trains.count
        realWorld = world.geoAnchor == nil ? nil : true
    }

    /// The game date and the funds, as a save's list shows them first
    /// (decision 184): "Year 1 · Jan 3 (Wed) 14:20 · Funds $ 12,345",
    /// "第 1 年 1 月 3 日（三）14:20 · 資金 $ 12,345".
    public func dateAndFundsText(in language: DisplayLanguage) -> String {
        let date = GameTime(seconds: seconds).calendarText(in: language)
        let money = Money(balance).moneyText
        return language.text("\(date) · Funds \(money)", "\(date) · 資金 \(money)")
    }

    /// What has been built: "Real-world map · 5 stations · 2 lines · 2
    /// trains", or "實景地圖 · 5 座車站 · 2 條路線 · 2 列列車".
    public func networkText(in language: DisplayLanguage) -> String {
        let map = realWorld == true ? [language.text("Real-world map", "實景地圖")] : []
        switch language {
        case .english:
            func count(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "1 \(one)" : "\(n) \(many)" }
            return (map + [count(stations, "station", "stations"), count(lines, "line", "lines"), count(trains, "train", "trains")])
                .joined(separator: " · ")
        case .traditionalChinese:
            return (map + ["\(stations) 座車站", "\(lines) 條路線", "\(trains) 列列車"]).joined(separator: " · ")
        }
    }

    /// "Day 3 · 14:20 · $ 12,345 · 5 stations · 2 lines · 2 trains", after
    /// "Real-world map · " on one.
    public func text(in language: DisplayLanguage) -> String {
        let time = GameTime(seconds: seconds).displayText(in: language)
        let money = Money(balance).moneyText
        let map = realWorld == true ? [language.text("Real-world map", "實景地圖")] : []
        switch language {
        case .english:
            func count(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "1 \(one)" : "\(n) \(many)" }
            return (map + [time, money, count(stations, "station", "stations"), count(lines, "line", "lines"), count(trains, "train", "trains")])
                .joined(separator: " · ")
        case .traditionalChinese:
            return (map + [time, money, "\(stations) 座車站", "\(lines) 條路線", "\(trains) 列列車"]).joined(separator: " · ")
        }
    }
}

/// Why a save cannot be loaded or written.
public enum SaveError: Error, Hashable, Sendable {
    /// The file is not a save of this app (not JSON, or another app's).
    case notASave
    /// A later build wrote it, in a version this one does not read.
    case newerVersion(Int)
    /// It is this app's, but its game cannot be read: damaged, or broken
    /// in a way GameCore refuses.
    case damaged
    /// The file could not be read, written, moved or deleted.
    case fileSystem

    public func playerMessage(in language: DisplayLanguage) -> String {
        switch self {
        case .notASave:
            language.text("That file is not an Along the Line save.", "這個檔案不是《沿線》的存檔。")
        case .newerVersion(let version):
            language.text(
                "That save comes from a newer version of the game (save format \(version)). Update the app to load it.",
                "這個存檔來自較新版本的遊戲（存檔格式 \(version)）。請更新 App 後再讀取。"
            )
        case .damaged:
            language.text("That save is damaged and cannot be loaded.", "這個存檔已損壞，無法讀取。")
        case .fileSystem:
            language.text("The save could not be read or written. Try again.", "無法讀寫存檔，請再試一次。")
        }
    }
}

/// The whole file.
private struct SaveFile: Codable {
    let app: String
    let savedAt: Date
    let summary: SaveSummary
    let game: SavedGame
}

/// Only what a list needs and what decides whether the game loads.
private struct Header: Decodable {
    struct Game: Decodable {
        let saveVersion: Int
    }

    let app: String
    let savedAt: Date
    let summary: SaveSummary
    let game: Game
}
