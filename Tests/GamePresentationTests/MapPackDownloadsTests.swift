import Foundation
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
        MapPackDownloads.forget(.hongKong)
        // The bundled one again (none in a test run, which has no app).
        XCTAssertEqual(MapPack.current(.hongKong)?.root, MapPack.bundled(.hongKong)?.root)
        XCTAssertNotEqual(MapPack.current(.hongKong)?.root, root)
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

    /// The asset pack's manifest holds the city's folder at the path the
    /// app asks for, under the ID the app asks for. Decision 789: an open
    /// city's; a city not open yet has none, so no release uploads its
    /// pack and no device fetches it before it can be played. Decision
    /// 818: Rovaniemi's is open.
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

    /// Decision 818: the app carries Hong Kong's pack and not Rovaniemi's,
    /// which only its asset pack brings: the app's project copies the one
    /// folder and leaves the other out.
    func testTheAppCarriesHongKongsPackAndNotRovaniemis() throws {
        let repository = BundledRealData.directory.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: repository.appendingPathComponent("RailwayGameApp/project.yml"), encoding: .utf8)
        XCTAssertTrue(project.contains("- path: Resources/MapPacks/hongkong\n        type: folder"))
        XCTAssertFalse(project.contains("- path: Resources/MapPacks\n"))
        XCTAssertFalse(project.contains("Resources/MapPacks/rovaniemi"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.appendingPathComponent("RailwayGameApp/AssetPacks/rovaniemi.json").path))
    }

    /// Decision 818: a city the app does not carry is "not downloaded" in
    /// the settings until its download is in, not "built-in data".
    func testACityTheAppDoesNotCarryIsNotDownloadedUntilItIs() {
        XCTAssertEqual(MapPackStatus.bundled.text(in: .traditionalChinese, carried: false), "尚未下載")
        XCTAssertEqual(MapPackStatus.failed("x").text(in: .english, carried: false), "Not downloaded")
        XCTAssertEqual(MapPackStatus.downloading.text(in: .traditionalChinese, carried: false), "下載中")
        XCTAssertEqual(MapPackStatus.downloaded.text(in: .english, carried: false), "Downloaded")
        XCTAssertEqual(MapPackStatus.bundled.text(in: .traditionalChinese), "使用內建資料")
        // A test run carries no app bundle, so neither city is carried here.
        XCTAssertNil(MapPack.bundled(.rovaniemi))
        XCTAssertFalse(OverseasMap.rovaniemi.isCarried)
        XCTAssertNil(MapPack.current(.rovaniemi))
    }

    /// Decision 818: the real-world data waits for a download only until it
    /// answers, or for at most the time it is given.
    func testWaitingForADownloadEndsWhenItAnswersOrTimesOut() {
        XCTAssertTrue(MapPackDownloads.waitForAnswers([], timeout: 5))
        var started = Date()
        XCTAssertFalse(MapPackDownloads.waitForAnswers([.rovaniemi], timeout: 0.2), "not begun")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.2)
        MapPackDownloads.note(.rovaniemi, .downloading)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            MapPackDownloads.note(.rovaniemi, .failed("no network"))
        }
        started = Date()
        XCTAssertTrue(MapPackDownloads.waitForAnswers([.rovaniemi], timeout: 10))
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertTrue(MapPackDownloads.waitForAnswers([.rovaniemi], timeout: 0), "answered already")
    }
}
