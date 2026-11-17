import Foundation

// Decision 776: a city's map pack downloaded apart from the app (Apple-hosted
// Background Assets, decision 697's plan). The app hands each downloaded
// pack's folder to ``MapPackDownloads/use(_:root:)``; the game then reads the
// city from ``MapPack/current(_:)``, which is the downloaded pack when one is
// whole and fits, and the bundled one otherwise. While the app still carries
// a city's pack, a download is read only when its `pack.json` is the bundled
// one's, so an old download never stands in for newer data in the app.

/// The map packs downloaded apart from the app, shared by the task that
/// downloads them and the loaders that read them.
public enum MapPackDownloads {
    private final class Store: @unchecked Sendable {
        let lock = NSLock()
        var roots: [OverseasMap: URL] = [:]
        var statuses: [OverseasMap: MapPackStatus] = [:]
    }

    private static let store = Store()

    /// Why a downloaded folder was not taken.
    public enum Refusal: Error, Equatable, Sendable {
        /// Its `pack.json` is missing or out of shape.
        case noManifest
        /// Its `pack.json` is of another city.
        case otherCity(String)
        /// A file its `pack.json` lists is missing or not of the listed size.
        case incomplete(String)
        /// The app carries the city's pack, and the download is not the same.
        case differsFromBundled
    }

    /// Takes the pack downloaded to `root` for `city` when it is whole and
    /// fits (see ``check(_:root:bundled:)``), and says why not otherwise.
    /// A pack taken is read by ``MapPack/current(_:)`` from then on.
    @discardableResult
    public static func use(_ city: OverseasMap, root: URL) -> Refusal? {
        use(city, root: root, bundled: MapPack.bundled(city))
    }

    /// ``use(_:root:)`` against the bundled pack at `bundled` (`nil` for an
    /// app that carries none of the city).
    @discardableResult
    public static func use(_ city: OverseasMap, root: URL, bundled: MapPack?) -> Refusal? {
        if let refusal = check(city, root: root, bundled: bundled) { return refusal }
        store.lock.lock()
        defer { store.lock.unlock() }
        store.roots[city] = root
        return nil
    }

    /// Forgets the download of `city`; the bundled pack is read again.
    public static func forget(_ city: OverseasMap) {
        store.lock.lock()
        defer { store.lock.unlock() }
        store.roots[city] = nil
        store.statuses[city] = nil
    }

    /// Posted (on the thread that changed it) when a city's ``status(_:)``
    /// changes, for a screen that shows it.
    public static let statusChanged = Notification.Name("MapPackDownloads.statusChanged")

    /// How the download of `city`'s pack stands in this run of the app;
    /// ``MapPackStatus/bundled`` until the app says otherwise.
    public static func status(_ city: OverseasMap) -> MapPackStatus {
        store.lock.lock()
        defer { store.lock.unlock() }
        return store.statuses[city] ?? .bundled
    }

    /// Keeps how the download of `city`'s pack stands, as the app that
    /// downloads it found it.
    public static func note(_ city: OverseasMap, _ status: MapPackStatus) {
        store.lock.lock()
        let changed = (store.statuses[city] ?? .bundled) != status
        store.statuses[city] = status
        store.lock.unlock()
        if changed { NotificationCenter.default.post(name: statusChanged, object: nil) }
    }

    /// The downloads of `cities` in one line for a problem report, reasons
    /// and all ("mappack-hongkong used"); `nil` when there are none.
    public static func report(of cities: Set<OverseasMap> = OverseasMaps.open) -> String? {
        let parts = OverseasMap.allCases.filter(cities.contains).map { "\($0.assetPackID) \(status($0).reportText)" }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    /// The folder of the downloaded pack of `city` that was taken, if any.
    public static func root(_ city: OverseasMap) -> URL? {
        store.lock.lock()
        defer { store.lock.unlock() }
        return store.roots[city]
    }

    /// Whether the pack downloaded to `root` can be read for `city`: its
    /// `pack.json` names the city, every file it lists is there at the
    /// listed size, and, when the app carries a pack of the city at
    /// `bundled`, its `pack.json` is byte for byte the bundled one's.
    /// `nil` when it can.
    public static func check(_ city: OverseasMap, root: URL, bundled: MapPack?) -> Refusal? {
        let pack = MapPack(root: root)
        guard let data = try? pack.file("pack", "json"),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return .noManifest }
        guard manifest.id == city.packFolder else { return .otherCity(manifest.id) }
        for (name, entry) in manifest.files.sorted(by: { $0.key < $1.key }) {
            let path = root.appendingPathComponent(name).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
            guard size == entry.bytes else { return .incomplete(name) }
        }
        if let bundled, let carried = try? bundled.file("pack", "json"), carried != data {
            return .differsFromBundled
        }
        return nil
    }

    private struct Manifest: Decodable {
        struct Entry: Decodable {
            let bytes: Int64
        }

        let id: String
        let files: [String: Entry]
    }
}

/// Decision 776, later: how the download of a city's map pack stands, for
/// the settings' row and a problem report. The player is told only what
/// the game reads; why a download was not taken goes in the report.
public enum MapPackStatus: Equatable, Sendable {
    /// The app reads the pack it carries: it is not set up to download, or
    /// has not begun.
    case bundled
    /// The download was asked for and has not answered yet.
    case downloading
    /// The download was taken; the game reads it.
    case downloaded
    /// The download arrived and was not taken; the bundled pack is read.
    case refused(MapPackDownloads.Refusal)
    /// The download did not arrive (the error, described); the bundled
    /// pack is read.
    case failed(String)

    /// What the settings say of it, after the city's name.
    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .downloading: language.text("Downloading", "下載中")
        case .downloaded: language.text("Downloaded", "已下載")
        case .bundled, .refused, .failed: language.text("Built-in data", "使用內建資料")
        }
    }

    /// What a problem report says of it, in the words of the app's log.
    public var reportText: String {
        switch self {
        case .bundled: "bundled"
        case .downloading: "downloading"
        case .downloaded: "used"
        case let .refused(refusal): "not used: \(refusal)"
        case let .failed(error): "not fetched: \(error.prefix(200))"
        }
    }
}

extension OverseasMap {
    /// Decision 776, later: the name of the settings' row of the city's
    /// map pack ("Hong Kong Map").
    public func mapPackTitle(in language: DisplayLanguage) -> String {
        language.text("\(name(in: .english)) Map", "\(name(in: .traditionalChinese))地圖")
    }

    /// Decision 776: the ID of the city's asset pack on App Store Connect
    /// (`RailwayGameApp/AssetPacks/<folder>.json`'s `assetPackID`).
    public var assetPackID: String {
        "mappack-\(packFolder)"
    }

    /// Decision 776: where the city's `pack.json` lies in the downloaded
    /// assets (the asset pack holds `MapPacks/<folder>`, as the bundle does).
    public var assetPackManifestPath: String {
        "MapPacks/\(packFolder)/pack.json"
    }
}

extension MapPack {
    /// Decision 776: the pack the game reads for `city`: the downloaded one
    /// when ``MapPackDownloads`` took one, the bundled one otherwise.
    public static func current(_ city: OverseasMap) -> MapPack? {
        MapPackDownloads.root(city).map(MapPack.init(root:)) ?? bundled(city)
    }
}
