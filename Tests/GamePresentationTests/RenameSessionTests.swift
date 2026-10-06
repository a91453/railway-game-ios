import GameCore
import GamePresentation
import XCTest

/// Renaming the selected station and line, and the line's colour, through
/// the session.
final class RenameSessionTests: XCTestCase {
    @MainActor
    func testTheSessionRenamesAndColours() throws {
        let session = GameSession(world: DemoWorld.make(in: .english))
        let central = try XCTUnwrap(session.world.stations.first { $0.name == "Central" })
        session.selectStation(central.id)
        session.renameSelectedStation(to: "Main Square")
        XCTAssertEqual(session.world.station(id: central.id)?.name, "Main Square")
        XCTAssertEqual(session.message?.text, "Renamed Central to Main Square.")
        session.renameSelectedStation(to: "")
        XCTAssertEqual(session.message?.kind, .failure)

        let line = try XCTUnwrap(session.world.lines.first)
        session.selectLine(line.id)
        session.renameSelectedLine(to: "Red Line")
        XCTAssertEqual(session.world.line(id: line.id)?.name, "Red Line")
        session.setSelectedLineColor(LineColor.presets[1])
        XCTAssertEqual(session.world.line(id: line.id)?.color, LineColor.presets[1])
        XCTAssertEqual(LineColor.presets[1].hexText, "#EF5350")
        XCTAssertEqual(LineColor(rgb: 0x00E5FF)?.hexText, "#00E5FF")
        XCTAssertEqual(LineColor(rgb: 0)?.hexText, "#000000")
    }
}
