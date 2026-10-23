@testable import GamePresentation
import XCTest

final class Map3DQualityTests: XCTestCase {
    func testAutomaticIsTheSharpestUntilLowPowerOrHeat() {
        let sharp = Map3DQuality.Plan(framesPerSecond: 60, fewerPixels: false, lowersWhenOver: true)
        let saving = Map3DQuality.Plan(framesPerSecond: 30, fewerPixels: true, lowersWhenOver: true)
        XCTAssertEqual(Map3DQuality.automatic.plan(lowPower: false, heat: .nominal), sharp)
        XCTAssertEqual(Map3DQuality.automatic.plan(lowPower: false, heat: .fair), sharp)
        XCTAssertEqual(Map3DQuality.automatic.plan(lowPower: true, heat: .nominal), saving)
        XCTAssertEqual(Map3DQuality.automatic.plan(lowPower: false, heat: .serious), saving)
        XCTAssertEqual(Map3DQuality.automatic.plan(lowPower: false, heat: .critical), saving)
    }

    func testSavingAlwaysSaves() {
        for heat in [Map3DQuality.Heat.nominal, .critical] {
            XCTAssertEqual(Map3DQuality.saving.plan(lowPower: false, heat: heat),
                           Map3DQuality.Plan(framesPerSecond: 30, fewerPixels: true, lowersWhenOver: true))
        }
    }

    func testHighNeverLowersButWhenThePhoneIsAboutToSlowItselfDown() {
        for heat in [Map3DQuality.Heat.nominal, .fair, .serious] {
            for lowPower in [false, true] {
                XCTAssertEqual(Map3DQuality.high.plan(lowPower: lowPower, heat: heat),
                               Map3DQuality.Plan(framesPerSecond: 60, fewerPixels: false, lowersWhenOver: false))
            }
        }
        XCTAssertTrue(Map3DQuality.high.plan(lowPower: false, heat: .critical).fewerPixels)
    }

    func testTheChoiceIsKeptByName() {
        XCTAssertEqual(Map3DQuality.allCases.map(\.rawValue), ["automatic", "saving", "high", "off"])
        XCTAssertEqual(Map3DQuality.key, "map3D.quality")
    }

    // Decision 365.
    func testOldGPUsStartWithTheFlatMapOnly() {
        XCTAssertEqual(Map3DQuality.startingChoice(gpuFamily: 0), .off)
        XCTAssertEqual(Map3DQuality.startingChoice(gpuFamily: 5), .off)
        XCTAssertEqual(Map3DQuality.startingChoice(gpuFamily: 6), .off)
        XCTAssertEqual(Map3DQuality.startingChoice(gpuFamily: 7), .automatic)
        XCTAssertEqual(Map3DQuality.startingChoice(gpuFamily: 9), .automatic)
    }

    func testOffPutsAway3DAndDrawsTheLightestLookIfOpened() {
        XCTAssertFalse(Map3DQuality.off.shows3D)
        for quality in [Map3DQuality.automatic, .saving, .high] {
            XCTAssertTrue(quality.shows3D)
            XCTAssertEqual(quality.drawn, quality)
        }
        XCTAssertEqual(Map3DQuality.off.drawn, .saving)
        XCTAssertNil(Map3DSunShadow.plan(.off, lowPower: false, heat: .nominal, overBudget: false))
    }

    func testOnlySavingDrawsOneSampleAPixel() {
        XCTAssertEqual(Map3DQuality.allCases.map(\.samplesPerPixel), [4, 1, 4, 1])
    }

    func testAKeptChoiceReadsBackAsItWas() {
        for quality in Map3DQuality.allCases {
            XCTAssertEqual(Map3DQuality(rawValue: quality.rawValue), quality)
        }
    }
}
