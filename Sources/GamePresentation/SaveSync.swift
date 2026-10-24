import Foundation

// Decision 397: the saves kept in step with a second folder, the player's
// own iCloud (iCloud Drive's container of the app; the app hands the folder
// over, ``SaveSyncFolder``), so a game goes on on another iPhone or an iPad.
// The saves' folder on the device stays the one every save is read from and
// written to (``SaveLibrary``, unchanged); a round of ``SaveSync`` copies
// what changed on one side to the other, and never writes over a save that
// changed on both: it keeps both. Without iCloud nothing runs, and the
// saves stay on the device as before.

/// A folder of files a ``SaveSync`` round reads and writes: the device's
/// saves (``DirectorySaveFolder``) or the copy in iCloud (the app's own,
/// which coordinates its reads and writes with iCloud's).
public protocol SaveSyncFolder: Sendable {
    /// The files in the folder, by name, and whether each can be read now
    /// (a file in iCloud may be on the way to the device). Throws when the
    /// folder cannot be listed at all: the round then changes nothing.
    func files() throws -> [String: SaveSyncFolderFile]
    func read(_ name: String) throws -> Data
    /// Writes `data` as `name`, whole or not at all.
    func write(_ data: Data, to name: String) throws
    func remove(_ name: String) throws
    /// The other versions of `name` that the folder keeps beside the one it
    /// shows: what another device wrote at the same moment (iCloud's
    /// conflict versions). Empty for a folder on the device.
    func otherVersions(of name: String) -> [Data]
    /// Forgets the other versions of `name`, once they are kept as saves.
    func discardOtherVersions(of name: String)
}

/// A file in a ``SaveSyncFolder``.
public struct SaveSyncFolderFile: Hashable, Sendable {
    /// `false` while the file is still on its way from iCloud: a save in
    /// it is left for a later round, never taken for gone.
    public var isAvailable: Bool

    public init(isAvailable: Bool = true) {
        self.isAvailable = isAvailable
    }
}

