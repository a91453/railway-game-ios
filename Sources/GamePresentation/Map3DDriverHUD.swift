import GameCore

/// Decision 403: what the 3D map shows while it follows a train, in all
/// three views (``Map3DFollow/View``), as a driving game's cab display: a
/// strip at the top with the line, the way it runs, the next stop, how far
/// it is and how late the train runs; a speed card with its speed, the
/// limit it keeps to now and the next one ahead; and a short prompt near a
/// stop. The owner's OpenWorld reference's `maglev-view.js` info line
/// ("line · km/h · 下一站：X", or "停靠：X" while it stands) is the strip's
/// place; the limits, the distances and the punctuality are this project's
/// (the reference has none). Read from the world each time it is shown;
/// never stored.
public struct Map3DDriverHUD: Hashable, Sendable {
    /// The stop the strip names.
    public enum Place: Hashable, Sendable {
        /// The stop it runs to.
        case next(String)
        /// The stop it stands at.
        case at(String)
    }

    /// A curve limit ahead of the train, and how far ahead it starts.
    public struct LimitAhead: Hashable, Sendable {
        /// km/h.
        public let speed: Int64
        public let metres: Int64

        public init(speed: Int64, metres: Int64) {
            self.speed = speed
            self.metres = metres
        }
    }

    /// The prompt in the middle of the strip, when there is one.
    public enum Prompt: Hashable, Sendable {
        /// Within ``approachMetres`` of the stop it runs to.
        case approaching(station: String, metres: Int64)
        /// Just stood at a stop, with how late it arrived in seconds
        /// (negative when early).
        case arrived(lateness: Int64)
    }

    /// How near the stop the approach prompt shows: 1 km.
    public static let approachMetres: Int64 = 1_000
    /// How long after arriving the arrival prompt shows, in the game's
    /// seconds.
    public static let arrivedSeconds: Int64 = 30
    /// How far ahead a limit is named: 3 km, about the braking distance of
    /// a 300 km/h train.
    public static let limitLookaheadMetres: Int64 = 3_000

    /// The line it runs for, for the badge; `nil` for none.
    public let line: LineID?
    public let lineName: String?
    /// The service and its first and last stops.
    public let service: String?
    public let origin: String?
    public let terminus: String?
    public let place: Place?
    /// Metres to the stop it runs to; `nil` while it stands.
    public let metresToNext: Int64?
    /// Seconds behind its timetable (negative when early); `nil` for a
    /// train without a service.
    public let lateness: Int64?
    /// Whole km/h.
    public let speed: Int64
    /// The curve limit it keeps to now, km/h; `nil` where none holds or
    /// with the curve limits off.
    public let limitHere: Int64?
    public let limitAhead: LimitAhead?
    public let prompt: Prompt?

    public init(line: LineID?, lineName: String?, service: String?, origin: String?, terminus: String?, place: Place?,
                metresToNext: Int64?, lateness: Int64?, speed: Int64, limitHere: Int64?, limitAhead: LimitAhead?, prompt: Prompt?) {
        self.line = line
        self.lineName = lineName
        self.service = service
        self.origin = origin
        self.terminus = terminus
        self.place = place
        self.metresToNext = metresToNext
        self.lateness = lateness
        self.speed = speed
        self.limitHere = limitHere
        self.limitAhead = limitAhead
        self.prompt = prompt
    }

