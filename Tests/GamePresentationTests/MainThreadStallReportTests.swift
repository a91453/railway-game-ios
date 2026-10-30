import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The main actor while a save runs at 6000× (派工單 STALL97: 97.1's
/// real-world game of 74 stations, 13 lines and 83 trains, whose iPhone
/// reported the 2D map's beat stopping 1–3.6 s at a time, nearly all of
/// it untimed). The save is the player's and stays out of the repository;
/// run on request, in release to see the device's proportions:
///
///     STALL_SAVE=<save> swift test -c release -Xswiftc -enable-testing --filter MainThreadStallReportTests
///
/// The game loop of ``GameSession/startGameLoop()`` runs a tick at a time
/// (each worked out off the main actor, as the app does), with every piece
/// it does on the main actor timed, while a heartbeat on the main actor
/// notes each gap above `STALL_GAP` ms (default 100), as the app's 2D beat
/// does. `STALL_SECONDS` is how long it runs (default 60);
/// `STALL_REAL`, when set, gives the session the app's real-world data
/// first; `STALL_SLOW` the ms above which a main-actor piece is printed
/// (default 50).
@MainActor
final class MainThreadStallReportTests: XCTestCase {
    func testTheMainActorAt6000x() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["STALL_SAVE"] else {
            throw XCTSkip("set STALL_SAVE=<save> to time the main actor of a save at 6000x")
        }
        let seconds = Int(environment["STALL_SECONDS"] ?? "") ?? 60
        let gapLimit = Duration.milliseconds(Int(environment["STALL_GAP"] ?? "") ?? 100)
        let slow = Duration.milliseconds(Int(environment["STALL_SLOW"] ?? "") ?? 50)
        struct SharedFile: Decodable { let game: SavedGame }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let saved = try (try? JSONDecoder().decode(SharedFile.self, from: data).game) ?? JSONDecoder().decode(SavedGame.self, from: data)
        let game = HeadlessGame(world: saved.world)
        let session = game.session
        if environment["STALL_REAL"] != nil {
            try game.install(
                RealWorldDataSet(population: true, places: true, water: true, heights: true, coverage: true, baseMap: true),
                from: CommandLogReplay.realWorld
            )
            session.readLandRoundStations()
        }
        session.setSpeed(.fast)
        if session.world.clock.isPaused { session.togglePause() }

        let clock = ContinuousClock()
        func ms(_ duration: Duration) -> String {
            String(format: "%.1f ms", Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
        }
        func when(_ seconds: Int64) -> String {
            let day = seconds / GameTime.secondsPerDay, rest = seconds % GameTime.secondsPerDay
            return String(format: "day %lld %02lld:%02lld", day, rest / 3_600, rest % 3_600 / 60)
        }

        // The heartbeat: the main actor's gaps, as the app's 2D beat.
        final class Beats { var gaps: [(Duration, Int64)] = [] }
        let beats = Beats()
        let heartbeat = Task { @MainActor in
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(8))
                let now = clock.now
                if now - last > gapLimit {
                    beats.gaps.append((now - last, session.world.clock.now.seconds))
                    print("[stall] gap \(ms(now - last)) at \(when(session.world.clock.now.seconds))")
                }
                last = now
            }
        }

        // What the app's views ask of each new world on the main actor:
        // the keys their `onChange`/`task(id:)` compare with the last
        // world's, and the small reads the map's body makes.
        let probing = environment["STALL_PROBE"] != nil
        var probes: [String: (total: Duration, longest: Duration, at: Int64)] = [:]
        func probe(_ old: GameWorld, _ new: GameWorld) {
            func time(_ name: String, _ work: () -> Void) {
                let spent = clock.measure(work)
                var entry = probes[name] ?? (.zero, .zero, 0)
                entry.total += spent
                if spent > entry.longest { entry.longest = spent; entry.at = new.clock.now.seconds }
                probes[name] = entry
                if spent > slow { print("[probe] \(name) \(ms(spent)) at \(when(new.clock.now.seconds))") }
            }
            time("land ==") { _ = old.land == new.land }
            time("buildings ==") { _ = old.buildings == new.buildings }
            time("network ==") { _ = old.network == new.network }
            time("trains ==") { _ = old.trains == new.trains }
            time("lines ==") { _ = old.lines == new.lines }
            time("stations ==") { _ = old.stations == new.stations }
            time("passengers ==") { _ = old.passengers == new.passengers }
            time("roads ==") { _ = old.roads == new.roads }
            time("roadCellCount") { _ = new.roads?.roadCellCount }
            time("roads.built") { _ = new.roads?.built }
            time("waitingPassengerCounts") { _ = MapLayers.waitingPassengerCounts(in: new) }
            time("LineBadge.codes") { _ = LineBadge.codes(for: new.lines) }
            time("RealWorldFrame") { _ = RealWorldFrame(world: new) }
            time("depotRuns") { _ = new.depotRuns() }
            time("forecast") { _ = new.forecast() }
            time("MapWeather") { _ = MapWeather(world: new) }
            time("world ==") { _ = old == new }
        }

        let started = session.world.clock.now.seconds
        let end = clock.now + .seconds(seconds)
        var ticks = 0
        var work = Duration.zero, longestWork = Duration.zero
        var mainTotal = Duration.zero
        while clock.now < end {
            let beginning = clock.now
            guard var tick = session.beginLoopTick() else { break }
            let begin = clock.now - beginning
            tick.readsTraffic = true
            let working = clock.now
            let outcome = await tick.work()
            let worked = clock.now - working
            work += worked
            longestWork = max(longestWork, worked)
            let previous = session.world
            let finishing = clock.now
            session.finish(tick, with: outcome)
            let finished = clock.now - finishing
            if probing { probe(previous, session.world) }
            let releasing = clock.now
            let replaced = consume tick
            Task.detached(priority: .utility) { _ = consume replaced }
            let released = clock.now - releasing
            ticks += 1
            mainTotal += begin + finished + released
            let at = session.world.clock.now.seconds
            for (name, spent) in [("begin", begin), ("finish", finished), ("release", released)] where spent > slow {
                print("[main] \(name) \(ms(spent)) at \(when(at))")
            }
            if worked > .milliseconds(1_000) { print("[tick] off the main actor \(ms(worked)) at \(when(at))") }
            if case .failure(let error) = outcome {
                print("tick failed: \(error)")
                break
            }
            // The loop's rest between steps lets the heartbeat in.
            try? await Task.sleep(for: .milliseconds(1))
        }
        heartbeat.cancel()
        let ran = session.world.clock.now.seconds - started
        print("ran \(ticks) ticks, \(when(started)) → \(when(session.world.clock.now.seconds)) (\(ran / 3_600) game hours)")
        print("off the main actor: \(ms(work)) in all, longest \(ms(longestWork)); timed main-actor pieces \(ms(mainTotal))")
        let severe = beats.gaps.filter { $0.0 >= .milliseconds(250) }
        for (name, entry) in probes.sorted(by: { $0.value.longest > $1.value.longest }) {
            print("probe \(name): \(ms(entry.total)) in all, longest \(ms(entry.longest)) at \(when(entry.at))")
        }
        print("heartbeat gaps over \(ms(gapLimit)): \(beats.gaps.count), 250 ms or more: \(severe.count), longest \(ms(beats.gaps.map(\.0).max() ?? .zero))")
    }
}
