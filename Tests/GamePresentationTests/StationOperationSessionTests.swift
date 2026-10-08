import GameCore
import GamePresentation
import XCTest

/// Phase 5F in the app: the station panel sets a station's operation mode
/// (the reference's `operationMode`) through one `GameWorld` command.
final class StationOperationSessionTests: XCTestCase {
    func testTheSessionSetsTheSelectedStationsOperationMode() async throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 100_000)
        let alpha = try world.buildStation(named: "Alpha", at: TestLine.centre(1, 0)).id
        var closed = world
        try closed.setStationOperationMode(alpha, to: .closed)
        await MainActor.run { [world, closed] in
            let session = GameSession(world: world)
            session.setSelectedStationOperationMode(.closed)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Select a station on the map first."))
            XCTAssertEqual(session.world, world)

            session.selectStation(alpha)
            session.setSelectedStationOperationMode(.closed)
            XCTAssertEqual(session.world, closed)
            XCTAssertEqual(session.world.station(id: alpha)?.operationMode, .closed)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Alpha: Closed."))
            session.setSelectedStationOperationMode(.flowControl)
            XCTAssertEqual(session.world.station(id: alpha)?.operationMode, .flowControl)
            XCTAssertEqual(session.message?.text, "Alpha: Flow control.")
            session.setSelectedStationOperationMode(.normalFlow)
            XCTAssertEqual(session.world, world)
        }
        let chinese = await MainActor.run { () -> String? in
            let session = GameSession(world: closed, language: .traditionalChinese)
            session.selectStation(alpha)
            session.setSelectedStationOperationMode(.flowControl)
            return session.message?.text
        }
        XCTAssertEqual(chinese, "Alpha：流量控制。")
    }

    func testTheModesReadInBothLanguages() {
        XCTAssertEqual(StationOperationMode.allCases.map { $0.title(in: .english) }, ["Normal", "Flow control", "Closed"])
        XCTAssertEqual(StationOperationMode.allCases.map { $0.title(in: .traditionalChinese) }, ["正常營運", "流量控制", "車站關閉"])
        for mode in StationOperationMode.allCases {
            XCTAssertFalse(mode.detail(in: .english).isEmpty)
            XCTAssertFalse(mode.detail(in: .traditionalChinese).isEmpty)
        }
    }
}
