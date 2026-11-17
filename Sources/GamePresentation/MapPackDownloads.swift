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
        var packs: [OverseasMap: MapPack] = [:]
        var statuses: [OverseasMap: MapPackStatus] = [:]
        var clues: [OverseasMap: String] = [:]
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
        use(city, locators: [{ root.appendingPathComponent($0) }], bundled: bundled)
    }

    /// Decision 819: where a downloaded pack's file may lie, by its name in
    /// `pack.json` (`nil` when this way of looking finds no place for it).
    public typealias Locator = (String) -> URL?

    /// Takes the pack downloaded for `city` whose files lie where
    /// `locators` say: each file (`pack.json` first) is the first place
    /// they give, in order, that holds it at the listed size. Says why not
    /// otherwise, and keeps a ``clue(_:)`` of what was seen.
    @discardableResult
    public static func use(_ city: OverseasMap, locators: [Locator], bundled: MapPack?) -> Refusal? {
        let found = inspect(city, locators: locators, bundled: bundled)
        store.lock.lock()
        defer { store.lock.unlock() }
        switch found {
        case let .success(pack):
            store.packs[city] = pack
            store.clues[city] = nil
            return nil
        case let .failure(refused):
            store.clues[city] = refused.clue
            return refused.refusal
        }
    }

    /// Forgets the download of `city`; the bundled pack is read again.
    public static func forget(_ city: OverseasMap) {
        store.lock.lock()
        defer { store.lock.unlock() }
        store.packs[city] = nil
        store.statuses[city] = nil
        store.clues[city] = nil
    }

    /// Decision 819: what was seen of the last download of `city` that was
    /// not taken (where its `pack.json` lay, how many of its files were
    /// found and by which locator), for a problem report; `nil` after one
    /// was taken.
    public static func clue(_ city: OverseasMap) -> String? {
        store.lock.lock()
        defer { store.lock.unlock() }
        return store.clues[city]
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
        let parts = OverseasMap.allCases.filter(cities.contains).map { city -> String in
            let line = "\(city.assetPackID) \(status(city).reportText)"
            guard case .refused = status(city), let clue = clue(city) else { return line }
            return "\(line) (\(clue))"
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    /// The folder of the downloaded pack of `city` that was taken, if any.
    public static func root(_ city: OverseasMap) -> URL? {
        pack(city)?.root
    }

    /// The downloaded pack of `city` that was taken, if any.
    public static func pack(_ city: OverseasMap) -> MapPack? {
        store.lock.lock()
        defer { store.lock.unlock() }
        return store.packs[city]
    }

    /// Whether the pack downloaded to `root` can be read for `city`: its
    /// `pack.json` names the city, every file it lists is there at the
    /// listed size, and, when the app carries a pack of the city at
    /// `bundled`, its `pack.json` is byte for byte the bundled one's.
    /// `nil` when it can.
    public static func check(_ city: OverseasMap, root: URL, bundled: MapPack?) -> Refusal? {
        if case let .failure(refused) = inspect(city, locators: [{ root.appendingPathComponent($0) }], bundled: bundled) {
            return refused.refusal
        }
        return nil
    }

    private struct Refused: Error {
        let refusal: Refusal
        let clue: String
    }

    /// ``check(_:root:bundled:)`` with each file looked for by `locators`
    /// in turn: the pack it would read, or why not with what was seen.
    private static func inspect(_ city: OverseasMap, locators: [Locator], bundled: MapPack?) -> Result<MapPack, Refused> {
        func size(_ url: URL) -> Int64? {
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        }
        // `pack.json`: the first place that holds one.
        var manifestURL: URL?
        var data: Data?
        for locate in locators {
            guard let url = locate("pack.json"), let read = try? Data(contentsOf: url) else { continue }
            manifestURL = url
            data = read
            break
        }
        guard let manifestURL, let data, let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            let tried = locators.compactMap { $0("pack.json") }.map(shortened)
            return .failure(Refused(refusal: .noManifest, clue: "pack.json looked for at \(tried.isEmpty ? "nowhere" : tried.joined(separator: ", "))"))
        }
        // The folder as a folder is named when handed over ("…/hongkong", no
        // closing slash), so a pack read from it is the one it was given.
        let root = URL(fileURLWithPath: manifestURL.deletingLastPathComponent().path, isDirectory: false)
        guard manifest.id == city.packFolder else {
            return .failure(Refused(refusal: .otherCity(manifest.id), clue: "pack.json in \(describe(root))"))
        }
        // Every file it lists: the first place that holds it at its size.
        var files: [String: URL] = [:]
        var byLocator = Array(repeating: 0, count: locators.count)
        var missing: String?
        for (name, entry) in manifest.files.sorted(by: { $0.key < $1.key }) {
            guard let hit = locators.indices.lazy.compactMap({ index in
                locators[index](name).flatMap { size($0) == entry.bytes ? (index: index, url: $0) : nil }
            }).first else {
                if missing == nil { missing = name }
                continue
            }
            byLocator[hit.index] += 1
            if hit.url != root.appendingPathComponent(name) { files[name] = hit.url }
        }
        if let missing {
            let found = byLocator.reduce(0, +)
            let split = locators.count > 1 ? " (\(byLocator.map(String.init).joined(separator: ", ")) by locator)" : ""
            let tried = locators.compactMap { $0(missing) }.map { url in "\(shortened(url)) \(size(url).map { "\($0) B" } ?? "absent")" }
            return .failure(Refused(
                refusal: .incomplete(missing),
                clue: "found \(found) of \(manifest.files.count) files\(split); pack.json in \(describe(root)); \(missing) listed \(manifest.files[missing]?.bytes ?? 0) B, at \(tried.isEmpty ? "nowhere" : tried.joined(separator: ", "))"
            ))
        }
        if let bundled, let carried = try? bundled.file("pack", "json"), carried != data {
            return .failure(Refused(refusal: .differsFromBundled, clue: "pack.json in \(describe(root)), \(data.count) B; the app's \(carried.count) B"))
        }
        return .success(MapPack(root: root, files: files))
    }

    /// The last three parts of `url`'s path ("…/MapPacks/hongkong/pack.json"),
    /// enough to tell one place from another without the device's folders.
    private static func shortened(_ url: URL) -> String {
        let parts = url.standardizedFileURL.pathComponents.filter { $0 != "/" }
        return (parts.count > 3 ? "…/" : "/") + parts.suffix(3).joined(separator: "/")
    }

    /// `folder` shortened, with how many items it holds.
    private static func describe(_ folder: URL) -> String {
        let count = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.count
        let items = count.map { $0 == 1 ? "1 item" : "\($0) items" } ?? "unreadable"
        return "\(shortened(folder)) (\(items))"
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
        "\(assetPackFolderPath)/pack.json"
    }

    /// Decision 819: the city's folder in the downloaded assets; each file
    /// of its pack is asked for as `<this>/<its name in pack.json>`.
    public var assetPackFolderPath: String {
        "MapPacks/\(packFolder)"
    }
}

extension MapPack {
    /// Decision 776: the pack the game reads for `city`: the downloaded one
    /// when ``MapPackDownloads`` took one, the bundled one otherwise.
    public static func current(_ city: OverseasMap) -> MapPack? {
        MapPackDownloads.pack(city) ?? bundled(city)
    }
}
