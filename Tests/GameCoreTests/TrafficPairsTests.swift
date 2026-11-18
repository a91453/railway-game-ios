@testable import GameCore
import XCTest

/// Decision 878, later (TICK-TAIWAN): the overtake planner looks only at
/// pairs of services sharing two stations or more, and matches their
/// common points through each service's stations looked up once. These
/// check the shortcuts against the scans they replace.
final class TrafficPairsTests: XCTestCase {
    /// ``GameWorld/trafficPartners(_:)`` names exactly the later services
    /// sharing two stations or more, in ascending order.
    func testPartnersAreThePairsSharingTwoStations() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let count = Int.random(in: 0...12, using: &generator)
            let services: [[StationID]] = (0..<count).map { _ in
                (0..<Int.random(in: 0...8, using: &generator)).map { _ in StationID(rawValue: Int.random(in: 1...10, using: &generator)) }
            }
            let first = services.map { stations in
                stations.indices.reversed().reduce(into: [StationID: Int]()) { $0[stations[$1]] = $1 }
            }
            let partners = GameWorld.trafficPartners(first)
            for ia in services.indices {
                let expected = services.indices.filter { ib in
                    ib > ia && Set(services[ia]).intersection(services[ib]).count >= 2
                }
                XCTAssertEqual(partners[ia], expected, "\(services)")
            }
        }
    }

    /// ``GameWorld/preferredTrafficCommon(_:_:)`` gives, for every pair of
    /// a plan's services, what the scan point by point gave, on decision
    /// 366's line where stopping trains go back and forth (and so turn
    /// round, splitting their runs) and an express passes them.
    func testCommonPointsAreTheScansAlongAPlanOfTheDay() throws {
        for loopBetween in [false, true] {
            var world = try LocalPassTests.running(loopBetween: loopBetween).world
            var compared = 0
            for _ in 0..<120 {
                try world.advance(ticks: 60)
                let plan = world.trafficPlan()
                for a in plan.services {
                    for b in plan.services where b.train.id != a.train.id {
                        XCTAssertTrue(Self.same(world.preferredTrafficCommon(a, b), Self.scanned(a, b)))
                        compared += 1
                    }
                }
            }
            XCTAssertGreaterThan(compared, 0, "loop between \(loopBetween)")
        }
    }

    static func same(_ x: [[(ai: Int, bi: Int)]], _ y: [[(ai: Int, bi: Int)]]) -> Bool {
        x.count == y.count && zip(x, y).allSatisfy { p, q in p.count == q.count && zip(p, q).allSatisfy { $0.ai == $1.ai && $0.bi == $1.bi } }
    }

    /// The matching as it was written before the index: each run's first
    /// point at the station, searched for point by point.
    static func scanned(_ a: GameWorld.TrafficService, _ b: GameWorld.TrafficService) -> [[(ai: Int, bi: Int)]] {
        func runs(_ service: GameWorld.TrafficService) -> [Range<Int>] {
            var ranges: [Range<Int>] = [], start = 0
            for i in service.points.indices where i > 0 && i + 1 < service.points.count {
                let point = service.points[i]
                if point.calls && service.train.timetable[point.stop].reverses {
                    ranges.append(start..<(i + 1)); start = i
                }
            }
            ranges.append(start..<service.points.count)
            return ranges
        }
        var sequences: [[(ai: Int, bi: Int)]] = []
        for x in runs(a) {
            for y in runs(b) {
                let common = y.compactMap { j in x.first { a.points[$0].station == b.points[j].station }.map { (ai: $0, bi: j) } }
                if common.count >= 2 && zip(common, common.dropFirst()).allSatisfy({ $0.ai < $1.ai }) { sequences.append(common) }
            }
        }
        return sequences
    }
}
