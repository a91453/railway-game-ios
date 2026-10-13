import GameCore
@testable import GamePresentation
import XCTest

/// TestFlight 59.1: a station's waiting passengers by line and way, with
/// those changing trains and a closed line's wait for its first train.
final class StationWaitBreakdownTests: XCTestCase {
    func testWaitingIsShownByLineAndWayAndAClosedLineSaysSo() throws {
        let world = DemoWorld.make(in: .english)
        guard let station = world.stations.max(by: {
            world.waitingPassengers(at: $0.id).count < world.waitingPassengers(at: $1.id).count
        }) else { return XCTFail("the demo has stations") }
        var running = world
        try running.advance(ticks: 30)
        let rows = running.waitingBreakdown(at: station.id, in: .english)
        let groups = running.waitingPassengers(at: station.id)
        let byLine = Set(groups.map { "\($0.line.rawValue)/\($0.direction)" })
        XCTAssertEqual(rows.count, byLine.count)
        let total = groups.reduce(Int64(0)) { $0 + $1.count }
        let shown = rows.compactMap { row in
            row.split(separator: "·").dropFirst().first.flatMap { Int64($0.split(separator: " ").first ?? "") }
        }.reduce(0, +)
        XCTAssertEqual(shown, total)
        let changing = groups.filter { ($0.journey?.origin).map { $0 != station.id } ?? false }.reduce(Int64(0)) { $0 + $1.count }
        XCTAssertEqual(rows.contains { $0.contains("changing") }, changing > 0)
        let closed = Set(groups.map(\.line).filter { running.serviceLevel(of: $0, at: running.clock.now) == nil })
        XCTAssertEqual(rows.filter { $0.hasSuffix(" · closed, waiting for the first train") }.count,
                       Set(groups.filter { closed.contains($0.line) }.map { "\($0.line.rawValue)/\($0.direction)" }).count)
    }

    func testAClosedLinesPassengersWaitForTheFirstTrain() throws {
        var world = DemoWorld.make(in: .english)
        try world.advance(ticks: 30)
        guard let station = world.stations.first(where: { !world.waitingPassengers(at: $0.id).isEmpty }) else {
            return XCTFail("someone waits in the demo")
        }
        for line in Set(world.waitingPassengers(at: station.id).map(\.line)) {
            let minute = world.clock.now.minuteOfDay
            // A window that opens in an hour.
            let open = (minute + 60) % 1_440
            try world.setLineServiceWindow(line, to: .hours(open: open, close: open + 60))
        }
        let rows = world.waitingBreakdown(at: station.id, in: .traditionalChinese)
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            XCTAssertTrue(row.hasSuffix(" · 已收班，等首班車"), row)
        }
    }

    func testTheCrowdedNoteFromHalfTheRoom() throws {
        let world = DemoWorld.make(in: .english)
        for station in world.stations {
            let waiting = world.waitingPassengers(at: station.id).reduce(Int64(0)) { $0 + $1.count }
            XCTAssertEqual(world.crowdedStationNote(at: station.id, in: .english) != nil, waiting * 2 >= StationPassengers.capacity)
        }
    }

    func testTheGuideAnswersBothQuestions() throws {
        let platforms = try XCTUnwrap(HelpGuide.entries.first { $0.id == "islandOrSide" })
        XCTAssertTrue(HelpGuide.entries(matching: "島式").contains(platforms))
        XCTAssertTrue(HelpGuide.entries(matching: "island platform").contains(platforms))
        XCTAssertTrue(platforms.answer(in: .english).contains("11 m"))
        XCTAssertTrue(platforms.answer(in: .english).contains("88 m"))
        XCTAssertEqual(PlatformTrackLayout.island.reach, 88 * WorldCoordinate.unitsPerMetre)
        XCTAssertEqual(PlatformTrackLayout.side.reach, 50 * WorldCoordinate.unitsPerMetre)
        let crowded = try XCTUnwrap(HelpGuide.entries.first { $0.id == "crowdedButLowLoad" })
        XCTAssertTrue(HelpGuide.entries(matching: "客滿").contains(crowded))
        XCTAssertTrue(HelpGuide.entries(matching: "peak load").contains(crowded))
        XCTAssertTrue(crowded.answer(in: .english).contains("4,000"))
        XCTAssertEqual(StationPassengers.capacity, 4_000)
    }
}
