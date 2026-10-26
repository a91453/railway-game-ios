import Foundation
@testable import GamePresentation
import XCTest

/// Decision 417: one budget of triangles for what moves on the 3D map, and
/// the steps down and up under load.
final class Map3DMotionBudgetTests: XCTestCase {
    // MARK: The budget

    func testEachTierStartsWithItsOwnAndAStrongerOneDrawsMore() {
        XCTAssertNil(Map3DDeviceTier.forGPUFamily(4))
        XCTAssertEqual((5...7).map(Map3DDeviceTier.forGPUFamily), [.lower, .lower, .lower], "the A12–A14 and the M1")
        XCTAssertEqual(Map3DDeviceTier.forGPUFamily(8), .standard, "the A15–A16 and the M2")
        XCTAssertEqual(Map3DDeviceTier.forGPUFamily(9), .higher, "the A17 Pro, the M3 and on")
        XCTAssertEqual(Map3DDeviceTier.forGPUFamily(10), .higher)
        // Decision 259's, as before, on the lower two.
        XCTAssertEqual(Map3DDeviceTier.lower.streetLimits, Map3DStreetLimits(people: 500, vehicles: 150, buses: 10), "a third of the buses")
        XCTAssertEqual(Map3DDeviceTier.standard.streetLimits, Map3DStreetLimits(.full))
        let higher = Map3DDeviceTier.higher.streetLimits, standard = Map3DDeviceTier.standard.streetLimits
        XCTAssertGreaterThan(higher.people, standard.people)
        XCTAssertGreaterThan(higher.vehicles, standard.vehicles)
        XCTAssertGreaterThan(higher.buses, standard.buses)
        XCTAssertLessThan(Map3DDeviceTier.lower.triangles, Map3DDeviceTier.standard.triangles)
        XCTAssertLessThan(Map3DDeviceTier.standard.triangles, Map3DDeviceTier.higher.triangles)
    }

    func testWithFewTrainsTheStreetsDrawAll() {
        for tier in Map3DDeviceTier.allCases {
            XCTAssertEqual(Map3DMotionBudget(tier: tier).limits(), tier.streetLimits, "\(tier)")
            // A line or two of trains near the eye: still all.
            XCTAssertEqual(Map3DMotionBudget(tier: tier, trainTriangles: 30_000).limits(), tier.streetLimits, "\(tier)")
        }
        XCTAssertEqual(Map3DMotionBudget(tier: nil).limits(routeBuses: 3), Map3DStreetLimits(people: 0, vehicles: 3, buses: 3))
    }

    func testAStrongerDeviceKeepsItsStreetsWithMoreLines() {
        // Five lines of EMU3000s near the eye (the measured 400,000).
        let standard = Map3DMotionBudget(tier: .standard, trainTriangles: 400_000).limits(routeBuses: 10)
        let higher = Map3DMotionBudget(tier: .higher, trainTriangles: 400_000).limits(routeBuses: 10)
        XCTAssertLessThan(standard.vehicles, 10 + Map3DStreetDetail.full.vehicles)
        XCTAssertEqual(higher, Map3DStreetLimits(people: 2_000, vehicles: 610, buses: 45))
    }

    func testMoreTrainsLeaveTheStreetsFewerVehiclesFirstThenFewerPeople() {
        var last = Map3DStreetLimits(.full)
        var vehiclesFellBeforePeople = false
        for trains in stride(from: 0, through: 800_000, by: 20_000) {
            let limits = Map3DMotionBudget(tier: .standard, trainTriangles: trains).limits()
            XCTAssertLessThanOrEqual(limits.vehicles, last.vehicles, "\(trains)")
            XCTAssertLessThanOrEqual(limits.people, last.people, "\(trains)")
            XCTAssertLessThanOrEqual(limits.buses, last.buses, "\(trains)")
            if limits.vehicles < Map3DStreetDetail.full.vehicles, limits.people == Map3DStreetDetail.full.people { vehiclesFellBeforePeople = true }
            last = limits
        }
        XCTAssertTrue(vehiclesFellBeforePeople)
        // However many trains, a tenth of the streets stays.
        XCTAssertEqual(last, Map3DStreetLimits(people: 140, vehicles: 40, buses: 3))
    }

