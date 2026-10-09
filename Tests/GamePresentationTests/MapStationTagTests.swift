import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 119: a tap on a station shows a tag over it (its
/// name, who waits there and its lines' colours); holding it selects it for
/// its panel.
@MainActor
final class MapStationTagTests: XCTestCase {
    private static let alpha = StationID(rawValue: 1)
    private static let beta = StationID(rawValue: 2)

    private func twoStations() throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 100_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        return world
    }

    func testTheTagReadsTheStationAndItsLines() throws {
        var world = try twoStations()
        try world.createLine(named: "Main", stops: [Self.alpha, Self.beta])
        let tag = try XCTUnwrap(StationTag(world: world, station: Self.alpha))
        XCTAssertEqual(tag.name, "Alpha")
        XCTAssertEqual(tag.location, world.station(id: Self.alpha)?.location)
        XCTAssertEqual(tag.waiting, 0)
        XCTAssertNil(tag.waitingText(in: .english), "no one waiting: nothing said")
        XCTAssertEqual(tag.lines, [StationTag.LineMark(id: LineID(rawValue: 1), color: nil)])
        XCTAssertNil(StationTag(world: world, station: StationID(rawValue: 9)))

        let crowded = StationTag(station: Self.alpha, name: "Alpha", location: tag.location, waiting: 1_234, lines: [])
        XCTAssertEqual(crowded.waitingText(in: .english), "1,234 waiting")
        XCTAssertEqual(crowded.waitingText(in: .traditionalChinese), "候車 1,234 人")
    }

    func testHoldingAStationSelectsIt() throws {
        let world = try twoStations()
        let session = GameSession(world: world)
        let location = try XCTUnwrap(world.station(id: Self.beta)?.location)
        XCTAssertEqual(session.holdMap(at: location, reach: 256), Self.beta)
        XCTAssertEqual(session.selectedStationID, Self.beta)
        XCTAssertNil(session.holdMap(at: PlanPoint(x: 8_000, y: 4_000), reach: 256), "no station there")
        XCTAssertEqual(session.selectedStationID, Self.beta, "holding nothing keeps the selection")
        XCTAssertEqual(session.world, world, "never changes the world")
    }
}
