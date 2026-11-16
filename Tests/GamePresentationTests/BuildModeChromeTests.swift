import GameCore
import GamePresentation
import XCTest

/// Decision 803: what the screen puts away while a building tool is out.
final class BuildModeChromeTests: XCTestCase {
    func testNothingIsPutAwayWhileLooking() {
        let chrome = BuildModeChrome(isBuilding: false)
        XCTAssertTrue(chrome.showsStationMaster)
        XCTAssertTrue(chrome.showsMiniMap)
        XCTAssertTrue(chrome.showsAlerts)
        XCTAssertTrue(chrome.showsFaresAndStamps)
    }

    func testBuildingPutsAwayWhatTheBuildDoesNotNeed() {
        let chrome = BuildModeChrome(isBuilding: true)
        XCTAssertFalse(chrome.showsStationMaster)
        XCTAssertFalse(chrome.showsMiniMap)
        XCTAssertFalse(chrome.showsAlerts)
        XCTAssertFalse(chrome.showsFaresAndStamps)
    }

    /// The station master naming the first line's steps stays: the steps
    /// are done with the building tools.
    func testTheFirstLinesGuideStays() {
        let chrome = BuildModeChrome(isBuilding: true, guidesFirstLine: true)
        XCTAssertTrue(chrome.showsStationMaster)
        XCTAssertFalse(chrome.showsMiniMap)
    }

    /// Every building tool counts, and Select does not; back as soon as
    /// the tools are put away.
    @MainActor
    func testASessionBuildsWithAnyToolButSelect() throws {
        let world = GameWorld(
            bounds: try WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: Money(100_000_000)),
            clock: GameClock(speed: .paused)
        )
        let session = GameSession(world: world)
        XCTAssertFalse(session.buildModeChrome().isBuilding)
        for tool in [ConstructionTool.network, .building, .bus, .train] {
            session.selectTool(tool)
            XCTAssertTrue(session.buildModeChrome().isBuilding, "\(tool)")
            XCTAssertTrue(session.buildModeChrome(guidesFirstLine: true).showsStationMaster)
        }
        session.selectTool(.select)
        XCTAssertEqual(session.buildModeChrome(), BuildModeChrome(isBuilding: false))
    }
}