    func testThePlayersBusesAreNeverCutAndShareTheStreetsBuses() {
        // Ten of the player's buses, with room for all: the streets keep
        // 20 of their own 30 buses.
        let roomy = Map3DMotionBudget(tier: .standard).limits(routeBuses: 10)
        XCTAssertEqual(roomy.vehicles, 10 + Map3DStreetDetail.full.vehicles)
        XCTAssertEqual(roomy.buses, Map3DStreetLife.mostBuses)
        // However busy the lines, the player's buses are all drawn.
        let crowded = Map3DMotionBudget(tier: .standard, trainTriangles: 2_000_000).limits(routeBuses: 40)
        XCTAssertEqual(crowded.buses, 40)
        XCTAssertEqual(crowded.vehicles, 40 + 40)
        // A bus takes a car's room 15 times over.
        let one = Map3DMotionBudget(tier: .standard, trainTriangles: 470_000)
        XCTAssertLessThan(one.limits(routeBuses: 20).vehicles - 20, one.limits().vehicles)
    }

    func testAStepDownTakesAShareOfTheStreets() {
        let budget = Map3DMotionBudget(tier: .standard, step: .fewerOnStreets)
        XCTAssertEqual(budget.limits(), Map3DStreetLimits(people: 700, vehicles: 200, buses: 15))
        XCTAssertEqual(Map3DMotionBudget(tier: .standard, step: .fewerPixels).limits(), Map3DStreetLimits(people: 280, vehicles: 80, buses: 6))
        // The player's buses still all.
        XCTAssertEqual(Map3DMotionBudget(tier: .standard, step: .fewestOnStreets).limits(routeBuses: 7).buses, 7 + 5)
        // The A12–A14 leave the streets to the player's trains and buses.
        XCTAssertEqual(Map3DMotionBudget(tier: .lower, step: .fewerOnStreets).limits(), Map3DStreetLimits(people: 250, vehicles: 75, buses: 5))
        XCTAssertEqual(Map3DMotionBudget(tier: .lower, step: .fewestOnStreets).limits(routeBuses: 6), Map3DStreetLimits(people: 0, vehicles: 6, buses: 6))
    }

    func testTheTrainsTrianglesAreTheirModelsBoxesAndShadows() throws {
        let pack = Map3DModelPack.standard
        let head = try XCTUnwrap(pack.index(of: "set-emu3000-head"))
        var frame = Map3DTrains.Frame()
        frame.instances = [Map3DInstance(model: head, transform: [], stripe: (0, 0, 0)), Map3DInstance(model: head, transform: [], stripe: (0, 0, 0))]
        frame.boxes.addBox(base: .zero, forward: Map3DPoint(1, 0, 0), length: 20, width: 3, height: 3, top: 0, side: 0)
        XCTAssertEqual(frame.triangles(in: pack), 2 * pack.models[head].triangleCount + frame.boxes.triangleCount)
        XCTAssertEqual(frame.triangles(in: nil), frame.boxes.triangleCount)
    }

    // MARK: The trains' far models

