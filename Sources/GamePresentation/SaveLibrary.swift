import Foundation
import GameCore

// The app's saves (Stage C4), after the `Ci/` reference's local saves
// (`buildLocalSavePayload`: `{app, version, exportedAt, data}`; the draft it
// keeps while the player builds; slots, export and import): JSON files in a
// folder, the world in GameCore's versioned `SavedGame`. Foundation is used
// here and nowhere else in GamePresentation, for JSON and files only; it is
// part of the Swift toolchain on Linux too, so all of this is tested there.

/// The saves in one folder: the autosaves, and the player's own saves, one
/// file each.
///
/// Decision 192: the autosaves are the latest, `autosave.json`, written
/// whenever the game is left (the app leaves the foreground, the player
/// goes back to the start screen), and up to ``autosaveSlots`` taken in
/// turn every 15 minutes of play, `autosave-<n>.json`, each with the next
/// number, so the player can go back to one of them. A build before 192
/// wrote `autosave.json` alone; it is read as before.
///
/// A file is `{"app": "RailwayGame", "savedAt": "…", "summary": {…},
/// "game": {"saveVersion": 2, "world": {…}}}`. The summary repeats a few
/// facts of the world so a list of saves reads without decoding every
/// world; `game` is GameCore's ``SavedGame`` and alone decides what loads.
public struct SaveLibrary: Sendable {
    /// What a save is: one the app writes by itself (the latest or one of
    /// the slots, decision 192), or one the player made.
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

        /// The number of an autosave taken in turn (decision 192), or `nil`
        /// for the latest autosave and the player's own saves.
        public var slot: Int? { SaveLibrary.slotNumber(of: id) }

        /// Decision 502: the row of the player's saves the game is kept in.
        /// A save of the player's is its own row (an earlier version, its
        /// row's); an autosave names the row its game was last saved in or
        /// loaded from, or `nil` when it has none yet.
        public let row: String?

        /// How many earlier versions its row keeps (decision 502), at most
        /// ``SaveLibrary/versionsKept`` less one.
        public let earlierVersions: Int

        /// How long ago it was saved, by the clock on the wall (decision
        /// 192): "just now", "12 min ago", "3 h ago", "2 d ago"; "剛剛",
        /// "12 分鐘前"…; `nil` when that is not known.
        public func savedAgoText(at now: Date, in language: DisplayLanguage) -> String? {
            savedAt.map { SaveLibrary.agoText(from: $0, to: now, in: language) }
        }

        init(
            id: String, kind: Kind, savedAt: Date?, summary: SaveSummary?, problem: SaveError?, name: String? = nil,
            row: String? = nil, earlierVersions: Int = 0
        ) {
            self.id = id
            self.kind = kind
            self.savedAt = savedAt
            self.summary = summary
            self.problem = problem
            self.name = name
            self.row = kind == .manual ? SaveLibrary.row(of: id) : row
            self.earlierVersions = earlierVersions
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

    /// How many autosaves taken every 15 minutes are kept (decision 192),
    /// beside the latest: a high-speed demo's save is some 7.2 MB, so at
    /// most six files, some 43 MB.
    public static let autosaveSlots = 5

    /// How many versions a row of the player's saves keeps (decision 502):
    /// the one listed and the two saved before it, so a save made by
    /// mistake can be undone.
    public static let versionsKept = 3

    /// The longest name a save keeps; a longer one is cut.
    public static let maximumNameLength = 60

    /// The `"app"` every save names. Keep this identifier for save compatibility.
    public static let appName = "RailwayGame"
    static let autosaveFile = "autosave.json"
    /// The autosaves taken in turn (decision 192) are `autosave-<n>.json`.
    static let slotPrefix = "autosave-"
    /// What a save's news log's file name ends with: `autosave.json`'s is
    /// `autosave.news.json`.
    static let newsSuffix = ".news.json"
    /// What the file holding a save's name ends with (decision 184):
    /// `save-….json`'s is `save-….name`, plain UTF-8 text. Not `.json`, so
    /// no build lists it as a save.
    static let nameSuffix = ".name"
    /// Decision 502: the earlier versions of row `<stem>.json` are
    /// `Versions/<stem>/1.json` (the latest of them), `2.json`…, each with
    /// its news log. A folder, so no build lists them as saves, and the
    /// iCloud round (decision 397) copies none of them.
    static let versionsFolder = "Versions"
    /// Where saves being deleted wait until all of them are moved
    /// (``delete(_:)``), so a delete is all or nothing.
    static let deletingFolder = "Deleting"

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
        return Self.listed(entries)
    }

