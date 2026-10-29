@testable import GameCore
@testable import GamePresentation
import XCTest

/// A player's anonymous crash report on 0.5.0 (90.1), iPad Air (5th
/// generation): "with about 50 stations the whole thing froze and would
/// not move". A grid of 49 stations, 7 row lines and 7 column lines, so
/// every station is a transfer, two trains a line, or a player's save:
/// what the app's loop and the main actor work out at 6000× and after an
/// edit. The grid stays cheap in every build (its longest tick 16–19 ms
/// in Linux release); what froze 90.1 was the real map's passenger routes
/// at 06:00 (the 91.1 Kaohsiung save of 78 stations: 27.5 s, now 1.2 s).
@MainActor
final class FiftyStationFreezeTests: XCTestCase {
    static let columns = 7
    static let rows = 7

    static func grid() throws -> GameWorld {
        let spacing: Int64 = 1_500 * WorldCoordinate.unitsPerMetre
        let platform: Int64 = 150 * WorldCoordinate.unitsPerMetre
        var world = GameWorld(bounds: try WorldBounds(width: spacing * Int64(columns + 1), height: spacing * Int64(rows + 1)),
                              economy: GameEconomy(balance: 1_000_000_000, costs: testCosts),
                              clock: GameClock(now: GameTime(minutes: 300)))
        var nodes: [[TrackNodeID]] = []
        for y in 0..<rows {
            nodes.append(try (0..<columns).map { x in
                try world.buildTrackNode(at: WorldCoordinate(x: spacing * Int64(x + 1), y: spacing * Int64(y + 1)))
            })
        }
        var east: [[TrackEdgeID]] = []
        var south: [[TrackEdgeID]] = []
        for y in 0..<rows {
            east.append(try (0..<(columns - 1)).map { try world.buildTrackEdge(from: nodes[y][$0], to: nodes[y][$0 + 1]) })
        }
        for x in 0..<columns {
            south.append(try (0..<(rows - 1)).map { try world.buildTrackEdge(from: nodes[$0][x], to: nodes[$0 + 1][x]) })
        }
        var stations: [[StationID]] = []
        for y in 0..<rows {
            stations.append(try (0..<columns).map { x in
                let id = try world.buildStation(named: "S\(x)-\(y)",
                    at: PlanPoint(x: spacing * Int64(x + 1), y: spacing * Int64(y + 1))).id
                if x + 1 < columns {
                    try world.addTrackPlatform(id, on: east[y][x], from: 0, to: platform)
                } else {
                    try world.addTrackPlatform(id, on: east[y][x - 1], from: spacing - platform, to: spacing)
                }
                if y + 1 < rows {
                    try world.addTrackPlatform(id, on: south[x][y], from: 0, to: platform)
                } else {
                    try world.addTrackPlatform(id, on: south[x][y - 1], from: spacing - platform, to: spacing)
                }
                return id
            })
        }
        var lines: [LineID] = []
        for y in 0..<rows {
            lines.append(try world.createLine(named: "Row \(y)", stops: stations[y]).id)
        }
        for x in 0..<columns {
            lines.append(try world.createLine(named: "Column \(x)", stops: stations.map { $0[x] }).id)
        }
        for (index, line) in lines.enumerated() {
            try world.setLineServiceWindow(line, to: .allDay)
            for car in 0..<2 {
                let train = try world.purchaseTrain(named: "T\(index)-\(car)").id
                try world.assignTrain(train, to: line)
            }
        }
        for (index, id) in stations.joined().enumerated() {
            let kinds: [StationDemandKind] = [.residential, .office, .shopping, .scenic]
            try world.setStationDemand(id, to: StationDemand(kind: kinds[index % kinds.count], dailyTrips: 5_000))
        }
        world.setPassengerRoutingMode(.network)
        return world
    }

    /// The process's peak resident memory, as Linux counts it.
    static var peakMemory: String {
        (try? String(contentsOfFile: "/proc/self/status", encoding: .utf8))?
            .split(separator: "\n").first { $0.hasPrefix("VmHWM") }.map(String.init) ?? "unknown"
    }

    static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    /// One loop tick as the app runs it: the work off the main actor, then
    /// finishing it on the main actor.
    static func tick(_ session: GameSession) async throws -> (work: Duration, finish: Duration) {
        let clock = ContinuousClock()
        let tick = try XCTUnwrap(session.beginLoopTick())
        let start = clock.now
        let outcome = await tick.work()
        let worked = clock.now - start
        var finished = false
        let finish = clock.measure { finished = session.finish(tick, with: outcome) }
        XCTAssertTrue(finished)
        return (worked, finish)
    }

    /// What the main actor reads after a change (decision 465's list of
    /// what is common to every build).
    static func mainActorReads(_ session: GameSession) -> Duration {
        ContinuousClock().measure {
            _ = session.situationAlerts
            _ = session.nextSteps
            _ = session.trafficOverlay
            session.watchRouteHint()
        }
    }

