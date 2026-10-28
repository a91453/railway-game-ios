import GameCore

// Decision 464: a game that cannot keep up with its speed for a good while
// says so once, beside the speed, instead of leaving the player to find the
// dot of decision 226. On a big map the game loop also rests on purpose
// (decision 460's ``TickPace``), so the dot shows more often. The hint is
// screen state: nothing here is game state, and nothing is saved.

/// The hint beside the speed: the game runs slower than its speed, and the
/// speed that it can keep.
public struct SpeedLagHint: Equatable, Sendable {
    /// Why the game runs slow, as the hint says it.
    public enum Reason: Equatable, Sendable {
        /// The device cannot work out the ticks in time.
        case slow
        /// The phone is hot and the game loop rests more (``TickPace``).
        case warm
    }

    /// The speed the game is set to.
    public let speed: GameSpeed
    /// How fast it really ran when the hint came, in tenths of times real
    /// time, kept to two figures (``ViewingSpeed/actualTenths``).
    public let actualTenths: Int64
    public var reason: Reason

    public init(speed: GameSpeed, actualTenths: Int64, reason: Reason) {
        self.speed = speed
        self.actualTenths = actualTenths
        self.reason = reason
    }

    /// The fastest speed below the set one that the game can keep, or
    /// `nil` when there is none.
    public var suggestedSpeed: GameSpeed? {
        GameSpeed.allCases
            .filter { $0 != .paused && $0.tenthsPerTick < speed.tenthsPerTick && $0.tenthsPerTick * 10 <= actualTenths }
            .max { $0.tenthsPerTick < $1.tenthsPerTick }
    }

    /// Whether the hint offers to change the speed: not while the phone is
    /// hot, which cools by itself.
    public var offersSpeed: Bool { reason == .slow && suggestedSpeed != nil }

    /// "This map only runs about ×2000 on this device." / "The device is
    /// warm, so the game slows down for now."
    public func text(in language: DisplayLanguage) -> String {
        switch reason {
        case .slow:
            let times = ViewingSpeed.timesText(actualTenths)
            return language.text("This map only runs about \(times) on this device.", "這張地圖在這台裝置上大約只跑得到 \(times)。")
        case .warm:
            return language.text("The device is warm, so the game slows down for now.", "裝置有點燙，遊戲先放慢。")
        }
    }

    /// "Switch to ×1200", or `nil` when the hint offers no speed.
    public func switchText(in language: DisplayLanguage) -> String? {
        guard offersSpeed, let suggestedSpeed else { return nil }
        let times = ViewingSpeed.timesText(suggestedSpeed.tenthsPerTick * 10)
        return language.text("Switch to \(times)", "改成 \(times)")
    }

    public func dismissText(in language: DisplayLanguage) -> String {
        language.text("Got it", "知道了")
    }
}

/// Decides when the hint comes (decision 464): after the game has run under
/// ``lowPermille`` of its speed for ``sustained`` of real time. Once for
/// each speed in a game; none for the rest of the game once the player
/// dismisses it. It goes when the game keeps up again (the dot of decision
/// 226 goes at the same point), the speed changes or the game pauses.
public struct SpeedLagWatch: Equatable, Sendable {
    /// Under this share of the speed, in thousandths, the game counts as
    /// far behind.
    public static let lowPermille: Int64 = 700
    /// How long it must stay behind for the hint to come: long enough that
    /// a day's first passenger plan or a busy stretch is not taken for it.
    public static let sustained: Duration = .seconds(20)

    public private(set) var hint: SpeedLagHint?
    private var speed: GameSpeed?
    private var behindSince: Duration?
    private var shown: Set<GameSpeed> = []
    private var silenced = false

    public init() {}

    /// Forgets the stretch being timed and takes the hint away: the game
    /// paused or its loop stopped. What was shown stays remembered.
    public mutating func pause() {
        speed = nil
        behindSince = nil
        hint = nil
    }

    /// The player dismissed the hint: none again this game.
    public mutating func dismiss() {
        silenced = true
        hint = nil
    }

    /// The hint went before the player saw it (review L-2: the system
    /// closed the popover it could not show): it may come again at this
    /// speed after another ``sustained`` stretch behind.
    public mutating func withdraw() {
        if let speed = hint?.speed { shown.remove(speed) }
        behindSince = nil
        hint = nil
    }

    /// Notes that once the game had run `real` time at `speed`, it ran
    /// `permille` thousandths of that speed over the last seconds
    /// (``GameSpeedMeter/permilleOfSpeed``), with the phone at `heat`.
    public mutating func record(real: Duration, speed: GameSpeed, permille: Int64?, heat: Map3DQuality.Heat) {
        guard speed != .paused else { return pause() }
        if speed != self.speed {
            self.speed = speed
            behindSince = nil
            hint = nil
        }
        guard !silenced, let permille, permille < ViewingSpeed.behindPermille else {
            behindSince = nil
            hint = nil
            return
        }
        let reason: SpeedLagHint.Reason = heat >= .serious ? .warm : .slow
        if hint != nil {
            hint?.reason = reason
            return
        }
        if permille < Self.lowPermille, behindSince == nil { behindSince = real }
        guard let since = behindSince, real - since >= Self.sustained, !shown.contains(speed) else { return }
        shown.insert(speed)
        let actual = ViewingSpeed(speed: speed, permille: permille, trainKilometresPerHour: nil).actualTenths ?? 0
        hint = SpeedLagHint(speed: speed, actualTenths: actual, reason: reason)
    }
}
