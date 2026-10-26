import Foundation
@testable import GamePresentation
import XCTest

/// Decision 421 (V1): the frame time record's statistics, from samples
/// written out here.
final class FrameTimeRecordTests: XCTestCase {
    private let context2D = FrameTimeContext(screen: .map2D, speed: "normal", stations: 32, lines: 5)
    private let context3D = FrameTimeContext(screen: .map3D, speed: "normal", stations: 32, lines: 5, map3D: "automatic, standard full · 600000 triangles")

    /// Beats `intervals` milliseconds apart, from `start` seconds.
    private func beat(_ meter: FrameTimeMeter, _ intervals: [Double], from start: Double = 100) {
        var time = start
        meter.frame(at: time)
        for interval in intervals {
            time += interval / 1_000
            meter.frame(at: time)
        }
    }

    func testMedianAndPercentilesByNearestRank() {
        var distribution = FrameTimeDistribution()
        // 100 samples: 1.0 … 100.0 ms.
        for value in 1...100 { distribution.add(Double(value)) }
        let summary = distribution.summary
        XCTAssertEqual(summary?.count, 100)
        XCTAssertEqual(summary?.median, 50)
        XCTAssertEqual(summary?.p95, 95)
        XCTAssertEqual(summary?.p99, 99)
        XCTAssertEqual(summary?.longest, 100)
        // Nearest rank: of four, the median is the second.
        var four = FrameTimeDistribution()
        for value in [16.7, 16.6, 33.3, 16.8] { four.add(value) }
        XCTAssertEqual(four.percentile(0.5), 16.7)
        XCTAssertEqual(four.percentile(0.95), 33.3)
        XCTAssertEqual(four.percentile(1), 33.3)
    }

    func testStepsAreTenthsThenWholeMillisecondsThenTheLongest() {
        var distribution = FrameTimeDistribution()
        for value in [8.33, 99.94, 99.96, 250.4, 1_999.4, 2_500, 3_100.5] { distribution.add(value) }
        XCTAssertEqual(distribution.percentile(1.0 / 7), 8.3)
        XCTAssertEqual(distribution.percentile(2.0 / 7), 99.9)
        XCTAssertEqual(distribution.percentile(3.0 / 7), 100, "rounds up into whole milliseconds")
        XCTAssertEqual(distribution.percentile(4.0 / 7), 250)
        XCTAssertEqual(distribution.percentile(5.0 / 7), 1_999)
        XCTAssertEqual(distribution.percentile(6.0 / 7), 3_100.5, "past 2 s, the longest")
        XCTAssertEqual(distribution.longest, 3_100.5)
        // Nothing negative, nothing not a number.
        var odd = FrameTimeDistribution()
        odd.add(-3)
        odd.add(.nan)
        XCTAssertEqual(odd.count, 1)
        XCTAssertEqual(odd.percentile(0.5), 0)
        XCTAssertNil(FrameTimeDistribution().summary, "no sample, no summary")
    }

    func testStallsCountFromExactlyFiftyHundredAndTwoHundredFifty() {
        let meter = FrameTimeMeter()
        meter.begin(context2D, at: 100, wall: 1_000)
        beat(meter, [16.7, 49.9, 50, 99.9, 100, 249.9, 250, 16.7, 16.7, 16.7, 400])
        let segment = meter.end(at: 200)
        XCTAssertEqual(segment?.stalls, FrameTimeStalls(short: 2, long: 2, severe: 2))
        XCTAssertEqual(segment?.stalls.total, 6)
        XCTAssertEqual(segment?.longest?.milliseconds, 400)
        XCTAssertEqual(segment?.intervals?.count, 11)
        XCTAssertEqual(segment?.intervals?.longest, 400)
    }

    func testTheLongestStallSaysWhenAndInWhatContext() throws {
        let meter = FrameTimeMeter()
        meter.begin(context3D, at: 10, wall: 1_761_000_000)
        // Ten 16.7 ms intervals, a 180 ms stall, ten more, a 120 ms one.
        beat(meter, Array(repeating: 16.7, count: 10) + [180] + Array(repeating: 16.7, count: 10) + [120], from: 10)
        let segment = try XCTUnwrap(meter.end(at: 20))
        let longest = try XCTUnwrap(segment.longest)
        XCTAssertEqual(longest.milliseconds, 180)
        XCTAssertEqual(longest.at, 0.3, "10 × 16.7 ms + 180 ms in, to a tenth")
        XCTAssertTrue(longest.parts.isEmpty, "3D has no 2D parts")
        XCTAssertEqual(segment.context, context3D)
        XCTAssertEqual(segment.began, 1_761_000_000)
        XCTAssertEqual(segment.seconds, 10)
        XCTAssertEqual(segment.intervals?.median, 16.7)
    }