    /// Run on request, in release (`FREEZE_SAVE=<save>` plays that game
    /// instead of the grid):
    ///
    ///     FREEZE_REPORT=<game days> swift test -c release -Xswiftc -enable-testing --filter FiftyStationFreezeTests
    func testWhatFiftyStationsCostAtFullSpeedAndAfterEdits() async throws {
        guard let days = ProcessInfo.processInfo.environment["FREEZE_REPORT"].flatMap(Int.init) else {
            throw XCTSkip("set FREEZE_REPORT=<game days> to time 49 stations at 6000x")
        }
        let clock = ContinuousClock()
        var world: GameWorld!
        let built = clock.measure {
            if let path = ProcessInfo.processInfo.environment["FREEZE_SAVE"] {
                // A `.alongtheline` file or a `SavedGame`.
                struct SharedFile: Decodable { let game: SavedGame }
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
                world = ((try? JSONDecoder().decode(SharedFile.self, from: data).game) ?? (try? JSONDecoder().decode(SavedGame.self, from: data)))?.world
            } else {
                world = try? Self.grid()
            }
        }
        let session = GameSession(world: try XCTUnwrap(world))
        print("built in \(Self.ms(built)) ms: stations \(session.world.stations.count), lines \(session.world.lines.count), trains \(session.world.trains.count)")
        session.setSpeed(.fast)
        let start = session.world.clock.now
        var count = 0
        var worst = (work: Duration.zero, finish: Duration.zero, reads: Duration.zero)
        var total = Duration.zero
        var worstAt = start
        // What 90.1's station master corner worked out on the main actor
        // every game hour (decisions 459, 465 moved it off).
        var hour = (start.seconds / 60) / 60
        var advice = (count: 0, total: Duration.zero, worst: Duration.zero)
        while session.world.clock.now.seconds / 60 < (start.seconds / 60) + Int64(days) * 1_440 {
            let (work, finish) = try await Self.tick(session)
            let reads = Self.mainActorReads(session)
            count += 1
            total += work
            if work > worst.work { worst.work = work; worstAt = session.world.clock.now }
            worst.finish = max(worst.finish, finish)
            worst.reads = max(worst.reads, reads)
            if session.world.clock.now.seconds / 60 / 60 != hour {
                hour = session.world.clock.now.seconds / 60 / 60
                let took = clock.measure {
                    _ = StationMasterAdvice(world: session.world)
                    _ = CompanyRank(world: session.world)
                }
                advice.count += 1
                advice.total += took
                advice.worst = max(advice.worst, took)
            }
        }
        print("peak memory \(Self.peakMemory)")
        print(String(format: "hourly station master advice and rank: %d hours, average %.1f ms, longest %.1f ms",
                     advice.count, Self.ms(advice.total) / Double(max(advice.count, 1)), Self.ms(advice.worst)))
        print(String(format: "6000x %d days: %d ticks, work %.0f ms total, longest %.1f ms (at day %ld %02ld:%02ld), longest finish %.1f ms, longest main-actor reads %.1f ms",
                     days, count, Self.ms(total), Self.ms(worst.work), (worstAt.seconds / 60) / 1_440, (worstAt.seconds / 60) % 1_440 / 60, (worstAt.seconds / 60) % 60,
                     Self.ms(worst.finish), Self.ms(worst.reads)))

        session.setSpeed(.normal)
        let ids = session.world.stations.map(\.id)
        let line = try XCTUnwrap(session.world.lines.first)
        let edits: [(String, PlayerCommand)] = [
            ("link a transfer", .edit(.linkTransfer(ids[0], ids[1]))),
            ("buy a train", .edit(.purchaseTrain(name: "Bought"))),
            ("open a line", .edit(.createLine(name: "New", stops: [ids[0], ids[1], ids[2]], targets: nil))),
            ("change the times", .edit(.setLineWindow(line.id, .standard))),
        ] + (Self.newStation(in: session.world, session: session).map { [("build a station", $0)] } ?? [])
        for (name, command) in edits {
            var outcome: PlayerCommand.Outcome?
            let edit = clock.measure { outcome = session.perform(command) { _, _, _ in "" } }
            XCTAssertNotNil(outcome, name)
            let reads = Self.mainActorReads(session)
            let (work, finish) = try await Self.tick(session)
            print(String(format: "%@: edit %.1f ms, main-actor reads %.1f ms, next tick off the main actor %.1f ms, finishing it %.1f ms",
                         name, Self.ms(edit), Self.ms(reads), Self.ms(work), Self.ms(finish)))
        }
    }

    /// A new station's platform in the middle of the first track edge long
    /// enough that has none, as the station tool builds it.
    static func newStation(in world: GameWorld, session: GameSession) -> PlayerCommand? {
        let platform = 150 * WorldCoordinate.unitsPerMetre
        for edge in world.network.edges where edge.length > 4 * platform {
            let start = edge.length / 2 - platform / 2
            guard let from = world.network.node(edge.from)?.position, let to = world.network.node(edge.to)?.position else { continue }
            let point = PlanPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            let command = PlayerCommand.addPlatform(PlayerCommand.PlatformAddition(
                edge: edge.id, start: start, end: start + platform,
                station: .new(name: "Built", at: point, demand: StationDemand(kind: .residential, dailyTrips: 1_000))
            ))
            var copy = world
            if (try? session.apply(command, to: &copy)) != nil { return command }
        }
        return nil
    }
}
