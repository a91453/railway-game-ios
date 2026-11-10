import Foundation
@testable import GamePresentation
import XCTest

/// Decision 320: the rain over the 3D map, the reference's curtain of
/// parallel streaks.
final class Map3DRainTests: XCTestCase {
    private let rain = Map3DRain(MapWeather(sky: .rain))

    /// A clear day has no rain and no lightning.
    func testAClearDayHasNoRain() {
        let clear = Map3DRain(.clear)
        XCTAssertEqual(clear, .none)
        XCTAssertEqual(clear.look(night: 0).opacity, 0)
        XCTAssertEqual(clear.streakCount(.full), 0)
        XCTAssertTrue(clear.streaks(at: 12, width: 400, height: 800, detail: .full).isEmpty)
        XCTAssertEqual((0..<200).map { clear.flash(at: Double($0) * 0.1) }.max(), 0)
    }

    /// Under rain, the reference's counts for each street detail; at
    /// night its colour at 0.24, by day the 2D map's at 0.35, between
    /// them as the light fades. Harder and more streaks in a thunderstorm,
    /// most in a typhoon, whose wind leans them further.
    func testHowHardItRains() {
        XCTAssertEqual(Map3DStreetDetail.allCases.map(rain.streakCount), [140, 260, 480])
        XCTAssertEqual(rain.look(night: 1).colour, 0xC6D7E4)
        XCTAssertEqual(rain.look(night: 1).opacity, 0.24, accuracy: 1e-9)
        XCTAssertEqual(rain.look(night: 0).colour, 0x4A5A80)
        XCTAssertEqual(rain.look(night: 0).opacity, 0.35, accuracy: 1e-9)
        XCTAssertEqual(rain.look(night: 0.5).colour, 0x8899B2)
        XCTAssertEqual(rain.look(night: -1).colour, 0x4A5A80)
        XCTAssertEqual(rain.slant, 0.12)
        let storm = Map3DRain(MapWeather(sky: .thunderstorm)), typhoon = Map3DRain(MapWeather(sky: .typhoon))
        XCTAssertLessThan(rain.streakCount(.full), storm.streakCount(.full))
        XCTAssertLessThan(storm.streakCount(.full), typhoon.streakCount(.full))
        XCTAssertLessThan(storm.look(night: 0).opacity, typhoon.look(night: 0).opacity)
        XCTAssertLessThanOrEqual(typhoon.look(night: 0).opacity, 0.55)
        XCTAssertEqual(storm.slant, 0.12)
        XCTAssertGreaterThan(typhoon.slant, storm.slant)
    }

    /// Every streak leans the same way, 5 to 11 points long, starting on
    /// the screen; the same time gives the same streaks.
    func testTheStreaksAreParallelAndTheSameEveryTime() {
        for time in [0.0, 3.7, 1_000.25] {
            let streaks = rain.streaks(at: time, width: 402, height: 874, detail: .full)
            XCTAssertEqual(streaks.count, 480)
            XCTAssertEqual(streaks, rain.streaks(at: time, width: 402, height: 874, detail: .full))
            for streak in streaks {
                XCTAssertEqual((streak.x1 - streak.x0) / (streak.y1 - streak.y0), 0.12, accuracy: 1e-9)
                XCTAssertTrue((5...11).contains(streak.y1 - streak.y0))
                XCTAssertTrue((0..<402).contains(streak.x0) && (0..<874).contains(streak.y0))
            }
        }
        XCTAssertNotEqual(rain.streaks(at: 0, width: 402, height: 874, detail: .full),
                          rain.streaks(at: 0.5, width: 402, height: 874, detail: .full))
    }

    /// Each streak falls 0.85 to 1.15 times 220 points a second and
    /// drifts by the slant as it falls, coming back in at the top.
    func testTheStreaksFall() {
        let height = 874.0, width = 402.0, step = 0.05
        let before = rain.streaks(at: 10, width: width, height: height, detail: .reduced)
        let after = rain.streaks(at: 10 + step, width: width, height: height, detail: .reduced)
        for (a, b) in zip(before, after) {
            var fallen = b.y0 - a.y0
            if fallen < 0 { fallen += height }
            XCTAssertTrue((0.85 * 220 * step - 1e-6...1.15 * 220 * step + 1e-6).contains(fallen), "\(fallen)")
            var drifted = b.x0 - a.x0
            if drifted < -width / 2 { drifted += width }
            XCTAssertEqual(drifted, fallen * 0.12, accuracy: 1e-6)
        }
    }

