/// A point in game time, counted in whole game seconds since the game began
/// (Stage W2a; before it, whole game minutes).
public struct GameTime: Hashable, Comparable, Sendable {
    public var seconds: Int64

    public init(seconds: Int64) {
        self.seconds = seconds
    }

    /// The start of game minute `minutes`: `minutes × 60` seconds.
    ///
    /// - Precondition: the seconds fit in an `Int64`.
    public init(minutes: Int64) {
        let (seconds, overflow) = minutes.multipliedReportingOverflow(by: Self.secondsPerMinute)
        precondition(!overflow, "GameTime(minutes:) needs minutes × 60 to fit in an Int64")
        self.init(seconds: seconds)
    }

    public static let zero = GameTime(seconds: 0)

    /// Game seconds in a game minute.
    public static let secondsPerMinute: Int64 = 60
    /// Game seconds in a game hour.
    public static let secondsPerHour: Int64 = 60 * secondsPerMinute
    /// Game seconds in a game day (see ``minutesPerDay``).
    public static let secondsPerDay: Int64 = 24 * secondsPerHour

    /// The game minute this second falls in, rounded down (also before
    /// second 0): minute `m` runs from second `60m` to `60m + 59`.
    public var minute: Int64 {
        Self.floorDivide(seconds, Self.secondsPerMinute)
    }

    /// The second within its minute, `0..<60` (also before second 0).
    public var secondOfMinute: Int64 {
        // Not `seconds - 60 × minute`: near `Int64.min` the product overflows.
        let remainder = seconds % Self.secondsPerMinute
        return remainder < 0 ? remainder + Self.secondsPerMinute : remainder
    }

    /// Whether this is the start of a game minute.
    public var isWholeMinute: Bool {
        secondOfMinute == 0
    }

    /// `value ÷ divisor` rounded down, for a positive `divisor`.
    static func floorDivide(_ value: Int64, _ divisor: Int64) -> Int64 {
        let quotient = value / divisor
        return value % divisor < 0 ? quotient - 1 : quotient
    }

    public static func < (lhs: GameTime, rhs: GameTime) -> Bool {
        lhs.seconds < rhs.seconds
    }
}