    /// "Local · Alpha → Gamma", or as much of it as the train has; the
    /// service is left out when it is the line's own name.
    public var routeText: String? {
        var parts: [String] = []
        if let service, service != lineName { parts.append(service) }
        if let origin, let terminus { parts.append("\(origin) → \(terminus)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Next" or "Stopped at", above the station's name.
    public func placeLabel(in language: DisplayLanguage) -> String? {
        switch place {
        case .next?: language.text("Next", "下一站")
        case .at?: language.text("Stopped at", "停靠")
        case nil: nil
        }
    }

    public var placeName: String? {
        switch place {
        case .next(let name)?, .at(let name)?: name
        case nil: nil
        }
    }

    /// "3.8 km", or "640 m" under a kilometre.
    public static func distanceText(_ metres: Int64) -> String {
        let metres = max(0, metres)
        if metres < 1_000 { return "\((metres + 5) / 10 * 10) m" }
        let tenths = (metres + 50) / 100
        return "\(tenths / 10).\(tenths % 10) km"
    }

    public var distanceText: String? { metresToNext.map(Self.distanceText) }

    /// "On time", "8 s late", "3 min late", or early by as much.
    public static func latenessText(_ seconds: Int64, in language: DisplayLanguage) -> String {
        let amount = seconds.magnitude
        if amount == 0 { return language.text("On time", "準點") }
        let minutes = amount / UInt64(GameTime.secondsPerMinute)
        if seconds > 0 {
            return minutes > 0 ? language.text("\(minutes) min late", "晚 \(minutes) 分") : language.text("\(amount) s late", "晚 \(amount) 秒")
        }
        return minutes > 0 ? language.text("\(minutes) min early", "早 \(minutes) 分") : language.text("\(amount) s early", "早 \(amount) 秒")
    }

    public func latenessText(in language: DisplayLanguage) -> String? {
        lateness.map { Self.latenessText($0, in: language) }
    }

    /// The prompt's words: "Next stop Taoyuan, 640 m"; after arriving, "On
    /// time" (under a minute either way) or "3 min late".
    public func promptText(in language: DisplayLanguage) -> String? {
        switch prompt {
        case .approaching(let station, let metres)?:
            let distance = Self.distanceText(metres)
            return language.text("Next stop \(station), \(distance)", "下一站 \(station)，剩 \(distance)")
        case .arrived(let lateness)?:
            let minutes = lateness / GameTime.secondsPerMinute
            return Self.latenessText(minutes * GameTime.secondsPerMinute, in: language)
        case nil:
            return nil
        }
    }

    /// What VoiceOver reads for the speed card: "120 km/h, limit 75 km/h,
    /// 60 km/h in 1.5 km".
    public func speedLabel(in language: DisplayLanguage) -> String {
        var text = "\(speed) km/h"
        if let limitHere { text += language.text(", limit \(limitHere) km/h", "，限速 \(limitHere) km/h") }
        if let limitAhead {
            let distance = Self.distanceText(limitAhead.metres)
            text += language.text(", \(limitAhead.speed) km/h in \(distance)", "，\(distance) 後限 \(limitAhead.speed) km/h")
        }
        return text
    }
}

extension GameWorld {
    /// The 3D map's driving display for train `id` (see ``Map3DDriverHUD``),
    /// or `nil` for an unknown train.
    public func map3DDriverHUD(of id: TrainID, in language: DisplayLanguage) -> Map3DDriverHUD? {
        guard let train = train(id: id), let info = followBarInfo(of: id, in: language) else { return nil }
        let now = clock.now
        let metre = WorldCoordinate.unitsPerMetre
        var place: Map3DDriverHUD.Place?
        var metresToNext: Int64?
        var covered: Int64?
        var prompt: Map3DDriverHUD.Prompt?
        switch train.execution {
        case .travellingToStop(let stop, _)?:
            place = .next(stationName(train.timetable[stop].station))
            if let run = train.times?.run, let curve = runCurve(of: run, for: train.performance) {
                let elapsed = max(0, now.seconds - run.start.seconds)
                let done = elapsed >= run.seconds ? run.length : curve.distance(at: elapsed * 1000)
                covered = done
                let left = max(0, run.length - done) / metre
                metresToNext = left
                if left <= Map3DDriverHUD.approachMetres {
                    prompt = .approaching(station: stationName(train.timetable[stop].station), metres: left)
                }
            }
        case .waitingAtStop(let stop, let cycle)?:
            place = .at(stationName(train.timetable[stop].station))
            // Arrived here, not set off from its first stop.
            if stop > 0 || cycle > 0, let arrived = train.times?.arrival, now >= arrived,
               now.seconds - arrived.seconds <= Map3DDriverHUD.arrivedSeconds {
                let scheduled = train.timetable[stop].arrival.seconds &+ (train.timetablePeriod ?? 0) &* cycle
                prompt = .arrived(lateness: arrived.seconds - scheduled)
            }
        case nil:
            break
        }
        let here = curveLimit(of: id).flatMap { $0.ahead ? nil : $0.speed }
        var ahead: Map3DDriverHUD.LimitAhead?
        if curveSpeedLimits, let covered, let run = train.times?.run {
            // The stretch it is in, and any of the same limit straight
            // after it, are the limit here; the first lower than its top
            // speed past them is the one ahead.
            var through = covered
            for limit in run.limits.sorted(by: { $0.start < $1.start }) where limit.end > covered {
                if limit.start <= through, limit.speed == here {
                    through = max(through, limit.end)
                    continue
                }
                guard limit.start > covered, limit.speed < train.performance.topSpeed else { continue }
                let metres = (limit.start - covered) / metre
                if metres <= Map3DDriverHUD.limitLookaheadMetres { ahead = .init(speed: limit.speed, metres: metres) }
                break
            }
        }
        return Map3DDriverHUD(
            line: info.line,
            lineName: info.line.flatMap { line(id: $0)?.name },
            service: info.kind,
            origin: info.origin,
            terminus: info.terminus,
            place: place,
            metresToNext: metresToNext,
            lateness: lateness(of: id),
            speed: Int64(trainSpeedKMH(of: id).rounded()),
            limitHere: here,
            limitAhead: ahead,
            prompt: prompt
        )
    }
}
