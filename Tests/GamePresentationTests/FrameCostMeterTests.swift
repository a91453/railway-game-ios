@testable import GamePresentation
import XCTest

/// Decision 328: the flat map's frame readout.
final class FrameCostMeterTests: XCTestCase {
    func testOffItTimesNothingAndReadsNothing() {
        let meter = FrameCostMeter()
        meter.record(.railway, milliseconds: 5)
        XCTAssertEqual(meter.measure(.labels) { 7 }, 7)
        XCTAssertNil(meter.frame(at: 0))
        XCTAssertNil(meter.frame(at: 2))
        meter.isOn = true
        XCTAssertNil(meter.frame(at: 10))
        XCTAssertEqual(meter.frame(at: 11)?.parts, [])
    }

    func testASecondsReadingCountsTheFramesTheLongestGapAndEachPart() throws {
        let meter = FrameCostMeter()
        meter.isOn = true
        XCTAssertNil(meter.frame(at: 100))
        meter.record(.railway, milliseconds: 4)
        meter.record(.railway, milliseconds: 10)
        meter.record(.step, milliseconds: 2)
        XCTAssertNil(meter.frame(at: 100.25))
        XCTAssertNil(meter.frame(at: 100.75))
        let reading = try XCTUnwrap(meter.frame(at: 101))
        XCTAssertEqual(reading.framesPerSecond, 3, accuracy: 1e-9)
        XCTAssertEqual(reading.longestGapMilliseconds, 500, accuracy: 1e-6)
        XCTAssertEqual(reading.parts.map(\.part), [.step, .railway])
        let track = try XCTUnwrap(reading.parts.last)
        XCTAssertEqual(track.count, 2)
        XCTAssertEqual(track.millisecondsPerSecond, 14, accuracy: 1e-9)
        XCTAssertEqual(track.longestMilliseconds, 10)
        // The costliest first under the longest frame.
        XCTAssertEqual(reading.lines(in: .english), [
            "longest frame 500 ms · other 500 ms",
            "track and lines 14.0 ms/s · ×2 · max 10.0 ms",
            "tick 2.0 ms/s · ×1 · max 2.0 ms",
        ])
        // A new window begins with nothing counted.
        XCTAssertNil(meter.frame(at: 101.5))
        XCTAssertEqual(meter.frame(at: 102)?.parts, [])
    }

    /// Decision 377: why the railway was drawn again, counted beside its
    /// time; off, nothing is counted, and a new window starts afresh.
    func testTheReadoutSaysWhyTheRailwayWasDrawnAgain() throws {
        let meter = FrameCostMeter()
        meter.noteRedraw(.railway, because: .camera)
        meter.isOn = true
        XCTAssertNil(meter.frame(at: 0))
        meter.noteRedraw(.railway, because: .flow)
        meter.noteRedraw(.railway, because: .camera)
        meter.noteRedraw(.railway, because: .camera)
        meter.record(.railway, milliseconds: 30)
        meter.record(.railway, milliseconds: 20)
        meter.record(.railway, milliseconds: 10)
        let reading = try XCTUnwrap(meter.frame(at: 1))
        XCTAssertEqual(reading.parts.first?.reasons, [.camera: 2, .flow: 1])
        XCTAssertEqual(reading.lines(in: .english).last, "track and lines 60.0 ms/s · ×3 · max 30.0 ms · view moved ×2 · passenger flow ×1")
        XCTAssertEqual(reading.lines(in: .traditionalChinese).last, "軌道與路線 60.0 ms/s · ×3 · max 30.0 ms · 畫面移動 ×2 · 客流 ×1")
        meter.record(.railway, milliseconds: 5)
        XCTAssertEqual(meter.frame(at: 2)?.parts.first?.reasons, [:])
    }

