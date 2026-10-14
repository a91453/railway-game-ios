import GameCore

// The station panel's operations page (ARCHITECTURE decision 224, option A
// "月台俯視圖"): each platform as a track seen from above with the train
// standing at it now and how busy it has been, how many wait at the
// station, and the weather of the next days with what it does to the
// station's riders.
//
// The world keeps no record of when a platform was taken, so how busy a
// platform has been is sampled here: ``PlatformUse`` notes, once a game
// minute while the game runs, which platforms have a train standing at
// them, and keeps the last hour. It is the session's transient state, as
// the train diagram's history is (decision 206), and starts empty after a
// game is loaded.

/// Which platforms have had a train standing at them, a game minute at a
/// time, over the last ``window`` minutes.
public struct PlatformUse: Equatable, Sendable {
    /// How many game minutes it keeps.
    public static let window: Int64 = 60

    /// The platforms taken in each sampled minute, by the minute.
    private var taken: [Int64: Set<TrackPlatform>] = [:]
    private var last: Int64?

    public init() {}

    /// Notes the platforms `world`'s trains stand at, once for each game
    /// minute; starts again when the clock has gone back (a game loaded).
    public mutating func record(_ world: GameWorld) {
        let minute = Self.floorMinute(world.clock.now.seconds)
        if let last, minute < last { self = PlatformUse() }
        guard minute != last else { return }
        last = minute
        var platforms = Set<TrackPlatform>()
        for train in world.trains where train.position != nil {
            platforms.formUnion(world.trackPlatformsAlongWholeTrain(train.id))
        }
        taken[minute] = platforms
        taken = taken.filter { $0.key > minute - Self.window }
    }

    /// How many of the sampled minutes of the last hour before `now` had a
    /// train at `platform`, and how many minutes were sampled.
    public func use(of platform: TrackPlatform, now: GameTime) -> (taken: Int, sampled: Int) {
        let minute = Self.floorMinute(now.seconds)
        let recent = taken.filter { $0.key > minute - Self.window && $0.key <= minute }
        return (recent.values.filter { $0.contains(platform) }.count, recent.count)
    }

    private static func floorMinute(_ seconds: Int64) -> Int64 {
        let quotient = seconds / GameTime.secondsPerMinute
        return seconds % GameTime.secondsPerMinute < 0 ? quotient - 1 : quotient
    }
}

/// What the station's operations page shows (decision 224, 4A).
public struct StationOperations: Equatable, Sendable {
    /// How busy a platform has been: the share of the last hour with a
    /// train standing at it, in three steps, each with its word.
    public enum Busyness: Hashable, Sendable {
        case quiet, busy, packed

        public init(percent: Int) {
            if percent >= Self.packedFrom {
                self = .packed
            } else if percent >= Self.busyFrom {
                self = .busy
            } else {
                self = .quiet
            }
        }

        static let busyFrom = 50
        static let packedFrom = 80

        public func text(in language: DisplayLanguage) -> String {
            switch self {
            case .quiet: language.text("Quiet", "空")
            case .busy: language.text("Busy", "忙")
            case .packed: language.text("Packed", "擠")
            }
        }
    }

    /// One of the station's platforms.
    public struct Platform: Equatable, Sendable, Identifiable {
        /// 1 for the first of ``GameWorld/trackPlatforms(of:)``, as the
        /// station panel numbers them.
        public let number: Int
        public let platform: TrackPlatform
        /// The train standing at it now, with its line and where it goes.
        public let train: TrainID?
        public let trainName: String?
        public let line: LineID?
        public let lineColor: LineColor?
        public let cars: Int
        /// The last stop of its trip; `nil` when it ends here or has none.
        public let destination: String?
        /// Of the last hour, the share with a train standing at it (0 to
        /// 100), and how many minutes of it were seen; `nil` before any.
        public let busyPercent: Int?
        public let sampledMinutes: Int

        public var id: Int { number }

        public var busyness: Busyness? {
            busyPercent.map(Busyness.init(percent:))
        }

        /// "Line 1 to East", "Line 1, ends here", or "Free".
        public func trainText(lineName: String?, in language: DisplayLanguage) -> String {
            guard let trainName else { return language.text("Free", "空著") }
            let name = lineName ?? trainName
            guard let destination else { return language.text("\(name), ends here", "\(name)・終點") }
            return language.text("\(name) to \(destination)", "\(name)・往 \(destination)")
        }

        /// "82%", or "38% (last 20 min)" while less than an hour was seen.
        public func busyText(in language: DisplayLanguage) -> String? {
            guard let busyPercent else { return nil }
            if Int64(sampledMinutes) >= PlatformUse.window { return "\(busyPercent)%" }
            return language.text("\(busyPercent)% (last \(sampledMinutes) min)", "\(busyPercent)%（最近 \(sampledMinutes) 分）")
        }
    }