    func testSteppedDownTheFarModelsAndBoxesComeNearer() throws {
        let pack = Map3DModelPack.standard
        let head = try XCTUnwrap(pack.index(of: "set-emu3000-head"))
        let far = try XCTUnwrap(pack.index(of: "set-emu3000Far-head"))
        let reach = Map3DTrainSet.reach(of: "EMU3000")
        // In full, as before (decision 408).
        XCTAssertEqual(pack.model(head, forType: "EMU3000", count: 8, at: reach - 1), head)
        XCTAssertEqual(pack.model(head, forType: "EMU3000", count: 8, at: reach + 1), far)
        XCTAssertNil(pack.model(head, forType: "EMU3000", count: 8, at: Map3DTrains.modelReach + 1))
        // Stepped down: the far model from half as far, a box from 0.8.
        let nearer = Map3DLoadStep.nearerFarModels.reach(on: .standard)
        XCTAssertEqual(pack.model(head, forType: "EMU3000", count: 8, at: reach * 0.5 - 1, reach: nearer), head)
        XCTAssertEqual(pack.model(head, forType: "EMU3000", count: 8, at: reach * 0.5 + 1, reach: nearer), far)
        XCTAssertNil(pack.model(head, forType: "EMU3000", count: 8, at: Map3DTrains.modelReach * 0.8 + 1, reach: Map3DLoadStep.fewerPixels.reach(on: .higher)))
        // The steps before leave the trains alone.
        XCTAssertEqual(Map3DLoadStep.fewestOnStreets.reach(on: .standard), .standard)
        XCTAssertEqual(Map3DLoadStep.fewestOnStreets.reach(on: nil), .standard)
    }

    func testAStrongerDeviceKeepsItsModelsFarther() throws {
        let pack = Map3DModelPack.standard
        let head = try XCTUnwrap(pack.index(of: "set-emu3000-head"))
        let far = try XCTUnwrap(pack.index(of: "set-emu3000Far-head"))
        let reach = Map3DTrainSet.reach(of: "EMU3000")
        let higher = Map3DLoadStep.full.reach(on: .higher)
        XCTAssertEqual(pack.model(head, forType: "EMU3000", count: 8, at: reach * 1.5 - 1, reach: higher), head)
        XCTAssertEqual(pack.model(head, forType: "EMU3000", count: 8, at: reach * 1.5 + 1, reach: higher), far)
        XCTAssertEqual(pack.model(head, forType: "EMU3000", count: 8, at: Map3DTrains.modelReach * 1.25 - 1, reach: higher), far)
        XCTAssertNil(pack.model(head, forType: "EMU3000", count: 8, at: Map3DTrains.modelReach * 1.25 + 1, reach: higher))
        // A car with no far model: a box where it was.
        let puyuma = try XCTUnwrap(pack.index(of: "set-puyuma-head"))
        XCTAssertNil(pack.model(puyuma, forType: "puyuma", count: 8, at: Map3DTrains.modelReach + 1, reach: higher))
    }

    func testACarWithNoFarModelKeepsItsOwnAsFarAsBefore() throws {
        let pack = Map3DModelPack.standard
        let head = try XCTUnwrap(pack.index(of: "set-puyuma-head"))
        let reach = Map3DTrainSet.reach(of: "puyuma")
        let nearer = Map3DLoadStep.nearerFarModels.reach(on: .standard)
        XCTAssertEqual(pack.model(head, forType: "puyuma", count: 8, at: reach * 0.7, reach: nearer), head)
        XCTAssertEqual(pack.model(head, forType: "puyuma", count: 8, at: Map3DTrains.modelReach * 0.8 - 1, reach: nearer), head)
        XCTAssertNil(pack.model(head, forType: "puyuma", count: 8, at: Map3DTrains.modelReach * 0.8 + 1, reach: nearer))
    }

    // MARK: Stepping down and up

    static let heavy = Map3DLoadGovernor.Sample(framesPerSecond: 38, aim: 60, gpuMilliseconds: 8, drawingStreets: true)
    static let middling = Map3DLoadGovernor.Sample(framesPerSecond: 52, aim: 60, gpuMilliseconds: 8, drawingStreets: true)
    static let light = Map3DLoadGovernor.Sample(framesPerSecond: 60, aim: 60, gpuMilliseconds: 5, drawingStreets: true)