    /// Decision 330: of the longest frame, what no part on the main thread
    /// was timed in; the pieces of the step after a tick under it.
    func testTheLongestFrameKeepsWhatWasNotTimedAndThePiecesFollowTheirPart() throws {
        let meter = FrameCostMeter()
        meter.isOn = true
        XCTAssertNil(meter.frame(at: 10))
        XCTAssertNil(meter.frame(at: 10.1))
        // Between these two frames, 120 ms: 45 timed after the tick (of
        // it 40 the news, not counted twice), 15 of letting the old world
        // go, and the tick's own 30, off the main thread, not counted.
        meter.record(.afterStep, milliseconds: 45)
        meter.record(.stepNews, milliseconds: 40)
        meter.record(.stepWorld, milliseconds: 2)
        meter.record(.release, milliseconds: 15)
        meter.record(.step, milliseconds: 30)
        XCTAssertNil(meter.frame(at: 10.22))
        let reading = try XCTUnwrap(meter.frame(at: 11))
        XCTAssertEqual(reading.longestGapMilliseconds, 780, accuracy: 1e-6)
        // The longest gap is the last, with nothing timed in it.
        XCTAssertEqual(reading.longestGapUntimedMilliseconds, 780, accuracy: 1e-6)
        XCTAssertEqual(reading.lines(in: .traditionalChinese), [
            "最長一幀 780 ms · 其他 780 ms",
            "推進後 45.0 ms/s · ×1 · max 45.0 ms",
            "  · 新聞 40.0 ms/s · ×1 · max 40.0 ms",
            "  · 更新 2.0 ms/s · ×1 · max 2.0 ms",
            "推進 30.0 ms/s · ×1 · max 30.0 ms",
            "清理 15.0 ms/s · ×1 · max 15.0 ms",
        ])
    }

    func testTheTimedPartOfALongFrameIsTakenOff() throws {
        let meter = FrameCostMeter()
        meter.isOn = true
        XCTAssertNil(meter.frame(at: 0))
        meter.record(.afterStep, milliseconds: 45)
        meter.record(.stepNews, milliseconds: 40)
        meter.record(.release, milliseconds: 15)
        XCTAssertNil(meter.frame(at: 0.114))
        XCTAssertNil(meter.frame(at: 0.13))
        for frame in 1...52 { XCTAssertNil(meter.frame(at: 0.13 + Double(frame) / 60)) }
        let reading = try XCTUnwrap(meter.frame(at: 1.05))
        XCTAssertEqual(reading.longestGapMilliseconds, 114, accuracy: 1e-6)
        // 114 ms, less the 60 timed on the main thread (the news is in
        // the step after the tick's 45, not counted twice).
        XCTAssertEqual(reading.longestGapUntimedMilliseconds, 54, accuracy: 1e-6)
    }

    /// Decision 379: the view update holds the canvases, so the longest
    /// frame's "other" leaves it in and says how much of the frame it was;
    /// the sounds, off the main thread, are not taken off either.
    func testTheViewUpdateIsShownBesideTheLongestFrameNotTakenOff() throws {
        let meter = FrameCostMeter()
        meter.isOn = true
        XCTAssertNil(meter.frame(at: 0))
        meter.record(.railway, milliseconds: 20)
        meter.record(.mapBody, milliseconds: 30)
        meter.record(.viewUpdate, milliseconds: 150)
        meter.record(.soundPlayback, milliseconds: 29)
        XCTAssertNil(meter.frame(at: 0.2))
        for frame in 1...47 { XCTAssertNil(meter.frame(at: 0.2 + Double(frame) / 60)) }
        let reading = try XCTUnwrap(meter.frame(at: 1.05))
        XCTAssertEqual(reading.longestGapMilliseconds, 200, accuracy: 1e-6)
        XCTAssertEqual(reading.longestGapUntimedMilliseconds, 180, accuracy: 1e-6)
        XCTAssertEqual(reading.longestGapViewUpdateMilliseconds, 150, accuracy: 1e-6)
        let lines = reading.lines(in: .traditionalChinese)
        XCTAssertEqual(lines.first, "最長一幀 200 ms · 其他 180 ms（畫面更新 150 ms）")
        XCTAssertEqual(lines.firstIndex { $0.hasPrefix("  · 地圖 ") }, lines.firstIndex { $0.hasPrefix("畫面更新 ") }.map { $0 + 1 })
        XCTAssertEqual(FrameCostPart.mapBody.parent, .viewUpdate)
        XCTAssertFalse(FrameCostPart.soundPlayback.isOnMainThread)
    }

    func testEveryPartHasANameInBothLanguages() {
        for part in FrameCostPart.allCases {
            XCTAssertFalse(part.title(in: .english).isEmpty)
            XCTAssertFalse(part.title(in: .traditionalChinese).isEmpty)
        }
    }
}
