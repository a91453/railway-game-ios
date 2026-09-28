/// A point in game time, counted in whole game minutes since the game began.
public struct GameTime: Hashable, Comparable, Sendable {
    public var minutes: Int64

    public init(minutes: Int64) {
        self.minutes = minutes
    }

    public static let zero = GameTime(minutes: 0)

    public static func < (lhs: GameTime, rhs: GameTime) -> Bool {
        lhs.minutes < rhs.minutes
    }
}

extension GameTime: Codable {
    public init(from decoder: any Decoder) throws {
        self.init(minutes: try decoder.singleValueContainer().decode(Int64.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(minutes)
    }
}

/// How fast game time runs relative to simulation ticks.
public enum GameSpeed: String, CaseIterable, Codable, Sendable {
    case paused
    case normal
    case double

    /// Game minutes that pass per tick at this speed.
    public var minutesPerTick: Int64 {
        switch self {
        case .paused: 0
        case .normal: 1
        case .double: 2
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

    public init(now: GameTime = .zero, speed: GameSpeed = .paused) {
        self.now = now
        self.speed = speed
        self.resumeSpeed = speed == .paused ? .normal : speed
    }

    public var isPaused: Bool { speed == .paused }

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
    ///   largest minute a clock can hold; the clock is then unchanged.
    /// - Precondition: `ticks >= 0`.
    public mutating func advance(ticks: Int) throws(GameError) {
        now.minutes += try basicSteps(forTicks: ticks)
    }

    /// The basic steps (one game minute each) `ticks` ticks run at the
    /// current speed: none while paused, one per tick at 1x, two at 2x.
    ///
    /// Checks the multiplication and that the clock can hold the result
    /// before anything is changed, so a caller can validate a whole batch up
    /// front. Paused is always 0 steps, however many ticks.
    ///
    /// - Throws: ``GameError/clockOverflow``.
    /// - Precondition: `ticks >= 0`.
    func basicSteps(forTicks ticks: Int) throws(GameError) -> Int64 {
        precondition(ticks >= 0, "advance(ticks:) requires a non-negative tick count")
        let steps = Int64(ticks).multipliedReportingOverflow(by: speed.minutesPerTick)
        guard !steps.overflow, !now.minutes.addingReportingOverflow(steps.partialValue).overflow else {
            throw .clockOverflow
        }
        return steps.partialValue
    }

    /// Moves time on by `steps` basic steps that ``basicSteps(forTicks:)``
    /// already checked.
    mutating func advance(basicSteps steps: Int64) {
        now.minutes += steps
    }
}

extension GameClock {
    private enum CodingKeys: String, CodingKey {
        case now, speed, resumeSpeed
    }

    /// Decodes a clock, rejecting a resume speed no command can store:
    /// ``resume()`` returns to the speed that was running before the pause,
    /// so the resume speed is never paused, and a running clock's resume
    /// speed is its own speed.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        now = try container.decode(GameTime.self, forKey: .now)
        speed = try container.decode(GameSpeed.self, forKey: .speed)
        resumeSpeed = try container.decode(GameSpeed.self, forKey: .resumeSpeed)
        guard resumeSpeed != .paused, speed == .paused || speed == resumeSpeed else {
            throw DecodingError.dataCorruptedError(
                forKey: .resumeSpeed, in: container,
                debugDescription: "A clock resumes to the speed it was running at, never to paused."
            )
        }
    }
}
