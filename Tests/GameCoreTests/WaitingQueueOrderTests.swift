@testable import GameCore
import XCTest

/// Decision 328: a group joins a station's queue by halving to its minute
/// instead of searching from the front. The queue must come out exactly as
/// the search from the front made it, group for group, so that boarding,
/// saves and replays do not move.
final class WaitingQueueOrderTests: XCTestCase {
    /// The search from the front, as it was before decision 328.
    private static func enqueuedFromTheFront(_ group: WaitingGroup, into waiting: inout [WaitingGroup]) {
        if let index = waiting.firstIndex(where: {
            $0.since == group.since && $0.line == group.line && $0.direction == group.direction &&
                $0.destination == group.destination && $0.journey == group.journey && $0.readyAt == group.readyAt
        }) {
            let previous = waiting[index]
            waiting[index] = WaitingGroup(line: previous.line, direction: previous.direction,
                destination: previous.destination, since: previous.since, count: previous.count + group.count,
                journey: previous.journey, readyAt: previous.readyAt)
        } else {
            let insert = waiting.firstIndex {
                $0.since > group.since || $0.since == group.since && $0.destination > group.destination
            } ?? waiting.count
            waiting.insert(group, at: insert)
        }
    }

    func testAGroupJoinsTheQueueWhereTheSearchFromTheFrontPutIt() {
        var record = StationPassengers(station: StationID(rawValue: 1))
        var expected: [WaitingGroup] = []
        // A fixed sequence, the same on every run.
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        var minute: Int64 = 400
        var transfers = 0, joined = 0
        for _ in 0..<3_000 {
            if next(8) == 0 { minute += Int64(1 + next(3)) }
            let now = GameTime(minutes: minute)
            let from = StationID(rawValue: 1)
            let to = StationID(rawValue: 2 + next(4))
            let leg = PassengerRouteLeg(line: LineID(rawValue: 1 + next(2)), pattern: next(3) == 0 ? nil : 0,
                direction: next(2) == 0 ? .outbound : .inbound, from: from, to: to, rideSeconds: 60)
            let route = PassengerRoute(legs: [leg], rideMinutes: 1, waitMinutes: 0, transferSeconds: 0, walkSeconds: 0)
            guard let journey = PassengerJourney(origin: from, route: route) else { return XCTFail("no journey") }
            let count = Int64(1 + next(3))
            let before = record.waiting.count
            if next(3) == 0 {
                let readyAt = GameTime(minutes: minute + Int64(next(3)))
                guard record.enqueueTransfer(count, along: journey, at: now, readyAt: readyAt) == count else { break }
                Self.enqueuedFromTheFront(WaitingGroup(line: leg.line, direction: leg.direction, destination: to,
                    since: now, count: count, journey: journey, readyAt: readyAt), into: &expected)
                transfers += 1
            } else {
                guard record.waitingCount + count <= StationPassengers.capacity else { break }
                record.release(count, along: journey, at: now)
                Self.enqueuedFromTheFront(WaitingGroup(line: leg.line, direction: leg.direction, destination: to,
                    since: now, count: count, journey: journey), into: &expected)
            }
            if record.waiting.count == before { joined += 1 }
            XCTAssertEqual(record.waiting, expected)
            if record.waiting != expected { return }
            // Now and then a train takes some, so the queue does not only grow.
            if next(10) == 0, !expected.isEmpty {
                let index = next(expected.count)
                record.board([index: 1])
                let group = expected[index]
                if group.count == 1 {
                    expected.remove(at: index)
                } else {
                    expected[index] = WaitingGroup(line: group.line, direction: group.direction, destination: group.destination,
                        since: group.since, count: group.count - 1, journey: group.journey, readyAt: group.readyAt)
                }
            }
        }
        XCTAssertEqual(record.waiting, expected)
        XCTAssertEqual(record.waitingCount, expected.reduce(0) { $0 + $1.count })
        // Both ways in, and groups that joined one already waiting, were tried.
        XCTAssertGreaterThan(transfers, 100)
        XCTAssertGreaterThan(joined, 100)
        XCTAssertGreaterThan(expected.count, 500)
    }
}
