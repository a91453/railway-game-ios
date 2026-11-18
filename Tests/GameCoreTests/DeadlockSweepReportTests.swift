import Foundation
@testable import GameCore
import XCTest

/// Decision 877 (DEADLOCK-SWEEP): where and when the trains of a saved
/// game stand in a deadlock, GameCore alone. A report, run only on
/// request; it asserts nothing and changes no rule:
///
///     DEADLOCK_SWEEP=/tmp/worlds/hk-all-simple.json swift test --skip-build \
///       --filter DeadlockSweepReportTests
///
/// The save is any ``SavedGame`` (`BoughtWorldSaveTests` writes the maps
/// with every line on sale bought). ``SavedWorldTickReportTests`` counts
/// the most trains deadlocked at once; this says which trains, where,
/// from when to when, whom each waits for, and what else stood: the
/// trains ``GameWorld/strandedTrains()`` names, the trains in service that
/// did not move for `DEADLOCK_SWEEP_STANDING` minutes past their
/// departure, and each timetabled line's runs not sent on each whole day
/// played.
///
/// - `DEADLOCK_SWEEP_TICKS`: the ticks played (default 2,880: two game
///   days at a minute a tick).
/// - `DEADLOCK_SWEEP_SPEED`: the ``GameSpeed`` played at (default
///   `normal`, a minute a tick; `fast` is ten, as a player at fast forward
///   plays, and the world is then looked at every ten minutes).
/// - `DEADLOCK_SWEEP_BATCH`: the ticks of each ``GameWorld/advance(ticks:)``
///   (default 1).
/// - `DEADLOCK_SWEEP_STANDING`: minutes (default 20).
/// - `DEADLOCK_SWEEP_EACH=1`: a checksum of the world every game hour.
final class DeadlockSweepReportTests: XCTestCase {
    private static func clockText(_ seconds: Int64) -> String {
        let minutes = seconds % GameTime.secondsPerDay / 60
        return String(format: "day %lld %02lld:%02lld", seconds / GameTime.secondsPerDay, minutes / 60, minutes % 60)
    }

    /// FNV-1a of the world's JSON, keys sorted, at the normal speed: the
    /// speed played at is a setting, not what the trains did.
    private static func checksum(of played: GameWorld) throws -> UInt64 {
        var world = played
        world.setSpeed(.normal)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var checksum: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in try encoder.encode(world) { checksum = (checksum ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return checksum
    }

    /// Train `id` in a line: its name, its line, where it stands or what
    /// it is bound for, and whether it runs empty.
    private static func describe(_ id: TrainID, in world: GameWorld) -> String {
        guard let train = world.train(id: id) else { return "train \(id)" }
        let line = world.lines.first { $0.trains.contains(id) }?.name ?? "no line"
        let at = world.stationsStoppedAt(by: id).first.flatMap { world.station(id: $0)?.name }
        var bound = ""
        switch train.execution {
        case .travellingToStop(let stop, _)?: bound = "to " + (world.station(id: train.timetable[stop].station)?.name ?? "?")
        case .waitingAtStop(let stop, _)?:
            let next = stop + 1 < train.timetable.count ? world.station(id: train.timetable[stop + 1].station)?.name : nil
            bound = "waiting" + (next.map { ", next \($0)" } ?? ", last call")
        default: bound = "no service"
        }
        return "\(train.name) [\(line)] \(at.map { "at \($0)" } ?? "on the line") \(bound)\(train.isDeadheading ? " (empty)" : "")"
    }

    func testWhereASavedWorldDeadlocks() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DEADLOCK_SWEEP"] != nil else {
            throw XCTSkip("Set DEADLOCK_SWEEP=<save> to look for its deadlocks (decision 877).")
        }
        // `DEADLOCK_SWEEP_AUDIT=1` counts how often the track holders kept
        // for the same trains were settled again for another time, and
        // when that changed whom a claim binds; `DEADLOCK_SWEEP_STALE=1`
        // keeps them as they were, as the game did before decision 877.
        guard environment["DEADLOCK_SWEEP_AUDIT"] != nil || environment["DEADLOCK_SWEEP_STALE"] != nil else { return try sweep(audit: nil) }
        let audit = GameWorld.HolderAudit()
        audit.countsOnly = true
        audit.keepsStaleClaims = environment["DEADLOCK_SWEEP_STALE"] != nil
        try GameWorld.$holderAudit.withValue(audit) { try sweep(audit: audit) }
    }