    /// The autosaves alone (decision 192), as ``entries()`` lists them: the
    /// newest first. Reads no save of the player's.
    public func autosaves() -> [Entry] {
        Self.listed(autosaveFiles().map(entry(named:)))
    }

    /// The newest autosave that can be loaded, or `nil` (decision 192).
    /// Reads two files at most: the latest, and the autosave taken in turn
    /// with the highest number, the newest of those (each is numbered
    /// after the last). A save of the high-speed demo takes some 70 ms to
    /// read, and this is read while the game waits.
    public func newestAutosave() -> Entry? {
        newestCandidates().first { $0.problem == nil }
    }

    /// The latest autosave and the highest-numbered one taken in turn, as
    /// ``entries()`` orders them.
    private func newestCandidates() -> [Entry] {
        let files = autosaveFiles()
        let highest = files.compactMap(Self.slotNumber).max().map(Self.slotFile)
        return Self.listed([Self.autosaveFile, highest].compactMap { $0 }.filter(files.contains).map(entry(named:)))
    }

    /// `entries` in ``entries()``'s order.
    private static func listed(_ entries: [Entry]) -> [Entry] {
        entries.sorted { lhs, rhs in
            if (lhs.kind == .autosave) != (rhs.kind == .autosave) { return lhs.kind == .autosave }
            switch (lhs.savedAt, rhs.savedAt) {
            case let (left?, right?) where left != right: return left > right
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                // Two autosaves of one moment (decision 192: going back
                // keeps the game left in turn, then writes the latest): the
                // latest, then the higher number, was written after.
                if lhs.kind == .autosave, rhs.kind == .autosave, lhs.slot != rhs.slot {
                    return (lhs.slot ?? .max) > (rhs.slot ?? .max)
                }
                return lhs.id < rhs.id
            }
        }
    }

