import GameCore

/// Decision 305: the shortcut over a night no train runs in (research
/// `CITY_TRANSPORT_MANAGER_STUDY_2026-10-19.md` §4.15). While every train
/// stands still, the session can run the game at its fastest speed up to
/// a little before the first train moves again, tick by tick through
/// `GameWorld.advance(ticks:)`, so midnight, the books and the city run
/// as they would at any speed; the clock is never set.
///
/// Where it stops is found by running a copy of the world ahead
/// (``plan(for:)``): the first moment a train leaves a depot, is sent out
/// or starts a timetabled trip, whatever the line's hours, depots or
/// timetable say. A night with a train running (a line open all night,
/// a late timetabled train, freight, a train running empty to or from a
/// depot) has nothing to skip.
public struct NightSkip: Hashable, Sendable {
    /// Where the skip stops: whole minutes from when it was worked out,
    /// ``lead`` or a little more before ``firstMove``.
    public let stop: GameTime
    /// The start of the minute in which the first train moves again.
    public let firstMove: GameTime

    /// How long before the first train moves the skip stops: time to see
    /// the morning begin.
    public static let lead: Int64 = 10 * GameTime.secondsPerMinute
    /// The shortest stretch worth skipping.
    public static let shortest: Int64 = GameTime.secondsPerHour
    /// How far ahead the first move is looked for.
    public static let horizon: Int64 = GameTime.secondsPerDay

    /// Whether `train` is on its way: placed, and on a trip, running
    /// empty, or with track still to cover.
    public static func isRunning(_ train: Train) -> Bool {
        train.position != nil && (train.execution != nil || train.isDeadheading || train.movement.hasRemainingPath)
    }

    /// The skip from `world` as it is, or `nil` when there is nothing to
    /// skip: no train placed, a train running now, or the first move less
    /// than ``shortest`` (with ``lead``) or more than ``horizon`` away.
    public static func plan(for world: GameWorld) -> NightSkip? {
        guard let firstMove = firstMove(after: world) else { return nil }
        return plan(from: world.clock.now, firstMove: firstMove)
    }

    /// The skip from `now` when the first train moves at `firstMove`.
    static func plan(from now: GameTime, firstMove: GameTime) -> NightSkip? {
        let minute = GameTime.secondsPerMinute
        let gap = (firstMove.seconds - lead - now.seconds) / minute * minute
        guard gap >= shortest else { return nil }
        return NightSkip(stop: GameTime(seconds: now.seconds + gap), firstMove: firstMove)
    }

    /// When a train first moves after `world` as it is, run ahead on a
    /// copy at the fastest speed and then a minute at a time; `nil` when
    /// no train is placed, one runs now, or none moves within ``horizon``.
    static func firstMove(after world: GameWorld) -> GameTime? {
        let placed = world.trains.filter { $0.position != nil }
        guard !placed.isEmpty, !placed.contains(where: isRunning) else { return nil }
        let rest = Rest(world)
        let start = world.clock.now.seconds
        var probe = world
        probe.setSpeed(.fast)
        var quiet = probe
        while true {
            guard probe.clock.now.seconds - start < horizon else { return nil }
            quiet = probe
            do { try probe.advance(ticks: 1) } catch { return nil }
            if Rest(probe) != rest { break }
        }
        // The move is within that last tick: find the minute it begins.
        quiet.setSpeed(.normal)
        while true {
            let before = quiet.clock.now
            do { try quiet.advance(ticks: 1) } catch { return nil }
            if Rest(quiet) != rest { return before }
        }
    }

    /// The speed for the next tick of a skip `remaining` seconds from its
    /// stop: the fastest whose tick does not pass it.
    static func speed(remaining: Int64) -> GameSpeed {
        let speeds: [GameSpeed] = [.fast, .double, .normal, .x60, .x10]
        return speeds.first { $0.tenthsPerTick / 10 <= remaining } ?? .x10
    }

    /// Where the trains stand: what a move changes.
    private struct Rest: Equatable {
        let trains: [TrainID: TrainPosition?]
        let running: Bool

        init(_ world: GameWorld) {
            trains = Dictionary(uniqueKeysWithValues: world.trains.map { ($0.id, $0.position) })
            running = world.trains.contains(where: NightSkip.isRunning)
        }
    }

    // MARK: - Text

    /// The shortcut's button, with where it stops.
    public func buttonTitle(in language: DisplayLanguage) -> String {
        language.text("Skip to Morning · \(stop.clockText)", "快轉到早上 · \(stop.clockText)")
    }

    /// What the shortcut does.
    public static func hint(in language: DisplayLanguage) -> String {
        language.text(
            "No trains run until the morning. Runs the game at top speed until just before the first one leaves.",
            "早上之前沒有車。用最快速度跑到第一班車出發前。"
        )
    }

    /// The button while a skip runs, which stops it.
    public static func stopTitle(at stop: GameTime, in language: DisplayLanguage) -> String {
        language.text("Skipping to \(stop.clockText) · Stop", "快轉到 \(stop.clockText) · 停止")
    }

