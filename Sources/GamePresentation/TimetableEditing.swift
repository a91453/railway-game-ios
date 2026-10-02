import GameCore

// A train's own timetable (Stage C2): the screen for `setTrainTimetable`
// (Stages O, P, Q1 and W2b), after the timetable concepts of the reference
// pack (`Railway/railway_game_reference_clean/01_MIGRATION_MAP.md` §2, from
// the compiled core's `TimetableWindow`): where it starts
// (`CmdSetTimetableStart`), how long it travels to each stop and waits there
// (`CmdChangeTimetable`'s travel and wait times, the migration map's
// `travelAllowance` and `minimumDwell`), shown as arrival and departure
// (`gui.timetable_arrival_departure`), and how often it repeats. Every
// control is one `setTrainTimetable` command with an edited copy of the
// train's timetable, read from the world each time: nothing is drafted, and
// GameCore decides whether the train may take it.

/// Edits of a timetable, as pure functions of its stops.
public enum TimetableEditing {
    /// How long a new stop is after the one before it. The reference fills
    /// travel times from a run of the train (`CmdAutofillTimetable`); the
    /// app has no such run yet, so it suggests three minutes and the player
    /// moves them.
    public static let defaultTravel: Int64 = 3 * GameTime.secondsPerMinute
    /// How long a new stop is scheduled to wait.
    public static let defaultDwell: Int64 = GameTime.secondsPerMinute
    /// What one press of a time control moves.
    public static let step: Int64 = GameTime.secondsPerMinute

    /// `stops` with a stop at `station` added at the end: the default travel
    /// after the last departure, or at `start` for the first stop, waiting
    /// the default dwell.
    public static func appending(_ station: StationID, to stops: [ScheduledStop], start: GameTime) -> [ScheduledStop] {
        let arrival = stops.last.map { GameTime(seconds: $0.departure.seconds + defaultTravel) } ?? start
        return stops + [ScheduledStop(station: station, arrival: arrival, departure: GameTime(seconds: arrival.seconds + defaultDwell))]
    }

    /// The earliest the stop at `index` may arrive: when the stop before it
    /// leaves, or second 0 for the first.
    static func earliestArrival(of index: Int, in stops: [ScheduledStop]) -> Int64 {
        index == 0 ? 0 : stops[index - 1].departure.seconds
    }

    /// Whether the stop at `index` can arrive earlier.
    public static func canArriveEarlier(_ index: Int, in stops: [ScheduledStop]) -> Bool {
        stops.indices.contains(index) && stops[index].arrival.seconds > earliestArrival(of: index, in: stops)
    }

    /// Whether the stop at `index` can leave earlier.
    public static func canLeaveEarlier(_ index: Int, in stops: [ScheduledStop]) -> Bool {
        stops.indices.contains(index) && stops[index].departure > stops[index].arrival
    }

    /// The stop at `index` arriving `delta` seconds later (earlier when
    /// negative), with its departure and every later stop moved with it,
    /// so the travel to it changes and nothing else: never before the stop
    /// before it leaves (or second 0). Moving the first stop moves the
    /// whole timetable, the reference's start.
    public static func movingArrival(of index: Int, by delta: Int64, in stops: [ScheduledStop]) -> [ScheduledStop] {
        guard stops.indices.contains(index) else { return stops }
        let shift = max(delta, earliestArrival(of: index, in: stops) - stops[index].arrival.seconds)
        return stops.enumerated().map { offset, stop in
            offset < index ? stop : stop.shifted(arrival: shift, departure: shift)
        }
    }

    /// The stop at `index` leaving `delta` seconds later (earlier when
    /// negative), with every later stop moved with it, so its wait changes
    /// and nothing else: never before it arrives.
    public static func movingDeparture(of index: Int, by delta: Int64, in stops: [ScheduledStop]) -> [ScheduledStop] {
        guard stops.indices.contains(index) else { return stops }
        let shift = max(delta, stops[index].arrival.seconds - stops[index].departure.seconds)
        return stops.enumerated().map { offset, stop in
            offset < index ? stop : stop.shifted(arrival: offset == index ? 0 : shift, departure: shift)
        }
    }

