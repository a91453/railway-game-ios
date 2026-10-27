import Foundation
@testable import GameCore
import XCTest

/// The ticks of a save file a player sent, timed (派工單 AQ: a Kaohsiung
/// game of 78 stations whose 06:00 tick took minutes). The file is the
/// player's and stays out of the repository; run on request:
///
///     PASSENGER_ROUTE_SAVE=<file> swift test --filter PassengerRouteSaveReportTests
///
/// `PASSENGER_ROUTE_SAVE` is a save (`SavedGame`, or a shared
/// `.alongtheline` file holding one under `game`). `PASSENGER_ROUTE_UNTIL`
/// is how many game seconds to run (default 120, which crosses 06:00 from
/// 05:59:57); `PASSENGER_ROUTE_SPEED` the speed (a ``GameSpeed`` raw
/// value, default `x60`). `PASSENGER_ROUTE_DUMP`, when set, is where the
/// world at the end is written, to compare two builds byte for byte.
final class PassengerRouteSaveReportTests: XCTestCase {
    private struct SharedFile: Decodable {
        let game: SavedGame
    }

    func testTheTicksOfASave() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["PASSENGER_ROUTE_SAVE"] else {
            throw XCTSkip("set PASSENGER_ROUTE_SAVE=<file> to time a save's ticks")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let saved = try (try? JSONDecoder().decode(SharedFile.self, from: data).game)
            ?? JSONDecoder().decode(SavedGame.self, from: data)
        let seconds = Int64(environment["PASSENGER_ROUTE_UNTIL"] ?? "") ?? 120
        let speed = try XCTUnwrap(GameSpeed(rawValue: environment["PASSENGER_ROUTE_SPEED"] ?? "x60"))
        var world = saved.world
        world.setSpeed(speed)
        let end = world.clock.now.seconds + seconds
        let clock = ContinuousClock()
        var slowest = Duration.zero, total = Duration.zero, ticks = 0
        print("stations \(world.stations.count), lines \(world.lines.count), trains \(world.trains.count), from \(world.clock.now.seconds)")
        while world.clock.now.seconds < end {
            let before = world.clock.now.seconds
            let spent = try clock.measure { try world.advance(ticks: 1) }
            ticks += 1
            total += spent
            slowest = max(slowest, spent)
            if spent > .milliseconds(200) { print("tick at \(before): \(spent)") }
        }
        print("ticks \(ticks), total \(total), slowest \(slowest)")
        if let dump = environment["PASSENGER_ROUTE_DUMP"] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            try encoder.encode(SavedGame(world: world)).write(to: URL(fileURLWithPath: dump))
        }
    }
}