/// A folder on the device, read and written as it is.
public struct DirectorySaveFolder: SaveSyncFolder {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func files() throws -> [String: SaveSyncFolderFile] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        return Dictionary(names.map { ($0, SaveSyncFolderFile()) }, uniquingKeysWith: { first, _ in first })
    }

    public func read(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }

    public func write(_ data: Data, to name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    public func remove(_ name: String) throws {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func otherVersions(of name: String) -> [Data] { [] }

    public func discardOtherVersions(of name: String) {}
}

/// Keeps the device's saves and a second folder in step (decision 397).
///
/// A save is its file and the files kept beside it, its news log and its
/// name (``SaveLibrary``): `<stem>.json`, `<stem>.news.json`,
/// `<stem>.name`, copied together. Nothing else in the folder is copied:
/// the preferences, the challenge records, the achievements and the
/// stamps stay on the device.
///
/// Each round compares each save on the two sides with how it was when
/// they were last the same (``State``), so it knows which side changed:
/// - changed on one side only: copied to the other, or deleted there when
///   it was deleted;
/// - changed on both, the same way: nothing to do;
/// - changed on both, differently: both are kept. The device's stays as it
///   is; the other's is added to the device as a save of the player's own,
///   named as another device's (``Outcome/keptBoth``), then the device's is
///   copied over it in the other folder, with the new save beside it;
/// - deleted on one side and changed on the other: the changed one is kept
///   on both;
/// - a save whose file is on its way from iCloud, or that cannot be read:
///   left as it is for a later round.
///
/// Nothing is ever written over or deleted that was not, the round before,
/// the same on both sides, so no save is lost to another device's.
public enum SaveSync {
    /// When the round runs (decision 397).
    public enum Mode: Hashable, Sendable {
        /// On the start screen: copies both ways.
        case full
        /// While a game is open: copies from the device and adds saves new
        /// to it, but never writes over or deletes a save on the device,
        /// which may be the game being played; that waits for the start
        /// screen.
        case keepingDevice
    }

    /// What the last round left the two sides as: each save's fingerprint
    /// when the two were the same. Kept on the device, beside the saves,
    /// in a file that is not a save (``stateFileName``).
    public struct State: Codable, Hashable, Sendable {
        public var synced: [String: UInt64]

        public init(synced: [String: UInt64] = [:]) {
            self.synced = synced
        }

        /// The state in `url`, or none yet (a first round, or a file that
        /// cannot be read: every save is then compared as new on both
        /// sides, and kept twice at worst, never lost).
        public static func read(from url: URL) -> State {
            guard let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
            return state
        }

        public func write(to url: URL) throws {
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        }
    }

    /// What a round did.
    public struct Outcome: Hashable, Sendable {
        /// Saves copied from the other folder to the device.
        public var downloaded: [String] = []
        /// Saves copied from the device to the other folder.
        public var uploaded: [String] = []
        /// Saves deleted on one side because they were deleted on the other.
        public var deleted: [String] = []
        /// The saves another device changed too, each kept on the device as
        /// a save of the player's own beside the device's: their new file
        /// names.
        public var keptBoth: [String] = []
        /// Whether something could not be read or written (the other folder
        /// full, or not there): those saves are left as they were, on the
        /// device as before, for the next round.
        public var isIncomplete = false

        public init() {}
    }

    /// The file the state is kept in, in the saves' folder. Not `.json`, so
    /// no build lists it as a save, and not copied.
    public static let stateFileName = "save-sync.data"

    /// Runs a round between the device's saves `local` and `cloud`, from
    /// and to `state`, in `mode`. A save kept twice is named in `language`,
    /// stamped `now` when its own date cannot be read.
    public static func run(
        local: any SaveSyncFolder, cloud: any SaveSyncFolder, state: inout State,
        mode: Mode = .full, language: DisplayLanguage, now: Date
    ) -> Outcome {
        var outcome = Outcome()
        guard let localFiles = try? local.files().filter({ downloadingName($0.key) == nil }),
              let cloudFiles = try? standingIn(cloud.files()) else {
            outcome.isIncomplete = true
            return outcome
        }
        let localSaves = saves(in: localFiles)
        let cloudSaves = saves(in: cloudFiles)
        // Names taken on either side, so a save kept twice takes a free one.
        var taken = Set(localFiles.keys).union(cloudFiles.keys)

        // First, what iCloud itself kept twice: another device wrote the
        // same file at the same moment.
        for stem in cloudSaves.keys.sorted() {
            let file = stem + ".json"
            let versions = cloud.otherVersions(of: file)
            guard !versions.isEmpty else { continue }
            var keptAll = true
            for data in versions {
                let group = SaveGroup(files: [file: data])
                if let name = keepAsCopy(group, local: local, cloud: cloud, taken: &taken, state: &state, language: language, now: now) {
                    outcome.keptBoth.append(name)
                } else {
                    keptAll = false
                }
            }
            if keptAll {
                cloud.discardOtherVersions(of: file)
            } else {
                outcome.isIncomplete = true
            }
        }

        for stem in Set(localSaves.keys).union(cloudSaves.keys).union(state.synced.keys).sorted() {
            let base = state.synced[stem]
            // A save on its way from iCloud waits for the next round.
            let members = [stem + ".json", stem + SaveLibrary.newsSuffix, stem + SaveLibrary.nameSuffix]
            if members.contains(where: { cloudFiles[$0]?.isAvailable == false }) {
                continue
            }
            let mine: SaveGroup?
            let theirs: SaveGroup?
            do {
                mine = try localSaves[stem].map { try SaveGroup(reading: $0, from: local) }
                theirs = try cloudSaves[stem].map { try SaveGroup(reading: $0, from: cloud) }
            } catch {
                outcome.isIncomplete = true
                continue
            }
            let (l, c) = (mine?.fingerprint, theirs?.fingerprint)
            do {
                if l == c {
                    state.synced[stem] = l
                } else if c == base {
                    // Changed on the device only.
                    if let mine {
                        try mine.write(to: cloud, over: theirs)
                        outcome.uploaded.append(stem)
                    } else {
                        try theirs?.remove(from: cloud)
                        outcome.deleted.append(stem)
                    }
                    state.synced[stem] = l
                } else if l == base {
                    // Changed in the other folder only.
                    if let theirs {
                        guard mode == .full || mine == nil else { continue }
                        try theirs.write(to: local, over: mine)
                        outcome.downloaded.append(stem)
                    } else {
                        guard mode == .full else { continue }
                        try mine?.remove(from: local)
                        outcome.deleted.append(stem)
                    }
                    state.synced[stem] = c
                } else if let mine, let theirs {
                    // Changed on both, differently: both are kept.
                    guard let name = keepAsCopy(theirs, local: local, cloud: cloud, taken: &taken, state: &state, language: language, now: now) else {
                        outcome.isIncomplete = true
                        continue
                    }
                    outcome.keptBoth.append(name)
                    try mine.write(to: cloud, over: theirs)
                    outcome.uploaded.append(stem)
                    state.synced[stem] = l
                } else if let mine {
                    // Deleted in the other folder, changed on the device.
                    try mine.write(to: cloud, over: nil)
                    outcome.uploaded.append(stem)
                    state.synced[stem] = l
                } else if let theirs {
                    // Deleted on the device, changed in the other folder.
                    try theirs.write(to: local, over: nil)
                    outcome.downloaded.append(stem)
                    state.synced[stem] = c
                }
            } catch {
                outcome.isIncomplete = true
            }
        }
        return outcome
    }

    /// Adds `group` to both sides as a save of the player's own under a
    /// free name, named as another device's. Returns its file name, or
    /// `nil` when it could not be written on the device (nothing is then
    /// changed on the other side either).
    private static func keepAsCopy(
        _ group: SaveGroup, local: any SaveSyncFolder, cloud: any SaveSyncFolder, taken: inout Set<String>,
        state: inout State, language: DisplayLanguage, now: Date
    ) -> String? {
        let stem = freeStem(for: group.savedAt ?? now, taken: taken)
        var files: [String: Data] = [:]
        if let save = group.files[group.stem + ".json"] { files[stem + ".json"] = save }
        if let news = group.files[group.stem + SaveLibrary.newsSuffix] { files[stem + SaveLibrary.newsSuffix] = news }
        let given = group.files[group.stem + SaveLibrary.nameSuffix].flatMap { String(data: $0, encoding: .utf8) }.flatMap(SaveLibrary.cleanName)
        files[stem + SaveLibrary.nameSuffix] = Data(copyName(of: given, in: language).utf8)
        let copy = SaveGroup(files: files)
        do {
            try copy.write(to: local, over: nil)
        } catch {
            try? copy.remove(from: local)
            return nil
        }
        taken.formUnion(files.keys)
        // The other side gets it in this round or the next: it is new there.
        if (try? copy.write(to: cloud, over: nil)) != nil {
            state.synced[stem] = copy.fingerprint
        }
        return stem + ".json"
    }

    /// The name a save kept twice is given: the other device's, after its
    /// own name when it had one.
    static func copyName(of given: String?, in language: DisplayLanguage) -> String {
        let name = given.map { language.text("\($0) (other device)", "\($0)（另一台裝置）") }
            ?? language.text("From another device", "另一台裝置的進度")
        return SaveLibrary.cleanName(name) ?? name
    }

    /// `save-<stamp>-icloud.json`'s stem, with `-2`, `-3`… when taken.
    private static func freeStem(for date: Date, taken: Set<String>) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let stem = "save-\(formatter.string(from: date))-other"
        var candidate = stem
        var number = 2
        while taken.contains(candidate + ".json") || taken.contains(candidate + SaveLibrary.nameSuffix) {
            candidate = "\(stem)-\(number)"
            number += 1
        }
        return candidate
    }

    /// The saves among `files`: each stem whose `<stem>.json` is there, and
    /// the names of its files.
    static func saves(in files: [String: SaveSyncFolderFile]) -> [String: [String]] {
        var saves: [String: [String]] = [:]
        for name in files.keys where name.hasSuffix(".json") && !name.hasSuffix(SaveLibrary.newsSuffix) {
            let stem = String(name.dropLast(".json".count))
            saves[stem] = [name, stem + SaveLibrary.newsSuffix, stem + SaveLibrary.nameSuffix].filter { files[$0] != nil }
        }
        return saves
    }

    /// `files` with each stand-in iCloud lists for a file it has not
    /// brought to the device yet, `.<name>.icloud`, as that file, not
    /// available.
    static func standingIn(_ files: [String: SaveSyncFolderFile]) -> [String: SaveSyncFolderFile] {
        var listed: [String: SaveSyncFolderFile] = [:]
        for (name, file) in files {
            if let real = downloadingName(name) {
                listed[real] = SaveSyncFolderFile(isAvailable: false)
            } else if listed[name]?.isAvailable != false {
                listed[name] = file
            }
        }
        return listed
    }

    /// The name of the file a stand-in `.<name>.icloud` is for; `nil` for
    /// any other name.
    static func downloadingName(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > ".icloud".count + 1 else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    /// FNV-1a, 64 bits: the same bytes give the same number on every
    /// device and every build.
    static func fingerprint(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        data.withUnsafeBytes { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash &*= 0x0000_0100_0000_01b3
            }
        }
        return hash
    }
}

