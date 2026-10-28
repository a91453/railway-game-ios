@testable import GameCore
import XCTest

/// 派工單 AQ: one search from an origin answers every destination, resumed
/// where it stopped (``PassengerRouteSearches``). Each answer must be the
/// one a search for that destination alone finds, whatever order the
/// destinations and banned rides are asked in.
final class PassengerRouteSearchTests: XCTestCase {
    private typealias Found = (PassengerRoute, [PassengerRideEdge])?

    private func same(_ lhs: Found, _ rhs: Found) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (left?, right?): left.0 == right.0 && left.1 == right.1
        default: false
        }
    }

    /// A random network of `stations` stations: lines both ways, some rings,
    /// walks between stations near each other, a closed station or two.
    private func graph(_ random: inout SplitMix64, stations: Int) -> PassengerRouteGraph {
        let ids = (1...stations).map { StationID(rawValue: $0) }
        var paths: [PassengerRouteGraph.ServicePath] = []
        for line in 1...(3 + random.below(4)) {
            let calls = ids.filter { _ in random.below(3) == 0 }.shuffled(using: &random)
            guard calls.count >= 2 else { continue }
            let runs = (1..<calls.count).map { _ in Int64(60 + random.below(400)) }
            let headway = Int64(120 + random.below(1_200))
            let dwell = Int64(random.below(60))
            let isRing = random.below(4) == 0
            let stops = isRing ? calls + [calls[0]] : calls
            let ringRuns = isRing ? runs + [Int64(60 + random.below(400))] : runs
            paths.append(PassengerRouteGraph.ServicePath(
                line: LineID(rawValue: line), pattern: nil, direction: .outbound,
                stations: stops, runSeconds: ringRuns, headway: headway, isRing: isRing, dwellSeconds: dwell))
            paths.append(PassengerRouteGraph.ServicePath(
                line: LineID(rawValue: line), pattern: nil, direction: .inbound,
                stations: stops.reversed(), runSeconds: ringRuns.reversed(), headway: headway, isRing: isRing,
                dwellSeconds: dwell))
        }
        // Points about 300 m apart on a line, so neighbours can walk.
        let metre = WorldCoordinate.unitsPerMetre
        let points = ids.map { _ in PlanPoint(x: Int64(random.below(3_000)) * metre, y: Int64(random.below(600)) * metre) }
        var walks: [StationID: [PassengerWalk]] = [:]
        for (from, origin) in ids.enumerated() {
            for (to, destination) in ids.enumerated() where to != from {
                if let walk = PassengerWalk(from: points[from], to: points[to], station: destination,
                                            linked: random.below(40) == 0) {
                    walks[origin, default: []].append(walk)
                }
            }
        }
        let closed = Set(ids.filter { _ in random.below(12) == 0 })
        return PassengerRouteGraph(paths: paths, walks: walks, closed: closed)
    }

    func testAResumedSearchFindsWhatASearchForOneDestinationFinds() {
        check(seed: 0xA0_2026_1027, checkpointLimit: 16, searchLimit: 512, labelBudget: 400_000)
    }

    /// 派工單 BB: with few copies kept, a banned search starts from a copy
    /// further back and runs on, and a dropped one starts again; neither
    /// changes an answer.
    func testFewCopiesFindTheSame() {
        check(seed: 0xBB_2026_1028, checkpointLimit: 1, searchLimit: 1, labelBudget: 400_000, graphs: 12)
        check(seed: 0xBB_2026_1029, checkpointLimit: 3, searchLimit: 8, labelBudget: 60, graphs: 12)
    }

    /// 派工單 BB: the copies kept stay within their limits however many
    /// calls one search reaches and however many rides are banned (one at
    /// each call and each set of bans took 200 stations past 1.4 GB),
    /// counted, not measured.
    func testTheCopiesKeptHaveALimit() {
        var random = SplitMix64(seed: 0xBB_2026_1030)
        let stations = 60
        let graph = graph(&random, stations: stations)
        XCTAssertGreaterThan(graph.lookup.nodeSlot.count, 4 * 16, "more calls than copies")
        let ids = (1...stations).map { StationID(rawValue: $0) }
        for (searchLimit, labelBudget) in [(16, 400_000), (128, 2_000)] {
            var searches = PassengerRouteSearches(graph: graph, checkpointLimit: 16, searchLimit: searchLimit,
                                                  labelBudget: labelBudget)
            var most = 0, mostLabels = 0, banned = 0
            for origin in ids.prefix(6) {
                for destination in ids where destination != origin {
                    guard let first = searches.shortest(from: origin, to: destination, banning: []) else { continue }
                    for edge in first.1 {
                        _ = searches.shortest(from: origin, to: destination, banning: [edge])
                        banned += 1
                        most = max(most, searches.copies)
                        if searches.bannedSearches > 1 { mostLabels = max(mostLabels, searches.bannedLabels) }
                    }
                }
            }
            XCTAssertGreaterThan(banned, 2 * 16, "more banned searches than are kept")
            XCTAssertLessThanOrEqual(most, 16 + searchLimit)
            XCTAssertLessThanOrEqual(mostLabels, labelBudget)
            XCTAssertGreaterThan(most, 16, "the copies were used")
        }
    }

    private func check(seed: UInt64, checkpointLimit: Int, searchLimit: Int, labelBudget: Int, graphs: Int = 40,
                       file: StaticString = #filePath, line: UInt = #line) {
        var random = SplitMix64(seed: seed)
        var asked = 0, found = 0
        for _ in 0..<graphs {
            let stations = 6 + random.below(14)
            let graph = graph(&random, stations: stations)
            var searches = PassengerRouteSearches(graph: graph, checkpointLimit: checkpointLimit,
                                                  searchLimit: searchLimit, labelBudget: labelBudget)
            let ids = (1...stations).map { StationID(rawValue: $0) }
            for origin in ids {
                // The rides of some first routes, banned one or two at a
                // time, as the k-shortest search bans them.
                var banSets: [Set<PassengerRideEdge>] = [[]]
                for destination in ids.shuffled(using: &random) {
                    for bans in banSets.shuffled(using: &random).prefix(4) {
                        let alone = graph.shortest(from: origin, to: destination, banning: bans)
                        let resumed = searches.shortest(from: origin, to: destination, banning: bans)
                        asked += 1
                        if alone != nil { found += 1 }
                        XCTAssertTrue(same(alone, resumed), "\(origin) → \(destination) banning \(bans)",
                                      file: file, line: line)
                        XCTAssertLessThanOrEqual(searches.copies, checkpointLimit + searchLimit,
                                                 file: file, line: line)
                        XCTAssertTrue(searches.bannedLabels <= labelBudget || searches.bannedSearches == 1,
                                      file: file, line: line)
                        if let edges = alone?.1, !edges.isEmpty {
                            let edge = edges[random.below(edges.count)]
                            banSets.append(bans.union([edge]))
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(found, asked / 4, "most questions have a route", file: file, line: line)
    }
}

private extension Array {
    func shuffled(using random: inout SplitMix64) -> [Element] {
        var copy = self
        guard copy.count > 1 else { return copy }
        for index in stride(from: copy.count - 1, to: 0, by: -1) {
            copy.swapAt(index, random.below(index + 1))
        }
        return copy
    }
}
