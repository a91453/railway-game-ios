import Foundation
@testable import GamePresentation
import XCTest

/// Decision 884: the station master's part in the winter event: the
/// Christmas hat while the decorations show, and each week's mission told
/// once.
final class WinterStationMasterTests: XCTestCase {
    private let calendar = WinterEvent.calendar(in: TimeZone(identifier: "Asia/Taipei")!)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testHatOnlyDuringTheEventWithDecorations() {
        XCTAssertEqual(WinterStationMaster.outfit(at: date(2026, 11, 30), switchedOn: true, calendar: calendar), "")
        XCTAssertEqual(WinterStationMaster.outfit(at: date(2026, 12, 1), switchedOn: true, calendar: calendar), "Christmas")
        XCTAssertEqual(WinterStationMaster.outfit(at: date(2027, 1, 6), switchedOn: true, calendar: calendar), "Christmas")
        XCTAssertEqual(WinterStationMaster.outfit(at: date(2027, 1, 7), switchedOn: true, calendar: calendar), "")
        XCTAssertEqual(WinterStationMaster.outfit(at: date(2026, 12, 24), switchedOn: false, calendar: calendar), "")
    }

    func testEachWeekToldOnce() throws {
        XCTAssertNil(WinterStationMaster.announcement(at: date(2026, 11, 30), told: nil, calendar: calendar))
        let first = try XCTUnwrap(WinterStationMaster.announcement(at: date(2026, 12, 1), told: nil, calendar: calendar))
        XCTAssertEqual(first.key, "2026.1")
        XCTAssertEqual(first.beat.speaker, .stationMaster)
        XCTAssertEqual(first.beat.moment, .winterWeek(season: 2026, week: 1))
        XCTAssertTrue(first.beat.text(in: .traditionalChinese).hasPrefix("冬季活動開始了！第 1 週的任務是「點燈週」"))
        // Told: not again that week, but the next week's is.
        XCTAssertNil(WinterStationMaster.announcement(at: date(2026, 12, 7), told: first.key, calendar: calendar))
        let second = try XCTUnwrap(WinterStationMaster.announcement(at: date(2026, 12, 8), told: first.key, calendar: calendar))
        XCTAssertEqual(second.key, "2026.2")
        XCTAssertFalse(second.beat.text(in: .english).contains("has begun"))
        // A week missed is skipped: only the current week's is told.
        XCTAssertEqual(WinterStationMaster.announcement(at: date(2026, 12, 22), told: first.key, calendar: calendar)?.key, "2026.4")
        // Week 5 runs into January; nothing to tell on the last days.
        XCTAssertEqual(WinterStationMaster.announcement(at: date(2027, 1, 2), told: nil, calendar: calendar)?.key, "2026.5")
        XCTAssertNil(WinterStationMaster.announcement(at: date(2027, 1, 6), told: nil, calendar: calendar))
    }

    func testSantaWeekOnRovaniemiAsksForTheVillage() throws {
        let beat = try XCTUnwrap(WinterStationMaster.announcement(at: date(2026, 12, 15), told: nil, onSantaMap: true, calendar: calendar)).beat
        XCTAssertTrue(beat.text(in: .traditionalChinese).contains("聖誕老人村"))
        let elsewhere = try XCTUnwrap(WinterStationMaster.announcement(at: date(2026, 12, 15), told: nil, calendar: calendar)).beat
        XCTAssertTrue(elsewhere.text(in: .traditionalChinese).contains("1,000"))
    }

    /// Every face has its hatted twin in the asset catalog.
    func testEveryFaceHasAChristmasImage() throws {
        let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RailwayGameApp/Resources/Assets.xcassets")
        for mood in ["Normal", "Happy", "Worried"] {
            let set = catalog.appendingPathComponent("StationMasterTaiwan\(mood)\(WinterStationMaster.outfitSuffix).imageset")
            let svg = try String(contentsOf: set.appendingPathComponent("station-master-taiwan-\(mood.lowercased())-christmas.svg"), encoding: .utf8)
            XCTAssertTrue(svg.contains("#8C1C1C"), mood)
            XCTAssertFalse(svg.contains("transform") || svg.contains("opacity"), mood)
        }
    }
}
