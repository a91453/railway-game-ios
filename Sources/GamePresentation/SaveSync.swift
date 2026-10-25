import Foundation
import GameCore

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
    /// Whose folder it is (a fingerprint of the iCloud account), or `nil`
    /// when that cannot be told. A round finding another than the last
    /// one's compares every save as new: another account's saves are not
    /// how this device's were left.
    var owner: UInt64? { get }
}

extension SaveSyncFolder {
    public var owner: UInt64? { nil }
}

/// A file in a ``SaveSyncFolder``.
public struct SaveSyncFolderFile: Hashable, Sendable {
    /// `false` while the file is still on its way from iCloud: a save in
    /// it is left for a later round, never taken for gone.
    public var isAvailable: Bool
    /// `false` while the file is in the folder on this device but not yet
    /// in iCloud itself (offline, or still going up): another device does
    /// not see it yet. Always `true` for a folder on the device.
    public var isUploaded: Bool

    public init(isAvailable: Bool = true, isUploaded: Bool = true) {
        self.isAvailable = isAvailable
        self.isUploaded = isUploaded
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
/// `<stem>.name`, copied together. Only the player's own saves and the
/// latest autosave are copied: the autosaves taken in turn (decision 192)
/// stay on the device, as do the preferences, the challenge records, the
/// achievements and the stamps.
///
/// Each round compares each save on the two sides with how it was when
/// they were last the same (``State``), so it knows which side changed:
/// - changed on one side only: copied to the other. Deleted on the device:
///   deleted in the other folder. Deleted in the other folder: kept on the
///   device as it is (only the player deletes a save there), not copied
///   back unless changed;
/// - changed on both, the same way: nothing to do;
/// - changed on both, differently: both are kept. The device's stays as it
///   is; the other's is added to the device as a save of the player's own,
///   named as another device's (``Outcome/keptBoth``), then the device's is
///   copied over it in the other folder, with the new save beside it;
/// - deleted on one side and changed on the other: the changed one is kept
///   on both;
/// - a save whose file is on its way from iCloud, or that cannot be read:
///   left as it is for a later round;
/// - a later build's save, which this build cannot read: never written
///   over a save here, nor as the autosave (`SaveGroup.canTakeInPlace`).
///
/// Nothing is ever written over or deleted that was not, the round before,
/// the same on both sides, so no save is lost to another device's.
public enum SaveSync {
    /// When the round runs (decision 397).
    public enum Mode: Hashable, Sendable {
        /// On the start screen: copies both ways.
        case full
        /// While a game is open: copies from the device and adds saves new
        /// to it, but never writes over a save on the device, which may be
        /// the game being played, nor the autosave where there is none;
        /// that waits for the start screen.
        case keepingDevice
    }

    /// What the last round left the two sides as: each save's fingerprint
    /// when the two were the same. Kept on the device, beside the saves,
    /// in a file that is not a save (``stateFileName``).
    public struct State: Codable, Hashable, Sendable {
        public var synced: [String: UInt64]
        /// The other folder's ``SaveSyncFolder/owner`` when `synced` was
        /// recorded.
        public var owner: UInt64?
        /// The other folder's mark (``markFileName``) when `synced` was
        /// recorded.
        public var mark: String?
        /// The saves another device deleted, kept on this one as they were
        /// (their fingerprints): not copied back, not deleted here.
        public var leftHere: [String: UInt64]

        public init(synced: [String: UInt64] = [:], owner: UInt64? = nil, mark: String? = nil, leftHere: [String: UInt64] = [:]) {
            self.synced = synced
            self.owner = owner
            self.mark = mark
            self.leftHere = leftHere
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            synced = try container.decode([String: UInt64].self, forKey: .synced)
            owner = try container.decodeIfPresent(UInt64.self, forKey: .owner)
            mark = try container.decodeIfPresent(String.self, forKey: .mark)
            leftHere = try container.decodeIfPresent([String: UInt64].self, forKey: .leftHere) ?? [:]
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
        /// Saves deleted in the other folder because they were deleted on
        /// the device. A round never deletes a save on the device.
        public var deleted: [String] = []
        /// The saves another device changed too, each kept on the device as
        /// a save of the player's own beside the device's: their new file
        /// names.
        public var keptBoth: [String] = []
        /// Whether something could not be read or written (the other folder
        /// full, or not there): those saves are left as they were, on the
        /// device as before, for the next round.
        public var isIncomplete = false
        /// Where each save on the device stands after the round, by stem
        /// (the autosaves taken in turn, never copied, are not in it).
        public var marks: [String: CloudSaveMark] = [:]
        /// How many saves another device put in iCloud are still on their
        /// way to this one.
        public var downloading = 0

        public init() {}

        /// How many saves on the device another device cannot see yet.
        public var waiting: Int {
            marks.values.filter { $0 == .waiting }.count
        }
    }

    /// The file the state is kept in, in the saves' folder. Not `.json`, so
    /// no build lists it as a save, and not copied.
    public static let stateFileName = "save-sync.data"

    /// The file in the other folder that tells it apart: a random mark,
    /// written by the first round that finds none. A folder emptied (the
    /// account's iCloud data deleted) and filled again by another device
    /// has another mark, so this device knows the saves there are not how
    /// it left them. Not `.json`, so not a save.
    public static let markFileName = "save-sync.id"

    /// Runs a round between the device's saves `local` and `cloud`, from
    /// and to `state`, in `mode`. A save kept twice is named in `language`,
    /// stamped `now` when its own date cannot be read.
    public static func run(
        local: any SaveSyncFolder, cloud: any SaveSyncFolder, state: inout State,
        mode: Mode = .full, language: DisplayLanguage, now: Date, isGameOpen: () -> Bool = { false }
    ) -> Outcome {
        var outcome = Outcome()
        guard let localFiles = try? local.files().filter({ downloadingName($0.key) == nil }),
              let cloudFiles = try? standingIn(cloud.files()) else {
            outcome.isIncomplete = true
            return outcome
        }
        let localSaves = saves(in: localFiles)
        let cloudSaves = saves(in: cloudFiles)
        // Another account's folder, or another folder of the same account
        // (its iCloud data deleted, then filled again, or not listed yet):
        // the saves there are not how the last round left them. Every save
        // is then compared as new: at worst one is kept twice.
        let mark: String
        switch cloudFiles[markFileName]?.isAvailable {
        case true?:
            guard let data = try? cloud.read(markFileName), let read = String(data: data, encoding: .utf8) else {
                outcome.isIncomplete = true
                return outcome
            }
            mark = read
        case false?:
            outcome.isIncomplete = true
            return outcome
        case nil:
            mark = UUID().uuidString
            guard (try? cloud.write(Data(mark.utf8), to: markFileName)) != nil else {
                outcome.isIncomplete = true
                return outcome
            }
        }
        if state.owner != cloud.owner || state.mark != mark {
            state = State(owner: cloud.owner, mark: mark)
        }
        // Names taken on either side, so a save kept twice takes a free one.
        var taken = Set(localFiles.keys).union(cloudFiles.keys)

        // First, what iCloud itself kept twice: another device wrote the
        // same file at the same moment.
        for stem in cloudSaves.keys.sorted() {
            // The news log's and name's other versions are not kept: the
            // save's own are, each with its own name.
            cloud.discardOtherVersions(of: stem + SaveLibrary.newsSuffix)
            cloud.discardOtherVersions(of: stem + SaveLibrary.nameSuffix)
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

        // The saves the two sides hold the same of after the round.
        var settled: Set<String> = []
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
            // Deleted on another device, kept here as it was: left alone.
            if let left = state.leftHere[stem] {
                if theirs == nil, l == left { continue }
                state.leftHere[stem] = nil
            }
            // While a game is open, nothing is written as the autosave,
            // even where the device has none: the game being played saves
            // there next, and would be copied over the other device's. A
            // game started while the round runs counts too.
            let mayDownload = !SaveLibrary.isAutosave(stem + ".json") || (mode == .full && !isGameOpen())
            do {
                if l == c {
                    state.synced[stem] = l
                    settled.insert(stem)
                } else if c == base {
                    // Changed on the device only.
                    if let mine {
                        try mine.write(to: cloud, over: theirs)
                        outcome.uploaded.append(stem)
                        settled.insert(stem)
                    } else {
                        try theirs?.remove(from: cloud)
                        outcome.deleted.append(stem)
                    }
                    state.synced[stem] = l
                } else if l == base {
                    // Changed in the other folder only.
                    if let theirs {
                        guard mode == .full || mine == nil, mayDownload, theirs.canTakeInPlace(over: mine) else { continue }
                        try theirs.write(to: local, over: mine)
                        outcome.downloaded.append(stem)
                        settled.insert(stem)
                    } else {
                        // Deleted in the other folder: kept here, as only
                        // the player deletes a save on this device. Not
                        // copied back either, unless changed here.
                        state.synced[stem] = nil
                        if let l { state.leftHere[stem] = l }
                        continue
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
                    settled.insert(stem)
                    state.synced[stem] = l
                } else if let mine {
                    // Deleted in the other folder, changed on the device.
                    try mine.write(to: cloud, over: nil)
                    outcome.uploaded.append(stem)
                    settled.insert(stem)
                    state.synced[stem] = l
                } else if let theirs {
                    // Deleted on the device, changed in the other folder.
                    guard mayDownload, theirs.canTakeInPlace(over: nil) else { continue }
                    try theirs.write(to: local, over: nil)
                    outcome.downloaded.append(stem)
                    settled.insert(stem)
                    state.synced[stem] = c
                }
            } catch {
                outcome.isIncomplete = true
            }
        }
        // A save kept twice is the same on both sides once it is in iCloud.
        for name in outcome.keptBoth {
            let stem = String(name.dropLast(".json".count))
            if state.synced[stem] != nil { settled.insert(stem) }
        }
        fillMarks(&outcome, local: local, cloud: cloud, listed: cloudFiles, settled: settled)
        return outcome
    }

    /// Fills in `outcome`'s marks: where each save on the device stands,
    /// from the two folders as the round left them. `listed` is the other
    /// folder as the round found it, used when it cannot be listed again.
    private static func fillMarks(
        _ outcome: inout Outcome, local: any SaveSyncFolder, cloud: any SaveSyncFolder,
        listed: [String: SaveSyncFolderFile], settled: Set<String>
    ) {
        guard let localFiles = try? local.files().filter({ downloadingName($0.key) == nil }) else { return }
        let cloudFiles = (try? standingIn(cloud.files())) ?? listed
        let localSaves = saves(in: localFiles)
        for (stem, names) in saves(in: cloudFiles) where localSaves[stem] == nil {
            if names.contains(where: { cloudFiles[$0]?.isAvailable == false }) {
                outcome.downloading += 1
            }
        }
        for stem in localSaves.keys {
            let members = [stem + ".json", stem + SaveLibrary.newsSuffix, stem + SaveLibrary.nameSuffix].compactMap { cloudFiles[$0] }
            if members.contains(where: { !$0.isAvailable }) {
                outcome.marks[stem] = .downloading
            } else if cloudFiles[stem + ".json"] == nil {
                outcome.marks[stem] = .onlyOnDevice
            } else if settled.contains(stem), members.allSatisfy(\.isUploaded) {
                outcome.marks[stem] = .inICloud
            } else {
                outcome.marks[stem] = .waiting
            }
        }
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

    /// The saves among `files` that are copied: each stem whose
    /// `<stem>.json` is there, and the names of its files. The autosaves
    /// taken in turn (decision 192) are the device's own way back and stay
    /// on it: only the latest autosave goes to the other device.
    static func saves(in files: [String: SaveSyncFolderFile]) -> [String: [String]] {
        var saves: [String: [String]] = [:]
        for name in files.keys where name.hasSuffix(".json") && !name.hasSuffix(SaveLibrary.newsSuffix) && SaveLibrary.slotNumber(of: name) == nil {
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
    public static func fingerprint(_ data: Data) -> UInt64 {
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

    /// Whether a save another device wrote may take its own name on this
    /// one, over `old` or where there is none: always, unless this build
    /// cannot read it (a later build's, of a newer save version). Then
    /// only a save of the player's own where there is none: the app never
    /// writes over those, and lists it as needing an update. An autosave
    /// of a later build would be written over by this build's next one,
    /// and that copied back over the later build's game; it waits, for
    /// the app to be updated, or for this device's next autosave, when
    /// the two are kept twice.
    func canTakeInPlace(over old: SaveGroup?) -> Bool {
        guard isNewerThanThisBuild else { return true }
        return old == nil && !SaveLibrary.isAutosave(stem + ".json")
    }

    /// Whether its file is of a save version later than this build reads.
    var isNewerThanThisBuild: Bool {
        struct Head: Decodable {
            struct Game: Decodable { let saveVersion: Int }
            let game: Game
        }
        guard let data = files[stem + ".json"], let head = try? JSONDecoder().decode(Head.self, from: data) else { return false }
        return head.game.saveVersion > SavedGame.currentVersion
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
    /// When a file cannot be written (the folder full), the files written
    /// are put back as `old` had them, so `old` is left whole.
    func write(to folder: any SaveSyncFolder, over old: SaveGroup?) throws {
        let save = stem + ".json"
        var written: [String] = []
        do {
            for (name, data) in files.sorted(by: { $0.key < $1.key }) where name != save {
                try folder.write(data, to: name)
                written.append(name)
            }
            if let data = files[save] {
                try folder.write(data, to: save)
            }
        } catch {
            for name in written {
                if let data = old?.files[name] {
                    try? folder.write(data, to: name)
                } else {
                    try? folder.remove(name)
                }
            }
            throw error
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

/// Where a save on the device stands with iCloud after the last round
/// (decision 397, later), as its row in the list of saves shows it.
public enum CloudSaveMark: Hashable, Sendable {
    /// Not in iCloud: kept on this device alone (deleted on another
    /// device, or not put in iCloud yet).
    case onlyOnDevice
    /// In iCloud as it is here: another device gets it.
    case inICloud
    /// Not yet the same in iCloud: going up, waiting to be online, or
    /// another device's newer one waiting for the start screen.
    case waiting
    /// Another device's newer one is on its way to this one.
    case downloading

    /// The few words beside the save.
    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .onlyOnDevice: language.text("On this device only", "只在這台")
        case .inICloud: language.text("In iCloud", "已在 iCloud")
        case .waiting: language.text("Waiting to sync", "等待同步")
        case .downloading: language.text("Downloading", "下載中")
        }
    }

    /// The SF Symbol beside the words.
    public var systemImage: String {
        switch self {
        case .onlyOnDevice: "iphone"
        case .inICloud: "checkmark.icloud"
        case .waiting: "icloud.and.arrow.up"
        case .downloading: "icloud.and.arrow.down"
        }
    }
}

/// Whether the saves are kept in the player's iCloud too (decision 397), as
/// the start screen and the list of saves tell it (decision 397, later).
public enum CloudSaves: Hashable, Sendable {
    /// A build that does not use iCloud (the tests, the UI tests): nothing
    /// is said.
    case off
    /// iCloud is not on for the game on this device (signed out, iCloud
    /// Drive off, or the game turned off in iCloud's settings): the saves
    /// are on the device alone, and the player is told where to turn it on.
    case iCloudOff
    /// A round is running.
    case syncing
    /// The last round, at that moment, left every save the same in iCloud.
    case synced(at: Date)
    /// The last round left saves not yet the same: `uploads` on this
    /// device another device cannot see yet (going up, or offline), and
    /// `downloads` on their way here.
    case waiting(uploads: Int, downloads: Int)
    /// The last round could not copy some of them (iCloud full, or not
    /// reached); they are on the device as before.
    case incomplete

    /// What the last round, ended at `date`, says (`nil`: no iCloud).
    public static func after(_ outcome: SaveSync.Outcome?, at date: Date) -> CloudSaves {
        guard let outcome else { return .iCloudOff }
        if outcome.isIncomplete { return .incomplete }
        if outcome.waiting > 0 || outcome.downloading > 0 || outcome.marks.values.contains(.downloading) {
            let downloads = outcome.downloading + outcome.marks.values.filter { $0 == .downloading }.count
            return .waiting(uploads: outcome.waiting, downloads: downloads)
        }
        return .synced(at: date)
    }

    /// Whether the line's Sync Now can be tapped: no round is running
    /// (with iCloud off, a round looks again, as the player may have
    /// turned it on).
    public var canSyncNow: Bool {
        switch self {
        case .off, .syncing: false
        case .iCloudOff, .synced, .waiting, .incomplete: true
        }
    }

    /// The SF Symbol beside the line, or `nil` when nothing is said.
    public var systemImage: String? {
        switch self {
        case .off: nil
        case .iCloudOff: "icloud.slash"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .synced: "checkmark.icloud"
        case .waiting: "icloud.and.arrow.up"
        case .incomplete: "exclamationmark.icloud"
        }
    }

    /// The line on the start screen and under the list of saves, or `nil`;
    /// a time is said as `now` sees it.
    public func footnote(in language: DisplayLanguage, now: Date = Date()) -> String? {
        switch self {
        case .off:
            return nil
        case .iCloudOff:
            return language.text(
                "iCloud is off, so your saves are on this device only. To play on another iPhone or iPad, turn on iCloud Drive and this game in Settings › your name › iCloud.",
                "iCloud 沒有開，存檔只在這台裝置上。想在另一台 iPhone 或 iPad 接著玩，請到「設定 › 你的名字 › iCloud」打開 iCloud 雲碟和這個遊戲。"
            )
        case .syncing:
            return language.text("Syncing with iCloud…", "正在和 iCloud 同步…")
        case .synced(let date):
            let ago = SaveLibrary.agoText(from: date, to: now, in: language)
            return language.text(
                "Your saves are in your iCloud (synced \(ago)), so you can go on playing on your other iPhone or iPad.",
                "存檔已放進你的 iCloud（\(ago)同步），換一台 iPhone 或 iPad 都能接著玩。"
            )
        case let .waiting(uploads, downloads):
            var parts: [String] = []
            if uploads > 0 {
                parts.append(language.text(
                    uploads == 1 ? "1 save is waiting to go up to iCloud; it goes when you are online." : "\(uploads) saves are waiting to go up to iCloud; they go when you are online.",
                    "\(uploads) 個存檔等待上傳到 iCloud，連上網路後會自動上傳。"
                ))
            }
            if downloads > 0 {
                parts.append(language.text(
                    downloads == 1 ? "1 save from your other device is downloading." : "\(downloads) saves from your other device are downloading.",
                    "另一台裝置的 \(downloads) 個存檔正在下載。"
                ))
            }
            return parts.joined(separator: language.text(" ", ""))
        case .incomplete:
            return language.text(
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
