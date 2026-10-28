import Foundation
#if canImport(Glibc)
import Glibc
#endif
@testable import GameCore
import XCTest

/// Every route of a synthetic network of many stations, timed, with the
/// process's peak memory (派工單 BB: the searches of #1385 kept a copy of
/// themselves at every call, past 1 GB at 120 stations). Run on request:
///
///     PASSENGER_ROUTE_SYNTHETIC=200 swift test -c release --filter PassengerRouteMemoryReportTests
///
/// `PASSENGER_ROUTE_SYNTHETIC` is the number of stations: a line for
/// every five, both ways, of 12 to 21 stations, with walks between
/// stations near each other. Each origin asks every destination its three
/// routes, as a passenger plan does. The checksum of the routes compares
/// two builds. `PASSENGER_ROUTE_LIMITS=<checkpoints>,<searches>,<labels>`
/// sets the limits of ``PassengerRouteSearches``.
final class PassengerRouteMemoryReportTests: XCTestCase {
    func testEveryRouteOfASyntheticNetwork() throws {
        guard let stations = Int(ProcessInfo.processInfo.environment["PASSENGER_ROUTE_SYNTHETIC"] ?? "") else {
            throw XCTSkip("set PASSENGER_ROUTE_SYNTHETIC=<stations> to time a synthetic network")
        }
        var random = SplitMix64(seed: 0xBB_2026_1028)
        let ids = (1...stations).map { StationID(rawValue: $0) }
        var paths: [PassengerRouteGraph.ServicePath] = []
        for line in 1...max(1, stations / 5) {
            let calls = Array(random.shuffled(ids).prefix(12 + random.below(10)))
            let runs = (1..<calls.count).map { _ in Int64(90 + random.below(300)) }
            let headway = Int64(300 + random.below(900))
            for direction in [LineDirection.outbound, .inbound] {
                let forward = direction == .outbound
                paths.append(PassengerRouteGraph.ServicePath(
                    line: LineID(rawValue: line), pattern: nil, direction: direction,
                    stations: forward ? calls : calls.reversed(), runSeconds: forward ? runs : runs.reversed(),
                    headway: headway, isRing: false, dwellSeconds: 30))
            }
        }
        let metre = WorldCoordinate.unitsPerMetre
        let points = ids.map { _ in PlanPoint(x: Int64(random.below(20_000)) * metre, y: Int64(random.below(20_000)) * metre) }
        var walks: [StationID: [PassengerWalk]] = [:]
        for (from, origin) in ids.enumerated() {
            for (to, destination) in ids.enumerated() where to != from {
                if let walk = PassengerWalk(from: points[from], to: points[to], station: destination) {
                    walks[origin, default: []].append(walk)
                }
            }
        }
        let graph = PassengerRouteGraph(paths: paths, walks: walks, closed: [])
        let limits = (ProcessInfo.processInfo.environment["PASSENGER_ROUTE_LIMITS"] ?? "").split(separator: ",").compactMap { Int($0) }
        var searches = limits.count == 3
            ? PassengerRouteSearches(graph: graph, checkpointLimit: limits[0], searchLimit: limits[1],
                                     labelBudget: limits[2])
            : PassengerRouteSearches(graph: graph)
        var checksum: UInt64 = 0xcbf2_9ce4_8422_2325
        var routes = 0
        var mostCopies = 0, mostLabels = 0
        let clock = ContinuousClock()
        let spent = clock.measure {
            for origin in ids {
                for destination in ids where destination != origin {
                    for route in Self.routes(from: origin, to: destination, searches: &searches) {
                        routes += 1
                        for byte in String(describing: route).utf8 {
                            checksum = (checksum ^ UInt64(byte)) &* 0x100_0000_01b3
                        }
                    }
                    mostCopies = max(mostCopies, searches.copies)
                    mostLabels = max(mostLabels, searches.bannedLabels)
                }
            }
        }
        print("stations \(stations), paths \(paths.count), routes \(routes), checksum \(String(checksum, radix: 16)), "
            + "time \(spent), most copies \(mostCopies), most banned labels \(mostLabels), peak memory \(Self.peakMegabytes()) MB")
    }

    /// The k-shortest routes of `GameWorld.passengerRoutes(from:to:limit:searches:)`,
    /// on a graph with no world.
    private static func routes(from origin: StationID, to destination: StationID,
                               searches: inout PassengerRouteSearches) -> [PassengerRoute] {
        guard let first = searches.shortest(from: origin, to: destination, banning: []) else { return [] }
        var selected = [first.0]
        var candidates: [(route: PassengerRoute, edges: [PassengerRideEdge], bans: Set<PassengerRideEdge>)] = []
        var chosen = (route: first.0, edges: first.1, bans: Set<PassengerRideEdge>())
        var tried: Set<Set<PassengerRideEdge>> = [[]]
        while selected.count < 3 {
            for edge in chosen.edges {
                var bans = chosen.bans
                bans.insert(edge)
                guard tried.insert(bans).inserted,
                      let found = searches.shortest(from: origin, to: destination, banning: bans),
                      !selected.contains(found.0), !candidates.contains(where: { $0.route == found.0 })
                else { continue }
                candidates.append((found.0, found.1, bans))
            }
            guard !candidates.isEmpty else { break }
            candidates.sort { passengerRoutePrecedes($0.route, $1.route) }
            chosen = candidates.removeFirst()
            selected.append(chosen.route)
        }
        return selected.sorted(by: passengerRoutePrecedes)
    }

    /// The process's peak resident memory (`getrusage`'s `ru_maxrss`:
    /// kilobytes on Linux, bytes on Apple's systems).
    static func peakMegabytes() -> Int {
        var usage = rusage()
        #if canImport(Darwin)
        getrusage(RUSAGE_SELF, &usage)
        return Int(usage.ru_maxrss) / 1_048_576
        #else
        getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage)
        return Int(usage.ru_maxrss) / 1_024
        #endif
    }
}