extension GameTime: Codable {
    public init(from decoder: any Decoder) throws {
        self.init(seconds: try decoder.singleValueContainer().decode(Int64.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(seconds)
    }
}

/// How fast game time runs relative to simulation ticks.
///
/// The host ticks every 100 ms of real time (ARCHITECTURE decision 12), so
/// a speed's name is how many times real time it runs at: ``x1`` is real
/// time. ``normal`` and ``double`` keep the names they had before Stage W2a,
/// when they were the only speeds: a game minute and two a tick, 600 and
/// 1200 times real time.
public enum GameSpeed: String, CaseIterable, Codable, Sendable {
    case paused
    case x1
    case x10
    case x60
    case normal
    case double

    /// Tenths of a game second that pass per tick at this speed: only
    /// ``x1`` runs less than a whole second a tick.
    public var tenthsPerTick: Int64 {
        switch self {
        case .paused: 0
        case .x1: 1
        case .x10: 10
        case .x60: 60
        case .normal: 600
        case .double: 1200
        }
    }
}

/// Deterministic game time.
///
/// The clock never reads the wall clock. The host (a future SwiftUI or
/// SpriteKit layer) converts real elapsed time into whole ticks and calls
/// ``advance(ticks:)``; the same ticks at the same speeds always produce the
/// same game time.
public struct GameClock: Hashable, Codable, Sendable {
    public private(set) var now: GameTime
    public private(set) var speed: GameSpeed
    /// The speed ``resume()`` returns to. Never `.paused`.
    private var resumeSpeed: GameSpeed
    /// Tenths of a game second that ticks have run but that do not yet make
    /// a whole second, `0..<10`. Only ``GameSpeed/x1`` runs part of a second
    /// a tick; the other speeds leave this as it is, so it carries over
    /// a change of speed and a pause.
    public private(set) var pendingTenths: Int64

    public init(now: GameTime = .zero, speed: GameSpeed = .paused) {
        self.now = now
        self.speed = speed
        self.resumeSpeed = speed == .paused ? .normal : speed
        self.pendingTenths = 0
    }

    public var isPaused: Bool { speed == .paused }

    /// The speed the clock runs at: its speed, or while paused the speed
    /// ``resume()`` returns to. Never `.paused`.
    public var runningSpeed: GameSpeed { isPaused ? resumeSpeed : speed }

    public mutating func pause() {
        speed = .paused
    }

    /// Resumes at the speed that was active before pausing (1x by default).
    public mutating func resume() {
        speed = resumeSpeed
    }

    public mutating func setSpeed(_ newSpeed: GameSpeed) {
        speed = newSpeed
        if newSpeed != .paused {
            resumeSpeed = newSpeed
        }
    }

    /// Advances game time by `ticks` ticks at the current speed, or by nothing
    /// if the result would not fit.
    ///
    /// - Throws: ``GameError/clockOverflow`` if the time would pass the
    ///   largest second a clock can hold; the clock is then unchanged.
    /// - Precondition: `ticks >= 0`.
    public mutating func advance(ticks: Int) throws(GameError) {
        let steps = try basicSteps(forTicks: ticks)
        now.seconds += steps.seconds
        pendingTenths = steps.pendingTenths
    }

    /// The basic steps (one game second each) `ticks` ticks run at the
    /// current speed, and the tenths of a second left over: the
    /// ``pendingTenths`` and the speed's ``GameSpeed/tenthsPerTick`` for
    /// every tick, in whole seconds, and the rest. None while paused, one
    /// second every 10 ticks at ``GameSpeed/x1``, 60 a tick at
    /// ``GameSpeed/normal``.
    ///
    /// Checks the arithmetic and that the clock can hold the result before
    /// anything is changed, so a caller can validate a whole batch up
    /// front: a batch is refused only when its seconds would not fit, never
    /// because its tenths would not. Paused is always 0 steps, however many
    /// ticks.
    ///
    /// - Throws: ``GameError/clockOverflow``.
    /// - Precondition: `ticks >= 0`.
    func basicSteps(forTicks ticks: Int) throws(GameError) -> (seconds: Int64, pendingTenths: Int64) {
        precondition(ticks >= 0, "advance(ticks:) requires a non-negative tick count")
        // ticks × (10·whole + part) + pending tenths, with ticks = 10q + r:
        // 10·(ticks·whole + q·part) + (r·part + pending) tenths.
        let (whole, part) = speed.tenthsPerTick.quotientAndRemainder(dividingBy: 10)
        let (q, r) = Int64(ticks).quotientAndRemainder(dividingBy: 10)
        let tenths = r * part + pendingTenths
        let (full, long) = Int64(ticks).multipliedReportingOverflow(by: whole)
        let (seconds, longer) = full.addingReportingOverflow(q * part + tenths / 10)
        guard !long, !longer, !now.seconds.addingReportingOverflow(seconds).overflow else { throw .clockOverflow }
        return (seconds, tenths % 10)
    }

    /// Keeps the tenths of a second that ``basicSteps(forTicks:)`` left
    /// over.
    mutating func keep(pendingTenths tenths: Int64) {
        pendingTenths = tenths
    }

    /// Moves time on by `seconds` basic steps that ``basicSteps(forTicks:)``
    /// already checked.
    mutating func advance(basicSteps seconds: Int64) {
        now.seconds += seconds
    }
}

extension GameClock {
    private enum CodingKeys: String, CodingKey {
        case now, speed, resumeSpeed, pendingTenths
    }

    /// Decodes a clock, rejecting a resume speed no command can store:
    /// ``resume()`` returns to the speed that was running before the pause,
    /// so the resume speed is never paused, and a running clock's resume
    /// speed is its own speed. A clock with no tenths pending has no
    /// `"pendingTenths"` key, which is also how clocks saved before Stage
    /// W2a read; an explicit `null` and a value outside `0..<10` are
    /// rejected.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        now = try container.decode(GameTime.self, forKey: .now)
        speed = try container.decode(GameSpeed.self, forKey: .speed)
        resumeSpeed = try container.decode(GameSpeed.self, forKey: .resumeSpeed)
        pendingTenths = container.contains(.pendingTenths) ? try container.decode(Int64.self, forKey: .pendingTenths) : 0
        guard resumeSpeed != .paused, speed == .paused || speed == resumeSpeed else {
            throw DecodingError.dataCorruptedError(
                forKey: .resumeSpeed, in: container,
                debugDescription: "A clock resumes to the speed it was running at, never to paused."
            )
        }
        guard (0..<10).contains(pendingTenths) else {
            throw DecodingError.dataCorruptedError(
                forKey: .pendingTenths, in: container,
                debugDescription: "A clock's pending tenths of a second are 0 to 9."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(now, forKey: .now)
        try container.encode(speed, forKey: .speed)
        try container.encode(resumeSpeed, forKey: .resumeSpeed)
        if pendingTenths > 0 {
            try container.encode(pendingTenths, forKey: .pendingTenths)
        }
    }
}
