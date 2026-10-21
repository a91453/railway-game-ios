@testable import GamePresentation
import XCTest

/// Decision 328: the flat map's frame readout.
final class FrameCostMeterTests: XCTestCase {
    func testOffItTimesNothingAndReadsNothing() {
        let meter = FrameCostMeter()
        meter.record(.track, milliseconds: 5)
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
        meter.record(.track, milliseconds: 4)
        meter.record(.track, milliseconds: 10)
        meter.record(.step, milliseconds: 2)
        XCTAssertNil(meter.frame(at: 100.25))
        XCTAssertNil(meter.frame(at: 100.75))
        let reading = try XCTUnwrap(meter.frame(at: 101))
        XCTAssertEqual(reading.framesPerSecond, 3, accuracy: 1e-9)
        XCTAssertEqual(reading.longestGapMilliseconds, 500, accuracy: 1e-6)
        XCTAssertEqual(reading.parts.map(\.part), [.step, .track])
        let track = try XCTUnwrap(reading.parts.last)
        XCTAssertEqual(track.count, 2)
        XCTAssertEqual(track.millisecondsPerSecond, 14, accuracy: 1e-9)
        XCTAssertEqual(track.longestMilliseconds, 10)
        // The costliest first under the longest frame.
        XCTAssertEqual(reading.lines(in: .english), [
            "longest frame 500 ms",
            "track 14.0 ms/s · ×2 · max 10.0 ms",
            "tick 2.0 ms/s · ×1 · max 2.0 ms",
        ])
        // A new window begins with nothing counted.
        XCTAssertNil(meter.frame(at: 101.5))
        XCTAssertEqual(meter.frame(at: 102)?.parts, [])
    }

    func testEveryPartHasANameInBothLanguages() {
        for part in FrameCostPart.allCases {
            XCTAssertFalse(part.title(in: .english).isEmpty)
            XCTAssertFalse(part.title(in: .traditionalChinese).isEmpty)
        }
    }
}