    /// Lightning flashes in a thunderstorm and a typhoon, as on the 2D
    /// map, never under plain rain.
    func testLightning() {
        let times = (0..<400).map { Double($0) * 0.05 }
        XCTAssertEqual(times.map(rain.flash).max(), 0)
        for sky in [MapWeather.Sky.thunderstorm, .typhoon] {
            let weather = MapWeather(sky: sky)
            XCTAssertEqual(times.map(Map3DRain(weather).flash), times.map(weather.flash))
            XCTAssertGreaterThan(times.map(Map3DRain(weather).flash).max() ?? 0, 0)
        }
    }

    /// PERF_3D_RAIN (2026-10-30): the 3D map makes the streaks' seeds
    /// once for a rain and a street detail; frames whose clock and camera
    /// move make none again, and hand the GPU the same 16 floats however
    /// many streaks fall. (Before, every frame of the `Canvas` over the
    /// map worked out all 480 to 720 streaks on the main thread.)
    func testFramesMakeNoStreaksOnceTheSeedsAreMade() {
        var drawing = Map3DRainDrawing()
        let typhoon = Map3DRain(MapWeather(sky: .typhoon))
        XCTAssertTrue(drawing.update(typhoon, detail: .full))
        XCTAssertEqual(drawing.count, 720)
        // Ten seconds at 60 frames, the cab's camera running along the
        // track: nothing the rain is made from changes.
        for frame in 0..<600 {
            XCTAssertFalse(drawing.update(typhoon, detail: .full))
            let uniforms = typhoon.uniforms(seconds: 1_000 + Double(frame) / 60, width: 402, height: 874, night: 0, flash: 0,
                                            count: drawing.count)
            XCTAssertEqual(uniforms.count, 16)
        }
        XCTAssertEqual(drawing.builds, 1)
        // The street detail stepping down, and the rain stopping, make
        // them again, once each.
        XCTAssertTrue(drawing.update(typhoon, detail: .reduced))
        XCTAssertEqual(drawing.count, 390)
        XCTAssertFalse(drawing.update(typhoon, detail: .reduced))
        XCTAssertTrue(drawing.update(.none, detail: .reduced))
        XCTAssertEqual(drawing.count, 0)
        XCTAssertEqual(drawing.builds, 3)
    }

    /// The GPU's streaks are the ones the `Canvas` drew: the shader's
    /// sums in `Float` (``Map3DRain/shaderStreak(_:of:uniforms:)``) land
    /// within a twentieth of a point of ``Map3DRain/streaks(at:width:height:detail:)``
    /// over the clock's whole period, so the rain still falls where, as
    /// fast and as long as before.
    func testTheGPUsStreaksAreTheCanvases() {
        let seeds = rain.seeds(.full)
        XCTAssertEqual(seeds.count, 480 * 4)
        for seconds in [0.0, 0.5, 37.25, 299.9, 599.98] {
            let uniforms = rain.uniforms(seconds: seconds, width: 402, height: 874, night: 0, flash: 0, count: 480)
            let streaks = rain.streaks(at: seconds, width: 402, height: 874, detail: .full)
            for (index, streak) in streaks.enumerated() {
                let gpu = Map3DRain.shaderStreak(index, of: seeds, uniforms: uniforms)
                // Across the edge the two may wrap to either side.
                let dx = abs(gpu.x0 - streak.x0), dy = abs(gpu.y0 - streak.y0)
                XCTAssertLessThan(min(dx, 402 - dx), 0.05, "\(seconds) \(index)")
                XCTAssertLessThan(min(dy, 874 - dy), 0.05, "\(seconds) \(index)")
                XCTAssertEqual(gpu.y1 - gpu.y0, streak.y1 - streak.y0, accuracy: 1e-4)
            }
        }
        // The clock the shader reads stays small, so a Float keeps it.
        XCTAssertEqual(Map3DRain.shaderSeconds(600 * 1_000_000 + 12.5), 12.5, accuracy: 1e-3)
        XCTAssertEqual(Map3DRain.shaderSeconds(-1), 599, accuracy: 1e-4)
    }