    /// The stop at `index` turning the train round as it leaves, or no
    /// longer.
    public static func togglingReverse(of index: Int, in stops: [ScheduledStop]) -> [ScheduledStop] {
        guard stops.indices.contains(index) else { return stops }
        var edited = stops
        let stop = stops[index]
        edited[index] = ScheduledStop(station: stop.station, arrival: stop.arrival, departure: stop.departure, reverses: !stop.reverses)
        return edited
    }

    /// `stops` without the stop at `index`; the others keep their times.
    public static func removing(_ index: Int, from stops: [ScheduledStop]) -> [ScheduledStop] {
        guard stops.indices.contains(index) else { return stops }
        var edited = stops
        edited.remove(at: index)
        return edited
    }

    /// The shortest period `stops` can repeat with in whole minutes: from
    /// the first arrival to the last departure, rounded up, and at least a
    /// minute. `nil` without stops.
    public static func shortestPeriod(of stops: [ScheduledStop]) -> Int64? {
        guard let first = stops.first, let last = stops.last else { return nil }
        let span = last.departure.seconds - first.arrival.seconds
        let minute = GameTime.secondsPerMinute
        return max(minute, (span + minute - 1) / minute * minute)
    }

    /// `period` grown to ``shortestPeriod(of:)`` if `stops` no longer fit
    /// in it; `nil` stays `nil`.
    public static func period(_ period: Int64?, fitting stops: [ScheduledStop]) -> Int64? {
        guard let period, let shortest = shortestPeriod(of: stops) else { return period }
        return max(period, shortest)
    }
}

private extension ScheduledStop {
    func shifted(arrival arrivalShift: Int64, departure departureShift: Int64) -> ScheduledStop {
        ScheduledStop(
            station: station,
            arrival: GameTime(seconds: arrival.seconds + arrivalShift),
            departure: GameTime(seconds: departure.seconds + departureShift),
            reverses: reverses
        )
    }
}

/// One stop of a timetable as the editor lists it.
public struct TimetableRow: Hashable, Sendable {
    public let index: Int
    public let stationName: String
    /// "08:05 → 08:06"; "Day 2 · 00:05 → 00:06" on a later day than the
    /// first stop; with seconds when they are not 0.
    public let timesText: String
    /// "3 min from Hill · waits 1 min"; the first stop says only its wait.
    public let detailText: String
    public let reverses: Bool
}

extension GameWorld {
    /// Train `id`'s timetable, stop by stop. Empty without one.
    public func timetableRows(of id: TrainID, in language: DisplayLanguage) -> [TimetableRow] {
        guard let stops = train(id: id)?.timetable, let first = stops.first else { return [] }
        let firstDay = first.arrival.seconds / GameTime.secondsPerDay
        return stops.enumerated().map { index, stop in
            let wait = durationText(seconds: stop.departure.seconds - stop.arrival.seconds, in: language)
            var detail = language.text("waits \(wait)", "停 \(wait)")
            if index > 0 {
                let previous = stops[index - 1]
                let travel = durationText(seconds: stop.arrival.seconds - previous.departure.seconds, in: language)
                detail = language.text("\(travel) from \(stationName(previous.station)) · ", "距 \(stationName(previous.station)) \(travel) · ") + detail
            }
            return TimetableRow(
                index: index,
                stationName: stationName(stop.station),
                timesText: "\(Self.timetableTime(stop.arrival, firstDay: firstDay, in: language)) → \(Self.timetableTime(stop.departure, firstDay: firstDay, in: language))",
                detailText: detail,
                reverses: stop.reverses
            )
        }
    }

    /// Train `id`'s timetable in one line: "3 stops from Day 1 · 08:00 ·
    /// repeats every 60 min"; "3 站，第 1 日 · 08:00 起 · 每 60 分重複".
    /// `nil` without one.
    public func timetableSummary(of id: TrainID, in language: DisplayLanguage) -> String? {
        guard let train = train(id: id), let first = train.timetable.first else { return nil }
        let count = train.timetable.count
        let start = first.arrival.isWholeMinute ? first.arrival.displayText(in: language) : first.arrival.displayTextWithSeconds(in: language)
        let repeats = train.timetablePeriod.map { period in
            language.text("repeats every \(durationText(seconds: period, in: language))", "每 \(durationText(seconds: period, in: language))重複")
        } ?? language.text("runs once", "只跑一次")
        return language.text(
            "\(count) \(count == 1 ? "stop" : "stops") from \(start) · \(repeats)",
            "\(count) 站，\(start) 起 · \(repeats)"
        )
    }

