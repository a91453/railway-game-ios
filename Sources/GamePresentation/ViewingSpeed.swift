import GameCore

// Watching at a true speed (ARCHITECTURE decision 195): how fast game time
// really runs, and how fast the followed train goes, for the status pill.
// A new game runs at 600 times real time, so a train at 300 km/h crosses
// 50 km of map a second; the follow bar offers real time and 10× in one
// tap, and the pill says the train's speed and whether the device keeps up
// with the chosen speed. Measured from what the session's game loop puts
// in place; nothing here is game state.
//
// The reference (`Ci/`) has speed buttons (`setSpeed`, `.sp-btn`) and shows
// a train's speed in whole km/h (`metroFormatSpeedKmh`); it measures no
// actual speed.

/// How fast game time has really run over the last seconds, against what
/// its speed should give (decision 195): the ticks the game loop put in
/// place over the real time it ran. A tick the device was too slow to work
/// out in time, or one dropped for a command (decision 143), is game time
/// that did not run.
public struct GameSpeedMeter: Hashable, Sendable {
    /// The real time a reading looks back over.
    public static let window: Duration = .seconds(3)
    /// The least real time a reading is taken over: less reads too much
    /// into one late tick.
    public static let shortestReading: Duration = .seconds(1)

    private struct Sample: Hashable, Sendable {
        /// Real time the game had run when it was taken.
        let real: Duration
        /// Ticks put in place by then.
        let ticks: Int64
    }

    /// The real time a tick stands for at any speed.
    public let tickInterval: Duration
    private var speed: GameSpeed?
    private var samples: [Sample] = []

    public init(tickInterval: Duration = GameSession.tickInterval) {
        self.tickInterval = tickInterval
    }

    /// Forgets what it has measured: the game paused, or stopped running.
    public mutating func reset() {
        speed = nil
        samples = []
    }

    /// Notes that once the game had run `real` time, `ticks` ticks had been
    /// put in place at `speed`. A new speed, or a pause, starts again.
    public mutating func record(real: Duration, ticks: Int64, speed: GameSpeed) {
        guard speed != .paused else { return reset() }
        if speed != self.speed {
            self.speed = speed
            samples = []
        }
        if let last = samples.last, real < last.real || ticks < last.ticks {
            samples = []
        }
        samples.append(Sample(real: real, ticks: ticks))
        // Keeps the last sample at or before the window's start, so a
        // reading spans the whole window once there is one.
        while samples.count > 2, samples[1].real <= real - Self.window {
            samples.removeFirst()
        }
    }

    /// The game time that ran, in thousandths of what the speed should
    /// have run over the same real time, or `nil` paused or before
    /// ``shortestReading``.
    public var permilleOfSpeed: Int64? {
        guard speed != nil, let first = samples.first, let last = samples.last else { return nil }
        let span = last.real - first.real
        guard span >= Self.shortestReading else { return nil }
        let due = Self.milliseconds(span) * 1_000 / max(1, Self.milliseconds(tickInterval))
        return (last.ticks - first.ticks) * 1_000_000 / max(1, due)
    }

    static func milliseconds(_ duration: Duration) -> Int64 {
        let parts = duration.components
        return parts.seconds * 1_000 + parts.attoseconds / 1_000_000_000_000_000
    }
}

/// How fast the followed train goes (decision 195): the track it covered
/// over the last game seconds, measured tick by tick from where it was to
/// where it is along the way it was to go. At the speeds a tick runs less
/// than ``windowSeconds`` that is its speed now; at 600× a tick is a game
/// minute, and it is that minute's average, stops included.
public struct TrainSpeedometer: Hashable, Sendable {
    /// The game seconds a reading looks back over.
    public static let windowSeconds: Int64 = 5

    private struct Sample: Hashable, Sendable {
        /// Game time, in seconds.
        let time: Int64
        /// Track covered since the first sample, in world units.
        let distance: Int64
    }

    private var train: TrainID?
    private var samples: [Sample] = []

    public init() {}

    /// Notes train `id` (or none) from where `before` had it to where
    /// `after`, the world a tick or a step later, has it. Another train, a
    /// jump (placed, turned, taken off) or time running back starts again.
    public mutating func observe(_ id: TrainID?, from before: GameWorld, to after: GameWorld) {
        guard let id, let now = after.train(id: id), let position = now.position else {
            train = nil
            samples = []
            return
        }
        let time = after.clock.now.seconds
        guard id == train, let last = samples.last, time >= last.time,
              let was = before.train(id: id)?.position,
              let covered = GameWorld.trackDistance(from: was, along: before.train(id: id)?.movement.remainingEdges ?? [], to: position, in: after)
        else {
            train = id
            samples = [Sample(time: time, distance: 0)]
            return
        }
        // Within a game second (at real time) the train has not moved.
        guard time > last.time else { return }
        samples.append(Sample(time: time, distance: last.distance + covered))
        while samples.count > 2, samples[1].time <= time - Self.windowSeconds {
            samples.removeFirst()
        }
    }

    /// The train's speed in whole km/h, or `nil` before it has run a game
    /// second.
    public var kilometresPerHour: Int64? {
        guard let first = samples.first, let last = samples.last, last.time > first.time else { return nil }
        // Units a second × 3,600 ÷ (64 units a metre × 1,000), rounded.
        let units = last.distance - first.distance
        let seconds = last.time - first.time
        return (units * 9 * 2 + 160 * seconds) / (2 * 160 * seconds)
    }
}

