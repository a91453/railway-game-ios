import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 535 (continued), REVIEW-L4 L4-2: the board and the diagram read
/// a ring's fixed-timetable runs the ring's way round, past the seam, and a
/// whole lap ends where it began. The ring is `SaveFixtures/v80-ring-runs.json`'s
/// six-stop line, its runs changed in memory only.
final class RingRunBoardTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private struct Fixture {
        let world: GameWorld
        let lineObject: [String: Any]
    }

    private func fixture() throws -> Fixture {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("SaveFixtures/v80-ring-runs.json"))
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let lines = try XCTUnwrap((object["world"] as? [String: Any])?["lines"] as? [[String: Any]])
        return Fixture(world: world, lineObject: lines[0])
    }

    /// The fixture's ring with `runs` and none of them sent out; not a ring
    /// when `ring` is false.
    private func line(_ runs: [LineRun], ring: Bool = true) throws -> ServiceLine {
        var object = try fixture().lineObject
        object["runs"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(runs))
        object.removeValue(forKey: "runDays")
        if !ring { object.removeValue(forKey: "ring") }
        let line = try JSONDecoder().decode(ServiceLine.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(line.isRing, ring)
        XCTAssertEqual(line.stops.count, 6)
        return line
    }

    private func times(_ count: Int, from start: Int64) -> [LineRunTime] {
        (0..<count).map { LineRunTime(arrival: start + Int64($0) * 300, departure: start + Int64($0) * 300 + (($0 == 0 || $0 == count - 1) ? 0 : 60)) }
    }

    private var now: Int64 { 22_200 }

    private func rows(_ line: ServiceLine, world: GameWorld) -> [[DepartureBoard.Row]] {
        line.stops.map { DepartureBoard.runRows(of: line, at: $0, in: world, now: now) }
    }

    /// Inner from the last stop to the first: one leg, across the seam. On
    /// `main` before the fix the first stop's row read a time the run does
    /// not have.
    func testARunAcrossTheSeamIsOnBothItsStopsBoards() throws {
        let world = try fixture().world
        let ring = try line([LineRun(from: 5, to: 0, times: times(2, from: 25_000), way: .inner)])
        let boards = rows(ring, world: world)
        XCTAssertEqual(boards.map(\.count), [1, 0, 0, 0, 0, 1])
        let leaving = try XCTUnwrap(boards[5].first)
        XCTAssertEqual(leaving.destination, ring.stops[0])
        XCTAssertFalse(leaving.endsHere)
        XCTAssertNil(leaving.comesFrom)
        XCTAssertEqual(leaving.scheduled?.seconds, 25_000)
        let arriving = try XCTUnwrap(boards[0].first)
        XCTAssertEqual(arriving.destination, ring.stops[0])
        XCTAssertTrue(arriving.endsHere)
        XCTAssertEqual(arriving.comesFrom, ring.stops[5])
        XCTAssertEqual(arriving.scheduled?.seconds, 25_300)
    }

    /// The fixture's D → A inner run calls at D, E, F, A, not back through
    /// C and B.
    func testARunIsListedAtTheStopsItCallsAtTheRingsWay() throws {
        let world = try fixture().world
        for way in RingDirection.allCases {
            let ring = try line([LineRun(from: 3, to: 0, times: times(4, from: 28_800), way: way)])
            let calls = way == .inner ? [3, 4, 5, 0] : [3, 2, 1, 0]
            let boards = rows(ring, world: world)
            XCTAssertEqual(boards.map(\.count), (0..<6).map { calls.contains($0) ? 1 : 0 }, "\(way)")
            for (position, call) in calls.enumerated() {
                let row = try XCTUnwrap(boards[call].first)
                XCTAssertEqual(row.scheduled?.seconds, 28_800 + Int64(position) * 300, "\(way) \(call)")
                XCTAssertEqual(row.comesFrom, position > 0 ? ring.stops[calls[position - 1]] : nil, "\(way) \(call)")
                XCTAssertEqual(row.endsHere, position == calls.count - 1, "\(way) \(call)")
                XCTAssertEqual(row.destination, ring.stops[0], "\(way) \(call)")
            }
        }
    }

    /// A whole lap (`from == to`) leaves its first stop for that same stop
    /// and comes back to end there: two rows at it, one at every other stop.
    func testAWholeLapLeavesAndEndsAtItsFirstStop() throws {
        let world = try fixture().world
        let ring = try line([LineRun(from: 2, to: 2, times: times(7, from: 24_000), way: .outer)])
        let boards = rows(ring, world: world)
        XCTAssertEqual(boards.map(\.count), [1, 1, 2, 1, 1, 1])
        let atStart = boards[2].sorted { $0.secondsAway < $1.secondsAway }
        XCTAssertEqual(atStart.map(\.endsHere), [false, true])
        XCTAssertEqual(atStart.map(\.destination), [ring.stops[2], ring.stops[2]])
        XCTAssertEqual(atStart.map(\.comesFrom), [nil, ring.stops[3]])
        XCTAssertEqual(atStart.map { $0.scheduled?.seconds }, [24_000, 25_800])
        XCTAssertEqual(Set(atStart.map(\.id)).count, 2)
        for stop in [3, 4, 5, 0, 1] {
            let row = try XCTUnwrap(boards[stop].first)
            XCTAssertFalse(row.endsHere)
            XCTAssertEqual(row.destination, ring.stops[2])
            XCTAssertEqual(row.comesFrom, ring.stops[(stop + 1) % 6])
        }
    }

    /// A line that is not a ring reads its runs as before, both ways.
    func testALineThatIsNotARingIsUnchanged() throws {
        let world = try fixture().world
        let plain = try line([LineRun(from: 0, to: 3, times: times(4, from: 25_000)),
                              LineRun(from: 3, to: 0, times: times(4, from: 26_000))], ring: false)
        let boards = rows(plain, world: world)
        XCTAssertEqual(boards.map(\.count), [2, 2, 2, 2, 0, 0])
        let down = boards.map { $0.filter { $0.id.hasSuffix("|1|0") } }
        XCTAssertEqual(down[0].first?.endsHere, true)
        XCTAssertEqual(down[1].first?.comesFrom, plain.stops[2])
        XCTAssertEqual(down[3].first?.comesFrom, nil)
        XCTAssertEqual(down[3].first?.destination, plain.stops[0])
        XCTAssertEqual(boards[0].first { $0.id == "r\(plain.id.rawValue)|0|0" }?.destination, plain.stops[3])
        XCTAssertEqual(boards[1].map(\.id).sorted(), ["r\(plain.id.rawValue)|0|0", "r\(plain.id.rawValue)|1|0"])
    }

    // MARK: The diagram

    private func diagram(_ line: ServiceLine) -> [[TrainDiagram.Point]] {
        TrainDiagram.runTrips(of: line, rows: TrainDiagram.Rows(line: line), from: 0, to: 40_000, now: now)
            .flatMap(\.lines)
    }

    func testTheDiagramDrawsARunTheRingsWayAcrossTheSeam() throws {
        let inner = try line([LineRun(from: 3, to: 0, times: times(4, from: 28_800), way: .inner)])
        // D, E, F, then down to the extra row after F (A again).
        XCTAssertEqual(diagram(inner).map { $0.map(\.place) }, [[3, 4, 4, 5, 5, 6]])
        XCTAssertEqual(diagram(inner).first?.last?.time, 28_800 + 900)
        let seam = try line([LineRun(from: 5, to: 0, times: times(2, from: 25_000), way: .inner)])
        XCTAssertEqual(diagram(seam).map { $0.map(\.place) }, [[5, 6]])
        let outer = try line([LineRun(from: 0, to: 4, times: times(3, from: 25_000), way: .outer)])
        // A, then up from the extra row to F, E.
        XCTAssertEqual(diagram(outer).map { $0.map(\.place) }, [[6, 5, 5, 4]])
    }

    func testTheDiagramDrawsAWholeLap() throws {
        let lap = try line([LineRun(from: 0, to: 0, times: times(7, from: 24_000), way: .inner)])
        XCTAssertEqual(diagram(lap).map { $0.map(\.place) }, [[0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6]])
    }

    func testTheDiagramOfALineThatIsNotARingIsUnchanged() throws {
        let plain = try line([LineRun(from: 3, to: 0, times: times(4, from: 26_000))], ring: false)
        XCTAssertEqual(diagram(plain).map { $0.map(\.place) }, [[3, 2, 2, 1, 1, 0]])
    }
}
