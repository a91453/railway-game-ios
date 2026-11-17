import Foundation
@testable import GamePresentation
import XCTest

/// Decision 815: the winter tune plays from 1 December to 6 January by the
/// device's date, the theme on every other day.
final class MusicTuneTests: XCTestCase {
    private let calendar = WinterEvent.calendar(in: TimeZone(identifier: "Asia/Taipei")!)

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testTheWinterTunePlaysFromTheFirstOfDecemberToTheSixthOfJanuary() {
        XCTAssertEqual(MusicTune.playing(at: date(2026, 11, 30, 23, 59), calendar: calendar), .theme)
        XCTAssertEqual(MusicTune.playing(at: date(2026, 12, 1, 0, 0), calendar: calendar), .winter)
        XCTAssertEqual(MusicTune.playing(at: date(2026, 12, 25), calendar: calendar), .winter)
        XCTAssertEqual(MusicTune.playing(at: date(2026, 12, 31, 23, 59), calendar: calendar), .winter)
        XCTAssertEqual(MusicTune.playing(at: date(2027, 1, 1, 0, 0), calendar: calendar), .winter)
        XCTAssertEqual(MusicTune.playing(at: date(2027, 1, 6, 23, 59), calendar: calendar), .winter)
        XCTAssertEqual(MusicTune.playing(at: date(2027, 1, 7, 0, 0), calendar: calendar), .theme)
        XCTAssertEqual(MusicTune.playing(at: date(2027, 7, 15), calendar: calendar), .theme)
    }

    /// Every day of a year: the winter tune exactly on the event's days.
    func testTheTuneFollowsTheWinterEventOnEveryDay() {
        var day = date(2026, 1, 1)
        var winterDays = 0
        while day < date(2027, 1, 1) {
            let track = MusicTune.playing(at: day, calendar: calendar)
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
        XCTAssertEqual(MusicTune.playing(at: taipeiMidnight, calendar: calendar), .winter)
        XCTAssertEqual(MusicTune.playing(at: taipeiMidnight, calendar: utc), .theme)
    }

    /// During the winter event the winter tune and the theme take turns,
    /// each played once; outside it the theme loops on its own.
    func testTheTunesTakeTurnsDuringTheWinterEvent() {
        let christmas = date(2026, 12, 25)
        let winter = MusicPlay(tune: .winter, loops: false)
        let theme = MusicPlay(tune: .theme, loops: false)
        XCTAssertEqual(MusicTune.play(at: christmas, continuing: nil, calendar: calendar), winter)
        XCTAssertEqual(MusicTune.play(after: .winter, at: christmas, calendar: calendar), theme)
        XCTAssertEqual(MusicTune.play(after: .theme, at: christmas, calendar: calendar), winter)
        // Four turns: winter, theme, winter, theme.
        var turns = [MusicTune.play(at: christmas, continuing: nil, calendar: calendar)]
        while turns.count < 4 { turns.append(MusicTune.play(after: turns.last!.tune, at: christmas, calendar: calendar)) }
        XCTAssertEqual(turns.map(\.tune), [.winter, .theme, .winter, .theme])
        XCTAssertFalse(turns.contains(where: \.loops))

        let summer = date(2027, 7, 15)
        let looping = MusicPlay(tune: .theme, loops: true)
        XCTAssertEqual(MusicTune.play(at: summer, continuing: nil, calendar: calendar), looping)
        XCTAssertEqual(MusicTune.play(at: summer, continuing: looping, calendar: calendar), looping)
    }

    /// Coming back to the app keeps the turn under way; the event's first
    /// and last days switch at once.
    func testATurnGoesOnAndTheEventsEdgesSwitch() {
        let christmas = date(2026, 12, 25)
        let theme = MusicPlay(tune: .theme, loops: false)
        let winter = MusicPlay(tune: .winter, loops: false)
        let looping = MusicPlay(tune: .theme, loops: true)
        XCTAssertEqual(MusicTune.play(at: christmas, continuing: theme, calendar: calendar), theme)
        XCTAssertEqual(MusicTune.play(at: christmas, continuing: winter, calendar: calendar), winter)
        // The theme looping since November gives way on 1 December.
        XCTAssertEqual(MusicTune.play(at: date(2026, 12, 1, 0, 0), continuing: looping, calendar: calendar), winter)
        // On 7 January either turn gives way to the theme, looping.
        let over = date(2027, 1, 7, 0, 0)
        XCTAssertEqual(MusicTune.play(at: over, continuing: winter, calendar: calendar), looping)
        XCTAssertEqual(MusicTune.play(at: over, continuing: theme, calendar: calendar), looping)
        XCTAssertEqual(MusicTune.play(after: .winter, at: over, calendar: calendar), looping)
        XCTAssertEqual(MusicTune.play(after: .theme, at: over, calendar: calendar), looping)
    }

    /// Every file the music plays is made by the audio tool, listed in
    /// its manifest as music of that tune at the same loudness, and
    /// bundled with the app: the theme's loop has a seam, a turn's file
    /// rings out to silence.
    func testEveryTuneIsBundledInTheManifest() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("tools/audio/manifest.json"))) as? [String: Any]
        let entries = manifest?["files"] as? [[String: Any]] ?? []
        let project = try String(contentsOf: root.appendingPathComponent("RailwayGameApp/RailwayGame.xcodeproj/project.pbxproj"), encoding: .utf8)
        var loudness: [Double] = []
        let plays = [MusicPlay(tune: .theme, loops: true), MusicPlay(tune: .theme, loops: false), MusicPlay(tune: .winter, loops: false)]
        for play in plays {
            let file = "\(play.resource.name).\(play.resource.extension)"
            let entry = try XCTUnwrap(entries.first { $0["file"] as? String == file }, file)
            XCTAssertEqual(entry["kind"] as? String, "music", file)
            XCTAssertEqual(entry["tune"] as? String, play.tune.rawValue, file)
            if play.loops {
                XCTAssertNotNil(entry["loopSeam"], file)
            } else {
                XCTAssertEqual(try XCTUnwrap(entry["endLevel"] as? Double, file), 0, accuracy: 0.001, "\(file) rings out to silence")
            }
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
        let entry = try XCTUnwrap(entries.first { $0["file"] as? String == "music-winter.m4a" })
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(entry["seconds"] as? Double), 90)
    }
}
