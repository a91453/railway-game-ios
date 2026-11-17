import Foundation
@testable import GamePresentation
import XCTest

/// Decision 815: the winter tune plays from 1 December to 6 January by the
/// device's date, the theme on every other day.
final class MusicTrackTests: XCTestCase {
    private let calendar = WinterEvent.calendar(in: TimeZone(identifier: "Asia/Taipei")!)

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testTheWinterTunePlaysFromTheFirstOfDecemberToTheSixthOfJanuary() {
        XCTAssertEqual(MusicTrack.playing(at: date(2026, 11, 30, 23, 59), calendar: calendar), .theme)
        XCTAssertEqual(MusicTrack.playing(at: date(2026, 12, 1, 0, 0), calendar: calendar), .winter)
        XCTAssertEqual(MusicTrack.playing(at: date(2026, 12, 25), calendar: calendar), .winter)
        XCTAssertEqual(MusicTrack.playing(at: date(2026, 12, 31, 23, 59), calendar: calendar), .winter)
        XCTAssertEqual(MusicTrack.playing(at: date(2027, 1, 1, 0, 0), calendar: calendar), .winter)
        XCTAssertEqual(MusicTrack.playing(at: date(2027, 1, 6, 23, 59), calendar: calendar), .winter)
        XCTAssertEqual(MusicTrack.playing(at: date(2027, 1, 7, 0, 0), calendar: calendar), .theme)
        XCTAssertEqual(MusicTrack.playing(at: date(2027, 7, 15), calendar: calendar), .theme)
    }

    /// Every day of a year: the winter tune exactly on the event's days.
    func testTheTuneFollowsTheWinterEventOnEveryDay() {
        var day = date(2026, 1, 1)
        var winterDays = 0
        while day < date(2027, 1, 1) {
            let track = MusicTrack.playing(at: day, calendar: calendar)
            XCTAssertEqual(track == .winter, WinterEvent.isOn(at: day, calendar: calendar), "\(day)")
            if track == .winter { winterDays += 1 }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        // 1–6 January and all of December.
        XCTAssertEqual(winterDays, 6 + 31)
    }

    /// The day turns at the device's own midnight: 1 December in Taipei
    /// begins at 16:00 UTC on 30 November.
    func testTheDayTurnsAtTheDevicesMidnight() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let taipeiMidnight = utc.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 16))!
        XCTAssertEqual(MusicTrack.playing(at: taipeiMidnight, calendar: calendar), .winter)
        XCTAssertEqual(MusicTrack.playing(at: taipeiMidnight, calendar: utc), .theme)
    }

    /// Both tunes are made by the audio tool, listed in its manifest as
    /// music loops at the same loudness, and bundled with the app.
    func testEveryTuneIsABundledLoopInTheManifest() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("tools/audio/manifest.json"))) as? [String: Any]
        let entries = manifest?["files"] as? [[String: Any]] ?? []
        let project = try String(contentsOf: root.appendingPathComponent("RailwayGameApp/RailwayGame.xcodeproj/project.pbxproj"), encoding: .utf8)
        var loudness: [Double] = []
        for track in MusicTrack.allCases {
            let file = "\(track.resource.name).\(track.resource.extension)"
            let entry = try XCTUnwrap(entries.first { $0["file"] as? String == file }, file)
            XCTAssertEqual(entry["kind"] as? String, "music", file)
            XCTAssertNotNil(entry["loopSeam"], file)
            loudness.append(try XCTUnwrap(entry["loudnessLufs"] as? Double, file))
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("RailwayGameApp/Resources/Audio/\(file)").path), "\(file) is bundled")
            XCTAssertTrue(project.contains("\(file) in Resources"), "\(file) is in the app's resources")
        }
        XCTAssertLessThanOrEqual(loudness.max()! - loudness.min()!, 0.5, "the tunes are equally loud")
    }

    /// The winter tune runs at least a minute and a half, so it is not
    /// heard going round every few bars.
    func testTheWinterTuneIsAtLeastAMinuteAndAHalf() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("tools/audio/manifest.json"))) as? [String: Any]
        let entries = manifest?["files"] as? [[String: Any]] ?? []
        let entry = try XCTUnwrap(entries.first { $0["file"] as? String == "music-winter.caf" })
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(entry["seconds"] as? Double), 90)
    }
}
