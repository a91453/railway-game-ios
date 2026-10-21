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
        XCTAssertEqual(Map3DQuality.allCases.map(\.rawValue), ["automatic", "saving", "high"])
        XCTAssertEqual(Map3DQuality.key, "map3D.quality")
    }
}
