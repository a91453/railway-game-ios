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
        guard let group = Bundle.main.object(forInfoDictionaryKey: "BAAppGroupID") as? String, !group.isEmpty,
              Bundle.main.object(forInfoDictionaryKey: "BAUsesAppleHosting") as? Bool == true
        else { return false }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
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
                try? await AssetPackManager.shared.remove(assetPackWithID: city.assetPackID)
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
            try await AssetPackManager.shared.remove(assetPackWithID: city.assetPackID)
        } catch {
            log.notice("map pack \(city.assetPackID, privacy: .public) not removed: \(String(describing: error), privacy: .public)")
            return false
        }
        MapPackChoices.set(city, removed: true)
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
    /// and is worth asking for again.
    private static func fetch(_ city: OverseasMap) async -> Bool {
        do {
            let manager = AssetPackManager.shared
            let pack = try await manager.assetPack(withID: city.assetPackID)
            try await manager.ensureLocalAvailability(of: pack)
            var refusal = take(city, from: manager)
            // DEBUG-138: a pack whose `pack.json` is not the app's own is the
            // version an earlier build was given (0.6.0 (138) on the owner's
            // iPhone kept 137's Hong Kong pack, uploaded again eight minutes
            // before the build came out). The system looks for a new version
            // only now and then, so ask it now, while the app is open, and
            // take the new version once it is down.
            if refusal == .differsFromBundled {
                let (updating, _) = try await manager.checkForUpdates()
                log.notice("map pack \(city.assetPackID, privacy: .public) differs from the app's; updating: \(updating.contains(city.assetPackID), privacy: .public)")
                if updating.contains(city.assetPackID) {
                    MapPackDownloads.note(city, .downloading)
                    let latest = try await manager.assetPack(withID: city.assetPackID)
                    if #available(iOS 26.4, *) {
                        try await manager.ensureLocalAvailability(of: latest, requireLatestVersion: true)
                    } else {
                        try await manager.ensureLocalAvailability(of: latest)
                    }
                    refusal = take(city, from: manager)
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
        let folder = city.assetPackFolderPath
        var askedForFolder = false
        var folderURL: URL?
        let locators: [MapPackDownloads.Locator] = [
            { try? manager.url(for: FilePath("\(folder)/\($0)")) },
            { name in
                if !askedForFolder {
                    askedForFolder = true
                    folderURL = try? manager.url(for: FilePath(folder))
                }
                return folderURL?.appendingPathComponent(name)
            },
        ]
        return MapPackDownloads.use(city, locators: locators, expected: expected)
    }
}