    private func entry(named name: String) -> Entry {
        let kind: Kind = Self.isAutosave(name) ? .autosave : .manual
        guard let data = try? Data(contentsOf: url(of: name)) else {
            return Entry(id: name, kind: kind, savedAt: nil, summary: nil, problem: .fileSystem)
        }
        let given = playerName(of: name)
        let versions = kind == .manual ? versionNumbers(of: name).count : 0
        switch Self.header(of: data) {
        case .success(let header):
            return Entry(
                id: name, kind: kind, savedAt: header.savedAt, summary: header.summary, problem: nil, name: given,
                row: header.row.flatMap(Self.validRow), earlierVersions: versions
            )
        case .failure(let problem):
            return Entry(id: name, kind: kind, savedAt: nil, summary: nil, problem: problem, name: given, earlierVersions: versions)
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

    /// Writes `world` as the autosave, over the last one, or as a save of
    /// the player's own, saved at `date`. The file is replaced whole or
    /// not at all.
    ///
    /// Decision 502: `row` is the row of the player's saves the game is
    /// kept in. A save of the player's is written as that row's newest
    /// version, the one before kept as an earlier version
    /// (``versionsKept``); without a row, or when `row` is not a name of
    /// one, it is a new row. An autosave keeps `row` in its file, so the
    /// game finds its row again when another game starts
    /// (``archiveAutosave()``) or on another device.
    @discardableResult
    public func save(
        _ world: GameWorld, news: NewsLog? = nil, as kind: Kind, at date: Date, named playerName: String? = nil, row: String? = nil
    ) throws(SaveError) -> Entry {
        let row = row.flatMap(Self.validRow)
        let data = try Self.encode(world, row: kind == .autosave ? row : nil, at: date)
        let name = kind == .autosave ? Self.autosaveFile : (row ?? freeName(for: date))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if kind == .manual { try keepVersion(of: name) }
            try data.write(to: url(of: name), options: .atomic)
        } catch {
            throw .fileSystem
        }
        // The news log is a convenience: failing to keep it never fails the
        // save.
        if let news, let log = try? JSONEncoder().encode(news) {
            try? log.write(to: url(of: Self.newsFile(of: name)), options: .atomic)
        }
        let entry = Entry(
            id: name, kind: kind, savedAt: date, summary: SaveSummary(world: world), problem: nil, name: self.playerName(of: name),
            row: row, earlierVersions: kind == .manual ? versionNumbers(of: name).count : 0
        )
        // So is its name (decision 184); the autosave has none.
        guard kind == .manual, let playerName else { return entry }
        return (try? rename(entry, to: playerName)) ?? entry
    }

    /// What writing an autosave in turn did (decision 192): the autosave
    /// written, and the files of the oldest that it took the place of.
    public struct SlotWrite: Hashable, Sendable {
        public let entry: Entry
        public let removed: [String]
    }

    /// Writes `world` as the next autosave taken in turn (decision 192),
    /// `autosave-<n>.json` with the next number, then deletes the oldest
    /// beyond ``autosaveSlots``. The new one is written whole before any
    /// is deleted, so a failure never leaves fewer than there were.
    @discardableResult
    public func saveAutosaveSlot(_ world: GameWorld, news: NewsLog? = nil, at date: Date, row: String? = nil) throws(SaveError) -> SlotWrite {
        let row = row.flatMap(Self.validRow)
        let data = try Self.encode(world, row: row, at: date)
        let name = Self.slotFile(nextSlot())
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(of: name), options: .atomic)
        } catch {
            throw .fileSystem
        }
        if let news, let log = try? JSONEncoder().encode(news) {
            try? log.write(to: url(of: Self.newsFile(of: name)), options: .atomic)
        }
        return SlotWrite(entry: Entry(id: name, kind: .autosave, savedAt: date, summary: SaveSummary(world: world), problem: nil, row: row), removed: pruneSlots())
    }

    /// Keeps the latest autosave as the next one taken in turn (decision
    /// 192), before the player goes back to an earlier one and the latest
    /// is written over: going back can be undone. The file is moved, not
    /// written again. Does nothing when there is no latest autosave.
    ///
    /// The slot named `sparing` (the one being gone back to) is not
    /// deleted to make room: until the game gone back to is autosaved as
    /// the latest, it may be the only one of that game that can be read
    /// (Continue falling back past damaged ones, decision 192, later).
    public func keepLatestAutosaveInSlot(sparing: String? = nil) throws(SaveError) {
        let latest = url(of: Self.autosaveFile)
        guard FileManager.default.fileExists(atPath: latest.path) else { return }
        let name = Self.slotFile(nextSlot())
        do {
            try FileManager.default.moveItem(at: latest, to: url(of: name))
        } catch {
            throw .fileSystem
        }
        try? FileManager.default.moveItem(at: url(of: Self.newsFile(of: Self.autosaveFile)), to: url(of: Self.newsFile(of: name)))
        pruneSlots(sparing: sparing.flatMap(Self.slotNumber))
    }

    /// Keeps the newest autosave as a save of the player's own before
    /// another game starts and writes over it, as the reference archives the
    /// current draft before a fresh start
    /// (`archiveMetroAppCurrentDraftBeforeFreshStart`). Does nothing when
    /// there is no autosave.
    ///
    /// Decision 192: the older autosaves of that game are deleted, so the
    /// autosaves are always of the game being played and never more than
    /// ``autosaveSlots`` and the latest. Only the two that may be the
    /// newest are read (``newestAutosave()``); of those, one that cannot be
    /// read is kept as a save of the player's too, listed with why, as
    /// before 192: it may be a later build's.
    ///
    /// Decision 502: the newest goes into the row its game is kept in,
    /// when that row is still there, as the row's newest version (nothing,
    /// when the row already holds that very game); only a game with no
    /// row is a new one.
    public func archiveAutosave() throws(SaveError) {
        let candidates = newestCandidates()
        let newest = candidates.first { $0.problem == nil }
        let kept = Set(candidates.filter { $0 == newest || $0.problem != nil }.map(\.id))
        let files = autosaveFiles()
        // Kept first: one that fails to move stops here, with none deleted.
        for entry in candidates where kept.contains(entry.id) {
            if entry == newest, let row = entry.row, FileManager.default.fileExists(atPath: url(of: row).path) {
                try keepInRow(entry, row: row)
                continue
            }
            let name = freeName(for: entry.savedAt ?? Date())
            do {
                try FileManager.default.moveItem(at: url(of: entry.id), to: url(of: name))
            } catch {
                throw .fileSystem
            }
            // Its news log goes with it.
            try? FileManager.default.moveItem(at: url(of: Self.newsFile(of: entry.id)), to: url(of: Self.newsFile(of: name)))
        }
        // Deleting is tidying up: failing to never stops the new game.
        // An autosave kept in its row is gone already, or is the game the
        // row holds.
        for name in files where !kept.contains(name) || newest?.id == name && newest?.row != nil {
            try? FileManager.default.removeItem(at: url(of: name))
            try? FileManager.default.removeItem(at: url(of: Self.newsFile(of: name)))
        }
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

    /// Deletes `entry` with its news log, its name and, a row of the
    /// player's saves, its earlier versions (decision 502).
    public func delete(_ entry: Entry) throws(SaveError) {
        try delete([entry])
    }

    /// Deletes `entries`, each as ``delete(_:)`` does, all or none
    /// (decision 502): every one's files are first moved aside, and one
    /// that cannot be (or a save no longer there) moves the others back
    /// and deletes nothing.
    public func delete(_ entries: [Entry]) throws(SaveError) {
        let fileManager = FileManager.default
        let aside = url(of: Self.deletingFolder).appendingPathComponent(UUID().uuidString, isDirectory: true)
        var moved: [(from: URL, to: URL)] = []
        do {
            try fileManager.createDirectory(at: aside, withIntermediateDirectories: true)
            for (index, entry) in entries.enumerated() {
                let folder = aside.appendingPathComponent("\(index)", isDirectory: true)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                var members = [entry.id, Self.newsFile(of: entry.id), Self.nameFile(of: entry.id)]
                if entry.kind == .manual, let row = entry.row, row == entry.id { members.append(Self.versionsPath(of: row)) }
                for (number, member) in members.enumerated() {
                    let from = url(of: member)
                    // The save itself must be there; what lies beside it may not.
                    guard number == 0 || fileManager.fileExists(atPath: from.path) else { continue }
                    let to = folder.appendingPathComponent("\(number)")
                    if failingMoves.contains(member) { throw SaveError.fileSystem }
                    try fileManager.moveItem(at: from, to: to)
                    moved.append((from, to))
                }
            }
        } catch {
            for (from, to) in moved.reversed() {
                try? fileManager.moveItem(at: to, to: from)
            }
            try? fileManager.removeItem(at: url(of: Self.deletingFolder))
            throw .fileSystem
        }
        // Gone from the list already: failing to free the space only
        // leaves it for the next delete.
        try? fileManager.removeItem(at: url(of: Self.deletingFolder))
    }

    /// Test only: save files whose move ``delete(_:)`` fails, to show
    /// it deletes all or none.
    var failingMoves: Set<String> = []

    // MARK: - Rows and their versions (decision 502)

    /// The row `name` belongs to: itself, or the row of an earlier version
    /// `Versions/<stem>/<n>.json`; `nil` for an autosave.
    static func row(of name: String) -> String? {
        if isAutosave(name) { return nil }
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 3, parts[0] == versionsFolder, versionNumber(of: String(parts[2])) != nil {
            return validRow(String(parts[1]) + ".json")
        }
        return validRow(name)
    }

    /// `name` when it can name a row of the player's saves: a save in the
    /// folder itself that is no autosave; otherwise `nil`.
    static func validRow(_ name: String) -> String? {
        guard name.hasSuffix(".json"), !name.hasSuffix(newsSuffix), !name.contains("/"), !name.hasPrefix("."),
              name != ".json", !isAutosave(name) else { return nil }
        return name
    }

    /// `Versions/<stem>`, the folder of row `row`'s earlier versions.
    static func versionsPath(of row: String) -> String {
        "\(versionsFolder)/\(row.dropLast(".json".count))"
    }

    static func versionFile(_ number: Int, of row: String) -> String {
        "\(versionsPath(of: row))/\(number).json"
    }

    private static func versionNumber(of file: String) -> Int? {
        guard file.hasSuffix(".json"), !file.hasSuffix(newsSuffix) else { return nil }
        let digits = file.dropLast(".json".count)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(digits), number > 0 else { return nil }
        return number
    }

    /// The numbers of row `row`'s earlier versions, the latest (1) first.
    private func versionNumbers(of row: String) -> [Int] {
        guard Self.validRow(row) != nil else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: url(of: Self.versionsPath(of: row)).path)) ?? []
        return files.compactMap(Self.versionNumber).sorted()
    }

    /// The earlier versions of `entry`'s row, the latest first (decision
    /// 502): loading one goes back to the game as it was saved then. The
    /// row itself, its newest version, is not among them.
    public func earlierVersions(of entry: Entry) -> [Entry] {
        guard entry.kind == .manual, let row = entry.row else { return [] }
        return versionNumbers(of: row).map { entryOfVersion($0, of: row) }
    }

    private func entryOfVersion(_ number: Int, of row: String) -> Entry {
        let name = Self.versionFile(number, of: row)
        guard let data = try? Data(contentsOf: url(of: name)) else {
            return Entry(id: name, kind: .manual, savedAt: nil, summary: nil, problem: .fileSystem)
        }
        switch Self.header(of: data) {
        case .success(let header):
            return Entry(id: name, kind: .manual, savedAt: header.savedAt, summary: header.summary, problem: nil, name: playerName(of: row))
        case .failure(let problem):
            return Entry(id: name, kind: .manual, savedAt: nil, summary: nil, problem: problem, name: playerName(of: row))
        }
    }

    /// Keeps row `row`'s save as its latest earlier version, before it is
    /// written over; the oldest beyond ``versionsKept`` goes. The save is
    /// copied whole before any version moves, so a failure leaves every
    /// version there was. Nothing when there is no save there yet.
    private func keepVersion(of row: String) throws {
        let fileManager = FileManager.default
        let current = url(of: row)
        guard fileManager.fileExists(atPath: current.path) else { return }
        let folder = url(of: Self.versionsPath(of: row))
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let incoming = folder.appendingPathComponent("incoming.json")
        let incomingNews = folder.appendingPathComponent("incoming" + Self.newsSuffix)
        try? fileManager.removeItem(at: incoming)
        try? fileManager.removeItem(at: incomingNews)
        try fileManager.copyItem(at: current, to: incoming)
        try? fileManager.copyItem(at: url(of: Self.newsFile(of: row)), to: incomingNews)
        let older = Self.versionsKept - 1
        func file(_ number: Int) -> URL { url(of: Self.versionFile(number, of: row)) }
        func news(_ number: Int) -> URL { url(of: Self.newsFile(of: Self.versionFile(number, of: row))) }
        // The oldest kept is pushed out, then each moves one along.
        for number in versionNumbers(of: row).reversed() where number >= older {
            try fileManager.removeItem(at: file(number))
            try? fileManager.removeItem(at: news(number))
        }
        for number in versionNumbers(of: row).reversed() {
            try fileManager.moveItem(at: file(number), to: file(number + 1))
            try? fileManager.removeItem(at: news(number + 1))
            try? fileManager.moveItem(at: news(number), to: news(number + 1))
        }
        if older > 0 {
            try fileManager.moveItem(at: incoming, to: file(1))
            if fileManager.fileExists(atPath: incomingNews.path) { try? fileManager.moveItem(at: incomingNews, to: news(1)) }
        } else {
            try? fileManager.removeItem(at: incoming)
            try? fileManager.removeItem(at: incomingNews)
        }
    }

    /// Writes autosave `entry` as row `row`'s newest version
    /// (``archiveAutosave()``), its news log with it. Nothing when the row
    /// holds the same game already: saved, then left without a change.
    private func keepInRow(_ entry: Entry, row: String) throws(SaveError) {
        let data: Data
        do {
            data = try Data(contentsOf: url(of: entry.id))
        } catch {
            throw .fileSystem
        }
        if let held = try? Data(contentsOf: url(of: row)), Self.holdSameGame(data, held) { return }
        do {
            try keepVersion(of: row)
            // The row's file is the player's: it names no row of its own.
            let file = try Self.decodeFile(data)
            let rowData = try Self.encode(file: SaveFile(app: file.app, savedAt: file.savedAt, summary: file.summary, game: file.game, news: nil))
            try rowData.write(to: url(of: row), options: .atomic)
        } catch let error as SaveError {
            throw error
        } catch {
            throw .fileSystem
        }
        let news = url(of: Self.newsFile(of: row))
        try? FileManager.default.removeItem(at: news)
        try? FileManager.default.copyItem(at: url(of: Self.newsFile(of: entry.id)), to: news)
    }

    /// Whether save files `a` and `b` hold the same world. Their summaries
    /// are compared first, so two different games are told apart without
    /// reading either world.
    private static func holdSameGame(_ a: Data, _ b: Data) -> Bool {
        guard case .success(let first) = header(of: a), case .success(let second) = header(of: b),
              first.summary == second.summary,
              let one = try? decode(a), let other = try? decode(b) else { return false }
        return one == other
    }

    /// `world` saved at `date` as a file to share, named after the app and
    /// the date, in the temporary folder (the reference's "导出本地存档").
    /// Decision 175, later: the file carries the game's news log `news`,
    /// which an import reads back and a build before it skips.
    ///
    /// Decision 409: the file is the game's own type,
    /// ``SharedNetwork/fileExtension``, so a friend who gets it taps it
    /// open in the game; it is JSON as before. It carries `company`, the
    /// postcard's company name, when given.
    public static func exportFile(for world: GameWorld, news: NewsLog? = nil, company: String? = nil, at date: Date) throws(SaveError) -> URL {
        let data = try encode(world, news: news, company: company, at: date)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        let url = folder.appendingPathComponent("Along the Line \(stamp(date)).\(SharedNetwork.fileExtension)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw .fileSystem
        }
        return url
    }

    /// `entry` as a file to share (decision 381: the saves list's row
    /// menu), the same as the game menu's Export Save writes: its world
    /// and its news log, named by when it was saved.
    public func exportFile(of entry: Entry) throws(SaveError) -> URL {
        try Self.exportFile(for: load(entry), news: news(for: entry), at: entry.savedAt ?? Date())
    }

    // MARK: - The file

    /// The file for `world` saved at `date`, with the news log `news` when
    /// given (an exported file; a save in the folder keeps its news log
    /// beside it).
    public static func encode(_ world: GameWorld, news: NewsLog? = nil, company: String? = nil, at date: Date) throws(SaveError) -> Data {
        try encode(world, news: news, company: company, row: nil, at: date)
    }

    /// The file, with an autosave's `row` (decision 502) when given.
    static func encode(_ world: GameWorld, news: NewsLog? = nil, company: String? = nil, row: String?, at date: Date) throws(SaveError) -> Data {
        try encode(file: SaveFile(
            app: appName, savedAt: date, summary: SaveSummary(world: world), game: SavedGame(world: world), news: news, company: company, row: row
        ))
    }

    private static func encode(file: SaveFile) throws(SaveError) -> Data {
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
        try decodeWithNews(data).world
    }

    /// The world in a save file, as ``decode(_:)`` reads it, and the news
    /// log an exported file carries (decision 175, later), or `nil`: none,
    /// or one that cannot be read, which never stops the game loading.
    public static func decodeWithNews(_ data: Data) throws(SaveError) -> (world: GameWorld, news: NewsLog?) {
        let file = try decodeFile(data)
        return (file.game.world, file.news)
    }

    /// The whole file `data`, as ``decodeWithNews(_:)`` reads it.
    static func decodeFile(_ data: Data) throws(SaveError) -> SaveFile {
        _ = try header(of: data).get()
        do {
            return try decoder.decode(SaveFile.self, from: data)
        } catch {
            throw .damaged
        }
    }

    /// When a save was written, by the device's clock: "14:20" (decision
    /// 192, later: the autosave Continue fell back to).
    public static func clockText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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

    // MARK: - Autosaves in turn (decision 192)

    /// Whether save file `name` is an autosave: the latest, or one taken in
    /// turn.
    static func isAutosave(_ name: String) -> Bool {
        name == autosaveFile || slotNumber(of: name) != nil
    }

    /// `n` of `autosave-<n>.json`, or `nil` for any other name.
    static func slotNumber(of name: String) -> Int? {
        guard name.hasPrefix(slotPrefix), name.hasSuffix(".json") else { return nil }
        let digits = name.dropFirst(slotPrefix.count).dropLast(".json".count)
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber), let number = Int(digits) else { return nil }
        return number
    }

    static func slotFile(_ number: Int) -> String {
        "\(slotPrefix)\(number).json"
    }

    /// The autosaves' file names.
    private func autosaveFiles() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter(Self.isAutosave)
    }

    /// The numbers of the autosaves taken in turn, the lowest first.
    private func slotNumbers() -> [Int] {
        autosaveFiles().compactMap(Self.slotNumber).sorted()
    }

    /// The number after the highest taken.
    private func nextSlot() -> Int {
        (slotNumbers().last ?? 0) + 1
    }

    /// Deletes the autosaves taken in turn beyond ``autosaveSlots``, the
    /// lowest numbers (the oldest taken) first, with their news logs, but
    /// for slot `spared`. Returns their file names.
    @discardableResult
    private func pruneSlots(sparing spared: Int? = nil) -> [String] {
        let numbers = slotNumbers()
        var kept = Array(numbers.suffix(Self.autosaveSlots))
        if let spared, numbers.contains(spared), !kept.contains(spared), !kept.isEmpty {
            kept.removeFirst()
            kept.append(spared)
        }
        let removed = numbers.filter { !kept.contains($0) }.map(Self.slotFile)
        for name in removed {
            try? FileManager.default.removeItem(at: url(of: name))
            try? FileManager.default.removeItem(at: url(of: Self.newsFile(of: name)))
            try? FileManager.default.removeItem(at: url(of: Self.nameFile(of: name)))
        }
        return removed
    }

    /// How long ago `date` was at `now` (decision 192), after the
    /// reference's relative time (`Railway/city_world_reference`'s
    /// `dom-*.js`, `p(e, t)`): under 45 seconds "just now", then minutes
    /// under an hour, hours under a day, then days, each rounded to the
    /// nearest. A date after `now` is "just now".
    public static func agoText(from date: Date, to now: Date, in language: DisplayLanguage) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        let seconds = Int((elapsed).rounded(.toNearestOrAwayFromZero))
        if seconds < 45 { return language.text("just now", "剛剛") }
        let minutes = (seconds + 30) / 60
        if minutes < 60 { return language.text("\(minutes) min ago", "\(minutes) 分鐘前") }
        let hours = (minutes + 30) / 60
        if hours < 24 { return language.text("\(hours) h ago", "\(hours) 小時前") }
        let days = (hours + 12) / 24
        return language.text("\(days) d ago", "\(days) 天前")
    }

    /// The name of a new row of the player's saves saved at `date`
    /// (decision 502), none of `taken` nor of a save there now: a game
    /// takes it when first saved, before the save is written.
    public func newRow(at date: Date, besides taken: [String] = []) -> String {
        freeName(for: date, besides: taken)
    }

    /// `save-<stamp>.json`, or with `-2`, `-3`… when that is taken.
    private func freeName(for date: Date, besides taken: [String] = []) -> String {
        let stem = "save-\(Self.stamp(date))"
        var name = "\(stem).json"
        var number = 2
        while FileManager.default.fileExists(atPath: url(of: name).path) || taken.contains(name) {
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
    /// `true` for a game with unlimited funds (decision 200), whose funds
    /// read "∞"; absent otherwise, and in every summary written before it.
    public let unlimitedFunds: Bool?

    public init(world: GameWorld) {
        seconds = world.clock.now.seconds
        balance = world.economy.balance.amount
        stations = world.stations.count
        lines = world.lines.count
        trains = world.trains.count
        realWorld = world.geoAnchor == nil ? nil : true
        unlimitedFunds = world.economy.unlimitedFunds ? true : nil
    }

    /// The funds: the balance, or "∞" with unlimited funds.
    private var fundsText: String {
        unlimitedFunds == true ? "∞" : Money(balance).moneyText
    }

    /// The game date and the funds, as a save's list shows them first
    /// (decision 184): "Year 1 · Jan 3 (Wed) 14:20 · Funds $ 12,345",
    /// "第 1 年 1 月 3 日（三）14:20 · 資金 $ 12,345".
    public func dateAndFundsText(in language: DisplayLanguage) -> String {
        let date = GameTime(seconds: seconds).calendarText(in: language)
        let money = fundsText
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
        let money = fundsText
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
    /// Decision 409: a file someone sent is larger than any save
    /// (``SharedNetwork/maximumBytes``), so it is not read.
    case tooLarge

    public func playerMessage(in language: DisplayLanguage) -> String {
        switch self {
        case .notASave:
            language.text("That file is not an Along the Line save.", "這個檔案不是《沿線》的存檔。")
        case .newerVersion:
            language.text(
                "That save comes from a newer version of the game. Update the app to load it.",
                "這個存檔來自較新版本的遊戲，請更新 App 後再讀取。"
            )
        case .damaged:
            language.text("That save is damaged and cannot be loaded.", "這個存檔已損壞，無法讀取。")
        case .fileSystem:
            language.text("The save could not be read or written. Try again.", "無法讀寫存檔，請再試一次。")
        case .tooLarge:
            language.text("That file is too large to be an Along the Line save.", "這個檔案太大，不是《沿線》的存檔。")
        }
    }
}

/// The whole file.
///
/// Decision 175, later: `news`, the news log, only in an exported file, an
/// optional key a build before it skips (`JSONDecoder` ignores keys a type
/// does not name), so the save version stays.
///
/// Decision 409: `company`, the company name on the postcard of a network
/// shared with a friend, the same way: optional, only in an exported file.
///
/// Decision 502: `row`, in an autosave only, the row of the player's saves
/// its game is kept in, the same way: optional, so the save version stays,
/// and in the file, so it goes where the autosave goes (iCloud, decision
/// 397).
struct SaveFile: Codable {
    let app: String
    let savedAt: Date
    let summary: SaveSummary
    let game: SavedGame
    let news: NewsLog?
    let company: String?
    let row: String?

    init(app: String, savedAt: Date, summary: SaveSummary, game: SavedGame, news: NewsLog?, company: String? = nil, row: String? = nil) {
        self.app = app
        self.savedAt = savedAt
        self.summary = summary
        self.game = game
        self.news = news
        self.company = company
        self.row = row
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        app = try container.decode(String.self, forKey: .app)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        summary = try container.decode(SaveSummary.self, forKey: .summary)
        game = try container.decode(SavedGame.self, forKey: .game)
        // The news log is a convenience: one that cannot be read is left out.
        news = try? container.decodeIfPresent(NewsLog.self, forKey: .news)
        // So is the company name; ``SharedNetwork`` cleans and cuts it.
        company = try? container.decodeIfPresent(String.self, forKey: .company)
        // So is the row (decision 502): without it the game gets a new one.
        row = try? container.decodeIfPresent(String.self, forKey: .row)
    }
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
    let row: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        app = try container.decode(String.self, forKey: .app)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        summary = try container.decode(SaveSummary.self, forKey: .summary)
        game = try container.decode(Game.self, forKey: .game)
        row = try? container.decodeIfPresent(String.self, forKey: .row)
    }

    private enum CodingKeys: String, CodingKey {
        case app, savedAt, summary, game, row
    }
}
