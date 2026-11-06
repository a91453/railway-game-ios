import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 614 (PERF-115): what one build command costs on a late-game
/// network, from the press to the ticks after it. Run on request.
///
/// Make the save (not committed; a generated game, kept in a scratch
/// directory):
///
///     PERF_MAKE_SAVE=/tmp/big.json swift test -c release -Xswiftc -enable-testing \
///       --skip-build --filter BuildCommandCostReportTests/testMakingALateGameSave
@MainActor
final class BuildCommandCostReportTests: XCTestCase {
    static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    /// `world` in a session with the app's real-world data, as the
    /// launcher hands it.
    static func session(of world: GameWorld) throws -> GameSession {
        let session = GameSession(world: world, language: .traditionalChinese)
        let data = Map3DOpenEveryStartTests.data
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.heights = data.heights
        session.coverage = data.coverage
        session.railways = data.railways
        return session
    }

    /// The whole of Taiwan with every line on sale bought that its money allows, played
    /// a few game hours so the trains are out.
    func testMakingALateGameSave() async throws {
        guard let path = ProcessInfo.processInfo.environment["PERF_MAKE_SAVE"] else {
            throw XCTSkip("set PERF_MAKE_SAVE=<file> to make the save")
        }
        // The fixed frame time test's Taipei (decision 421) with its real
        // lines laid as the player's own, then every real line on sale
        // bought on top.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PERF115-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        await launcher.loadRealWorldData { Map3DOpenEveryStartTests.data }.value
        let own = Int(ProcessInfo.processInfo.environment["PERF_OWN_LINES"] ?? "") ?? 20
        let opened = await launcher.openFrameTimeBench(lines: own)
        let session = try XCTUnwrap(opened, "the frame time test's game")
        print("PERF115 laid: stations \(session.world.stations.count), lines \(session.world.lines.count), trains \(session.world.trains.count)")
        let lines = Int(ProcessInfo.processInfo.environment["PERF_LINES"] ?? "") ?? 40
        print("PERF115 on sale: \(session.buyableRealLines.map(\.id).joined(separator: " "))")
        var bought = 0
        for _ in 0..<lines {
            guard let line = session.buyableRealLines.first(where: { session.realLineOffer(for: $0).problem == nil }) else { break }
            let offer = session.realLineOffer(for: line)
            if session.acquireRealLine(offer) { bought += 1; print("PERF115 bought \(line.id)") } else { break }
        }
        print("PERF115 bought \(bought): stations \(session.world.stations.count), lines \(session.world.lines.count), trains \(session.world.trains.count), edges \(session.world.network.edges.count)")
        var world = session.world
        world.setSpeed(.normal)
        try world.advance(ticks: Int(ProcessInfo.processInfo.environment["PERF_HOURS"] ?? "").map { $0 * 60 } ?? 180)
        print("PERF115 at \(world.clock.now.clockText): trains \(world.trains.count)")
        try SaveLibrary.encode(world, at: Date()).write(to: URL(fileURLWithPath: path))
    }

