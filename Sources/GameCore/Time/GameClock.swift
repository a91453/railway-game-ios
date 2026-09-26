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

    /// Advances game time by `ticks` fixed steps at the current speed.
    public mutating func advance(ticks: Int) {
        precondition(ticks >= 0, "advance(ticks:) requires a non-negative tick count")
        now.minutes += Int64(ticks) * speed.minutesPerTick
    }
}