    func testWhatIsHeavyAndWhatIsLight() {
        XCTAssertTrue(Self.heavy.isHeavy)
        XCTAssertFalse(Self.heavy.isLight)
        XCTAssertFalse(Self.middling.isHeavy)
        XCTAssertFalse(Self.middling.isLight)
        XCTAssertTrue(Self.light.isLight)
        // The frames kept, but the GPU over its 10 ms.
        XCTAssertTrue(Map3DLoadGovernor.Sample(framesPerSecond: 60, aim: 60, gpuMilliseconds: 11, drawingStreets: true).isHeavy)
        // The frames kept, the GPU within its budget but not well within.
        XCTAssertFalse(Map3DLoadGovernor.Sample(framesPerSecond: 60, aim: 60, gpuMilliseconds: 8, drawingStreets: true).isLight)
        // At 30 a second (Saving, Low Power Mode).
        XCTAssertTrue(Map3DLoadGovernor.Sample(framesPerSecond: 21, aim: 30, gpuMilliseconds: 8, drawingStreets: true).isHeavy)
        XCTAssertTrue(Map3DLoadGovernor.Sample(framesPerSecond: 30, aim: 30, gpuMilliseconds: 12, drawingStreets: true).isLight)
    }

    /// A level, as `tier streets drawing`.
    static func level(_ governor: Map3DLoadGovernor) -> String {
        let level = governor.level
        return "\(level.tier) \(level.streets) \(level.drawing)"
    }

    /// The CPU behind (the street life's work), the GPU behind alone, and
    /// both, at 60 frames a second (10 ms each's share).
    static let cpuBound = Map3DLoadGovernor.Sample(framesPerSecond: 38, aim: 60, cpuMilliseconds: 14, gpuMilliseconds: 6, drawingStreets: true)
    static let gpuBound = Map3DLoadGovernor.Sample(framesPerSecond: 38, aim: 60, cpuMilliseconds: 5, gpuMilliseconds: 14, drawingStreets: true)
    static let bothBound = Map3DLoadGovernor.Sample(framesPerSecond: 38, aim: 60, cpuMilliseconds: 14, gpuMilliseconds: 14, drawingStreets: true)

    func testTheLadderGoesThroughTheLowerTiersStreetsToEachTiersFull() {
        XCTAssertEqual(Map3DLoadLevel.all.map { "\($0.tier) \($0.streets)" }, [
            "lower fewestOnStreets", "lower fewerOnStreets", "lower full", "standard full", "higher full",
        ])
        XCTAssertEqual(Map3DDeviceTier.allCases.map(Map3DLoadLevel.top(of:)), [2, 3, 4])
        XCTAssertEqual(Map3DLoadLevel(tier: .higher, streets: .full).reach, Map3DModelReach(farModel: 1.5, box: 1.25))
        XCTAssertEqual(Map3DLoadLevel(tier: .higher, streets: .full, drawing: .nearerFarModels).reach, Map3DModelReach(farModel: 0.5, box: 0.8))
        XCTAssertEqual(Map3DLoadLevel(tier: .standard, streets: .full).summary, "standard full · 600000 triangles")
        XCTAssertEqual(Map3DLoadLevel(tier: .lower, streets: .fewestOnStreets, drawing: .fewerPixels).summary,
                       "lower fewestOnStreets fewerPixels · 250000 triangles")
    }

    func testWhatIsBehindTheCPUOrTheGPU() {
        XCTAssertTrue(Self.cpuBound.isCPUOver)
        XCTAssertFalse(Self.cpuBound.isGPUOver)
        XCTAssertFalse(Self.cpuBound.sparesTheGPUFirst)
        XCTAssertTrue(Self.gpuBound.sparesTheGPUFirst)
        XCTAssertFalse(Self.bothBound.sparesTheGPUFirst, "both: the order")
        // Not known (no times yet): the order.
        XCTAssertFalse(Self.heavy.sparesTheGPUFirst)
        XCTAssertFalse(Map3DLoadGovernor.Sample(framesPerSecond: 38, aim: 60, gpuMilliseconds: 0, drawingStreets: true).isGPUOver)
        // At 30 frames a second the shares are 20 ms.
        XCTAssertFalse(Map3DLoadGovernor.Sample(framesPerSecond: 20, aim: 30, cpuMilliseconds: 14, gpuMilliseconds: 6, drawingStreets: true).isCPUOver)
    }