extension GameWorld {
    /// The track from a head at `start` to one at `end`, going the way the
    /// edges `ahead` lead, in world units; `nil` when `end` is not on that
    /// way (behind `start` on its edge, turned the other way, or on no edge
    /// `ahead` names). The length ``TrainMotion`` glides a train along.
    static func trackDistance(from start: TrainPosition, along ahead: some Sequence<TrackEdgeID>, to end: TrainPosition, in world: GameWorld) -> Int64? {
        guard case .onEdge(var traversal, let startOffset) = start, case .onEdge(let target, let endOffset) = end else { return nil }
        var total: Int64 = 0
        var offset = startOffset
        var next = ahead.makeIterator()
        while true {
            guard let edge = world.network.edge(traversal.edge), let length = world.trackGeometry(of: traversal.edge)?.length else { return nil }
            if traversal == target, endOffset >= offset {
                return total + endOffset - offset
            }
            if traversal.edge == target.edge, traversal.direction != target.direction { return nil }
            total += max(0, length - offset)
            let node = traversal.direction == .forward ? edge.to : edge.from
            guard let id = next.next(), let following = world.network.edge(id) else { return nil }
            if following.from == node {
                traversal = TrackTraversal(edge: id, direction: .forward)
            } else if following.to == node {
                traversal = TrackTraversal(edge: id, direction: .backward)
            } else {
                return nil
            }
            offset = 0
        }
    }
}

/// What the status pill says about speed (decision 195): the speed the
/// game is set to, how fast it really runs, and the followed train's speed.
public struct ViewingSpeed: Hashable, Sendable {
    /// From this share of the speed up the game reads as running at it.
    public static let steadyPermille: Int64 = 950
    /// Under this share of the speed the game is falling behind.
    public static let behindPermille: Int64 = 800

    /// The speed the game is set to.
    public let speed: GameSpeed
    /// How fast it really runs, in tenths of times real time, as shown:
    /// the speed itself while it keeps up, otherwise two figures; `nil`
    /// paused or before a reading.
    public let actualTenths: Int64?
    public let isBehind: Bool
    /// The followed train's speed in km/h, or `nil` following none.
    public let trainKilometresPerHour: Int64?

    /// `permille` of `speed` (``GameSpeedMeter/permilleOfSpeed``), shown as
    /// a player reads it.
    public init(speed: GameSpeed, permille: Int64?, trainKilometresPerHour: Int64?) {
        self.speed = speed
        self.trainKilometresPerHour = trainKilometresPerHour
        guard speed != .paused, let permille else {
            actualTenths = nil
            isBehind = false
            return
        }
        let set = speed.tenthsPerTick * 10
        isBehind = permille < Self.behindPermille
        actualTenths = permille >= Self.steadyPermille ? set : Self.twoFigures(set * permille / 1_000)
    }

    init(speed: GameSpeed, actualTenths: Int64?, isBehind: Bool, trainKilometresPerHour: Int64?) {
        self.speed = speed
        self.actualTenths = actualTenths
        self.isBehind = isBehind
        self.trainKilometresPerHour = trainKilometresPerHour
    }

    /// `tenths` kept to its two leading figures (a tenth at least): 5,870
    /// tenths (587×) are 590×, 45 tenths 4.5×.
    static func twoFigures(_ tenths: Int64) -> Int64 {
        var step: Int64 = 1
        while tenths >= step * 100 { step *= 10 }
        return (tenths + step / 2) / step * step
    }

    /// "×600", "×4.5": `tenths` of times real time.
    public static func timesText(_ tenths: Int64) -> String {
        tenths % 10 == 0 ? "×\(tenths / 10)" : "×\(tenths / 10).\(tenths % 10)"
    }

    /// "actual ×600", or falling behind "actual ×290 (falling behind)";
    /// `nil` without a reading.
    public func actualText(in language: DisplayLanguage) -> String? {
        guard let actualTenths else { return nil }
        let times = Self.timesText(actualTenths)
        return isBehind
            ? language.text("actual \(times) (falling behind)", "實際 \(times)（跟不上）")
            : language.text("actual \(times)", "實際 \(times)")
    }

    /// "285 km/h", the followed train's speed, or `nil` following none.
    public var trainSpeedText: String? {
        trainKilometresPerHour.map { "\(Money($0).displayText) km/h" }
    }

    /// What VoiceOver reads for the readout.
    public func accessibilityText(in language: DisplayLanguage) -> String {
        var parts: [String] = []
        if let actualTenths {
            let times = Self.timesText(actualTenths).dropFirst()
            parts.append(isBehind
                ? language.text("The game really runs \(times) times real time, slower than its speed", "遊戲實際以真實時間的 \(times) 倍進行，跟不上設定的速度")
                : language.text("The game runs \(times) times real time", "遊戲以真實時間的 \(times) 倍進行"))
        }
        if let trainKilometresPerHour {
            parts.append(language.text("the train runs at \(trainKilometresPerHour) km/h", "列車時速 \(trainKilometresPerHour) 公里"))
        }
        return parts.joined(separator: language.text(", ", "，"))
    }
}
