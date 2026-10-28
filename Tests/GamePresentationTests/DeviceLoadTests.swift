import GameCore
@testable import GamePresentation
import XCTest

/// Decision 460: the device's memory and CPU tiers, what they set, and the
/// game loop's pace.
final class DeviceLoadTests: XCTestCase {
    private let gib: UInt64 = 1 << 30

    /// What `ProcessInfo.physicalMemory` tells, a little under the box's.
    func testTheMemoryTierOfEachDevice() {
        let devices: [(String, Double, DeviceMemoryTier)] = [
            ("iPhone XR, 3 GB", 2.8, .tight), ("iPhone 12, 4 GB", 3.7, .tight), ("iPhone 13 mini, 4 GB", 3.7, .tight),
            ("iPhone 12 Pro, 6 GB", 5.6, .roomy), ("iPhone 15, 6 GB", 5.6, .roomy),
            ("iPhone 15 Pro, 8 GB", 7.5, .ample), ("iPad Pro M1, 16 GB", 15.6, .ample),
        ]
        for (name, gigabytes, tier) in devices {
            XCTAssertEqual(DeviceMemoryTier.forPhysicalMemory(UInt64(gigabytes * Double(gib))), tier, name)
        }
    }

    /// The app's own limit, when the system tells it, takes the lower.
    func testTheAppsLimitTakesTheLower() {
        let six = UInt64(5.6 * Double(gib))
        // A 6 GB phone that lets the app use 2.2 GB (other apps open).
        XCTAssertEqual(DeviceMemoryTier.of(physical: six, limit: DeviceMemoryTier.limit(footprint: 700 << 20, available: 1_500 << 20)), .tight)
        XCTAssertEqual(DeviceMemoryTier.of(physical: six, limit: DeviceMemoryTier.limit(footprint: 700 << 20, available: 2_300 << 20)), .roomy)
        // Never higher than the device.
        XCTAssertEqual(DeviceMemoryTier.of(physical: 3 * gib + gib / 2, limit: 5 << 30), .tight)
        // The Simulator tells nothing left: the device's alone.
        XCTAssertNil(DeviceMemoryTier.limit(footprint: 700 << 20, available: 0))
        XCTAssertNil(DeviceMemoryTier.limit(footprint: nil, available: 1 << 30))
        XCTAssertEqual(DeviceMemoryTier.of(physical: six, limit: nil), .roomy)
    }

    func testWhatTheMemoryTierSets() {
        XCTAssertFalse(DeviceMemoryTier.tight.keepsSceneBuilt)
        XCTAssertTrue(DeviceMemoryTier.roomy.keepsSceneBuilt)
        XCTAssertTrue(DeviceMemoryTier.ample.keepsSceneBuilt)
        XCTAssertEqual(DeviceMemoryTier.allCases.filter(\.startsLower), [.tight])
    }

    /// Automatic starts a rung lower on a device of little memory, but
    /// where it got to last time stands; the other looks are unchanged.
    func testAutomaticStartsLowerWithLittleMemory() {
        let standardTop = Map3DLoadLevel.top(of: .standard)
        XCTAssertEqual(Map3DLoadGovernor.start(for: .automatic, device: .standard), standardTop - 1)
        XCTAssertEqual(Map3DLoadGovernor.start(for: .automatic, device: .standard, memory: .roomy), standardTop - 1)
        XCTAssertEqual(Map3DLoadGovernor.start(for: .automatic, device: .standard, memory: .tight), standardTop - 2)
        XCTAssertEqual(Map3DLoadGovernor.start(for: .automatic, device: .lower, memory: .tight), 0)
        XCTAssertEqual(Map3DLoadGovernor.start(for: .automatic, device: .higher, memory: .tight), Map3DLoadLevel.top(of: .higher) - 2)
        XCTAssertEqual(Map3DLoadGovernor.start(for: .automatic, device: .standard, remembered: standardTop, memory: .tight), standardTop)
        XCTAssertEqual(Map3DLoadGovernor.start(for: .high, device: .standard, memory: .tight), Map3DLoadLevel.top(of: .higher))
        XCTAssertEqual(Map3DLoadGovernor.start(for: .saving, device: .standard, memory: .tight), Map3DLoadLevel.top(of: .lower))
    }

    /// Below 300 MB left a step down at once, then not again for ten
    /// seconds however low; above it nothing.
    func testTheMemoryWatchStepsDownBeforeTheWarning() {
        var watch = Map3DMemoryWatch()
        XCTAssertFalse(watch.record(available: 800 << 20))
        XCTAssertFalse(watch.record(available: nil))
        XCTAssertFalse(watch.record(available: 0))
        XCTAssertTrue(watch.record(available: 250 << 20))
        for _ in 1..<Map3DMemoryWatch.waitWindows {
            XCTAssertFalse(watch.record(available: 100 << 20))
        }
        XCTAssertTrue(watch.record(available: 100 << 20))
        // And with the governor: one step down in its order.
        var governor = Map3DLoadGovernor(top: Map3DLoadLevel.top(of: .standard))
        governor.relieve()
        XCTAssertLessThan(governor.rung, Map3DLoadLevel.top(of: .standard))
    }

