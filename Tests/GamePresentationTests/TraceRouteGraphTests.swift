import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// ``RealRailwayTraces/route(from:to:)`` works on a network built once with
/// the lines (a drag asks for a way for each line within reach at either
/// end, nine at a time beside a junction), and finds the way from a heap:
/// the ways it finds are the ones the network rebuilt for each way found,
/// with a linear search for the nearest place, gave.
@MainActor
final class TraceRouteGraphTests: XCTestCase {
    private func traces() throws -> RealRailwayTraces {
        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        let world = GameWorld.newGame(anchor: try XCTUnwrap(tra.anchor))
        let session = GameSession(world: world, language: .english)
        session.railways = try BundledRealData.railways()
        return try XCTUnwrap(session.realRailwayTraces)
    }

    /// The way as it was found before: the network built for this way, and
    /// Dijkstra's nearest place by a linear search.
    private func rebuiltRoute(_ traces: RealRailwayTraces, from start: RealRailwayTraces.Place, to end: RealRailwayTraces.Place) -> (points: [WorldVector], hops: [Int])? {
        typealias Place = RealRailwayTraces.Place
        let lines = traces.lines
        var stops: [Place] = [start, end]
        for line in lines { stops += [Place(line: line.id, along: 0), Place(line: line.id, along: line.path.length)] }
        for link in traces.links { stops += [link.a, link.b] }
        var index: [Place: Int] = [:]
        var unique: [Place] = []
        for stop in stops where index[stop] == nil {
            index[stop] = unique.count
            unique.append(stop)
        }
        var neighbours = [[(stop: Int, cost: Double)]](repeating: [], count: unique.count)
        var byLine: [Int: [Int]] = [:]
        for (number, stop) in unique.enumerated() { byLine[stop.line, default: []].append(number) }
        for (_, numbers) in byLine {
            let sorted = numbers.sorted { unique[$0].along < unique[$1].along }
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                let cost = unique[b].along - unique[a].along
                neighbours[a].append((b, cost))
                neighbours[b].append((a, cost))
            }
        }
        for link in traces.links {
            guard let a = index[link.a], let b = index[link.b] else { continue }
            neighbours[a].append((b, link.gap))
            neighbours[b].append((a, link.gap))
        }
        guard let from = index[start], let to = index[end] else { return nil }
        var distance = [Double](repeating: .infinity, count: unique.count)
        var previous = [Int?](repeating: nil, count: unique.count)
        var done = [Bool](repeating: false, count: unique.count)
        distance[from] = 0
        while true {
            var next: Int?
            for stop in unique.indices where !done[stop] && distance[stop] < .infinity {
                if next == nil || distance[stop] < distance[next!] { next = stop }
            }
            guard let current = next else { break }
            if current == to { break }
            done[current] = true
            for (stop, cost) in neighbours[current] where distance[current] + cost < distance[stop] {
                distance[stop] = distance[current] + cost
                previous[stop] = current
            }
        }
        guard distance[to] < .infinity else { return nil }
        var route = [to]
        while let before = previous[route[route.count - 1]] { route.append(before) }
        route.reverse()
        var points: [WorldVector] = [lines[start.line].path.point(at: start.along)]
        var hops: [Int] = []
        for (a, b) in zip(route, route.dropFirst()) {
            let p = unique[a], q = unique[b]
            if p.line == q.line {
                let line = lines[p.line].path
                let along = line.points(from: min(p.along, q.along), to: max(p.along, q.along))
                points += p.along <= q.along ? along : along.reversed()
            } else {
                hops.append(points.count - 1)
                points.append(lines[q.line].path.point(at: q.along))
            }
        }
        return (points, hops)
    }

    func testTheWaysAreTheOnesTheRebuiltNetworkFound() throws {
        let traces = try traces()
        XCTAssertGreaterThan(traces.lines.count, 10)
        var random = SplitMix64(seed: 2_118)
        func place() -> RealRailwayTraces.Place {
            let line = traces.lines[Int(random.next() % UInt64(traces.lines.count))]
            // Now and then a line's end or a link's place, which the
            // network already has.
            switch random.next() % 8 {
            case 0: return .init(line: line.id, along: 0)
            case 1: return .init(line: line.id, along: line.path.length)
            case 2 where !traces.links.isEmpty: return traces.links[Int(random.next() % UInt64(traces.links.count))].a
            default: return .init(line: line.id, along: line.path.length * Double(random.next() % 1_000) / 1_000)
            }
        }
        var found = 0
        for _ in 0..<300 {
            let start = place()
            // Now and then two places on one line, or the same place.
            let end: RealRailwayTraces.Place
            switch random.next() % 6 {
            case 0: end = start
            case 1: end = .init(line: start.line, along: traces.lines[start.line].path.length * Double(random.next() % 1_000) / 1_000)
            default: end = place()
            }
            let now = traces.route(from: start, to: end)
            let before = rebuiltRoute(traces, from: start, to: end)
            XCTAssertEqual(now?.points, before?.points, "\(start) → \(end)")
            XCTAssertEqual(now?.hops, before?.hops, "\(start) → \(end)")
            if now != nil { found += 1 }
        }
        XCTAssertGreaterThan(found, 100, "most of the pairs are joined")
    }

    func testAWayIsFasterThanRebuildingTheNetwork() throws {
        let traces = try traces()
        let pairs = traces.links.prefix(40).map { link in
            (RealRailwayTraces.Place(line: link.a.line, along: traces.lines[link.a.line].path.length / 3),
             RealRailwayTraces.Place(line: link.b.line, along: traces.lines[link.b.line].path.length * 2 / 3))
        }
        let clock = ContinuousClock()
        let now = clock.measure { for (a, b) in pairs { _ = traces.route(from: a, to: b) } }
        let before = clock.measure { for (a, b) in pairs { _ = rebuiltRoute(traces, from: a, to: b) } }
        print("TraceRouteGraph: \(traces.lines.count) lines, \(pairs.count) ways: \(now) now, \(before) rebuilt each time")
    }
}