    /// How often train `id`'s timetable repeats: "Every 7 min"; "每 7 分".
    /// `nil` when it runs once.
    public func timetablePeriodText(of id: TrainID, in language: DisplayLanguage) -> String? {
        guard let period = train(id: id)?.timetablePeriod else { return nil }
        let every = durationText(seconds: period, in: language)
        return language.text("Every \(every)", "每 \(every)")
    }

    /// "08:05", "08:05:30", or with the day ("Day 2 · 00:05") when it is not
    /// the timetable's first day.
    static func timetableTime(_ time: GameTime, firstDay: Int64, in language: DisplayLanguage) -> String {
        if time.seconds / GameTime.secondsPerDay != firstDay {
            return time.isWholeMinute ? time.displayText(in: language) : time.displayTextWithSeconds(in: language)
        }
        let clock = time.clockText
        let seconds = time.secondOfMinute
        return time.isWholeMinute ? clock : "\(clock):\(seconds < 10 ? "0" : "")\(seconds)"
    }
}

extension GameSession {
    /// Adds a stop at `station` to the end of the selected train's
    /// timetable (see ``TimetableEditing/appending(_:to:start:)``); a first
    /// stop arrives at the next whole minute.
    public func addStopToSelectedTrainTimetable(_ station: StationID) {
        guard let train = requireSelectedTrain() else { return }
        let start = GameTime(seconds: (world.clock.now.seconds / GameTime.secondsPerMinute + 1) * GameTime.secondsPerMinute)
        let stops = TimetableEditing.appending(station, to: train.timetable, start: start)
        setTimetable(of: train, to: stops) { world in
            let stop = stops[stops.count - 1]
            let firstDay = stops[0].arrival.seconds / GameTime.secondsPerDay
            let name = world.station(id: station)?.name ?? "#\(station.rawValue)"
            let arrival = GameWorld.timetableTime(stop.arrival, firstDay: firstDay, in: language)
            let departure = GameWorld.timetableTime(stop.departure, firstDay: firstDay, in: language)
            return language.text(
                "\(train.name) now calls at \(name): arrives \(arrival), leaves \(departure).",
                "\(train.name) 加停 \(name)：\(arrival) 到，\(departure) 開。"
            )
        }
    }

    /// Moves when the selected train arrives at stop `index` by `delta`
    /// seconds (see ``TimetableEditing/movingArrival(of:by:in:)``).
    public func moveSelectedTrainArrival(at index: Int, by delta: Int64) {
        guard let train = requireSelectedTrain(), train.timetable.indices.contains(index) else { return }
        let stops = TimetableEditing.movingArrival(of: index, by: delta, in: train.timetable)
        setTimetable(of: train, to: stops) { world in
            let name = world.station(id: stops[index].station)?.name ?? ""
            let time = GameWorld.timetableTime(stops[index].arrival, firstDay: stops[0].arrival.seconds / GameTime.secondsPerDay, in: language)
            return language.text("\(train.name) arrives at \(name) at \(time).", "\(train.name) \(time) 到 \(name)。")
        }
    }

    /// Moves when the selected train leaves stop `index` by `delta`
    /// seconds (see ``TimetableEditing/movingDeparture(of:by:in:)``).
    public func moveSelectedTrainDeparture(at index: Int, by delta: Int64) {
        guard let train = requireSelectedTrain(), train.timetable.indices.contains(index) else { return }
        let stops = TimetableEditing.movingDeparture(of: index, by: delta, in: train.timetable)
        setTimetable(of: train, to: stops) { world in
            let name = world.station(id: stops[index].station)?.name ?? ""
            let time = GameWorld.timetableTime(stops[index].departure, firstDay: stops[0].arrival.seconds / GameTime.secondsPerDay, in: language)
            return language.text("\(train.name) leaves \(name) at \(time).", "\(train.name) \(time) 從 \(name) 發車。")
        }
    }