    /// A day of the forecast at the station.
    public struct Day: Equatable, Sendable, Identifiable {
        public let date: GameDate
        public let isToday: Bool
        public let weather: Weather
        /// A typhoon blows over the station that day.
        public let typhoon: Bool
        /// What the day takes off the station's riders, in whole percent:
        /// the weather on every line, and a typhoon here.
        public let weatherDropPercent: Int
        public let typhoonDropPercent: Int

        public var id: Int64 { date.day }

        /// "Today", "Tomorrow" or "5/12（六）".
        public func dayText(in language: DisplayLanguage) -> String {
            if isToday { return language.text("Today", "今天") }
            return date.shortText(in: language)
        }

        /// "Typhoon", or the weather's name.
        public func weatherText(in language: DisplayLanguage) -> String {
            typhoon ? language.text("Typhoon", "颱風") : weather.title(in: language)
        }

        /// "Riders −10%", "Riders here −35%", or `nil` when the day takes
        /// nothing off.
        public func effectText(in language: DisplayLanguage) -> String? {
            if typhoonDropPercent > 0 {
                let total = 100 - (100 - weatherDropPercent) * (100 - typhoonDropPercent) / 100
                return language.text("Riders here −\(total)%", "這站乘客 −\(total)%")
            }
            guard weatherDropPercent > 0 else { return nil }
            return language.text("Riders −\(weatherDropPercent)%", "乘客 −\(weatherDropPercent)%")
        }
    }

    public let station: StationID
    /// How many wait at the station, and how full its room for them is.
    public let waiting: Int64
    public let crowding: MapProblems.Crowding
    public let platforms: [Platform]
    /// Today and the next days; empty when the world has no weather.
    public let days: [Day]

    /// "128 waiting", "1,960 waiting · crowded" or "4,000 waiting · full".
    public func waitingText(in language: DisplayLanguage) -> String {
        let count = Self.grouped(waiting)
        switch crowding {
        case .normal: return language.text("\(count) waiting", "候車 \(count) 人")
        case .crowded: return language.text("\(count) waiting · crowded", "候車 \(count) 人・擁擠")
        case .full: return language.text("\(count) waiting · full", "候車 \(count) 人・客滿")
        }
    }

    /// `value` with thousands separators: "4,000".
    static func grouped(_ value: Int64) -> String {
        let digits = String(value.magnitude)
        var text = value < 0 ? "-" : ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { text.append(",") }
            text.append(digit)
        }
        return text
    }

    /// How many days the weather card shows.
    public static let forecastDays = 4

    /// The page of `station` in `world`, with how busy its platforms have
    /// been from `use`.
    public init(world: GameWorld, station: StationID, use: PlatformUse) {
        self.station = station
        let waiting = world.waitingPassengers(at: station).reduce(Int64(0)) { $0 + $1.count }
        self.waiting = waiting
        self.crowding = MapProblems.Crowding(waiting: waiting)

        var standing: [TrackPlatform: TrainID] = [:]
        for train in world.trains where train.position != nil {
            for platform in world.trackPlatformsAlongWholeTrain(train.id) where platform.station == station {
                standing[platform] = standing[platform].map { min($0, train.id) } ?? train.id
            }
        }
        let now = world.clock.now
        self.platforms = world.trackPlatforms(of: station).enumerated().map { index, platform in
            let trainID = standing[platform]
            let train = trainID.flatMap { world.train(id: $0) }
            let line = trainID.flatMap { world.assignedLine(of: $0) }
            let last = train?.timetable.last?.station
            let seen = use.use(of: platform, now: now)
            return Platform(
                number: index + 1,
                platform: platform,
                train: trainID,
                trainName: train?.name,
                line: line,
                lineColor: line.flatMap { world.line(id: $0)?.color },
                cars: train?.cars ?? 0,
                destination: last == nil || last == station ? nil : last.map { world.stationName($0) },
                busyPercent: seen.sampled > 0 ? (seen.taken * 100 + seen.sampled / 2) / seen.sampled : nil,
                sampledMinutes: seen.sampled
            )
        }

        guard let point = world.station(id: station)?.point else {
            self.days = []
            return
        }
        let today = now.seconds / GameTime.secondsPerDay
        let typhoons = world.typhoons(onDay: today).filter { $0.covers(point) }
        self.days = world.forecast(days: Self.forecastDays).map { forecast in
            let day = forecast.date.day
            let typhoon = typhoons.filter { $0.isActive(onDay: day) }.map(\.drop).max()
            return Day(
                date: forecast.date,
                isToday: day == today,
                weather: forecast.weather,
                typhoon: typhoon != nil,
                weatherDropPercent: Int(world.weatherDrop(onDay: day) / 10),
                typhoonDropPercent: Int((typhoon ?? 0) / 10)
            )
        }
    }
}