    /// The setting that starts the skip by itself.
    public static func settingTitle(in language: DisplayLanguage) -> String {
        language.text("Skip quiet nights automatically", "夜裡沒有車時自動快轉")
    }

    /// What the setting does.
    public static func settingFooter(in language: DisplayLanguage) -> String {
        language.text(
            "When no train runs at night, the game runs at top speed until just before the first train of the morning, then goes back to your speed.",
            "夜裡沒有車時，遊戲用最快速度跑到早上第一班車出發前，再回到原本的速度。"
        )
    }
}

/// A skip under way (decision 305): where it stops, and the speed to go
/// back to.
public struct NightSkipRun: Hashable, Sendable {
    public let stop: GameTime
    let firstMove: GameTime
    /// The speed the game ran at, or would resume at, before the skip.
    let speed: GameSpeed
    /// Whether the game was paused before the skip.
    let wasPaused: Bool
    /// The session's ``GameSession/commandRevision`` when the skip last
    /// changed the speed: a command since then ends it.
    var revision: Int
}

extension GameSession {
    /// The skip the shortcut offers now (decision 305), or `nil`. The run
    /// ahead is kept until a command: until then the world goes on as it
    /// ran, so the first move stays where it was found.
    public var nightSkip: NightSkip? {
        guard nightSkipRun == nil, !isPausedForBuilding else { return nil }
        let now = world.clock.now
        if world.trains.contains(where: NightSkip.isRunning) { return nil }
        if let memo = nightSkipMemo, memo.revision == commandRevision, memo.from <= now,
           memo.firstMove.map({ now < $0 }) ?? (now.seconds < memo.from.seconds + GameTime.secondsPerHour) {
            return memo.firstMove.flatMap { NightSkip.plan(from: now, firstMove: $0) }
        }
        let firstMove = NightSkip.firstMove(after: world)
        nightSkipMemo = NightSkipMemo(revision: commandRevision, from: now, firstMove: firstMove)
        return firstMove.flatMap { NightSkip.plan(from: now, firstMove: $0) }
    }

    /// Runs the game at its fastest speed to the skip's stop (decision
    /// 305); does nothing when there is nothing to skip.
    public func skipToMorning() {
        guard let skip = nightSkip else { return }
        let clock = world.clock
        isPausedForEvent = false
        nightSkipRun = NightSkipRun(
            stop: skip.stop, firstMove: skip.firstMove, speed: clock.runningSpeed, wasPaused: clock.isPaused, revision: commandRevision
        )
        driveNightSkip()
    }

    /// Ends the skip under way where it is, back at the speed before it.
    public func stopNightSkip() {
        guard nightSkipRun != nil else { return }
        endNightSkip(pausing: false)
    }

    /// The player chose a speed or paused while a skip ran: the speed is
    /// theirs, and the night is not skipped by itself again.
    func dropNightSkip() {
        guard let run = nightSkipRun else { return }
        autoSkipDeclined = run.firstMove
        nightSkipRun = nil
    }

    /// After a tick (decision 305): goes on with the skip under way, at
    /// the speed whose tick lands on its stop, or ends it; or starts one
    /// when the setting asks to.
    func continueNightSkip() {
        guard let run = nightSkipRun else {
            if skipsQuietNights, !world.clock.isPaused, tutorial == nil, let skip = nightSkip, autoSkipDeclined != skip.firstMove {
                skipToMorning()
            }
            return
        }
        if world.clock.isPaused {
            // An event paused it: the player sees it at their own speed.
            endNightSkip(pausing: true)
        } else if run.revision != commandRevision || world.clock.now >= run.stop || world.trains.contains(where: NightSkip.isRunning) {
            endNightSkip(pausing: false)
        } else {
            driveNightSkip()
        }
    }

    /// Sets the speed for the skip's next tick.
    private func driveNightSkip() {
        guard var run = nightSkipRun else { return }
        let speed = NightSkip.speed(remaining: run.stop.seconds - world.clock.now.seconds)
        if world.clock.speed != speed {
            logging(.setSpeed(speed)) { $0.setSpeed(speed) }
        }
        run.revision = commandRevision
        nightSkipRun = run
    }

    /// Back at the speed before the skip; paused if it was, or if
    /// `pausing`.
    private func endNightSkip(pausing: Bool) {
        guard let run = nightSkipRun else { return }
        nightSkipRun = nil
        autoSkipDeclined = run.firstMove
        var clock = world.clock
        clock.setSpeed(run.speed)
        if clock != world.clock { logging(.setSpeed(run.speed)) { $0.setSpeed(run.speed) } }
        if run.wasPaused || pausing { logging(.pause) { $0.pause() } }
    }
}

/// The run ahead behind ``GameSession/nightSkip``: the first move found
/// from `from`, for the commands up to `revision`.
struct NightSkipMemo {
    let revision: Int
    let from: GameTime
    let firstMove: GameTime?
}