    func testItStepsDownInOrderAfterThreeHeavyHalfSeconds() {
        for sample in [Self.heavy, Self.cpuBound, Self.bothBound] {
            var governor = Map3DLoadGovernor()
            var levels: [String] = []
            for _ in 0..<30 {
                if governor.record(sample) { levels.append(Self.level(governor)) }
            }
            XCTAssertEqual(levels, [
                "standard full full", "lower full full", "lower fewerOnStreets full", "lower fewestOnStreets full",
                "lower fewestOnStreets nearerFarModels", "lower fewestOnStreets fewerPixels",
            ], "\(sample)")
        }
        // Two heavy half seconds and a middling one: no step.
        var other = Map3DLoadGovernor()
        for sample in [Self.heavy, Self.heavy, Self.middling, Self.heavy, Self.heavy] { XCTAssertFalse(other.record(sample)) }
        XCTAssertEqual(other.rung, 4)
    }

    func testTheGPUBehindAloneSparesTheGPUBeforeTheStreets() {
        var governor = Map3DLoadGovernor(top: 3)
        var levels: [String] = []
        for _ in 0..<30 {
            if governor.record(Self.gpuBound) { levels.append(Self.level(governor)) }
        }
        XCTAssertEqual(levels, [
            "standard full nearerFarModels", "standard full fewerPixels", "lower full fewerPixels", "lower fewerOnStreets fewerPixels",
            "lower fewestOnStreets fewerPixels",
        ])
        // Back up the last way down first: the pixels, then the far models,
        // then the streets.
        var back = Map3DLoadGovernor(top: 3)
        for _ in 0..<6 { back.record(Self.gpuBound) }
        XCTAssertEqual(Self.level(back), "standard full fewerPixels")
        for _ in 0..<20 { back.record(Self.light) }
        XCTAssertEqual(Self.level(back), "standard full nearerFarModels")
        for _ in 0..<20 { back.record(Self.light) }
        XCTAssertEqual(Self.level(back), "standard full full")
    }

    func testWithNothingOnTheStreetsItSparesTheGPUFirst() {
        var governor = Map3DLoadGovernor(top: 3)
        var away = Self.cpuBound
        away.drawingStreets = false
        for _ in 0..<3 { governor.record(away) }
        XCTAssertEqual(Self.level(governor), "standard full nearerFarModels")
    }

    func testALookThatKeepsItsPixelsStopsAtTheTrains() {
        var governor = Map3DLoadGovernor()
        governor.deepest = Map3DLoadGovernor.deepest(lowersWhenOver: false)
        for _ in 0..<60 { governor.record(Self.heavy) }
        XCTAssertEqual(Self.level(governor), "lower fewestOnStreets nearerFarModels")
        var lowered = Map3DLoadGovernor()
        for _ in 0..<60 { lowered.record(Self.gpuBound) }
        XCTAssertEqual(lowered.level.drawing, .fewerPixels)
        lowered.deepest = Map3DLoadGovernor.deepest(lowersWhenOver: false)
        XCTAssertEqual(lowered.level.drawing, .nearerFarModels)
    }

    func testOnAutomaticItStartsLowAndClimbsToItsOwnTier() {
        for (device, start, climbed) in [(Map3DDeviceTier.lower, "lower fewestOnStreets full", 2), (.standard, "lower full full", 1),
                                         (.higher, "standard full full", 1)] {
            var governor = Map3DLoadGovernor(top: Map3DLoadLevel.top(of: device), start: Map3DLoadGovernor.start(for: .automatic, device: device))
            XCTAssertEqual(Self.level(governor), start, "\(device)")
            var steps = 0
            for _ in 0..<1_000 where governor.record(Self.light) { steps += 1 }
            XCTAssertEqual(steps, climbed, "\(device)")
            XCTAssertEqual(governor.rung, Map3DLoadLevel.top(of: device), "no higher than its own tier")
        }
    }

    func testBatterySaverAndHighQualityStartAtTheirTop() {
        for device in Map3DDeviceTier.allCases {
            XCTAssertEqual(Map3DLoadGovernor.start(for: .saving, device: device), 2)
            XCTAssertEqual(Map3DLoadGovernor.start(for: .off, device: device), 2)
            XCTAssertEqual(Map3DLoadGovernor.start(for: .high, device: device), 4)
        }
        XCTAssertEqual(Map3DLoadGovernor.start(for: .automatic, device: nil), 0)
    }