    func testFramesThatNeverReachedTheScreenAreCountedApart() {
        let meter = FrameTimeMeter()
        meter.begin(context3D, at: 0, wall: 0)
        beat(meter, Array(repeating: 16.7, count: 10), from: 1)
        meter.frame(at: 0)
        meter.frame(at: 0)
        let segment = meter.end(at: 2)
        XCTAssertEqual(segment?.notPresented, 2)
        XCTAssertEqual(segment?.intervals?.count, 10, "not among the intervals")
        XCTAssertEqual(segment?.stalls.total, 0)
    }

    func testAnEmptyOrShortStretchIsNotKeptAndAnEmptyLogSaysNothing() {
        let meter = FrameTimeMeter()
        XCTAssertNil(meter.end(at: 1), "nothing begun")
        meter.begin(context2D, at: 0, wall: 0)
        XCTAssertNil(meter.end(at: 1), "no frame")
        meter.begin(context2D, at: 0, wall: 0)
        beat(meter, Array(repeating: 16.7, count: FrameTimeMeter.fewestIntervals - 1))
        XCTAssertNil(meter.end(at: 1), "too few intervals")
        XCTAssertNil(FrameTimeLog().reportText(in: .english))
        XCTAssertEqual(FrameTimeLog.decoded(Data("not json".utf8)), FrameTimeLog())
    }

    func testAStretchEndsWhenTheScreenOrSpeedChangesOrItRunsTooLong() {
        let meter = FrameTimeMeter()
        XCTAssertNil(meter.update(context2D, at: 0, wall: 0), "begins one")
        beat(meter, Array(repeating: 16.7, count: 20), from: 0.5)
        var more = context2D
        more.stations = 40
        XCTAssertNil(meter.update(more, at: 1, wall: 1), "the counts are only the latest")
        XCTAssertEqual(meter.context?.stations, 40)
        var faster = more
        faster.speed = "double"
        let ended = meter.update(faster, at: 2, wall: 2)
        XCTAssertEqual(ended?.context.stations, 40)
        XCTAssertEqual(ended?.context.speed, "normal")
        XCTAssertEqual(meter.context?.speed, "double")
        beat(meter, Array(repeating: 16.7, count: 20), from: 3)
        XCTAssertNil(meter.update(faster, at: 2 + FrameTimeMeter.longestSegment - 1, wall: 0))
        XCTAssertNotNil(meter.update(faster, at: 2 + FrameTimeMeter.longestSegment, wall: 0), "too long: a new one")
    }

    func testThe3DMapsWorkMemoryAndHeat() throws {
        let meter = FrameTimeMeter()
        meter.begin(context3D, at: 0, wall: 0)
        for (cpu, gpu) in [(4.0, 6.0), (5.0, 7.0), (12.0, 20.0)] {
            meter.drew(cpuMilliseconds: cpu, triangles: Int(cpu) * 1_000, drawCalls: Int(gpu), chunks: 3)
            meter.gpu(milliseconds: gpu)
        }
        meter.memory(footprint: 500 * 1_048_576, available: 1_500 * 1_048_576)
        meter.memory(footprint: 700 * 1_048_576, available: 1_300 * 1_048_576)
        meter.memory(footprint: 600 * 1_048_576, available: nil)
        meter.memoryWarning()
        for state in ["nominal", "nominal", "fair", "serious", "fair"] { meter.thermal(state) }
        beat(meter, Array(repeating: 16.7, count: 10), from: 1)
        let segment = try XCTUnwrap(meter.end(at: 2))
        XCTAssertEqual(segment.cpu, FrameTimeStats(count: 3, median: 5, p95: 12, p99: 12, longest: 12))
        XCTAssertEqual(segment.gpu?.median, 7)
        XCTAssertEqual(segment.triangles, 12_000)
        XCTAssertEqual(segment.drawCalls, 20)
        XCTAssertEqual(segment.chunks, 3)
        XCTAssertEqual(segment.memoryPeak, 700)
        XCTAssertEqual(segment.memoryLeast, 1_300)
        XCTAssertEqual(segment.memoryWarnings, 1)
        XCTAssertEqual(segment.thermal, ["nominal", "fair", "serious", "fair"])
    }

    /// The flat map's longest stall carries decision 328's parts timed in
    /// it, the longest first, and what no part was timed in.
    func testThe2DLongestStallCarriesItsParts() throws {
        let costs = FrameCostMeter()
        costs.keepsFrameParts = true
        let meter = FrameTimeMeter(costs: costs)
        meter.begin(context2D, at: 0, wall: 0)
        beat(meter, Array(repeating: 16.7, count: 10), from: 1)
        // In the next frame, 300 ms: the parts take 120 + 80 + 30 + 10.
        costs.record(.afterStep, milliseconds: 120)
        costs.record(.stepNews, milliseconds: 100) // a piece of the one above: not counted again
        costs.record(.ground, milliseconds: 80)
        costs.record(.labels, milliseconds: 30)
        costs.record(.trains, milliseconds: 10)
        costs.record(.step, milliseconds: 500) // off the main thread
        XCTAssertTrue(meter.frame(at: 1.167 + 0.3))
        // The next frame's parts start afresh.
        costs.record(.ground, milliseconds: 60)
        meter.frame(at: 1.167 + 0.3 + 0.0167)
        let segment = try XCTUnwrap(meter.end(at: 2))
        let longest = try XCTUnwrap(segment.longest)
        XCTAssertEqual(longest.milliseconds, 300)
        XCTAssertEqual(longest.parts, [
            FrameTimeStall.Part(part: "afterStep", milliseconds: 120),
            FrameTimeStall.Part(part: "ground", milliseconds: 80),
            FrameTimeStall.Part(part: "labels", milliseconds: 30),
            FrameTimeStall.Part(part: FrameTimeStall.Part.untimed, milliseconds: 60),
        ])
        XCTAssertEqual(segment.stalls.severe, 1)
    }