    private func sweep(audit: GameWorld.HolderAudit?) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["DEADLOCK_SWEEP"] else { return }
        let ticks = Int(environment["DEADLOCK_SWEEP_TICKS"] ?? "") ?? 2_880
        let batch = max(1, Int(environment["DEADLOCK_SWEEP_BATCH"] ?? "") ?? 1)
        let standing = Int64(environment["DEADLOCK_SWEEP_STANDING"] ?? "") ?? 20
        let speed = environment["DEADLOCK_SWEEP_SPEED"].flatMap(GameSpeed.init(rawValue:)) ?? .normal
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent + " \(speed.rawValue)" + (batch > 1 ? " x\(batch)" : "")
        var world = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: URL(fileURLWithPath: path))).world
        world.setSpeed(speed)
        func say(_ text: String) { FileHandle.standardError.write(Data(("DEADLOCK_SWEEP \(name) " + text + "\n").utf8)) }
        say("\(world.stations.count) stations, \(world.lines.count) lines, \(world.trains.count) trains, traffic control \(world.isTrafficControlEnabled), "
            + "block sections \(world.blockSections), from \(Self.clockText(world.clock.now.seconds))")

        // `DEADLOCK_SWEEP_WATCH=<from>-<to>` (clock seconds): every placed
        // train at each look between them; `DEADLOCK_SWEEP_WATCH_LINE`:
        // only the trains of lines whose name holds it.
        let watch = environment["DEADLOCK_SWEEP_WATCH"].flatMap { text -> ClosedRange<Int64>? in
            let ends = text.split(separator: "-").compactMap { Int64($0) }
            return ends.count == 2 && ends[0] <= ends[1] ? ends[0]...ends[1] : nil
        }
        let watchLine = environment["DEADLOCK_SWEEP_WATCH_LINE"]
        // A deadlock from the tick it is first seen to the last.
        struct Episode {
            var from: Int64, to: Int64, most: Int, mostAt: Int64, trains: Set<TrainID>, text: [String]
        }
        var episodes: [Episode] = [], open: Episode?
        var stranded: [TrainID: (from: Int64, to: Int64, text: String)] = [:], strandedDone: [String] = []
        // Each train in service as it last changed.
        var still: [TrainID: (position: TrainPosition?, execution: TimetableExecution?, since: Int64)] = [:]
        var stood: [String] = []
        var deadlockedTicks = 0, most = 0
        let started = Date()
        let opened = world.clock.now.seconds
        var played = 0
        while played < ticks {
            let step = min(batch, ticks - played)
            try world.advance(ticks: step)
            played += step
            let now = world.clock.now.seconds
            let waits = world.routeWaits()
            let deadlocked = waits.filter(\.isDeadlocked)
            if !deadlocked.isEmpty {
                deadlockedTicks += 1
                most = max(most, deadlocked.count)
                var episode = open ?? Episode(from: now, to: now, most: 0, mostAt: now, trains: [], text: [])
                episode.to = now
                episode.trains.formUnion(deadlocked.map(\.train))
                if deadlocked.count > episode.most {
                    episode.most = deadlocked.count
                    episode.mostAt = now
                    episode.text = deadlocked.map { "    \(Self.describe($0.train, in: world)) <- held by \(Self.describe($0.holder, in: world))" }
                }
                open = episode
            } else if let episode = open {
                episodes.append(episode)
                open = nil
            }
            let strandedNow = Set(world.strandedTrains())
            for id in strandedNow {
                if stranded[id] == nil { stranded[id] = (now, now, Self.describe(id, in: world)) } else { stranded[id]!.to = now }
            }
            for (id, entry) in stranded where !strandedNow.contains(id) {
                strandedDone.append("stranded \(Self.clockText(entry.from)) to \(Self.clockText(entry.to)): \(entry.text)")
                stranded[id] = nil
            }
            for train in world.trains {
                let known = still[train.id]
                let due = world.departureDue(of: train).map { $0.seconds <= now } ?? false
                let counts: Bool
                switch train.execution {
                case .waitingAtStop?: counts = due
                case .travellingToStop?: counts = true
                default: counts = false
                }
                if counts, let known, known.position == train.position, known.execution == train.execution { continue }
                if let known, now - known.since >= standing * 60 {
                    stood.append("stood \(Self.clockText(known.since)) to \(Self.clockText(now)) (\((now - known.since) / 60) min): \(Self.describe(train.id, in: world))")
                }
                still[train.id] = counts ? (train.position, train.execution, now) : nil
            }
            if let watch, watch.contains(now) {
                let holders = Dictionary(uniqueKeysWithValues: waits.map { ($0.train, $0) })
                for train in world.trains where train.position != nil && (watchLine == nil || world.lines.contains { $0.trains.contains(train.id) && $0.name.contains(watchLine!) }) {
                    var text = "\(Self.clockText(now)) \(Self.describe(train.id, in: world))"
                    if case .onEdge(let traversal, let offset)? = train.position { text += " @\(traversal.edge.networkNumber ?? -1)\(traversal.direction == .forward ? "+" : "-")\(offset)" }
                    if let wait = holders[train.id] { text += " <- \(world.train(id: wait.holder)?.name ?? "?")\(wait.isDeadlocked ? " DEADLOCK" : "")" }
                    if let due = world.departureDue(of: train) { text += " due \(Self.clockText(due.seconds))" }
                    if world.isFollowing(train) { text += " following" }
                    say(text)
                }
            }
            if environment["DEADLOCK_SWEEP_EACH"] != nil, now % 3_600 == 0 {
                say("checksum \(String(try Self.checksum(of: world), radix: 16)) at \(Self.clockText(now))")
            }
        }
        if let episode = open { episodes.append(episode) }
        let now = world.clock.now.seconds
        for (_, entry) in stranded.sorted(by: { $0.key < $1.key }) {
            strandedDone.append("stranded \(Self.clockText(entry.from)) to the end: \(entry.text)")
        }
        for (id, known) in still.sorted(by: { $0.key < $1.key }) where now - known.since >= standing * 60 {
            stood.append("stood \(Self.clockText(known.since)) to the end (\((now - known.since) / 60) min): \(Self.describe(id, in: world))")
        }
        for episode in episodes {
            say("deadlock \(Self.clockText(episode.from)) to \(Self.clockText(episode.to)) (\((episode.to - episode.from) / 60 + 1) min), "
                + "\(episode.trains.count) trains in all, most \(episode.most) at \(Self.clockText(episode.mostAt)):\n" + episode.text.joined(separator: "\n"))
        }
        for line in strandedDone { say(line) }
        for line in stood { say(line) }
        // Each whole day's runs not sent, of the days whose every run has
        // passed its last chance.
        let firstDay = opened / GameTime.secondsPerDay
        for day in firstDay...(now / GameTime.secondsPerDay) {
            for line in world.lines where line.hasRuns {
                let runs = line.runs.indices.filter { line.runs[$0].runs(onDay: day) }
                let last = runs.map { line.runs[$0].start(onDay: day) }.max() ?? 0
                guard !runs.isEmpty, last + LineRun.latestDispatch < now else { continue }
                let missed = runs.filter { (line.runDays[$0] ?? -1) < day }
                if !missed.isEmpty {
                    let times = missed.prefix(12).map { index -> String in
                        let minute = (line.runs[index].start(onDay: day) - day * GameTime.secondsPerDay) / 60
                        return String(format: "%02lld:%02lld", minute / 60, minute % 60)
                    }
                    say("day \(day) \(line.name): \(missed.count) of \(runs.count) runs not sent (\(times.joined(separator: ", "))\(missed.count > 12 ? ", ..." : ""))")
                }
            }
        }
        if let audit {
            let times = audit.staleClaims.prefix(20).map { Self.clockText($0.seconds) + String(format: ":%02lld", $0.seconds % 60) }
            say("holders settled again for another time \(audit.settledAgain) times\(audit.keepsStaleClaims ? " (kept as they were)" : ""), "
                + "\(audit.staleClaims.count) changed whom a claim binds\(times.isEmpty ? "" : ": " + times.joined(separator: ", "))")
        }
        say("deadlocked: most \(most), in \(deadlockedTicks) of \(played / batch) looks, \(episodes.count) episodes; stranded \(strandedDone.count); stood \(stood.count); "
            + String(format: "%.0f s; ", Date().timeIntervalSince(started)) + "last \(String(try Self.checksum(of: world), radix: 16)) at \(Self.clockText(now))")
    }
}
