import Foundation
@testable import GameCore
import XCTest

/// ``GameWorld/servedWaitingLegs(onFreightLines:)``, which a loaded save's
/// passenger check and every command's sending away of the unserved
/// passengers make (`NEXT_PRIORITIES_2026-10-12.md` §2 item 3, a speed-up
/// only): whether a leg's service runs, which works out the service's
/// journey, is worked out once per line and pattern, not once per leg. The
/// legs it finds served are the ones it found asking every leg on its own
/// (``GameWorld/isServed(_:onFreightLines:)``), kept here as the reference.
///
/// On every committed save (``SaveFixtures``), as it loads and with waiting
/// passengers added for every line, its own service and each of its
/// patterns, one more pattern than it has, and a line that does not exist,
/// both ways, between stations on the line and off it, so that legs of one
/// line are served and unserved side by side, and legs of a freight line
/// are served only when freight lines count.
final class LoadJourneyCacheTests: XCTestCase {
    private static let saves = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("SaveFixtures")

    private static func worlds() throws -> [(String, GameWorld)] {
        let names = try FileManager.default.contentsOfDirectory(atPath: saves.path).filter { $0.hasSuffix(".json") }.sorted()
        return try names.map { name in
            (name, try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: saves.appendingPathComponent(name))).world)
        }
    }

    /// The legs still to ride of every waiting group, as the check gathers
    /// them.
    private static func pending(in world: GameWorld) -> Set<PassengerJourneyLeg> {
        Set(world.passengers.flatMap(\.waiting).flatMap { group in
            group.journey.map { Array($0.legs.dropFirst($0.current)) } ?? []
        })
    }

    /// The served legs, asking every leg on its own.
    private static func everyLegServed(in world: GameWorld, onFreightLines: Bool) -> Set<PassengerJourneyLeg> {
        Set(pending(in: world).filter { world.isServed($0, onFreightLines: onFreightLines) })
    }

    /// `world` with one passenger waiting at its first station for each leg
    /// of every line, pattern and direction between the line's first stops
    /// and a station off it.
    private static func withLegsOfEveryService(_ world: GameWorld) -> GameWorld {
        var world = world
        guard let first = world.stations.first?.id, let offLine = world.stations.last?.id else { return world }
        // The first station's record, made if it has none (records are in
        // station order).
        if world.passengers.first?.station != first { world.passengers.insert(StationPassengers(station: first), at: 0) }
        let at = 0
        var lines = world.lines.map { ($0.id, $0.patterns.count, $0.stops) }
        // A line that does not exist, between the first line's stops.
        if let first = lines.first { lines.append((LineID(rawValue: world.lines.map(\.id.rawValue).max()! + 1), 0, first.2)) }
        for (line, patterns, stops) in lines {
            let stations = Array(Set(stops.prefix(3) + [offLine])).sorted()
            for pattern in [nil] + (0...patterns).map(Optional.some) {
                for direction in [LineDirection.outbound, .inbound] {
                    for from in stations {
                        for to in stations where to != from {
                            let leg = PassengerRouteLeg(line: line, pattern: pattern, direction: direction, from: from, to: to, rideSeconds: 60)
                            let route = PassengerRoute(legs: [leg], rideMinutes: 1, waitMinutes: 0, transferSeconds: 0, walkSeconds: 0)
                            guard let journey = PassengerJourney(origin: from, route: route) else { continue }
                            world.passengers[at].release(1, along: journey, at: world.clock.now)
                        }
                    }
                }
            }
        }
        return world
    }

    func testEverySaveServesTheLegsEveryLegAskedOnItsOwnServes() throws {
        var served = 0, unserved = 0, saves = 0, savesWithJourneys = 0, freightOnly = 0
        for (name, loaded) in try Self.worlds() {
            saves += 1
            if !Self.pending(in: loaded).isEmpty { savesWithJourneys += 1 }
            for world in [loaded, Self.withLegsOfEveryService(loaded)] {
                for onFreightLines in [false, true] {
                    let reference = Self.everyLegServed(in: world, onFreightLines: onFreightLines)
                    XCTAssertEqual(world.servedWaitingLegs(onFreightLines: onFreightLines), reference, "\(name), on freight lines \(onFreightLines)")
                    served += reference.count
                    if onFreightLines { freightOnly += reference.subtracting(Self.everyLegServed(in: world, onFreightLines: false)).count }
                    unserved += Self.pending(in: world).count - reference.count
                }
            }
        }
        XCTAssertGreaterThan(saves, 40)
        XCTAssertGreaterThan(savesWithJourneys, 3, "saves with passengers waiting on planned journeys")
        XCTAssertGreaterThan(served, 500)
        XCTAssertGreaterThan(unserved, 500)
        XCTAssertGreaterThan(freightOnly, 0, "legs served only when freight lines count")
    }

    /// Of one line, its own service runs and a pattern it does not have
    /// does not: legs of both, side by side, are told apart however the
    /// legs are visited.
    func testServicesOfOneLineAreToldApart() throws {
        var compared = 0
        for (name, loaded) in try Self.worlds() {
            let world = Self.withLegsOfEveryService(loaded)
            let served = world.servedWaitingLegs()
            for line in world.lines {
                let legs = Self.pending(in: world).filter { $0.line == line.id }
                let own = legs.filter { $0.pattern == nil && world.isServed($0) }
                let beyond = legs.filter { $0.pattern == line.patterns.count }
                guard !own.isEmpty, !beyond.isEmpty else { continue }
                XCTAssertTrue(own.isSubset(of: served), "\(name), line \(line.id.rawValue)")
                XCTAssertTrue(beyond.isDisjoint(with: served), "\(name), line \(line.id.rawValue)")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 20)
    }
}
