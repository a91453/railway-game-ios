import GameCore
@testable import GamePresentation
import XCTest

/// Decision 354: the station's board a platform at a time, the trains due
/// within 15 minutes, or a quiet platform's next one.
final class DepartureBoardPlatformTests: XCTestCase {
    private func row(_ id: String, train: Int? = nil, away: Int64, to destination: Int = 2, endsHere: Bool = false,
                     boarding: Bool = false) -> DepartureBoard.Row {
        DepartureBoard.Row(
            id: id, train: train.map { TrainID(rawValue: $0) }, trainName: "", line: LineID(rawValue: 1), lineName: "L", color: nil,
            destination: StationID(rawValue: destination), endsHere: endsHere, passes: false, isBoarding: boarding,
            expected: GameTime(seconds: 9 * 3_600 + away), secondsAway: away, lateMinutes: 0)
    }

    func testEachPlatformListsItsTrainsWithinFifteenMinutesOrItsNextOne() {
        let groups = DepartureBoard.grouping([
            (row("a", away: 0, boarding: true), 2),
            (row("b", away: 4 * 60), 1),
            (row("c", away: 9 * 60, to: 3), nil),
            (row("d", away: 15 * 60), 2),
            (row("e", away: 16 * 60), 2),
            (row("f", away: 40 * 60), 3),
            (row("g", away: 47 * 60), 3),
            (row("h", away: 50 * 60, to: 4), nil),
            (row("i", away: 5 * 60, to: 9, endsHere: true), nil),
        ])
        XCTAssertEqual(groups.map(\.heading), [
            .platform(1), .platform(2), .platform(3),
            .direction(destination: StationID(rawValue: 3), endsHere: false),
            .direction(destination: StationID(rawValue: 4), endsHere: false),
            .direction(destination: StationID(rawValue: 9), endsHere: true),
        ], "the platforms in their order, then the ways trains go, those that end here last")
        XCTAssertEqual(groups.map { $0.rows.map(\.id) }, [["b"], ["a", "d"], ["f"], ["c"], ["h"], ["i"]],
                       "15 minutes on the dot is still listed; 16 is not")
        XCTAssertEqual(groups.map(\.isNextOnly), [false, false, true, false, true, false])

        XCTAssertNil(groups[1].noteText(in: .traditionalChinese))
        XCTAssertEqual(groups[2].noteText(in: .traditionalChinese), "15 分鐘內沒有車，下一班 09:40。")
        XCTAssertEqual(groups[2].noteText(in: .english), "No train in the next 15 min. Next at 09:40.")
        let world = DemoWorld.make(in: .english)
        XCTAssertEqual(groups[0].title(in: .traditionalChinese, world: world), "第 1 月台")
        XCTAssertEqual(groups[0].title(in: .english, world: world), "Platform 1")
        XCTAssertEqual(groups[5].title(in: .traditionalChinese, world: world), "抵達本站")
    }

    func testABusyPlatformListsAtMostSixTrains() {
        let rows = (0..<10).map { (row("r\($0)", away: Int64($0) * 60), Optional(1)) }
        let groups = DepartureBoard.grouping(rows)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].rows.count, DepartureBoard.rowsPerDirection)
    }

    /// The demo's Central: every train listed is due at one of its
    /// platforms within 15 minutes, or is a platform's next one; a train
    /// routed in is at the platform it is routed to.
    func testTheDemosCentralByPlatform() throws {
        var world = DemoWorld.make(in: .english)
        let station = try XCTUnwrap(world.stations.first { $0.name == "Central" }).id
        let platforms = world.trackPlatforms(of: station)
        XCTAssertGreaterThan(platforms.count, 1)
        var sawPlatform = false, sawRouted = false
        for _ in 0..<300 {
            try world.advance(ticks: 1)
            let board = DepartureBoard(world: world, station: station)
            let groups = board.byPlatform(in: world)
            XCTAssertEqual(groups.isEmpty, board.isEmpty)
            XCTAssertEqual(Set(groups.map(\.id)).count, groups.count)
            for group in groups {
                XCTAssertFalse(group.rows.isEmpty)
                XCTAssertEqual(group.rows.map(\.secondsAway), group.rows.map(\.secondsAway).sorted())
                if group.isNextOnly {
                    XCTAssertEqual(group.rows.count, 1)
                    XCTAssertGreaterThan(group.rows[0].secondsAway, DepartureBoard.soonSeconds)
                } else {
                    XCTAssertTrue(group.rows.allSatisfy { $0.secondsAway <= DepartureBoard.soonSeconds })
                }
                guard case .platform(let number) = group.heading else { continue }
                sawPlatform = true
                XCTAssertTrue(platforms.indices.contains(number - 1))
                for row in group.rows {
                    guard let train = row.train, let routed = Map3DNextDeparture.routedPlatform(of: train, at: station, in: world),
                          board.rows.first(where: { $0.train == train })?.id == row.id else { continue }
                    sawRouted = true
                    XCTAssertEqual(platforms[number - 1], routed)
                }
            }
            if sawPlatform && sawRouted { break }
        }
        XCTAssertTrue(sawPlatform, "Central's trains are listed by platform")
        XCTAssertTrue(sawRouted, "a train routed in is listed at its platform")
    }

    /// A station with no platform on the track lists its trains by the way
    /// they go.
    func testAStationWithoutPlatformsListsByDirection() throws {
        var world = DemoWorld.make(in: .english)
        try world.advance(ticks: 30)
        let station = try XCTUnwrap(world.stations.first { $0.name == "Central" }).id
        let board = DepartureBoard(world: world, station: station)
        XCTAssertFalse(board.rows.isEmpty)
        let other = DepartureBoard(station: StationID(rawValue: 9_999), directions: board.directions)
        for group in other.byPlatform(in: world) {
            guard case .direction = group.heading else { return XCTFail("\(group.heading)") }
        }
    }
}
