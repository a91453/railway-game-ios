import GameCore

/// The train card's flight-card layout (ARCHITECTURE decision 223, option A
/// "航班條"): the trip's first and last stops, a progress bar with the train
/// on it, how far is left, when it left and when it gets in (the
/// timetable's arrival struck through and the expected one beside it when
/// it is late), a status in words, and its speed, next stop and load.
///
/// The trip is the train's timetable as it runs now: a line's train gets
/// one for each trip it is sent on, and a repeating timetable's trip is its
/// current cycle. Read from the world each time it is shown; never stored.
public struct TrainCard: Hashable, Sendable {
    public let origin: String
    public let terminus: String
    /// The timetable's departure from the first stop and arrival at the
    /// last, in the cycle the train is on.
    public let departure: GameTime
    public let arrival: GameTime
    /// Whole minutes behind its timetable, 0 when on time or early
    /// (``Punctuality``: under a minute is on time).
    public let lateMinutes: Int64
    /// Whether the train has left its first stop.
    public let hasDeparted: Bool
    /// How far along the trip, 0 to 1, by the straight-line distance
    /// between its stops (the run it is on by its running curve).
    public let progress: Double
    /// Metres left to the last stop: the rest of the run it is on, exactly,
    /// and the straight lines between the stops after it.
    public let remainingMetres: Int64
    /// The next stop it calls at, and whole minutes until it is due there
    /// (lateness included); `nil` at the last stop.
    public let nextStop: String?
    public let nextStopMinutes: Int64?
    /// Whole km/h (``GameWorld/trainSpeedKMH(of:)``).
    public let speed: Int64
    public let load: TrainLoadInfo?
    /// The follow bar's status: whether it runs, has arrived, is held or
    /// is in its depot.
    public let state: FollowBarInfo.Status
    public let now: GameTime

    public init(
        origin: String, terminus: String, departure: GameTime, arrival: GameTime, lateMinutes: Int64,
        hasDeparted: Bool, progress: Double, remainingMetres: Int64, nextStop: String?, nextStopMinutes: Int64?,
        speed: Int64, load: TrainLoadInfo?, state: FollowBarInfo.Status, now: GameTime
    ) {
        self.origin = origin
        self.terminus = terminus
        self.departure = departure
        self.arrival = arrival
        self.lateMinutes = lateMinutes
        self.hasDeparted = hasDeparted
        self.progress = progress
        self.remainingMetres = remainingMetres
        self.nextStop = nextStop
        self.nextStopMinutes = nextStopMinutes
        self.speed = speed
        self.load = load
        self.state = state
        self.now = now
    }

    public var isLate: Bool { lateMinutes >= 1 }

    /// When it is expected at the last stop: the timetable's arrival plus
    /// its lateness.
    public var expectedArrival: GameTime {
        GameTime(seconds: arrival.seconds &+ lateMinutes &* GameTime.secondsPerMinute)
    }

    /// The status capsule: "On time" or "5 min late" while it runs (decision
    /// 223 shows it in words, not only in colour); otherwise the follow
    /// bar's status, as "Arrived" or "In depot".
    public func statusText(in language: DisplayLanguage) -> String {
        switch state {
        case .running:
            isLate ? language.text("\(lateMinutes) min late", "誤點 \(lateMinutes) 分") : language.text("On time", "準點")
        default:
            state.text(in: language) ?? language.text("On time", "準點")
        }
    }

    /// Whether the capsule is the punctuality one (on time or late), not a
    /// state such as "Arrived".
    public var showsPunctuality: Bool { state == .running }

    /// "Left 21 min ago", or "Leaves in 8 min" before it has left.
    public func departureText(in language: DisplayLanguage) -> String {
        if hasDeparted {
            let minutes = max(0, now.seconds - departure.seconds) / GameTime.secondsPerMinute
            return language.text("Left \(minutes) min ago", "\(minutes) 分前發車")
        }
        let minutes = max(0, departure.seconds - now.seconds) / GameTime.secondsPerMinute
        return language.text("Leaves in \(minutes) min", "\(minutes) 分後發車")
    }

    /// "Due in 53 min", or "Arrived" once it is there.
    public func arrivalText(in language: DisplayLanguage) -> String {
        if state == .arrived { return language.text("Arrived", "已抵達") }
        let minutes = max(0, expectedArrival.seconds - now.seconds) / GameTime.secondsPerMinute
        return language.text("Due in \(minutes) min", "\(minutes) 分後到站")
    }

