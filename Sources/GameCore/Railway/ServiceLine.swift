/// Stable identifier of a service line, unique within a ``GameWorld``.
///
/// IDs are allocated sequentially by the world (never reused), so the same
/// sequence of actions always yields the same IDs.
public struct LineID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: LineID, rhs: LineID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// How busy a time of day is, which sets how many trains a line runs then
/// (see ``TrainsInService``). Which minutes of the day have which level is
/// the world's ``ServiceDay``.
public enum ServiceLevel: String, CaseIterable, Codable, Sendable {
    case peak
    case offPeak
    case low
}

extension GameTime {
    /// Game minutes in a day. Game time has no calendar; days only group
    /// minutes for service planning and display.
    public static let minutesPerDay: Int64 = 24 * 60

    /// The minute of the day, `0..<1440`, counting from the start of the
    /// day that contains this minute (also before minute 0).
    public var minuteOfDay: Int {
        let minute = minutes % Self.minutesPerDay
        return Int(minute < 0 ? minute + Self.minutesPerDay : minute)
    }
}

/// When a line runs during the day: all day, or from `open` to `close`,
/// both minutes of the day, where `close` may run into the next morning.
///
/// A window from `open` to `close` contains minute of the day `m` when
/// `open <= m < close`, counting minutes before `open` as the next day's
/// (`m + 1440`): a window from 06:00 to 25:00 (`360` to `1500`) runs until
/// 01:00 the next morning. `open` is in `0...1439`, `close` is later than
/// `open` and no later than ``latestClose`` (06:00 the next morning).
public enum ServiceWindow: Hashable, Sendable {
    case allDay
    case hours(open: Int, close: Int)

    /// The latest a window may close: 06:00 the next morning.
    public static let latestClose = 1800

    /// From 06:00 to midnight, the window of a new line.
    public static let standard = ServiceWindow.hours(open: 360, close: 1440)

    /// Whether the window is one a line can have (see the type's rules).
    var isValid: Bool {
        switch self {
        case .allDay:
            true
        case .hours(let open, let close):
            (0...1439).contains(open) && open < close && close <= Self.latestClose
        }
    }

    /// Whether the line runs at `minuteOfDay` (`0..<1440`).
    ///
    /// - Precondition: the window is valid.
    public func contains(minuteOfDay minute: Int) -> Bool {
        switch self {
        case .allDay:
            return true
        case .hours(let open, let close):
            let counted = minute < open ? minute + 1440 : minute
            return open <= counted && counted < close
        }
    }
}

/// How many trains a line is to run at each ``ServiceLevel``. Each count is
/// 0 or more; a line never runs more than its journey allows (see
/// ``GameWorld/lineTrainsInService(_:at:)``).
public struct TrainsInService: Hashable, Sendable {
    public var peak: Int
    public var offPeak: Int
    public var low: Int

    public init(peak: Int, offPeak: Int, low: Int) {
        self.peak = peak
        self.offPeak = offPeak
        self.low = low
    }

    /// None at any level, as on a new line.
    public static let none = TrainsInService(peak: 0, offPeak: 0, low: 0)

    public subscript(level: ServiceLevel) -> Int {
        switch level {
        case .peak: peak
        case .offPeak: offPeak
        case .low: low
        }
    }

    var isValid: Bool {
        peak >= 0 && offPeak >= 0 && low >= 0
    }
}

/// Which ``ServiceLevel`` each minute of the day has, for every line of a
/// world: a list of bands, each starting at a minute of the day and lasting
/// until the next band starts (the last until midnight).
///
/// The first band starts at minute 0 and the starts strictly increase, so
/// every minute of the day has exactly one level.
public struct ServiceDay: Hashable, Sendable {
    /// A level from a minute of the day on.
    public struct Band: Hashable, Sendable {
        public let start: Int
        public let level: ServiceLevel

        public init(start: Int, level: ServiceLevel) {
            self.start = start
            self.level = level
        }
    }

    public let bands: [Band]

    public init(bands: [Band]) {
        self.bands = bands
    }

    /// Peak from 07:00 to 10:00 and 16:00 to 20:00, low from midnight to
    /// 07:00 and from 21:00, and off-peak otherwise: the day of the web
    /// reference (docs/WEB_REFERENCE_STUDY.md), and of every new world.
    public static let standard = ServiceDay(bands: [
        Band(start: 0, level: .low),
        Band(start: 420, level: .peak),
        Band(start: 600, level: .offPeak),
        Band(start: 960, level: .peak),
        Band(start: 1200, level: .offPeak),
        Band(start: 1260, level: .low),
    ])

    /// Whether the bands start at minute 0 and strictly increase within the
    /// day.
    var isValid: Bool {
        guard bands.first?.start == 0, let last = bands.last, last.start < 1440 else { return false }
        return zip(bands, bands.dropFirst()).allSatisfy { $0.start < $1.start }
    }

    /// The level at `minuteOfDay` (`0..<1440`).
    ///
    /// - Precondition: the day is valid.
    public func level(atMinuteOfDay minute: Int) -> ServiceLevel {
        bands.last { $0.start <= minute }!.level
    }
}

