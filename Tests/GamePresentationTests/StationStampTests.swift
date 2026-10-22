import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The station stamps (decision 348): which real station a served station
/// of the game is, the record kept on the device, and the passport's pages
/// and layout ported from the reference (`Ci` `voyager-passport.js`).
final class StationStampTests: XCTestCase {
    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent(StationStampRecords.fileName)
    }

    // MARK: - The passport (the reference's layout)

    /// The reference's `stampLayout` on the same IDs, run in Node: the
    /// port places every stamp where the website does.
    func testTheLayoutIsTheReferences() {
        let expected: [[Double]] = [
            [74.40876366019279, 41.31811328845766, 28.312918872805312, -0.18426169082522392],
            [37.09359478688901, 58.47825295219762, 30.7598429529462, 7.120918780565262],
            [39.395048116766766, 29.39486142898599, 31.91781249199994, 2.904081951826811],
        ]
        let layout = StationStampPassport.layout(["台北", "板橋", "猴硐"])
        XCTAssertEqual(layout.count, 3)
        for (placement, values) in zip(layout, expected) {
            XCTAssertEqual(placement.x, values[0], accuracy: 1e-9)
            XCTAssertEqual(placement.y, values[1], accuracy: 1e-9)
            XCTAssertEqual(placement.width, values[2], accuracy: 1e-9)
            XCTAssertEqual(placement.angle, values[3], accuracy: 1e-9)
        }
        // A full page of eight shrinks the stamps until they all fit.
        let full = StationStampPassport.layout(["a", "b", "c", "d", "e", "f", "g", "h"])
        XCTAssertEqual(full.count, 8)
        XCTAssertEqual(full[0].x, 74.44284980830287, accuracy: 1e-9)
        XCTAssertEqual(full[7].width, 25.89626036078437, accuracy: 1e-9)
        XCTAssertEqual(full[4].angle, -11.215089269913733, accuracy: 1e-9)
    }

    /// No two stamps of a page overlap, and each lies on the page.
    func testAPageOfStampsDoesNotOverlap() {
        let ids = (1...8).map { "station-\($0)" }
        let layout = StationStampPassport.layout(ids)
        XCTAssertEqual(layout, StationStampPassport.layout(ids), "The same stamps lie in the same places every time")
        for (index, a) in layout.enumerated() {
            XCTAssertGreaterThanOrEqual(a.x - a.halfWidth, 3 - 1e-9)
            XCTAssertLessThanOrEqual(a.x + a.halfWidth, 97 + 1e-9)
            XCTAssertGreaterThanOrEqual(a.y - a.halfHeight, 13 - 1e-9)
            XCTAssertLessThanOrEqual(a.y + a.halfHeight, 88 + 1e-9)
            XCTAssertLessThanOrEqual(abs(a.angle), 14)
            for b in layout[(index + 1)...] {
                XCTAssertTrue(
                    abs(a.x - b.x) > a.halfWidth + b.halfWidth || abs(a.y - b.y) > a.halfHeight + b.halfHeight,
                    "\(a) and \(b) overlap"
                )
            }
        }
        XCTAssertEqual(StationStampPassport.layout([]), [])
    }

    func testThePagesHoldEightStampsEach() {
        let stamps = (0..<19).map { index in
            StationStamp(key: "s\(index)", chinese: "站\(index)", english: nil, system: "tra_sched", earned: Date(timeIntervalSince1970: Double(index)))
        }
        let pages = StationStampPassport.pages(stamps)
        XCTAssertEqual(pages.map(\.count), [8, 8, 3])
        XCTAssertEqual(pages[1].first?.key, "s8")
        XCTAssertEqual(StationStampPassport.pages([]), [])
    }

    /// The date under a stamp, as the reference writes it (`2026.10.22`),
    /// in Taiwan time.
    func testTheDateUnderAStampIsTaiwans() {
        // 2026-10-21 17:30 UTC is 01:30 on the 22nd in Taiwan.
        let date = Date(timeIntervalSince1970: 1_792_603_800)
        XCTAssertEqual(StationStampPassport.dateLabel(date), "2026.10.22")
    }

    // MARK: - Which real station

    func testAServedStationNamedAsARealOneIsItsStamp() throws {
        let railways = try BundledRealData.railways()
        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        var world = GameWorld.newGame(anchor: try XCTUnwrap(tra.anchor))
        let taipei = try BundledRealData.point(tra.coordinate, in: world)
        let real = try world.buildStation(named: "台北車站", at: taipei)
        let numbered = try world.buildStation(named: "車站 2", at: PlanPoint(x: taipei.x + 2_000, y: taipei.y))

        let stations = StationStamps.realStations(of: [real, numbered], in: world, railways: railways)
        XCTAssertEqual(stations.map(\.key), ["台北"], "One stamp for the place, however many systems call it so")
        XCTAssertEqual(stations.first?.system, "tra_sched", "The first system in the site's order")
        XCTAssertEqual(stations.first?.chinese, "臺北")
        XCTAssertEqual(stations.first?.english, "Taipei")
    }

    /// The same name far from the real station is another place; a map
    /// that is not a real one has no real stations.
    func testTheSameNameElsewhereIsNoStamp() throws {
        let railways = try BundledRealData.railways()
        let houtong = try BundledRealData.station("猴硐", in: "tra_sched")
        var world = GameWorld.newGame(anchor: try XCTUnwrap(houtong.anchor))
        let far = try world.buildStation(named: "台北", at: try BundledRealData.point(houtong.coordinate, in: world))
        XCTAssertEqual(StationStamps.realStations(of: [far], in: world, railways: railways), [])

        var blank = GameWorld.newGame()
        let station = try blank.buildStation(named: "猴硐", at: PlanPoint(x: 1_000, y: 1_000))
        XCTAssertEqual(StationStamps.realStations(of: [station], in: blank, railways: railways), [])
    }

    func testTheCollectionCountsEachRealPlaceOnce() throws {
        let railways = try BundledRealData.railways()
        let total = StationStamps.total(in: railways)
        XCTAssertGreaterThan(total, 300, "TRA alone has more than 200 stations")
        XCTAssertLessThan(total, railways.stations.count, "台北 of TRA, THSR and the metro is one stamp")
    }

    func testEachSystemHasItsInk() {
        XCTAssertEqual(StationStampInk(system: "tra_sched"), .navy)
        XCTAssertEqual(StationStampInk(system: "thsr_sched"), .amber)
        XCTAssertEqual(StationStampInk(system: "afr_sched"), .red)
        XCTAssertEqual(StationStampInk(system: "ntdlrt"), .red)
        XCTAssertEqual(StationStampInk(system: "mrt"), .teal)
        XCTAssertEqual(StationStampInk(system: "krtc"), .teal)
    }

    // MARK: - The record

    func testCollectingKeepsEachStampOnceAndWritesTheFile() throws {
        let file = try temporaryFile()
        var records = StationStampRecords(file: file)
        XCTAssertEqual(records.count, 0)
        let day = Date(timeIntervalSince1970: 1_792_603_800)
        let taipei = StationStamps.RealStation(key: "台北", chinese: "臺北", english: "Taipei", system: "tra_sched")
        let houtong = StationStamps.RealStation(key: "猴硐", chinese: "猴硐", english: "Houtong", system: "tra_sched")
        XCTAssertEqual(records.collect([taipei, houtong], at: day).map(\.key), ["台北", "猴硐"])
        XCTAssertEqual(records.collect([taipei], at: day.addingTimeInterval(86_400)), [], "Already in the passport")
        XCTAssertTrue(records.contains("台北"))

        let read = StationStampRecords(file: file)
        XCTAssertEqual(read.stamps.map(\.key), ["台北", "猴硐"])
        XCTAssertEqual(read.stamps.first?.earned, day)
        XCTAssertEqual(read.stamps.first?.name(in: .english), "Taipei")
        XCTAssertEqual(read.stamps.first?.name(in: .traditionalChinese), "臺北")
    }

    /// As the achievements: a stamp collected in another launch is kept,
    /// and a file of a newer version is never written over.
    func testCollectingAddsToWhatTheFileHolds() throws {
        let file = try temporaryFile()
        var first = StationStampRecords(file: file)
        var second = StationStampRecords(file: file)
        let day = Date(timeIntervalSince1970: 1_792_603_800)
        _ = first.collect([StationStamps.RealStation(key: "台北", chinese: "臺北", english: "Taipei", system: "tra_sched")], at: day)
        _ = second.collect([StationStamps.RealStation(key: "左營", chinese: "左營", english: "Zuoying", system: "thsr_sched")], at: day)
        XCTAssertEqual(Set(StationStampRecords(file: file).stamps.map(\.key)), ["台北", "左營"])

        let newer = Data(#"{"version":99,"stamps":[]}"#.utf8)
        try newer.write(to: file)
        var records = StationStampRecords(file: file)
        XCTAssertEqual(records.count, 0)
        _ = records.collect([StationStamps.RealStation(key: "猴硐", chinese: "猴硐", english: nil, system: "tra_sched")], at: day)
        XCTAssertEqual(try Data(contentsOf: file), newer, "A newer app's file is left alone")
    }

    func testTheSummarySaysHowManyOfHowMany() {
        XCTAssertEqual(StationStampPassport.summary(count: 3, total: 412, in: .traditionalChinese), "車站紀念章 3/412")
        XCTAssertEqual(StationStampPassport.summary(count: 3, total: nil, in: .english), "Station stamps 3")
    }
}
