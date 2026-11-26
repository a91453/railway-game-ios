import BackgroundAssets
import Foundation
import GamePresentation
import os
import System

/// Decision 776: fetches the cities' map packs that App Store Connect hosts
/// apart from the app (Background Assets) and hands each whole one to
/// ``MapPackDownloads``, which the game reads from (``MapPack/current(_:)``);
/// decision 819: each of a pack's files by the URL `AssetPackManager` gives
/// for it.
///
/// It runs only in an app set up for Apple-hosted asset packs: one whose
/// Info.plist names the App Group the downloader extension shares
/// (`BAAppGroupID`) and that can open that group's folder. Without them
/// `AssetPackManager` stops the app on first use, so nothing here touches
/// it. Decision 858: the app people install carries no pack, only each
/// city's `pack.json`, so there a city is read only once this has taken its
/// download; the Debug app carries the packs whole and reads its own.
enum MapPackDownloader {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RailwayGame", category: "map-packs")

    /// Whether this build is set up for Apple-hosted asset packs.
    static var isAvailable: Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "BAUsesAppleHosting") as? Bool == true else { return false }
        return sharedFolder != nil
    }

    /// The App Group's folder the downloader extension shares, if any.
    private static var sharedFolder: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "BAAppGroupID") as? String, !group.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    /// Starts fetching every city's pack in the background; returns at once.
    static func start() {
        guard isAvailable else { return }
        // Decision 789: only the open cities have asset packs. Decision
        // 858: those the app does not carry first: the real-world data
        // waits for them.
        // MAP-PACK-MANAGE: a pack the player removed is not fetched again
        // (nor read, if the system fetched it back on an update: it is
        // removed once more) until they ask for it in the settings.
        let removed = MapPackChoices.removed()
        let cities = OverseasMap.allCases.filter { OverseasMaps.open.contains($0) && !removed.contains($0) }
            .sorted { !$0.isCarried && $1.isCarried }
        // Decision 776, later: the settings show how each stands.
        for city in cities { MapPackDownloads.note(city, .downloading) }
        for city in OverseasMap.allCases where OverseasMaps.open.contains(city) && removed.contains(city) {
            MapPackDownloads.note(city, .removed)
        }
        Task.detached(priority: .userInitiated) {
            for city in OverseasMap.allCases where OverseasMaps.open.contains(city) && removed.contains(city) {
                // Decision 991: every asset pack of its map.
                for id in city.assetPackIDs {
                    try? await AssetPackManager.shared.remove(assetPackWithID: id)
                }
            }
            // Decision 858: what is on the device already is taken before
            // anything is asked of the network, so a city downloaded
            // before is there at once, offline too.
            var waiting: [OverseasMap] = []
            for city in cities {
                if take(city, from: AssetPackManager.shared) == nil {
                    MapPackDownloads.note(city, .downloaded)
                    log.notice("map pack \(city.assetPackID, privacy: .public) used (on the device)")
                } else {
                    waiting.append(city)
                }
            }
            // The rest are fetched, and fetched again while they fail
            // (no network on the first launch): after 15 seconds, then
            // twice as long each time, up to five minutes.
            var pause: UInt64 = 15
            while !waiting.isEmpty {
                var failed: [OverseasMap] = []
                for city in waiting {
                    let fetched = await fetch(city)
                    if !fetched { failed.append(city) }
                }
                waiting = failed
                guard !waiting.isEmpty else { break }
                try? await Task.sleep(nanoseconds: pause * 1_000_000_000)
                pause = min(pause * 2, 300)
            }
        }
    }

    /// MAP-PACK-MANAGE: removes `city`'s pack from the device at the
    /// player's word; the game stops reading it at once. Whether it went.
    static func remove(_ city: OverseasMap) async -> Bool {
        guard isAvailable, !city.isCarried else { return false }
        do {
            // Decision 991: every asset pack of its map.
            for id in city.assetPackIDs {
                try await AssetPackManager.shared.remove(assetPackWithID: id)
            }
        } catch {
            log.notice("map pack \(city.assetPackID, privacy: .public) not removed: \(String(describing: error), privacy: .public)")
            return false
        }
        MapPackChoices.set(city, removed: true)
        Copier(city: city, manager: AssetPackManager.shared).removeCopies()
        MapPackDownloads.forget(city)
        MapPackDownloads.note(city, .removed)
        log.notice("map pack \(city.assetPackID, privacy: .public) removed by the player")
        return true
    }

    /// MAP-PACK-MANAGE: fetches `city`'s pack again at the player's word
    /// (one they removed, or one that did not come), as at launch.
    static func download(_ city: OverseasMap) {
        guard isAvailable else { return }
        MapPackChoices.set(city, removed: false)
        MapPackDownloads.note(city, .downloading)
        Task.detached(priority: .userInitiated) {
            _ = await fetch(city)
        }
    }

    /// Fetches `city`'s pack and takes it; `false` when it did not arrive
    /// and is worth asking for again. Decision 991: every asset pack its
    /// map is in (``OverseasMap/assetPackIDs``), the city's own first; it
    /// is taken once all of them are on the device.
    private static func fetch(_ city: OverseasMap) async -> Bool {
        do {
            let manager = AssetPackManager.shared
            for id in city.assetPackIDs {
                let pack = try await manager.assetPack(withID: id)
                try await manager.ensureLocalAvailability(of: pack)
            }
            var refusal = take(city, from: manager)
            // DEBUG-138: a pack whose `pack.json` is not the app's own is the
            // version an earlier build was given (0.6.0 (138) on the owner's
            // iPhone kept 137's Hong Kong pack, uploaded again eight minutes
            // before the build came out). The system looks for a new version
            // only now and then, so ask it now, while the app is open, and
            // take the new version once it is down.
            // Decision 991: or a part of it is (a file it lists not at the
            // listed size).
            var partOld = false
            if case .incomplete? = refusal, city.assetPackIDs.count > 1 { partOld = true }
            if refusal == .differsFromBundled || partOld {
                let (updating, _) = try await manager.checkForUpdates()
                let ids = city.assetPackIDs.filter(updating.contains)
                log.notice("map pack \(city.assetPackID, privacy: .public) differs from the app's; updating: \(ids.joined(separator: ", "), privacy: .public)")
                if !ids.isEmpty {
                    MapPackDownloads.note(city, .downloading)
                    for id in ids {
                        let latest = try await manager.assetPack(withID: id)
                        if #available(iOS 26.4, *) {
                            try await manager.ensureLocalAvailability(of: latest, requireLatestVersion: true)
                        } else {
                            try await manager.ensureLocalAvailability(of: latest)
                        }
                    }
                    refusal = take(city, from: manager)
                }
            }
            // DEBUG-150: 0.6.0 (150) on the owner's iPhone: every pack was
            // said to be on the device, yet not one of its files could be
            // found (the day before, 147 read them). The system's copy is
            // thrown away and fetched again, once each time this is asked.
            // MAP-PACK-COPY: in an app that carries the city too, once a
            // build (the player reads the carried one meanwhile), so a
            // problem report tells whether fetching again mends it.
            if refusal == .noManifest, !city.isCarried || refetchOnceThisBuild(city) {
                log.notice("map pack \(city.assetPackID, privacy: .public) said to be on the device but not found; fetching it again")
                MapPackDownloads.note(city, .downloading)
                for id in city.assetPackIDs {
                    try? await manager.remove(assetPackWithID: id)
                }
                for id in city.assetPackIDs {
                    let pack = try await manager.assetPack(withID: id)
                    try await manager.ensureLocalAvailability(of: pack)
                }
                refusal = take(city, from: manager)
                if refusal != nil {
                    MapPackDownloads.addToClue(city, "fetched again")
                } else {
                    MapPackDownloads.noteWay(city, ["fetched again", MapPackDownloads.way(city)].compactMap { $0 }.joined(separator: ", "))
                }
            }
            // Decision 858: the app carries no pack of the city, and the
            // one it lists has not come (a new version of the pack still
            // waits for its review, say): the one on the device is read
            // rather than none.
            if refusal == .differsFromBundled, !city.isCarried, take(city, from: manager, expected: nil) == nil {
                MapPackDownloads.note(city, .earlier)
                log.notice("map pack \(city.assetPackID, privacy: .public) used: not the version the app lists")
                return true
            }
            if let refusal {
                MapPackDownloads.note(city, .refused(refusal))
                let clue = MapPackDownloads.clue(city) ?? ""
                log.notice("map pack \(city.assetPackID, privacy: .public) not used: \(String(describing: refusal), privacy: .public) (\(clue, privacy: .public))")
            } else {
                MapPackDownloads.note(city, .downloaded)
                log.notice("map pack \(city.assetPackID, privacy: .public) used")
            }
            return true
        } catch {
            log.notice("map pack \(city.assetPackID, privacy: .public) not fetched: \(String(describing: error), privacy: .public)")
            // Decision 858: offline with another version of the pack on the
            // device, and no pack in the app: that one is read meanwhile
            // (taken once; asking again goes on).
            if !city.isCarried, MapPackDownloads.pack(city) != nil || take(city, from: AssetPackManager.shared, expected: nil) == nil {
                MapPackDownloads.note(city, .earlier)
                return false
            }
            MapPackDownloads.note(city, .failed(String(describing: error)))
            return false
        }
    }

    /// MAP-PACK-COPY: whether `city`'s pack is to be fetched again now in
    /// an app that carries it: the first time in this build of the app.
    private static func refetchOnceThisBuild(_ city: OverseasMap) -> Bool {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let key = "mapPacks.refetchedInBuild.\(city.rawValue)"
        guard UserDefaults.standard.string(forKey: key) != build else { return false }
        UserDefaults.standard.set(build, forKey: key)
        return true
    }

    /// Takes `city`'s pack as it lies on the device now (``MapPackDownloads``),
    /// or says why not.
    private static func take(_ city: OverseasMap, from manager: AssetPackManager) -> MapPackDownloads.Refusal? {
        take(city, from: manager, expected: MapPack.carriedManifest(city))
    }

    /// ``take(_:from:)`` against `expected`, the `pack.json` the download's
    /// must be (decision 858: the app's own copy of it); `nil` takes any
    /// whole pack of the city.
    private static func take(_ city: OverseasMap, from manager: AssetPackManager, expected: Data?) -> MapPackDownloads.Refusal? {
        // Decision 819: each file is asked for by its own path. The URL
        // `url(for:)` gives for one file is of that file only: on the
        // owner's iPhone (0.6.0 (136)) the folder of `pack.json`'s held
        // nothing else. The city's folder, asked for whole, is the second
        // place to look (Apple's answer to a bug in asking for a file,
        // FB19512759); asked for at most once, and only when needed.
        // Decision 991: a file of a part of the map (a name with a folder
        // in it) lies in that part's folder, beside the city's.
        // DEBUG-150: what the system said when it could not give a file,
        // and, third, the shared folder searched for the file by its path
        // (looked through at most once, and only when needed).
        var folderURLs: [String: URL?] = [:]
        var refusals: [String] = []
        var shared: [String: URL]?
        func ask(_ path: String) -> URL? {
            do {
                return try manager.url(for: FilePath(path))
            } catch {
                if refusals.count < 2 { refusals.append("\(path): \(String(describing: error).prefix(160))") }
                return nil
            }
        }
        func sharedFiles() -> [String: URL] {
            if let shared { return shared }
            let found = sharedFolder.map { MapPackDownloads.mapPackFiles(under: $0) } ?? [:]
            shared = found
            return found
        }
        // MAP-PACK-COPY: fourth, each file copied out of the system's into
        // the app's own folder through a file descriptor, which asks the
        // system to stage nothing (``Copier``).
        let copier = Copier(city: city, manager: manager)
        let locators: [MapPackDownloads.Locator] = [
            { ask(city.assetPackPath(of: $0)) },
            { name in
                let path = city.assetPackPath(of: name)
                let folder = (path as NSString).deletingLastPathComponent
                if folderURLs[folder] == nil {
                    folderURLs[folder] = .some(ask(folder))
                }
                return folderURLs[folder]??.appendingPathComponent((path as NSString).lastPathComponent)
            },
            { sharedFiles()[city.assetPackPath(of: $0)] },
            { copier.locate($0) },
        ]
        let refusal = MapPackDownloads.use(city, locators: locators, expected: expected)
        if refusal == nil {
            if copier.used > 0 {
                MapPackDownloads.noteWay(city, "copied out: \(copier.used) files, \(copier.copied) new")
            } else {
                // Read the usual way: a copy left from before is not needed.
                MapPackDownloads.noteWay(city, nil)
                copier.removeCopies()
            }
        }
        if refusal == .noManifest {
            let said = refusals.isEmpty ? "url(for:) gave no error" : "url(for:) said \(refusals.joined(separator: " | "))"
            let copied = copier.errors.isEmpty ? "copy gave no error" : "copy said \(copier.errors.joined(separator: " | "))"
            MapPackDownloads.addToClue(city, "\(said); \(copied); \(MapPackDownloads.describeMapPackFiles(sharedFiles()))")
        }
        return refusal
    }

    /// MAP-PACK-COPY: where the files copied out of the system's lie, a
    /// folder of each city's (`MapPacks/<folder>`, and each part's beside
    /// it), as in the bundle.
    fileprivate static var copiesFolder: URL? {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        return support.appendingPathComponent("MapPackCopies/MapPacks", isDirectory: true)
    }

    /// MAP-PACK-COPY (after DEBUG-150): 0.6.0 (150) and (151) on the
    /// owner's iPhone could not read one file of the packs: `url(for:)`
    /// answered for every file and folder that it had no permission to
    /// save "Staged Subpaths.plist" in the pack's folder (NSCocoaErrorDomain
    /// 513), on the first build whose packs were new versions of ones
    /// already on the device. Apple's forums tell of the same after an
    /// update (threads 859906 and 845723: reinstalling the app mends it).
    /// `url(for:)` stages the file it gives; `descriptor(for:)` opens the
    /// file and stages nothing, so each file is copied from it, once, into
    /// the app's own folder (`contents(at:)` when that fails), and read
    /// from there. A copy is kept while its `pack.json` is the one the
    /// system holds, and removed once the pack is read the usual way again.
    private final class Copier {
        let city: OverseasMap
        let manager: AssetPackManager
        private var found: [String: URL?] = [:]
        /// Files handed over, and of them copied in this pass.
        private(set) var used = 0
        private(set) var copied = 0
        /// What the system said when a file could not be copied (two at most).
        private(set) var errors: [String] = []

        init(city: OverseasMap, manager: AssetPackManager) {
            self.city = city
            self.manager = manager
        }

        func locate(_ name: String) -> URL? {
            if let known = found[name] { return known }
            let url = copy(name)
            found[name] = .some(url)
            if url != nil { used += 1 }
            return url
        }

        /// The city's folder of copies and each of its parts'.
        private var folders: [URL] {
            guard let root = MapPackDownloader.copiesFolder else { return [] }
            return ([city.packFolder] + city.partFolders).map { root.appendingPathComponent($0, isDirectory: true) }
        }

        func removeCopies() {
            for folder in folders where FileManager.default.fileExists(atPath: folder.path) {
                try? FileManager.default.removeItem(at: folder)
            }
        }

        private func copy(_ name: String) -> URL? {
            guard let root = MapPackDownloader.copiesFolder, let own = folders.first else { return nil }
            let fileManager = FileManager.default
            let destination = MapPack.place(of: name, root: own)
            // `pack.json` is copied each time: when it is not the one copied
            // before, nor is anything else, and the copies start again.
            if name != "pack.json", fileManager.fileExists(atPath: destination.path) { return destination }
            let path = city.assetPackPath(of: name)
            let pack = name.contains("/") ? "mappack-\(name.split(separator: "/")[0])" : city.assetPackID
            let staging = root.deletingLastPathComponent().appendingPathComponent("staging-\(UUID().uuidString)")
            do {
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var top = root.deletingLastPathComponent()
                try fileManager.createDirectory(at: top, withIntermediateDirectories: true)
                try? top.setResourceValues(values)
                try write(path, of: pack, to: staging)
                if name == "pack.json" {
                    if let held = try? Data(contentsOf: destination), let new = try? Data(contentsOf: staging), held == new {
                        try? fileManager.removeItem(at: staging)
                        return destination
                    }
                    removeCopies()
                }
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
                try fileManager.moveItem(at: staging, to: destination)
                copied += 1
                return destination
            } catch {
                try? fileManager.removeItem(at: staging)
                if errors.count < 2 { errors.append("\(path): \(String(describing: error).prefix(160))") }
                return nil
            }
        }

        /// Writes the file at `path` of the asset pack `pack` to `url`: read
        /// through a file descriptor, or whole when that cannot be opened.
        private func write(_ path: String, of pack: String, to url: URL) throws {
            let descriptor: FileDescriptor
            do {
                descriptor = try manager.descriptor(for: FilePath(path), searchingInAssetPackWithID: pack)
            } catch let opening {
                do {
                    let data = try manager.contents(at: FilePath(path), searchingInAssetPackWithID: pack, options: .mappedIfSafe)
                    try data.write(to: url)
                    return
                } catch {
                    throw CopyFailure(text: "descriptor: \(opening); contents: \(error)")
                }
            }
            defer { try? descriptor.close() }
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CopyFailure(text: "cannot create the copy")
            }
            let out = try FileHandle(forWritingTo: url)
            defer { try? out.close() }
            var buffer = [UInt8](repeating: 0, count: 1 << 20)
            while true {
                let count = try buffer.withUnsafeMutableBytes { try descriptor.read(into: $0) }
                if count == 0 { break }
                try out.write(contentsOf: buffer[0 ..< count])
            }
        }
    }

    private struct CopyFailure: Error, CustomStringConvertible {
        let text: String
        var description: String { text }
    }
}