/// One save's files, read.
private struct SaveGroup {
    let files: [String: Data]

    init(files: [String: Data]) {
        self.files = files
    }

    init(reading names: [String], from folder: any SaveSyncFolder) throws {
        var files: [String: Data] = [:]
        for name in names {
            files[name] = try folder.read(name)
        }
        self.files = files
    }

    var stem: String {
        let save = files.keys.first { $0.hasSuffix(".json") && !$0.hasSuffix(SaveLibrary.newsSuffix) } ?? ""
        return String(save.dropLast(".json".count))
    }

    /// The fingerprint of all its files, by name and bytes.
    var fingerprint: UInt64 {
        var hash = SaveSync.fingerprint(Data())
        for name in files.keys.sorted() {
            hash = (hash ^ SaveSync.fingerprint(Data(name.utf8))) &* 0x0000_0100_0000_01b3
            hash = (hash ^ SaveSync.fingerprint(files[name] ?? Data())) &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// When it was saved, from its file's head, or `nil`.
    var savedAt: Date? {
        struct Head: Decodable { let savedAt: Date }
        guard let data = files[stem + ".json"] else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Head.self, from: data))?.savedAt
    }

    /// Writes its files to `folder`, the save's own file last so a save
    /// appears there whole, and deletes the files of `old` it no longer has.
    func write(to folder: any SaveSyncFolder, over old: SaveGroup?) throws {
        let save = stem + ".json"
        for (name, data) in files where name != save {
            try folder.write(data, to: name)
        }
        if let data = files[save] {
            try folder.write(data, to: save)
        }
        for name in (old?.files.keys).map(Array.init) ?? [] where files[name] == nil {
            try folder.remove(name)
        }
    }