/// A service line: the stations its trains call at, in order, out from the
/// first and back from the last; the rate it plans its journeys at; when it
/// runs; and how many trains it is to run at each level.
///
/// A line is plan data. It never moves, routes or schedules a train; what
/// its trains would take, and how often they could run, is derived by
/// ``GameWorld/lineJourney(_:)`` and the queries beside it.
public struct ServiceLine: Identifiable, Hashable, Sendable {
    public let id: LineID
    public internal(set) var name: String
    /// The stations called at, in order: at least two, and no station twice
    /// in a row. The trains run from the first to the last and back, turning
    /// round at both ends.
    public internal(set) var stops: [StationID]
    /// The rate, in logical units per game minute, that the line's journey
    /// times are worked out at (see ``TrainMovement``). At least 1.
    public internal(set) var rate: Int64
    public internal(set) var window: ServiceWindow
    public internal(set) var trainsInService: TrainsInService

    /// The rate of a new line: one link a minute.
    public static let defaultRate: Int64 = TrainPosition.linkLength
    /// Minutes a train stays at a stop between the ends of the line.
    public static let dwellMinutes: Int64 = 1
    /// Minutes a train stays at either end of the line, where it turns round.
    public static let terminalDwellMinutes: Int64 = 2
    /// The shortest time between two trains of a line: it never runs more
    /// trains than its round trip allows at this headway.
    public static let minimumHeadwayMinutes: Int64 = 2

    /// Creates a line with the standard window, the default rate and no
    /// trains in service.
    public init(id: LineID, name: String, stops: [StationID]) {
        self.id = id
        self.name = name
        self.stops = stops
        self.rate = Self.defaultRate
        self.window = .standard
        self.trainsInService = .none
    }

    /// Whether `stops` can be a line's stops, judged without a world: at
    /// least two, and no station twice in a row.
    static func isStopList(_ stops: [StationID]) -> Bool {
        stops.count >= 2 && zip(stops, stops.dropFirst()).allSatisfy { $0 != $1 }
    }
}

// MARK: - Codable

extension ServiceWindow: Codable {
    private enum CodingKeys: String, CodingKey {
        case open, close
    }

    /// Decodes `"allDay"` or `{"open", "close"}`, rejecting a window no line
    /// can have rather than repairing it.
    public init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            guard text == "allDay" else {
                throw DecodingError.dataCorruptedError(in: single, debugDescription: "Unknown service window \"\(text)\".")
            }
            self = .allDay
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .hours(open: try container.decode(Int.self, forKey: .open), close: try container.decode(Int.self, forKey: .close))
        guard isValid else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "A service window opens in 0...1439 and closes after it, by 1800."
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .allDay:
            var container = encoder.singleValueContainer()
            try container.encode("allDay")
        case .hours(let open, let close):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(open, forKey: .open)
            try container.encode(close, forKey: .close)
        }
    }
}

extension TrainsInService: Codable {
    private enum CodingKeys: String, CodingKey {
        case peak, offPeak, low
    }

    /// Decodes `{"peak", "offPeak", "low"}`, rejecting a negative count.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            peak: try container.decode(Int.self, forKey: .peak),
            offPeak: try container.decode(Int.self, forKey: .offPeak),
            low: try container.decode(Int.self, forKey: .low)
        )
        guard isValid else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath, debugDescription: "Trains in service cannot be negative."
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(peak, forKey: .peak)
        try container.encode(offPeak, forKey: .offPeak)
        try container.encode(low, forKey: .low)
    }
}

extension ServiceDay: Codable {
    /// Decodes a list of `{"start", "level"}`, rejecting a day whose bands
    /// do not start at minute 0 or do not strictly increase within the day.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(bands: try container.decode([Band].self))
        guard isValid else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "A service day's bands start at minute 0 and strictly increase within the day."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bands)
    }
}

extension ServiceDay.Band: Codable {}

extension ServiceLine: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, stops, rate, window, trainsInService
    }

    /// Decodes a line, rejecting stops, a rate, a window or train counts no
    /// line can have rather than repairing them. That the stations exist is
    /// checked by the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(LineID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        stops = try container.decode([StationID].self, forKey: .stops)
        rate = try container.decode(Int64.self, forKey: .rate)
        window = try container.decode(ServiceWindow.self, forKey: .window)
        trainsInService = try container.decode(TrainsInService.self, forKey: .trainsInService)
        guard Self.isStopList(stops) else {
            throw DecodingError.dataCorruptedError(
                forKey: .stops, in: container, debugDescription: "Line \(id.rawValue) needs two stops or more, none twice in a row."
            )
        }
        guard rate >= 1 else {
            throw DecodingError.dataCorruptedError(forKey: .rate, in: container, debugDescription: "Line \(id.rawValue)'s rate must be at least 1.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(stops, forKey: .stops)
        try container.encode(rate, forKey: .rate)
        try container.encode(window, forKey: .window)
        try container.encode(trainsInService, forKey: .trainsInService)
    }
}