    /// "38.6 km left".
    public func remainingText(in language: DisplayLanguage) -> String {
        let tenths = (remainingMetres + 50) / 100
        return language.text("\(tenths / 10).\(tenths % 10) km left", "剩 \(tenths / 10).\(tenths % 10) km")
    }

    /// "Taoyuan · 3 min", or "—" at the last stop.
    public func nextStopText(in language: DisplayLanguage) -> String {
        guard let nextStop else { return "—" }
        guard let minutes = nextStopMinutes else { return nextStop }
        return language.text("\(nextStop) · \(minutes) min", "\(nextStop) \(minutes) 分")
    }
}

extension GameWorld {
    /// The train card of train `id` (see ``TrainCard``), or `nil` for an
    /// unknown train or one without a trip of two stops or more.
    public func trainCard(of id: TrainID, in language: DisplayLanguage) -> TrainCard? {
        guard let train = train(id: id), train.timetable.count > 1,
              let first = train.timetable.first, let last = train.timetable.last,
              let info = followBarInfo(of: id, in: language)
        else { return nil }
        let timetable = train.timetable
        let execution = train.execution
        let offset = (train.timetablePeriod ?? 0) &* (execution?.cycle ?? 0)
        let now = clock.now
        // The straight line between each stop and the next.
        let legs: [Int64] = zip(timetable, timetable.dropFirst()).map { a, b in
            guard let p = station(id: a.station)?.point, let q = station(id: b.station)?.point else { return 0 }
            let dx = Double(p.x - q.x), dy = Double(p.y - q.y)
            return Int64(((dx * dx + dy * dy).squareRoot() / Double(WorldCoordinate.unitsPerMetre)).rounded())
        }
        let total = legs.reduce(0, +)
        var progress: Double
        var remaining: Int64
        var next: Int?
        switch execution {
        case .waitingAtStop(let stop, _)?:
            let done = legs.prefix(stop).reduce(0, +)
            progress = total > 0 ? Double(done) / Double(total) : Double(stop) / Double(legs.count)
            remaining = legs.dropFirst(stop).reduce(0, +)
            next = stop + 1 < timetable.count ? stop + 1 : nil
        case .travellingToStop(let stop, _)?:
            let before = max(0, stop - 1)
            var fraction = 0.0
            var runLeft = legs.indices.contains(before) ? legs[before] : 0
            if let run = train.times?.run, let curve = run.curve(for: train.performance) {
                let elapsed = max(0, now.seconds - run.start.seconds)
                let covered = elapsed >= run.seconds ? run.length : curve.distance(at: elapsed * 1000)
                fraction = Double(covered) / Double(max(1, run.length))
                runLeft = (run.length - covered) / WorldCoordinate.unitsPerMetre
            }
            let done = Double(legs.prefix(before).reduce(0, +)) + fraction * Double(legs.indices.contains(before) ? legs[before] : 0)
            progress = total > 0 ? done / Double(total) : (Double(before) + fraction) / Double(legs.count)
            remaining = runLeft + legs.dropFirst(stop).reduce(0, +)
            next = stop
        case nil:
            // Between trips: the finished trip's timetable, done.
            progress = info.status == .notDeparted ? 0 : 1
            remaining = info.status == .notDeparted ? total : 0
            next = nil
        }
        let late = max(0, lateness(of: id) ?? 0)
        let lateMinutes = late / GameTime.secondsPerMinute
        var nextMinutes: Int64?
        if let next {
            let due = timetable[next].arrival.seconds &+ offset &+ late
            nextMinutes = max(0, due - now.seconds) / GameTime.secondsPerMinute
        }
        let hasDeparted: Bool
        switch execution {
        case .waitingAtStop(let stop, _)?: hasDeparted = stop > 0
        case .travellingToStop?: hasDeparted = true
        case nil: hasDeparted = info.status != .notDeparted
        }
        return TrainCard(
            origin: stationName(first.station),
            terminus: stationName(last.station),
            departure: GameTime(seconds: first.departure.seconds &+ offset),
            arrival: GameTime(seconds: last.arrival.seconds &+ offset),
            lateMinutes: execution == nil ? 0 : lateMinutes,
            hasDeparted: hasDeparted,
            progress: min(1, max(0, progress)),
            remainingMetres: max(0, remaining),
            nextStop: next.map { stationName(timetable[$0].station) },
            nextStopMinutes: nextMinutes,
            speed: Int64(trainSpeedKMH(of: id).rounded()),
            load: trainLoadInfo(of: id),
            state: info.status,
            now: now
        )
    }
}