    /// Deletes its files from `folder`, the save's own file first.
    func remove(from folder: any SaveSyncFolder) throws {
        let save = stem + ".json"
        if files[save] != nil { try folder.remove(save) }
        for name in files.keys where name != save {
            try folder.remove(name)
        }
    }
}

/// Whether the saves are kept in the player's iCloud too (decision 397), as
/// the list of saves tells it.
public enum CloudSaves: Hashable, Sendable {
    /// No iCloud: the saves are on the device alone, as they always were.
    /// Nothing is said: the player is not asked to do anything.
    case off
    /// The last round kept them in step.
    case on
    /// The last round could not copy some of them (iCloud full, or not
    /// reached); they are on the device as before.
    case incomplete

    /// The line under the list of saves, or `nil`.
    public func footnote(in language: DisplayLanguage) -> String? {
        switch self {
        case .off:
            nil
        case .on:
            language.text(
                "Your saves are kept in your iCloud too, so you can go on playing on your other iPhone or iPad.",
                "存檔也會放進你的 iCloud，換一台 iPhone 或 iPad 都能接著玩。"
            )
        case .incomplete:
            language.text(
                "Some saves could not be put in your iCloud yet. They are all still on this device.",
                "有些存檔還沒能放進你的 iCloud，不過都還在這台裝置上。"
            )
        }
    }

    /// What the start screen says when `count` saves were changed here and
    /// on another device, so both were kept.
    public static func keptTwiceText(_ count: Int, in language: DisplayLanguage) -> String {
        let name = SaveSync.copyName(of: nil, in: language)
        return count == 1
            ? language.text(
                "A save was changed on this device and another, so both are kept: “\(name)” is the other device's.",
                "這台和另一台裝置都改過同一個存檔，所以兩份都留著：「\(name)」是另一台裝置的。"
            )
            : language.text(
                "\(count) saves were changed on this device and another, so both of each are kept: the other device's are in Saves.",
                "有 \(count) 個存檔在這台和另一台裝置都改過，所以每個都留了兩份：另一台裝置的在「存檔」裡。"
            )
    }
}
