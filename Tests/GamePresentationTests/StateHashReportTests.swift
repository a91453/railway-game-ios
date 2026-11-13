import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// HEALTH-129 (`docs/research/HEALTH_129_2026-11-13.md`): a world played
/// with no commands and a hash of its whole saved state printed every game
/// hour, so two builds can be told to play it alike: run the same command
/// on each and compare the lines (diagnosing-bugs: a command that turns
/// red). It asserts nothing and runs only on request:
///
///     swift build -c release -Xswiftc -enable-testing --build-tests
///     STATE_HASH_REPORT=tymc STATE_HASH_MODE=minute swift test -c release --skip-build --filter StateHashReportTests
///
/// `STATE_HASH_REPORT` is the world: `wenhu`, `tymc`, `klrt` (bought as a
/// new game has them: simple rules, traffic control on;
/// `STATE_HASH_REALISTIC=1` under realistic rules), `tymc-peopled` (the
/// Taoyuan Airport MRT with the map's people, as `AirportReportTests`
/// plays it), `tra`, `hsr` and `demo` (the demos). `STATE_HASH_MODE` is
/// how the clock is stepped: `minute` (a minute a tick, one tick at a
/// time), `batch` (the same ticks, sixty to a call) or `fast` (the top
/// speed, ten minutes a tick). `STATE_HASH_HOURS` is the hours played (48).
@MainActor
final class StateHashReportTests: XCTestCase {
    func testAWorldsStateHourByHour() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let name = environment["STATE_HASH_REPORT"] else {
            throw XCTSkip("set STATE_HASH_REPORT=<world> to print its state's hash hour by hour")
        }
        let rules: NewGameRules = environment["STATE_HASH_REALISTIC"] != nil ? .realistic : .simple
        var world: GameWorld
        switch name {
        case "wenhu": world = try DepotReturnReportTests.bought("trtc:BR", rules: rules)
        case "tymc": world = try DepotReturnReportTests.bought("tymc:A", rules: rules, side: 1 << 22)
        case "klrt": world = try DepotReturnReportTests.bought("krtc:C", rules: rules)
        case "tymc-peopled": world = try AirportReportTests.bought("tymc:A", data: RealWorldData.load(file: RealWorldDataLoadTests.file), rules: rules)
        case "tra": world = try TRADemoTests.opened.get()
        case "hsr": world = try HighSpeedDemoTests.opened.get()
        case "demo": world = DemoWorld.make(in: .english)
        default: throw HeadlessGameError("STATE_HASH_REPORT \(name) is not a world of this report")
        }
        let mode = environment["STATE_HASH_MODE"] ?? "minute"
        let hours = environment["STATE_HASH_HOURS"].flatMap { Int($0) } ?? 48
        world.setSpeed(mode == "fast" ? .fast : .normal)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func line(_ hour: Int) throws {
            let data = try encoder.encode(SavedGame(world: world))
            // FNV-1a, 64 bits.
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in data { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
            FileHandle.standardError.write(Data(
                "STATE_HASH \(name) \(rules == .realistic ? "realistic" : "simple") \(mode) hour \(hour): \(String(hash, radix: 16)) clock \(world.clock.now.seconds) bytes \(data.count)\n".utf8
            ))
        }
        try line(0)
        for hour in 1...hours {
            switch mode {
            case "minute": for _ in 0..<60 { try world.advance(ticks: 1) }
            case "batch": try world.advance(ticks: 60)
            case "fast": for _ in 0..<6 { try world.advance(ticks: 1) }
            default: throw HeadlessGameError("STATE_HASH_MODE \(mode) is not minute, batch or fast")
            }
            try line(hour)
        }
    }
}