    /// What the shader reads: the screen, the clock, the slant, the
    /// streaks' look and the lightning's white at the 2D map's 0.35.
    func testTheUniformsCarryTheLook() {
        let storm = Map3DRain(MapWeather(sky: .thunderstorm))
        let day = storm.uniforms(seconds: 12, width: 402, height: 874, night: 0, flash: 1, count: 600)
        XCTAssertEqual(Array(day[0..<4]), [402, 874, 12, 0.12])
        XCTAssertEqual(day[4], Float(0x4A) / 255)
        XCTAssertEqual(day[5], Float(0x5A) / 255)
        XCTAssertEqual(day[6], Float(0x80) / 255)
        XCTAssertEqual(Double(day[7]), storm.look(night: 0).opacity, accuracy: 1e-6)
        XCTAssertEqual(Array(day[8..<12]), [1, 1, 1, 0.35])
        XCTAssertEqual(Array(day[12..<14]), [0.35, 600])
        let night = storm.uniforms(seconds: 12, width: 402, height: 874, night: 1, flash: 0, count: 600)
        XCTAssertEqual(night[4], Float(0xC6) / 255)
        XCTAssertEqual(night[11], 0)
    }

    /// The streaks are drawn when it rains, not on a clear day, with
    /// Reduce Motion or deep in a tunnel.
    func testWhenTheStreaksAreDrawn() {
        XCTAssertTrue(rain.drawsStreaks(reduceMotion: false, underground: false))
        XCTAssertFalse(rain.drawsStreaks(reduceMotion: true, underground: false))
        XCTAssertFalse(rain.drawsStreaks(reduceMotion: false, underground: true))
        XCTAssertFalse(Map3DRain.none.drawsStreaks(reduceMotion: false, underground: false))
        XCTAssertTrue(Map3DRain.none.seeds(.full).isEmpty)
    }

    /// PERF_3D_RAIN: what a frame of rain costs the main thread, before
    /// (every streak worked out and laid into a path, 60 times a second
    /// whatever the map drew) and now (16 floats a frame of the map), on
    /// a clear day, under rain and in a typhoon, the camera still and
    /// running along the track. Only the arithmetic: Linux has no
    /// SwiftUI `Canvas` to stroke the path, nor Metal. Opt in with
    /// `RAIN_COST_REPORT=<seconds of frames>`.
    func testRainCostReport() throws {
        guard let value = ProcessInfo.processInfo.environment["RAIN_COST_REPORT"], let seconds = Int(value), seconds > 0 else {
            throw XCTSkip("Set RAIN_COST_REPORT=<seconds> to measure the rain's main-thread work.")
        }
        let frames = seconds * 60
        func clock() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
        print("RAIN_COST_REPORT \(frames) frames at 60 a second, 402 x 874 points, street detail full")
        for (name, sky) in [("clear", MapWeather.Sky.clear), ("rain", .rain), ("typhoon", .typhoon)] {
            let rain = Map3DRain(MapWeather(sky: sky))
            for moving in [false, true] {
                // The cab's camera: the rain over the screen reads no
                // camera, so moving it changes nothing (the eye is moved
                // here only to say so).
                var eye = 0.0
                var points = 0, sink = 0.0
                var start = clock()
                for frame in 0..<frames {
                    if moving { eye += 25.0 / 60 }
                    let streaks = rain.streaks(at: Double(frame) / 60, width: 402, height: 874, detail: .full)
                    var path: [Double] = []
                    path.reserveCapacity(streaks.count * 4)
                    for streak in streaks { path += [streak.x0, streak.y0, streak.x1, streak.y1] }
                    points += path.count / 2
                    sink += path.last ?? 0
                }
                let before = Double(clock() - start) / Double(frames) / 1_000
                var drawing = Map3DRainDrawing()
                var floats = 0
                start = clock()
                for frame in 0..<frames {
                    if moving { eye += 25.0 / 60 }
                    _ = drawing.update(rain, detail: .full)
                    let uniforms = rain.uniforms(seconds: Double(frame) / 60, width: 402, height: 874, night: 0, flash: rain.flash(at: Double(frame) / 60),
                                                 count: drawing.count)
                    floats += uniforms.count
                    sink += Double(uniforms[2])
                }
                let after = Double(clock() - start) / Double(frames) / 1_000
                func ms(_ v: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", v) }
                print("  \(name), camera \(moving ? "moving" : "still"): before \(ms(before, 1)) µs a frame, \(points / frames) path points;"
                      + " now \(ms(after, 2)) µs, \(floats / frames) floats, seeds made \(drawing.builds) time(s) for \(drawing.count) streaks"
                      + (sink.isNaN || eye < 0 ? "?" : ""))
            }
        }
    }
}
