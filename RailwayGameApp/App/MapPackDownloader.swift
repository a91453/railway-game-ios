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
/// it; the bundled packs are read as before.
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
        // Decision 789: only the open cities have asset packs.
        let cities = OverseasMap.allCases.filter(OverseasMaps.open.contains)
        // Decision 776, later: the settings show how each stands.
        for city in cities { MapPackDownloads.note(city, .downloading) }
        Task.detached(priority: .utility) {
            for city in cities {
                await fetch(city)
            }
        }
    }

    private static func fetch(_ city: OverseasMap) async {
        do {
            let manager = AssetPackManager.shared
            let pack = try await manager.assetPack(withID: city.assetPackID)
            try await manager.ensureLocalAvailability(of: pack)
            var refusal = take(city, from: manager)
            // DEBUG-138: a pack whose files are not the app's own is the
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
            if let refusal {
                MapPackDownloads.note(city, .refused(refusal))
                let clue = MapPackDownloads.clue(city) ?? ""
                log.notice("map pack \(city.assetPackID, privacy: .public) not used: \(String(describing: refusal), privacy: .public) (\(clue, privacy: .public))")
            } else {
                MapPackDownloads.note(city, .downloaded)
                log.notice("map pack \(city.assetPackID, privacy: .public) used")
            }
        } catch {
            MapPackDownloads.note(city, .failed(String(describing: error)))
            log.notice("map pack \(city.assetPackID, privacy: .public) not fetched: \(String(describing: error), privacy: .public)")
        }
    }

    /// Takes `city`'s pack as it lies on the device now (``MapPackDownloads``),
    /// or says why not.
    private static func take(_ city: OverseasMap, from manager: AssetPackManager) -> MapPackDownloads.Refusal? {
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
        return MapPackDownloads.use(city, locators: locators, bundled: MapPack.bundled(city))
    }
}
