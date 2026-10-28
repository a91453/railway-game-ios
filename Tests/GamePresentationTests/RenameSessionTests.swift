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

    /// The colour menus name each colour: every preset a name of its own,
    /// any other colour by its hue.
    func testLineColourNames() {
        XCTAssertEqual(LineColor.presets[8].nameText(in: .english), "Blue")
        XCTAssertEqual(LineColor.presets[8].nameText(in: .traditionalChinese), "藍")
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let names = LineColor.presets.map { $0.nameText(in: language) }
            XCTAssertEqual(Set(names).count, names.count, "\(language): \(names)")
            XCTAssertFalse(names.contains { $0.contains("#") })
        }
        XCTAssertEqual(LineColor(rgb: 0x1273E0)?.nameText(in: .traditionalChinese), "藍")
        XCTAssertEqual(LineColor(rgb: 0)?.nameText(in: .english), "Black")
    }
}