    func testTheLogKeepsTheNewestWithinItsCountAndSize() throws {
        var log = FrameTimeLog()
        for index in 0..<(FrameTimeLog.mostSegments + 5) {
            log.add(FrameTimeSegment(context: context2D, began: Double(index), seconds: 60, intervals: nil))
        }
        XCTAssertEqual(log.segments.count, FrameTimeLog.mostSegments)
        XCTAssertEqual(log.segments.first?.began, Double(FrameTimeLog.mostSegments + 4), "the newest first")
        XCTAssertEqual(log.segments.last?.began, 5, "the oldest dropped")
        // Past the size: the oldest go first.
        var big = FrameTimeLog()
        let wide = FrameTimeContext(screen: .map3D, map3D: String(repeating: "x", count: 8_000))
        for index in 0..<12 { big.add(FrameTimeSegment(context: wide, began: Double(index), seconds: 60, intervals: nil)) }
        XCTAssertLessThanOrEqual(try big.encoded().count, FrameTimeLog.mostBytes)
        XCTAssertLessThan(big.segments.count, 12)
        XCTAssertEqual(big.segments.first?.began, 11)
        XCTAssertEqual(FrameTimeLog.decoded(try big.encoded()), big)
    }

    func testTheReportCallsThe2DPartABeatAndShowsBothParts() throws {
        let meter = FrameTimeMeter()
        var log = FrameTimeLog()
        meter.begin(context2D, at: 0, wall: 1_761_480_000)
        beat(meter, Array(repeating: 16.7, count: 10) + [260], from: 1)
        meter.begin(context3D, at: 10, wall: 1_761_480_010).map { log.add($0) }
        beat(meter, Array(repeating: 16.7, count: 10), from: 11)
        meter.frame(at: 0)
        meter.drew(cpuMilliseconds: 5, triangles: 400_000, drawCalls: 120, chunks: 30)
        meter.gpu(milliseconds: 8)
        log.add(try XCTUnwrap(meter.end(at: 12)))
        let chinese = try XCTUnwrap(log.reportText(in: .traditionalChinese))
        XCTAssertTrue(chinese.contains("2D 節拍（主執行緒醒來準備下一格的間隔，不是上螢幕的時間）"), chinese)
        XCTAssertTrue(chinese.contains("3D 上螢幕間隔"), chinese)
        XCTAssertTrue(chinese.contains("250 ms 以上（嚴重）×1；最長 260.0 ms"), chinese)
        XCTAssertTrue(chinese.contains("沒上螢幕 1 格"), chinese)
        XCTAssertTrue(chinese.contains("最多 400000 三角形、120 draw call、30 場景塊"), chinese)
        XCTAssertFalse(chinese.contains("2D 幀時間"), chinese)
        let english = try XCTUnwrap(log.reportText(in: .english))
        XCTAssertTrue(english.contains("2D beat"), english)
        XCTAssertFalse(english.lowercased().contains("2d frame time"), english)
        XCTAssertTrue(english.contains("median 16.7 ms, p95 16.7 ms"), english)
        // The newest first: 3D, then 2D.
        XCTAssertLessThan(try XCTUnwrap(english.range(of: "3D frames")).lowerBound, try XCTUnwrap(english.range(of: "2D beat")).lowerBound)
    }

    /// A report written while a stretch runs shows it first, and it goes on.
    func testAReportShowsTheStretchGoingOnFirst() throws {
        let meter = FrameTimeMeter()
        var log = FrameTimeLog()
        log.add(FrameTimeSegment(context: context3D, began: 0, seconds: 60, intervals: nil))
        meter.begin(context2D, at: 0, wall: 100)
        beat(meter, Array(repeating: 16.7, count: 10) + [300], from: 1)
        let going = try XCTUnwrap(meter.current(at: 3))
        XCTAssertEqual(going.stalls.severe, 1)
        XCTAssertEqual(going.seconds, 3)
        let text = try XCTUnwrap(log.reportText(in: .english, going: going))
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "2D beat")).lowerBound, try XCTUnwrap(text.range(of: "3D frames")).lowerBound)
        beat(meter, [16.7], from: 3)
        XCTAssertEqual(meter.end(at: 4)?.intervals?.count, 13, "it went on: two more")
        XCTAssertEqual(log.segments.count, 1, "not kept")
        XCTAssertNil(FrameTimeMeter().current(at: 1))
    }
}
