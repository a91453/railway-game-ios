import GameCore
import GamePresentation
import XCTest

final class ConstructionToolTests: XCTestCase {
    func testSessionStartsInSelectMode() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)

            XCTAssertEqual(session.tool, .select)
            XCTAssertEqual(session.placementHeading, .east)
        }
    }

    func testSwitchingToolsDoesNotChangeTheWorld() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            session.select(GridPosition(x: 1, y: 1))

            for tool in ConstructionTool.allCases {
                session.selectTool(tool)
                XCTAssertEqual(session.tool, tool)
            }

            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.selection, GridPosition(x: 1, y: 1), "switching tools keeps the selection")
        }
    }

    /// Stage F3c: the grid's track, station and remove tools are gone;
    /// the app offers every tool there is.
    func testTheToolsAreSelectNetworkAndTrain() {
        XCTAssertEqual(ConstructionTool.allCases, [.select, .network, .train])
        XCTAssertEqual(ConstructionTool.networkTools, ConstructionTool.allCases)
        XCTAssertEqual(ConstructionTool.allCases.map { $0.title(in: .english) }, ["Select", "Network", "Train"])
        XCTAssertEqual(ConstructionTool.allCases.map { $0.title(in: .traditionalChinese) }, ["選取", "路網", "列車"])
    }

    func testCompassHeadingsAreNamed() {
        XCTAssertEqual(CompassHeading.allCases.map { $0.name(in: .english) }, ["North", "East", "South", "West"])
        XCTAssertEqual(CompassHeading.allCases.map { $0.abbreviation(in: .english) }, ["N", "E", "S", "W"])
        XCTAssertEqual(CompassHeading.allCases.map { $0.name(in: .traditionalChinese) }, ["北", "東", "南", "西"])
        XCTAssertEqual(CompassHeading.allCases.map { $0.abbreviation(in: .traditionalChinese) }, ["北", "東", "南", "西"])
    }
}
