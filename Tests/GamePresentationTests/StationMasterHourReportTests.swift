import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// What the station master's corner works out on the main actor once a
/// game hour at 6000× (decision 459; 92.1's game of 81 stations and 22
/// lines stopped some 400 ms an hour): the advice as the corner worked it
/// out before, and as it reads it now from what the news kept, with the
/// game loop's ticks worked out off the main actor; and letting go of the
/// world a tick replaced. Run on request, in release:
///
///     STATION_MASTER_HOURS=24 swift test -c release -Xswiftc -enable-testing --filter StationMasterHourReportTests
///
/// `STATION_MASTER_HOURS` is the number of game hours; with
/// `STATION_MASTER_SAVE=<save>` (a `.alongtheline` file or a `SavedGame`)
/// the save's world, else a synthetic grid of 9 × 9 stations, a line along
/// every row and column (`STATION_MASTER_GRID` sets the side).
@MainActor
final class StationMasterHourReportTests: XCTestCase {
    func testWhatTheCornerWorksOutEachHour() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let hours = Int(environment["STATION_MASTER_HOURS"] ?? "") else {
            throw XCTSkip("set STATION_MASTER_HOURS=<hours> to time the station master's corner")
        }
        let world: GameWorld
        if let path = environment["STATION_MASTER_SAVE"] {
            struct SharedFile: Decodable { let game: SavedGame }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let saved = try (try? JSONDecoder().decode(SharedFile.self, from: data).game) ?? JSONDecoder().decode(SavedGame.self, from: data)
            world = saved.world
        } else {
            let side = Int(environment["STATION_MASTER_GRID"] ?? "") ?? 9
            world = try Self.grid(side: side, trains: Int(environment["STATION_MASTER_TRAINS"] ?? "") ?? 8)
        }
        let session = GameSession(world: world)
        session.setSpeed(.fast)
        let clock = ContinuousClock()
        var before = Duration.zero, now = Duration.zero, release = Duration.zero, releases = 0
        var slowestBefore = Duration.zero, slowestNow = Duration.zero, slowestRelease = Duration.zero, slowestReleaseAt: Int64 = 0
        var lastHour = session.adviceHour, seen = 0
        print("stations \(world.stations.count), lines \(world.lines.count), trains \(world.trains.count)")
        while seen < hours {
            var tick = session.beginLoopTick()
            let outcome = try await XCTUnwrap(tick).work()
            XCTAssertTrue(session.finish(try XCTUnwrap(tick), with: outcome))
            // What the game loop let go of on the main actor before
            // decision 459, which it now lets go of off it.
            let let_go = clock.measure { tick = nil }
            release += let_go
            releases += 1
            if let_go > slowestRelease { slowestRelease = let_go; slowestReleaseAt = session.world.clock.now.seconds }
            guard session.adviceHour != lastHour else { continue }
            lastHour = session.adviceHour
            seen += 1
            // What the corner did on the main actor before decision 459,
            // then what it does now.
            var old: StationMasterAdvice?
            let spentBefore = clock.measure {
                old = StationMasterAdvice(world: session.world, worstLosingLine: { session.worstLosingLine })
            }
            var new: StationMasterAdvice?
            let spentNow = clock.measure { new = session.stationMasterAdvice }
            XCTAssertEqual(new, old, "hour \(lastHour)")
            before += spentBefore
            now += spentNow
            slowestBefore = max(slowestBefore, spentBefore)
            slowestNow = max(slowestNow, spentNow)
        }
        func ms(_ duration: Duration) -> String {
            String(format: "%.2f ms", Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
        }
        print("hours \(hours): before \(ms(before / hours)) an hour (slowest \(ms(slowestBefore))), "
            + "now \(ms(now / hours)) (slowest \(ms(slowestNow))), worked out on the main actor \(session.stationMasterAdviceWorkedOut)")
        print("letting go of the world a tick replaced: \(ms(release / releases)) a tick (slowest \(ms(slowestRelease)) at \(slowestReleaseAt) s), \(releases) ticks")
    }

    /// A grid of `side × side` stations, 1 km apart, a line along every row
    /// and every column with `trains` trains of four cars, running all day
    /// from 07:00 (9 × 9 and 8: 81 stations, 18 lines, 144 trains, near
    /// 92.1's game).
    static func grid(side: Int, trains: Int) throws -> GameWorld {
        let spacing = 1_000 * WorldCoordinate.unitsPerMetre
        var world = GameWorld(bounds: try WorldBounds(width: spacing * Int64(side + 1), height: spacing * Int64(side + 1)),
                              economy: GameEconomy(balance: 1_000_000_000, costs: testCosts),
                              clock: GameClock(now: GameTime(minutes: 420)))
        let nodes = try (0..<side).map { y in
            try (0..<side).map { x in
                try world.buildTrackNode(at: WorldCoordinate(x: spacing * Int64(x + 1), y: spacing * Int64(y + 1)))
            }
        }
        let east = try (0..<side).map { y in
            try (0..<(side - 1)).map { try world.buildTrackEdge(from: nodes[y][$0], to: nodes[y][$0 + 1]) }
        }
        let south = try (0..<side).map { x in
            try (0..<(side - 1)).map { try world.buildTrackEdge(from: nodes[$0][x], to: nodes[$0 + 1][x]) }
        }
        let platform = 200 * WorldCoordinate.unitsPerMetre
        let stations = try (0..<side).map { y in
            try (0..<side).map { x in
                let id = try world.buildStation(named: "S\(x)-\(y)",
                    at: PlanPoint(x: spacing * Int64(x + 1), y: spacing * Int64(y + 1))).id
                if x + 1 < side {
                    try world.addTrackPlatform(id, on: east[y][x], from: 0, to: platform)
                } else {
                    try world.addTrackPlatform(id, on: east[y][x - 1], from: spacing - platform, to: spacing)
                }
                if y + 1 < side {
                    try world.addTrackPlatform(id, on: south[x][y], from: 0, to: platform)
                } else {
                    try world.addTrackPlatform(id, on: south[x][y - 1], from: spacing - platform, to: spacing)
                }
                return id
            }
        }
        var lines = try (0..<side).map { try world.createLine(named: "Row \($0)", stops: stations[$0]).id }
        lines += try (0..<side).map { x in try world.createLine(named: "Column \(x)", stops: stations.map { $0[x] }).id }
        for line in lines {
            try world.setLineServiceWindow(line, to: .allDay)
            for index in 0..<trains {
                let train = try world.purchaseTrain(named: "\(line.rawValue)-\(index)").id
                try world.setTrainCars(train, to: 4)
                try world.assignTrain(train, to: line)
            }
        }
        let kinds: [StationDemandKind] = [.residential, .office, .shopping, .scenic]
        for (index, id) in stations.joined().enumerated() {
            try world.setStationDemand(id, to: StationDemand(kind: kinds[index % kinds.count], dailyTrips: 5_000))
        }
        world.setPassengerRoutingMode(.network)
        return world
    }
}