    /// Makes the selected train turn round as it leaves stop `index`, or
    /// no longer.
    public func toggleSelectedTrainReverse(at index: Int) {
        guard let train = requireSelectedTrain(), train.timetable.indices.contains(index) else { return }
        let stops = TimetableEditing.togglingReverse(of: index, in: train.timetable)
        setTimetable(of: train, to: stops) { world in
            let name = world.station(id: stops[index].station)?.name ?? ""
            return stops[index].reverses
                ? language.text("\(train.name) turns round at \(name).", "\(train.name) 在 \(name) 折返。")
                : language.text("\(train.name) no longer turns round at \(name).", "\(train.name) 不再在 \(name) 折返。")
        }
    }

    /// Removes stop `index` from the selected train's timetable.
    public func removeSelectedTrainStop(at index: Int) {
        guard let train = requireSelectedTrain(), train.timetable.indices.contains(index) else { return }
        let name = world.station(id: train.timetable[index].station)?.name ?? ""
        let stops = TimetableEditing.removing(index, from: train.timetable)
        setTimetable(of: train, to: stops, repeatingEvery: stops.isEmpty ? nil : train.timetablePeriod) { _ in
            language.text("\(train.name) no longer calls at \(name).", "\(train.name) 不再停靠 \(name)。")
        }
    }

    /// Makes the selected train's timetable repeat, every
    /// ``TimetableEditing/shortestPeriod(of:)`` to begin with, or run once.
    public func setSelectedTrainTimetableRepeats(_ repeats: Bool) {
        guard let train = requireSelectedTrain() else { return }
        let period = repeats ? train.timetablePeriod ?? TimetableEditing.shortestPeriod(of: train.timetable) : nil
        setTimetable(of: train, to: train.timetable, repeatingEvery: period) { _ in
            Self.periodText(period, of: train, in: language)
        }
    }

    /// Lengthens or shortens how often the selected train's timetable
    /// repeats by `delta` seconds, never below
    /// ``TimetableEditing/shortestPeriod(of:)``.
    public func changeSelectedTrainTimetablePeriod(by delta: Int64) {
        guard let train = requireSelectedTrain(), let period = train.timetablePeriod else { return }
        let changed = TimetableEditing.period(period + delta, fitting: train.timetable)
        setTimetable(of: train, to: train.timetable, repeatingEvery: changed) { _ in
            Self.periodText(changed, of: train, in: language)
        }
    }

    /// Clears the selected train's timetable.
    public func clearSelectedTrainTimetable() {
        guard let train = requireSelectedTrain() else { return }
        setTimetable(of: train, to: [], repeatingEvery: nil) { _ in
            language.text("Cleared \(train.name)'s timetable.", "已清除 \(train.name) 的時刻表。")
        }
    }

    /// Sets `stops` as `train`'s timetable through
    /// `GameWorld.setTrainTimetable(_:to:repeatingEvery:)`, keeping its
    /// period grown to fit the stops (see
    /// ``TimetableEditing/period(_:fitting:)``).
    private func setTimetable(of train: Train, to stops: [ScheduledStop], message: (GameWorld) -> String) {
        setTimetable(of: train, to: stops, repeatingEvery: TimetableEditing.period(train.timetablePeriod, fitting: stops), message: message)
    }

    /// Sets `stops` as `train`'s timetable, repeating every `period`
    /// seconds or running once for `nil`.
    private func setTimetable(of train: Train, to stops: [ScheduledStop], repeatingEvery period: Int64?, message: (GameWorld) -> String) {
        perform { world throws(GameError) in
            try world.setTrainTimetable(train.id, to: stops, repeatingEvery: period)
            return message(world)
        }
    }

    private static func periodText(_ period: Int64?, of train: Train, in language: DisplayLanguage) -> String {
        guard let period else {
            return language.text("\(train.name)'s timetable runs once.", "\(train.name) 的時刻表只跑一次。")
        }
        let every = durationText(seconds: period, in: language)
        return language.text("\(train.name)'s timetable repeats every \(every).", "\(train.name) 的時刻表每 \(every)重複。")
    }
}