    func testTheDeviceRemembersWhereItGotToForTheLookAndTheSystem() {
        let kept = Map3DLoadGovernor.remembering(3, quality: .automatic, system: "26.1")
        XCTAssertEqual(Map3DLoadGovernor.remembered(kept, quality: .automatic, system: "26.1"), 3)
        XCTAssertEqual(Map3DLoadGovernor.start(for: .automatic, device: .standard, remembered: 3), 3)
        XCTAssertEqual(Map3DLoadGovernor.start(for: .automatic, device: .lower, remembered: 3), 2, "no higher than its tier")
        // Another look or another system: climbs again.
        XCTAssertNil(Map3DLoadGovernor.remembered(kept, quality: .high, system: "26.1"))
        XCTAssertNil(Map3DLoadGovernor.remembered(kept, quality: .automatic, system: "26.2"))
        XCTAssertNil(Map3DLoadGovernor.remembered(nil, quality: .automatic, system: "26.1"))
        XCTAssertNil(Map3DLoadGovernor.remembered("automatic|26.1|9", quality: .automatic, system: "26.1"))
        XCTAssertNil(Map3DLoadGovernor.remembered("rubbish", quality: .automatic, system: "26.1"))
        // Only Automatic starts where it got to.
        XCTAssertEqual(Map3DLoadGovernor.start(for: .high, device: .standard, remembered: 1), 4)
        // And a problem report says so.
        XCTAssertEqual(Map3DLoadGovernor.report(kept), "automatic, standard full · 600000 triangles")
        XCTAssertNil(Map3DLoadGovernor.report(nil))
        let report = ProblemReport(version: "1", build: "2", system: "iOS", device: "iPhone18,1", map3D: Map3DLoadGovernor.report(kept))
        XCTAssertTrue(report.text(in: .english).hasSuffix("3D map: automatic, standard full · 600000 triangles"))
        XCTAssertTrue(report.text(in: .traditionalChinese).hasSuffix("3D 地圖：automatic, standard full · 600000 triangles"))
    }

    func testItStepsBackUpAfterTenLightSecondsAndNotBetween() {
        var governor = Map3DLoadGovernor()
        for _ in 0..<3 { governor.record(Self.heavy) }
        XCTAssertEqual(governor.rung, 3)
        for _ in 0..<19 { XCTAssertFalse(governor.record(Self.light)) }
        // A middling half second starts the count again.
        governor.record(Self.middling)
        for _ in 0..<19 { governor.record(Self.light) }
        XCTAssertEqual(governor.rung, 3)
        XCTAssertTrue(governor.record(Self.light))
        XCTAssertEqual(governor.rung, 4)
        // Already at the top: no further.
        for _ in 0..<100 { XCTAssertFalse(governor.record(Self.light)) }
    }

    func testAStepUpTakenBackSoonWaitsTwiceAsLongNextTime() {
        var governor = Map3DLoadGovernor()
        func down() { for _ in 0..<3 { governor.record(Self.heavy) } }
        func lightUntilUp() -> Int {
            var windows = 0
            while governor.rung < governor.top, windows < 1_000 {
                governor.record(Self.light)
                windows += 1
            }
            return windows
        }
        down()
        XCTAssertEqual(lightUntilUp(), 20)
        // Heavy again 1.5 s after the step up: next time 20 s.
        down()
        XCTAssertEqual(lightUntilUp(), 40)
        down()
        XCTAssertEqual(lightUntilUp(), 80)
        down()
        XCTAssertEqual(lightUntilUp(), 160)
        down()
        XCTAssertEqual(lightUntilUp(), 240, "at most 2 minutes")
        // Heavy only long after the step up: no longer.
        for _ in 0..<Map3DLoadGovernor.relapseWindows { governor.record(Self.middling) }
        down()
        XCTAssertEqual(lightUntilUp(), 240)
    }

