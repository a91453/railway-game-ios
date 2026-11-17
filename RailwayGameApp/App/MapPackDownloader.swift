import BackgroundAssets
import Foundation
import GamePresentation
import os
import System

/// Decision 776: fetches the cities' map packs that App Store Connect hosts
/// apart from the app (Background Assets) and hands each whole one to
/// ``MapPackDownloads``, which the game reads from (``MapPack/current(_:)``).
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
            let manifest = try manager.url(for: FilePath(city.assetPackManifestPath))
            if let refusal = MapPackDownloads.use(city, root: manifest.deletingLastPathComponent()) {
                MapPackDownloads.note(city, .refused(refusal))
                log.notice("map pack \(city.assetPackID, privacy: .public) not used: \(String(describing: refusal), privacy: .public)")
            } else {
                MapPackDownloads.note(city, .downloaded)
                log.notice("map pack \(city.assetPackID, privacy: .public) used")
            }
        } catch {
            MapPackDownloads.note(city, .failed(String(describing: error)))
            log.notice("map pack \(city.assetPackID, privacy: .public) not fetched: \(String(describing: error), privacy: .public)")
        }
    }
}
