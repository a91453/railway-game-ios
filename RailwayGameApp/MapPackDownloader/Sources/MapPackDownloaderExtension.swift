import BackgroundAssets
import ExtensionFoundation
import StoreKit

/// Decision 776: the downloader extension of the cities' map packs that App
/// Store Connect hosts (Background Assets). The system runs it to fetch a
/// pack in the background, before the app asks; every pack is wanted, so it
/// lets each one download. The app takes a pack once it is whole
/// (`MapPackDownloader`, `MapPackDownloads`).
@main
struct MapPackDownloaderExtension: StoreDownloaderExtension {
    func shouldDownload(_ assetPack: AssetPack) -> Bool {
        true
    }
}