    /// One build command on the save at `PERF_SAVE`, taken apart: the
    /// command on the main actor, what the screen asks for after it, and
    /// the game loop's ticks after it beside the ticks before.
    ///
    ///     PERF_SAVE=/tmp/big.json PERF_COMMAND=track|station|line \
    ///       swift test -c release -Xswiftc -enable-testing --skip-build \
    ///       --filter BuildCommandCostReportTests/testWhatABuildCommandCosts
    func testWhatABuildCommandCosts() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["PERF_SAVE"] else { throw XCTSkip("set PERF_SAVE=<save> to time a build command") }
        let world = try SaveLibrary.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        let session = try Self.session(of: world)
        print("PERF115 world: stations \(world.stations.count), lines \(world.lines.count), trains \(world.trains.count), edges \(world.network.edges.count), \(world.clock.now.clockText)")
        session.setSpeed(.normal)
        let clock = ContinuousClock()
        // What the screen reads after a change, as the app does.
        func screen(_ label: String) {
            var parts: [String] = []
            func time(_ name: String, _ read: () -> Void) {
                parts.append(String(format: "%@ %.1f", name, Self.ms(clock.measure(read))))
            }
            time("traffic") { _ = session.trafficOverlay }
            time("advice") { _ = session.stationMasterAdvice }
            time("alerts") { _ = session.situationAlerts }
            time("sale") { _ = session.buyableRealLines }
            let world = session.world
            time("marks") { _ = MapMarks(world: world, situationAlerts: []) }
            time("mapAlerts") { _ = world.mapAlerts() }
            time("nextSteps") { _ = NextSteps(world: world) }
            time("transfers") { _ = session.wantedTransfers() }
            time("lineMap") { _ = LineMap(world: world) }
            time("equal") { _ = world == session.world }
            time("placeToPass") { _ = world.firstLineWithoutPlaceToPass() }
            print("PERF115   \(label) screen ms: \(parts.joined(separator: ", "))")
        }
        func tick(_ label: String) async throws -> Double {
            guard let tick = session.beginLoopTick() else { return 0 }
            if environment["PERF_PARTS"] != nil {
                var ahead = tick.world
                let routes = await clock.measure { ahead = await PassengerRoutesAhead.given(to: tick.world) }
                var after = ahead
                let core = try clock.measure { after = try GameSession.advanced(ahead, by: 1, listening: false).world }
                let advice = clock.measure { _ = tick.advice?.advice(of: after) }
                let traffic = clock.measure { _ = TrafficReading(world: after, train: nil, in: .traditionalChinese, previous: nil) }
                let alerts = clock.measure { _ = after.situationAlerts() }
                print(String(
                    format: "PERF115   %@ parts: routes ahead %.1f, advance %.1f, advice %.1f, traffic %.1f, alerts %.1f ms",
                    label, Self.ms(routes), Self.ms(core), Self.ms(advice), Self.ms(traffic), Self.ms(alerts)
                ))
            }
            var outcome: Result<GameSession.TickStep, GameError>!
            let step = await clock.measure { outcome = await tick.work() }
            let finish = clock.measure { session.finish(tick, with: outcome) }
            if case .failure(let error) = outcome { XCTFail("\(error)") }
            print(String(format: "PERF115   %@ tick at %@: step %.1f ms, finish %.1f ms", label, tick.world.clock.now.clockText, Self.ms(step), Self.ms(finish)))
            return Self.ms(step)
        }
        screen("opened")
        let warm = Int(environment["PERF_WARM"] ?? "") ?? 10
        var before: [Double] = []
        for index in 0..<warm { before.append(try await tick("warm \(index)")) }
        screen("steady")
        // The command, as the app's tools make it.
        let kind = environment["PERF_COMMAND"] ?? "track"
        let metre = WorldCoordinate.unitsPerMetre
        var built = false
        func pressing() throws -> Duration {
        let press: Duration
        switch kind {
        case "station":
            // A platform on the middle of the longest stretch of track.
            session.setNetworkMode(.platform)
            let edge = try XCTUnwrap(session.world.network.edges.max { ($0.length, $1.id.number) < ($1.length, $0.id.number) })
            let a = try XCTUnwrap(session.world.network.node(edge.from)).position.plan
            let b = try XCTUnwrap(session.world.network.node(edge.to)).position.plan
            let pick = clock.measure { session.tapNetwork(at: PlanPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), reach: 2_000 * metre) }
            print(String(format: "PERF115   pick ms: %.1f", Self.ms(pick)))
            let count = session.world.stations.count
            press = clock.measure { session.addNetworkPlatform() }
            built = session.world.stations.count > count
        case "line":
            // A short line over two of the first own line's stations.
            let line = try XCTUnwrap(session.world.lines.first)
            for stop in line.stops.prefix(3) {
                session.selectStation(stop)
                session.addSelectedStationToLineDraft()
            }
            let preview = clock.measure { _ = session.lineDraftSummary; _ = session.lineOpeningPreview }
            print(String(format: "PERF115   line preview ms: %.1f", Self.ms(preview)))
            let count = session.world.lines.count
            press = clock.measure { session.createLineFromDraft() }
            built = session.world.lines.count > count
        default:
            // Track from a dead end, 300 m on.
            session.setNetworkMode(.build)
            let ends = session.world.network.nodes.filter { $0.ends.count == 1 }
            var found: Duration?
            search: for end in ends {
                for (dx, dy) in [(300, 0), (-300, 0), (0, 300), (0, -300)] {
                    session.clearNetworkDraft()
                    let at = end.position.plan
                    session.tapNetwork(at: at, reach: 20 * metre)
                    session.tapNetwork(at: PlanPoint(x: at.x + Int64(dx) * metre, y: at.y + Int64(dy) * metre), reach: 20 * metre)
                    let preview = clock.measure { _ = session.networkPreview(now: true) }
                    guard session.networkPreview(now: true)?.problem == nil else { continue }
                    print(String(format: "PERF115   track preview ms: %.1f", Self.ms(preview)))
                    let count = session.world.network.edges.count
                    found = clock.measure { session.buildNetworkTrack() }
                    built = session.world.network.edges.count > count
                    if built { break search }
                }
            }
            press = try XCTUnwrap(found, "no dead end to build from")
        }
        return press
        }
        let press = try pressing()
        XCTAssertTrue(built, "\(kind): \(session.message?.text ?? "")")
        // For a profiler: the command taken back and made again.
        for _ in 0..<(Int(environment["PERF_REPEAT"] ?? "") ?? 0) {
            session.undo()
            print(String(format: "PERF115   again ms: %.1f", Self.ms(try pressing())))
        }
        print(String(format: "PERF115 %@ command on the main actor: %.1f ms (%@)", kind, Self.ms(press), session.message?.text ?? ""))
        screen("after")
        screen("again")
        var after: [Double] = []
        for index in 0..<(Int(environment["PERF_AFTER"] ?? "") ?? 5) { after.append(try await tick("after \(index)")) }
        print(String(
            format: "PERF115 %@: ticks before mean %.1f ms; first after %.1f ms, then %@",
            kind, before.reduce(0, +) / Double(max(1, before.count)), after.first ?? 0,
            after.dropFirst().map { String(format: "%.1f", $0) }.joined(separator: ", ")
        ))
    }
}