    func testTheCPUTierOfEachChip() {
        // Apple GPU family 5 = A12, 7 = A14 and M1, 8 = A15–A16 and M2, 9 = A17 Pro, M3 on.
        XCTAssertEqual(DeviceCPUTier.of(gpuFamily: 5, cores: 6), .lower)
        XCTAssertEqual(DeviceCPUTier.of(gpuFamily: 7, cores: 6), .lower)
        XCTAssertEqual(DeviceCPUTier.of(gpuFamily: 7, cores: 8), .standard, "the M1 iPad")
        XCTAssertEqual(DeviceCPUTier.of(gpuFamily: 8, cores: 6), .standard)
        XCTAssertEqual(DeviceCPUTier.of(gpuFamily: 9, cores: 6), .higher)
        XCTAssertEqual(DeviceCPUTier.of(gpuFamily: 10, cores: 10), .higher)
    }

    /// Ticks that keep up rest the interval as always; slow ones rest so
    /// the loop works at most its share, never longer than two seconds.
    func testTheLoopRestsByTheDevicesShare() {
        let interval = GameSession.tickInterval
        for tier in DeviceCPUTier.allCases {
            XCTAssertEqual(TickPace(cpu: tier).rest(afterWorking: .milliseconds(20), interval: interval), interval, "\(tier)")
            XCTAssertEqual(TickPace(cpu: tier).rest(afterWorking: .zero, interval: interval), interval, "\(tier)")
        }
        // Five ticks of 240 ms (92.1's game at 6000×).
        let work = Duration.milliseconds(1_200)
        XCTAssertEqual(TickPace(cpu: .higher).rest(afterWorking: work, interval: interval), interval)
        XCTAssertEqual(TickPace(cpu: .standard).rest(afterWorking: work, interval: interval), .milliseconds(300))
        XCTAssertEqual(TickPace(cpu: .lower).rest(afterWorking: work, interval: interval), .milliseconds(800))
        // Hot: the higher one rests too.
        XCTAssertEqual(TickPace(cpu: .higher, heat: .serious).rest(afterWorking: work, interval: interval), .milliseconds(800))
        XCTAssertEqual(TickPace(cpu: .higher, heat: .critical).rest(afterWorking: work, interval: interval), .milliseconds(1_800))
        XCTAssertEqual(TickPace(cpu: .standard, heat: .fair).busiestShare, 0.8)
        // The day's first plan, 14 s: two seconds, not nine.
        XCTAssertEqual(TickPace(cpu: .lower).rest(afterWorking: .seconds(14), interval: interval), TickPace.longestRest)
    }

    /// The share of real time the loop works is the pace's, and so how far
    /// the game falls behind its speed: with each tick taking `tick`, a
    /// step of five ticks.
    func testTheShareTheLoopWorks() {
        let interval = GameSession.tickInterval
        for (pace, tick, share) in [(TickPace(cpu: .lower), 240, 0.6), (TickPace(cpu: .standard), 240, 0.8), (TickPace(cpu: .higher), 240, 0.92),
                                    (TickPace(cpu: .lower), 10, 0.33)] {
            let work = Duration.milliseconds(5 * tick)
            let rest = pace.rest(afterWorking: work, interval: interval)
            let worked = work / (work + rest)
            XCTAssertEqual(worked, share, accuracy: 0.01, "\(pace.cpu) at \(tick) ms a tick")
        }
    }

    func testTheReportsLine() {
        let line = deviceLoadSummary(memory: .tight, physical: UInt64(3.7 * Double(gib)), limit: 2 * gib + gib / 10,
                                     pace: TickPace(cpu: .lower))
        XCTAssertEqual(line, "memory tight (3.7 GB, the app's limit 2.1 GB) · CPU lower, ticks at most 60% of the time")
        XCTAssertEqual(deviceLoadSummary(memory: .ample, physical: 8 * gib, limit: nil, pace: TickPace(cpu: .higher, heat: .serious)),
                       "memory ample (8.0 GB) · CPU higher, ticks at most 60% of the time")
        let context = FrameTimeContext(screen: .map2D, speed: "fast", stations: 81, lines: 22, device: "memory tight")
        XCTAssertTrue(context.text(in: .english).hasSuffix(" · device memory tight"))
        XCTAssertTrue(context.text(in: .traditionalChinese).hasSuffix(" · 裝置 memory tight"))
    }
}
