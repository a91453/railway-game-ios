import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 776: a map pack downloaded apart from the app is read only when
/// it is whole, of the right city and, while the app still carries the
/// city's pack, the same as the bundled one.
final class MapPackDownloadsTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() {
        MapPackDownloads.forget(.hongKong)
        MapPackDownloads.forget(.rovaniemi)
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        super.tearDown()
    }

    private var bundled: MapPack {
        get throws { try XCTUnwrap(HongKongRailwaysTests.pack(.hongKong)) }
    }

    /// A copy of the bundled Hong Kong pack in a folder of its own, as the
    /// download leaves it.
    private func downloaded() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mappack-\(UUID().uuidString)").appendingPathComponent("hongkong")
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        folders.append(folder.deletingLastPathComponent())
        try FileManager.default.copyItem(at: try bundled.root, to: folder)
        return folder
    }

    func testAWholeDownloadIsReadInsteadOfTheBundledPack() throws {
        let root = try downloaded()
        XCTAssertNil(MapPackDownloads.use(.hongKong, root: root, bundled: try bundled))
        XCTAssertEqual(MapPack.current(.hongKong)?.root, root)
        // It is read as the bundled one is.
        XCTAssertEqual(try MapPack.current(.hongKong)?.extent(), try bundled.extent())
        XCTAssertNotNil(MapPack.current(.hongKong)?.baseMapFile)
        // Decision 858: forgotten, the app's own is read again, and the
        // tests' process, like the app people install, carries none.
        MapPackDownloads.forget(.hongKong)
        XCTAssertNil(MapPack.bundled(.hongKong))
        XCTAssertNil(MapPack.current(.hongKong))
    }

    /// Decision 819 (MAPPACK-FIX): an Apple-hosted asset pack hands out a
    /// URL per file (`AssetPackManager.url(for:)`); the folder of the one
    /// it gave for `pack.json` need not hold the rest. On the owner's
    /// iPhone (0.6.0 (136)) that folder held `pack.json` alone, and the
    /// pack was refused at the first file it lists. Each file is looked
    /// for in turn until one is found at its listed size.
    func testAPackWhoseFilesLieApartFromItsManifestIsRead() throws {
        let whole = try downloaded()
        let names = try FileManager.default.contentsOfDirectory(atPath: whole.path).sorted()
        // `pack.json` alone in a folder, as the device had it.
        let manifestOnly = whole.deletingLastPathComponent().appendingPathComponent("manifest-only").appendingPathComponent("hongkong")
        try FileManager.default.createDirectory(at: manifestOnly, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: whole.appendingPathComponent("pack.json"), to: manifestOnly.appendingPathComponent("pack.json"))
        // Every other file in a folder of its own.
        var apart: [String: URL] = [:]
        for name in names where name != "pack.json" {
            let folder = whole.deletingLastPathComponent().appendingPathComponent("apart-\(name)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: whole.appendingPathComponent(name), to: folder.appendingPathComponent(name))
            apart[name] = folder.appendingPathComponent(name)
        }
        try FileManager.default.removeItem(at: whole)

        // Read from the manifest's folder alone, it is the device's refusal.
        XCTAssertEqual(MapPackDownloads.use(.hongKong, root: manifestOnly, bundled: try bundled), .incomplete("airfields.json"))
        XCTAssertNil(MapPackDownloads.root(.hongKong))
        let clue = try XCTUnwrap(MapPackDownloads.clue(.hongKong))
        XCTAssertTrue(clue.contains("found 0 of 16 files"), clue)
        XCTAssertTrue(clue.contains("manifest-only/hongkong (1 item)"), clue)

        // Looked for one by one, it is taken, and read from where each lies.
        let locators: [MapPackDownloads.Locator] = [
            { manifestOnly.appendingPathComponent($0) },
            { apart[$0] },
        ]
        XCTAssertNil(MapPackDownloads.use(.hongKong, locators: locators, bundled: try bundled))
        XCTAssertNil(MapPackDownloads.clue(.hongKong))
        let pack = try XCTUnwrap(MapPack.current(.hongKong))
        XCTAssertEqual(pack.root, manifestOnly)
        XCTAssertEqual(pack.baseMapFile, apart["basemap.pmtiles"])
        XCTAssertEqual(pack.buildingsFile, apart["buildings.pmtiles"])
        XCTAssertEqual(pack.terrainFile, apart["terrain.pmtiles"])
        XCTAssertEqual(try pack.extent(), try bundled.extent())
        XCTAssertNotNil(pack.airfields())
        XCTAssertEqual(try pack.file("hkmtr", "json"), try bundled.file("hkmtr", "json"))

        // A file no locator finds is named, with what each one found.
        apart["water.json"] = nil
        XCTAssertEqual(MapPackDownloads.use(.hongKong, locators: locators, bundled: try bundled), .incomplete("water.json"))
        let missing = try XCTUnwrap(MapPackDownloads.clue(.hongKong))
        XCTAssertTrue(missing.contains("found 15 of 16 files (0, 15 by locator)"), missing)
    }

    /// REVIEW-L27 P3-1 (MAP-PACK-ONCE): the open cities' packs are asked
    /// at every read, and ``MapPackDownloads/changes`` moves when a
    /// download is taken or forgotten, so what the app keeps (the
    /// airfields) is read again from a pack downloaded after the first
    /// read; a refused download or forgetting none leaves it as it was.
    func testTheOpenCitiesPacksFollowADownloadTakenAfterTheFirstRead() throws {
        let first = MapPack.currentOpen()
        XCTAssertEqual(first.map(\.root).first { $0.lastPathComponent == "hongkong" }, MapPack.bundled(.hongKong)?.root)
        let before = MapPackDownloads.changes

        let root = try downloaded()
        XCTAssertNil(MapPackDownloads.use(.hongKong, root: root, bundled: try bundled))
        XCTAssertEqual(MapPackDownloads.changes, before + 1)
        XCTAssertTrue(MapPack.currentOpen().contains { $0.root == root })
        XCTAssertEqual(MapPack.currentOpen().count, first.count + 1, "the tests' process carries no pack (decision 858)")

        let cut = try downloaded()
        try FileManager.default.removeItem(at: cut.appendingPathComponent("pack.json"))
        XCTAssertEqual(MapPackDownloads.use(.hongKong, root: cut, bundled: try bundled), .noManifest)
        XCTAssertEqual(MapPackDownloads.changes, before + 1)

        MapPackDownloads.forget(.hongKong)
        XCTAssertEqual(MapPackDownloads.changes, before + 2)
        XCTAssertFalse(MapPack.currentOpen().contains { $0.root == root })
        MapPackDownloads.forget(.hongKong)
        XCTAssertEqual(MapPackDownloads.changes, before + 2)
    }

    func testTheBundledPackIsReadWithoutADownload() {
        XCTAssertNil(MapPackDownloads.root(.hongKong))
        XCTAssertEqual(MapPack.current(.hongKong)?.root, MapPack.bundled(.hongKong)?.root)
    }

    func testEveryFileThePackListsMustBeThereAtItsSize() throws {
        let root = try downloaded()
        try FileManager.default.removeItem(at: root.appendingPathComponent("buildings.pmtiles"))
        XCTAssertEqual(MapPackDownloads.use(.hongKong, root: root, bundled: try bundled), .incomplete("buildings.pmtiles"))
        XCTAssertNil(MapPackDownloads.root(.hongKong))

        let cut = try downloaded()
        let file = cut.appendingPathComponent("hkmtr.json")
        try Data(try Data(contentsOf: file).dropLast()).write(to: file)
        XCTAssertEqual(MapPackDownloads.check(.hongKong, root: cut, bundled: nil), .incomplete("hkmtr.json"))
    }

    func testAFolderWithoutAPackOrOfAnotherCityIsRefused() throws {
        let root = try downloaded()
        let manifest = root.appendingPathComponent("pack.json")
        let text = try String(contentsOf: manifest, encoding: .utf8)
        try text.replacingOccurrences(of: #""id":"hongkong""#, with: #""id":"kinmen""#).write(to: manifest, atomically: true, encoding: .utf8)
        XCTAssertEqual(MapPackDownloads.check(.hongKong, root: root, bundled: nil), .otherCity("kinmen"))
        try FileManager.default.removeItem(at: manifest)
        XCTAssertEqual(MapPackDownloads.check(.hongKong, root: root, bundled: nil), .noManifest)
    }

    /// While the app carries the city, an older or newer download than the
    /// app's is not read; once the app no longer carries it, a whole
    /// download is.
    func testADownloadUnlikeTheBundledPackIsReadOnlyWhenTheAppHasNone() throws {
        let root = try downloaded()
        let manifest = root.appendingPathComponent("pack.json")
        var text = try String(contentsOf: manifest, encoding: .utf8)
        text = text.replacingOccurrences(of: #""english":"Hong Kong""#, with: #""english":"Hong Kong ""#)
        try text.write(to: manifest, atomically: true, encoding: .utf8)
        XCTAssertEqual(MapPackDownloads.use(.hongKong, root: root, bundled: try bundled), .differsFromBundled)
        XCTAssertNil(MapPackDownloads.root(.hongKong))
        XCTAssertNil(MapPackDownloads.use(.hongKong, root: root, bundled: nil))
        XCTAssertEqual(MapPackDownloads.root(.hongKong), root)
    }

    // MARK: - Decision 858: the app carries pack.json alone

    /// A folder with a pack's `pack.json` and none of its files, as the
    /// app people install carries each city, is not a pack to read; with
    /// every file it lists it is.
    func testAFolderWithItsPackJSONAloneIsNotAPack() throws {
        let whole = try downloaded()
        XCTAssertTrue(MapPack.isWhole(whole))
        let alone = whole.deletingLastPathComponent().appendingPathComponent("alone")
        try FileManager.default.createDirectory(at: alone, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: whole.appendingPathComponent("pack.json"), to: alone.appendingPathComponent("pack.json"))
        XCTAssertFalse(MapPack.isWhole(alone))
        try FileManager.default.removeItem(at: whole.appendingPathComponent("water.json"))
        XCTAssertFalse(MapPack.isWhole(whole))
        XCTAssertFalse(MapPack.isWhole(whole.appendingPathComponent("nowhere")))
    }

    /// The download is held against the app's own copy of `pack.json`
    /// (`expected`), which the app carries without the pack's files: the
    /// same is taken; another version is refused, and taken only when
    /// asked for with no `pack.json` to hold it against (the listed one
    /// did not come, and the app has no pack of its own to read).
    func testADownloadIsHeldAgainstTheAppsPackJSON() throws {
        let expected = try bundled.file("pack", "json")
        let root = try downloaded()
        let locators: [MapPackDownloads.Locator] = [{ root.appendingPathComponent($0) }]
        XCTAssertNil(MapPackDownloads.use(.hongKong, locators: locators, expected: expected))
        XCTAssertEqual(MapPackDownloads.root(.hongKong), root)
        MapPackDownloads.forget(.hongKong)

        let manifest = root.appendingPathComponent("pack.json")
        var text = try String(contentsOf: manifest, encoding: .utf8)
        text = text.replacingOccurrences(of: #""english":"Hong Kong""#, with: #""english":"Hong Kong ""#)
        try text.write(to: manifest, atomically: true, encoding: .utf8)
        XCTAssertEqual(MapPackDownloads.use(.hongKong, locators: locators, expected: expected), .differsFromBundled)
        XCTAssertNil(MapPack.current(.hongKong))
        XCTAssertNil(MapPackDownloads.use(.hongKong, locators: locators, expected: nil))
        XCTAssertEqual(MapPack.current(.hongKong)?.root, root)
    }

    /// Where a city's map lies is known from its `pack.json` alone, and is
    /// where its ground lies once its pack is read.
    func testACitysPlaceIsKnownFromItsPackJSON() throws {
        for city in OverseasMap.allCases where OverseasMaps.open.contains(city) {
            let pack = try XCTUnwrap(HongKongRailwaysTests.pack(city))
            let place = try XCTUnwrap(OverseasPlace(city: city, manifest: try pack.file("pack", "json")))
            let ground = try OverseasGround(city: city, pack: pack)
            XCTAssertEqual(place.anchor, ground.anchor)
            XCTAssertEqual(place.bounds, ground.bounds)
            XCTAssertTrue(place.holds(GameWorld.newOverseasGame(ground)))
            XCTAssertFalse(place.holds(GameWorld.newWholeTaiwanGame()))
        }
        XCTAssertNil(OverseasPlace(city: .hongKong, manifest: Data("{}".utf8)))
    }

    /// The real-world data waits for the downloads' answers, and no longer
    /// than it is told to.
    func testTheReadWaitsForTheDownloadsAnswers() {
        XCTAssertTrue(MapPackDownloads.waitForAnswers([], timeout: 0))
        let began = Date()
        XCTAssertFalse(MapPackDownloads.waitForAnswers([.hongKong], timeout: 0.2), "not begun is not answered")
        XCTAssertLessThan(Date().timeIntervalSince(began), 2)
        MapPackDownloads.note(.hongKong, .downloading)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { MapPackDownloads.note(.hongKong, .failed("offline")) }
        XCTAssertTrue(MapPackDownloads.waitForAnswers([.hongKong], timeout: 5))
        XCTAssertLessThan(Date().timeIntervalSince(began), 3)
        for answered in [MapPackStatus.downloaded, .earlier, .refused(.noManifest)] {
            MapPackDownloads.note(.hongKong, answered)
            XCTAssertTrue(MapPackDownloads.waitForAnswers([.hongKong], timeout: 0))
        }
    }

    /// A pack taken after the data was read is unread until the next read.
    func testAPackTakenAfterTheReadIsUnread() throws {
        MapPackDownloads.noteRead()
        XCTAssertFalse(MapPackDownloads.hasUnread)
        XCTAssertNil(MapPackDownloads.use(.hongKong, root: try downloaded(), bundled: nil))
        XCTAssertTrue(MapPackDownloads.hasUnread)
        MapPackDownloads.noteRead()
        XCTAssertFalse(MapPackDownloads.hasUnread)
    }

    /// What the settings say of a city the app does not carry, and of one
    /// read from a version the app does not list.
    func testTheSettingsSayNotDownloadedOfACityTheAppDoesNotCarry() {
        XCTAssertFalse(OverseasMap.hongKong.isCarried, "the tests' process carries no pack")
        for status in [MapPackStatus.bundled, .failed("no network"), .refused(.noManifest)] {
            XCTAssertEqual(status.text(in: .english, carried: false), "Not downloaded")
            XCTAssertEqual(status.text(in: .traditionalChinese, carried: false), "尚未下載")
        }
        XCTAssertEqual(MapPackStatus.downloading.text(in: .traditionalChinese, carried: false), "下載中")
        XCTAssertEqual(MapPackStatus.earlier.text(in: .traditionalChinese, carried: false), "已下載")
        XCTAssertEqual(MapPackStatus.earlier.reportText, "used: not the version the app lists")
    }

    /// The asset pack's manifest holds the city's folder at the path the
    /// app asks for, under the ID the app asks for. Decision 789: an open
    /// city's; a city not open yet has none, so no release uploads its
    /// pack and no device fetches it before it can be played. Decision
    /// 818: Rovaniemi's is open, so it has one (the app still carries its
    /// pack, as Hong Kong's).
    func testTheAssetPackManifestMatchesWhatTheAppAsksFor() throws {
        let repository = BundledRealData.directory.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for city in OverseasMap.allCases where !OverseasMaps.open.contains(city) {
            XCTAssertFalse(FileManager.default.fileExists(atPath: repository.appendingPathComponent("RailwayGameApp/AssetPacks/\(city.packFolder).json").path), city.packFolder)
        }
        for city in OverseasMap.allCases where OverseasMaps.open.contains(city) {
            let file = repository.appendingPathComponent("RailwayGameApp/AssetPacks/\(city.packFolder).json")
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            XCTAssertEqual(object["assetPackID"] as? String, city.assetPackID)
            let selectors = try XCTUnwrap(object["fileSelectors"] as? [[String: String]])
            XCTAssertEqual(selectors, [["directory": "MapPacks/\(city.packFolder)"]])
            XCTAssertEqual(city.assetPackManifestPath, "MapPacks/\(city.packFolder)/pack.json")
            let policy = try XCTUnwrap(object["downloadPolicy"] as? [String: Any])
            XCTAssertEqual(Array(policy.keys), ["prefetch"])
        }
    }

    /// Decision 776, later: the app keeps how each download stands; the
    /// settings say only what the game reads, a problem report says why.
    func testTheStatusOfADownloadIsKeptAndToldInTwoWays() {
        XCTAssertEqual(MapPackDownloads.status(.hongKong), .bundled)
        XCTAssertEqual(OverseasMap.hongKong.mapPackTitle(in: .english), "Hong Kong Map")
        XCTAssertEqual(OverseasMap.hongKong.mapPackTitle(in: .traditionalChinese), "香港地圖")
        XCTAssertEqual(MapPackDownloads.report(of: [.hongKong]), "mappack-hongkong bundled")
        XCTAssertNil(MapPackDownloads.report(of: []))

        let heard = expectation(forNotification: MapPackDownloads.statusChanged, object: nil)
        MapPackDownloads.note(.hongKong, .downloading)
        wait(for: [heard], timeout: 1)
        XCTAssertEqual(MapPackDownloads.status(.hongKong), .downloading)

        let told: [(MapPackStatus, String, String, String)] = [
            (.bundled, "Built-in data", "使用內建資料", "bundled"),
            (.downloading, "Downloading", "下載中", "downloading"),
            (.downloaded, "Downloaded", "已下載", "used"),
            (.refused(.incomplete("basemap.pmtiles")), "Built-in data", "使用內建資料", #"not used: incomplete("basemap.pmtiles")"#),
            (.refused(.differsFromBundled), "Built-in data", "使用內建資料", "not used: differsFromBundled"),
            (.failed("no network"), "Built-in data", "使用內建資料", "not fetched: no network"),
        ]
        for (status, english, chinese, report) in told {
            MapPackDownloads.note(.hongKong, status)
            XCTAssertEqual(MapPackDownloads.status(.hongKong), status)
            XCTAssertEqual(status.text(in: .english), english)
            XCTAssertEqual(status.text(in: .traditionalChinese), chinese)
            XCTAssertEqual(MapPackDownloads.report(of: [.hongKong]), "mappack-hongkong \(report)")
        }
        // A long error is cut, not carried whole.
        XCTAssertEqual(MapPackStatus.failed(String(repeating: "x", count: 500)).reportText.count, "not fetched: ".count + 200)
        // The open cities are what a report lists unasked.
        XCTAssertEqual(MapPackDownloads.report(), "mappack-hongkong not fetched: no network; mappack-rovaniemi bundled")

        MapPackDownloads.forget(.hongKong)
        XCTAssertEqual(MapPackDownloads.status(.hongKong), .bundled)
    }
}