    // MARK: The look in Settings

    func testTheLookPicksTheTier() {
        for device in Map3DDeviceTier.allCases {
            XCTAssertEqual(Map3DQuality.automatic.tier(device: device), device)
            XCTAssertEqual(Map3DQuality.saving.tier(device: device), .lower)
            XCTAssertEqual(Map3DQuality.off.tier(device: device), .lower)
            XCTAssertEqual(Map3DQuality.high.tier(device: device), .higher)
        }
        for quality in Map3DQuality.allCases { XCTAssertNil(quality.tier(device: nil), "\(quality)") }
    }

    func testEachLookSaysInALineWhatItGives() {
        XCTAssertEqual(Map3DQuality.saving.explanation(in: .traditionalChinese), "每秒 30 格、陰影與街景較少，比較不燙、比較省電。")
        XCTAssertEqual(Map3DQuality.automatic.explanation(in: .traditionalChinese), "依手機的能力調整，順的時候畫得多、卡的時候少一點。")
        XCTAssertEqual(Map3DQuality.high.explanation(in: .traditionalChinese), "畫面最豐富，手機可能發燙、耗電。")
        for quality in Map3DQuality.allCases {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                let line = quality.explanation(in: language)
                XCTAssertLessThanOrEqual(line.count, 110, "\(quality) \(language)")
                for word in ["triangle", "LOD", "antialias", "tier", "GPU", "三角形", "反鋸齒", "預算"] {
                    XCTAssertFalse(line.localizedCaseInsensitiveContains(word), "\(quality) \(language): \(word)")
                }
            }
        }
        XCTAssertEqual(Map3DQuality.allCases.map { $0.name(in: .traditionalChinese) }, ["自動", "省電", "高畫質", "關"])
    }

    func testHighQualityStepsDownOnlyForMemoryAndHeat() {
        var governor = Map3DLoadGovernor(start: Map3DLoadGovernor.start(for: .high, device: .standard))
        governor.deepest = Map3DLoadGovernor.deepest(lowersWhenOver: false)
        governor.stepsDownForLoad = false
        for _ in 0..<30 { XCTAssertFalse(governor.record(Self.heavy)) }
        XCTAssertEqual(governor.rung, 4)
        // The system warns of memory: two steps at once, and the next step
        // up later than at first.
        governor.relieve()
        XCTAssertEqual(Self.level(governor), "lower full full")
        XCTAssertEqual(governor.raiseWindows, 2 * Map3DLoadGovernor.firstRaiseWindows)
        governor.relieve()
        governor.relieve()
        XCTAssertEqual(Self.level(governor), "lower fewestOnStreets nearerFarModels", "no further than its deepest")
        // Light again: back up, a step at a time.
        for _ in 0..<(8 * Map3DLoadGovernor.firstRaiseWindows) { governor.record(Self.light) }
        XCTAssertEqual(Self.level(governor), "lower fewestOnStreets full")
        // Too hot: no higher than the lower tier's fewest on the streets.
        var hot = Map3DLoadGovernor()
        hot.highest = Map3DLoadGovernor.highest(heat: .critical)
        XCTAssertEqual(Self.level(hot), "lower fewestOnStreets full")
        for _ in 0..<1_000 { hot.record(Self.light) }
        XCTAssertEqual(hot.rung, 0)
        hot.highest = Map3DLoadGovernor.highest(heat: .serious)
        for _ in 0..<1_000 { hot.record(Self.light) }
        XCTAssertEqual(hot.rung, 4)
    }

    // MARK: Measured

    /// The triangles of the trains near the eye, as a frame draws them,
    /// against what the budget leaves the streets: `lines` lines with two
    /// trains each of `cars` cars within the trains' models' reach (one
    /// each way), their cars spread from 50 m to 850 m from the eye, and
    /// two of the player's buses a bus route (decision 400's measure:
    /// 9 buses a route, one every 5 minutes). Only on request:
    /// `MOTION_BUDGET_REPORT=1`.
    func testTheBudgetByLines() throws {
        guard ProcessInfo.processInfo.environment["MOTION_BUDGET_REPORT"] != nil else { throw XCTSkip("Set MOTION_BUDGET_REPORT=1.") }
        let pack = Map3DModelPack.standard
        var rows = ["| Tier | Type | Lines | Bus routes | Step | Train triangles | People | Vehicles | Buses | Moving triangles |",
                    "| --- | --- | --: | --: | --- | --: | --: | --: | --: | --: |"]
        for (type, cars) in [("EMU3000", 8), ("HSR", 12), ("A", 6)] {
            let laid = try XCTUnwrap(Map3DTrainSet.set(forKey: type, count: cars, locked: []))
            let models = (0..<cars).compactMap { pack.modelIndex(forType: type, carIndex: $0, count: cars) }
            XCTAssertEqual(models.count, cars, laid.key)
            for tier in Map3DDeviceTier.allCases {
            for (lines, routes) in [(1, 1), (2, 2), (5, 5), (10, 10), (20, 20)] {
                for step in [Map3DLoadStep.full, .nearerFarModels] {
                    var trains = 0
                    for train in 0..<(2 * lines) {
                        for (car, near) in models.enumerated() {
                            let distance = 50 + Float((train * cars + car) % 16) * 50
                            trains += pack.model(near, forType: type, count: cars, at: distance, reach: step.reach(on: tier))
                                .map { pack.models[$0].triangleCount } ?? 20
                        }
                    }
                    let buses = 2 * routes
                    let limits = Map3DMotionBudget(tier: tier, step: step, trainTriangles: trains).limits(routeBuses: buses)
                    let moving = trains + limits.people * Map3DMotionBudget.personTriangles
                        + (limits.vehicles - limits.buses) * Map3DMotionBudget.vehicleTriangles + limits.buses * Map3DMotionBudget.busTriangles
                    rows.append("| \(tier) | \(type) ×\(cars) | \(lines) | \(routes) | \(step) | \(trains) | \(limits.people) | \(limits.vehicles) | \(limits.buses) | \(moving) |")
                }
            }
            }
        }
        print(rows.joined(separator: "\n"))
    }

    /// TestFlight 87.1 (an iPhone 17 closing often, no crash report: the
    /// system closing it for memory, as decision 368's): what the 3D map
    /// keeps, against what decision 417's budget changes. The models (on
    /// the GPU once), a frame's moving things (the street life's three
    /// buffers, the trains' boxes of 20 lines) and the whole Taipei scene
    /// (its meshes, on the GPU once more). Only on request:
    /// `MOTION_BUDGET_REPORT=1`.
    func testWhatTheMapKeepsInMemory() throws {
        guard ProcessInfo.processInfo.environment["MOTION_BUDGET_REPORT"] != nil else { throw XCTSkip("Set MOTION_BUDGET_REPORT=1.") }
        func megabytes(_ bytes: Int) -> String { String(format: "%.1f MB", Double(bytes) / 1_000_000) }
        let vertex = MemoryLayout<Map3DVertex>.stride
        let models = Map3DModelPack.standard.models.reduce(0) { $0 + $1.vertices.count * vertex }
        // `Map3DMetalView.instanceStride`, three buffers of the higher tier's most.
        let most = Map3DDeviceTier.higher.streetLimits
        let life = 3 * (most.people + most.vehicles + most.buses) * 80
        let scene = try Map3DFrameCostReportTests.taipeiScene()
        var meshes = 0
        for chunk in scene.chunks {
            for mesh in [chunk.mesh, chunk.far, chunk.close, chunk.standIn, chunk.shadows] {
                meshes += mesh.vertices.count * vertex + mesh.indices.count * MemoryLayout<UInt32>.stride
            }
        }
        print("""
            | What | Memory |
            | --- | --: |
            | The models (\(Map3DModelPack.standard.models.count)) | \(megabytes(models)) |
            | Street life's three buffers, the higher tier's most | \(megabytes(life)) |
            | The Taipei scene's meshes (\(scene.chunks.count) chunks) | \(megabytes(meshes)) |
            """)
    }
}
