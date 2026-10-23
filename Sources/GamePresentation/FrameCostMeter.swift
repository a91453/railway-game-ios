import Foundation

// Decision 328: the flat map's frame readout. A player who finds the map
// slow turns it on in Settings, and it shows how many frames a second the
// map draws and what each part of a frame took, so a slow phone tells
// where the time goes (the 3D map shows its CPU and GPU times the same
// way). Off, nothing is timed.

/// A part of the flat map's work timed for the readout (decision 328).
public enum FrameCostPart: String, CaseIterable, Hashable, Sendable {
    /// GameCore's tick and the traffic reading, off the main thread.
    case step
    /// What the session does on the main thread after a tick.
    case afterStep
    /// The ground, the town and the population layer.
    case ground
    /// Decision 377: the railway canvas, the track and the lines over it
    /// (decision 371), and the track-drawing loupe.
    case railway
    /// Decision 377: the canvas over it, traffic control, the buildings
    /// and the stations (decision 371).
    case trafficAndStations
    /// The player's trains.
    case trains
    /// Decision 304's real trains.
    case realTrains
    /// The stations' names and waiting counts.
    case labels
    /// Decision 182's rain and lightning.
    case weather
    /// Decision 330: the world a tick replaced, let go on the main thread.
    case release
    // Decision 330: the pieces of ``afterStep``.
    /// Putting the step's world in place, logging it, clearing undo.
    case stepWorld
    /// The followed train: ending a follow, its speedometer.
    case stepFollow
    /// The platforms the trains stand at (``PlatformUse``).
    case stepPlatforms
    /// The arrival sound and the music.
    case stepSound
    /// The income, the shortfall and the day's loss.
    case stepIncome
    /// Fares over the stations, trips stamped, goals met, towns grown.
    case stepActions
    /// The secretary room's news.
    case stepNews
    /// The host's work at midnight (the achievements).
    case stepMidnight
    /// The night skip going on, ending or starting.
    case stepNightSkip

    /// The part this one is a piece of, when it is one: its time is in
    /// the parent's too.
    public var parent: FrameCostPart? {
        switch self {
        case .stepWorld, .stepFollow, .stepPlatforms, .stepSound, .stepIncome, .stepActions, .stepNews, .stepMidnight, .stepNightSkip:
            .afterStep
        default:
            nil
        }
    }

    /// Whether it runs on the main thread, between two frames: all but
    /// the tick.
    var isOnMainThread: Bool { self != .step }

    /// Its short name in the readout.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .step: language.text("tick", "推進")
        case .afterStep: language.text("after tick", "推進後")
        case .ground: language.text("ground", "地面")
        case .railway: language.text("track and lines", "軌道與路線")
        case .trafficAndStations: language.text("traffic and stations", "交通與車站")
        case .trains: language.text("trains", "列車")
        case .realTrains: language.text("real trains", "真實列車")
        case .labels: language.text("names", "站名")
        case .weather: language.text("weather", "天氣")
        case .release: language.text("clean-up", "清理")
        case .stepWorld: language.text("update", "更新")
        case .stepFollow: language.text("followed train", "跟隨列車")
        case .stepPlatforms: language.text("platforms", "月台")
        case .stepSound: language.text("sound", "音效")
        case .stepIncome: language.text("income", "收入")
        case .stepActions: language.text("map pulses", "地圖提示")
        case .stepNews: language.text("news", "新聞")
        case .stepMidnight: language.text("midnight", "午夜")
        case .stepNightSkip: language.text("night skip", "夜間快轉")
        }
    }
}

/// Decision 377: what changed when a map canvas was drawn again, the first
/// of its inputs found different, counted beside its time in the readout.
public enum MapRedrawReason: String, CaseIterable, Hashable, Sendable {
    case camera
    case layers
    case palette
    /// The track, the stations or the map's bounds.
    case railway
    /// The network tool's preview.
    case networkTool
    case expansion
    /// The edges' drawings, worked out again after the track changed.
    case edges
    case lines
    case routePreview
    /// The passenger load layer's strokes.
    case flow
    case lineCodes
    case journey

    /// Its short name in the readout.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .camera: language.text("view moved", "畫面移動")
        case .layers: language.text("layers", "圖層")
        case .palette: language.text("colours", "配色")
        case .railway: language.text("track or stations", "軌道或車站")
        case .networkTool: language.text("building", "建造")
        case .expansion: language.text("map area", "地圖範圍")
        case .edges: language.text("track shapes", "軌道形狀")
        case .lines: language.text("lines", "路線")
        case .routePreview: language.text("route shown", "路線預覽")
        case .flow: language.text("passenger flow", "客流")
        case .lineCodes: language.text("line codes", "路線代號")
        case .journey: language.text("journeys", "旅程")
        }
    }
}

/// What the flat map spent in one window of about a second (decision 328).
public struct FrameCostReading: Hashable, Sendable {
    /// One part's time in the window.
    public struct Part: Hashable, Sendable {
        public let part: FrameCostPart
        /// How many times it ran.
        public let count: Int
        /// Its time in all, in milliseconds a second.
        public let millisecondsPerSecond: Double
        /// The longest one, in milliseconds.
        public let longestMilliseconds: Double
        /// Decision 377: why it was drawn again, and how many times.
        public let reasons: [MapRedrawReason: Int]

        public init(part: FrameCostPart, count: Int, millisecondsPerSecond: Double, longestMilliseconds: Double, reasons: [MapRedrawReason: Int] = [:]) {
            self.part = part
            self.count = count
            self.millisecondsPerSecond = millisecondsPerSecond
            self.longestMilliseconds = longestMilliseconds
            self.reasons = reasons
        }
    }

    public let framesPerSecond: Double
    /// The longest time between two frames, in milliseconds: the main
    /// thread busy for that long.
    public let longestGapMilliseconds: Double
    /// Decision 330: of the longest frame, the time no part on the main
    /// thread was timed in (SwiftUI working the views out again, and
    /// whatever else is not timed), in milliseconds.
    public let longestGapUntimedMilliseconds: Double
    /// The parts that ran, in ``FrameCostPart``'s order.
    public let parts: [Part]

    public init(framesPerSecond: Double, longestGapMilliseconds: Double, longestGapUntimedMilliseconds: Double = 0, parts: [Part]) {
        self.framesPerSecond = framesPerSecond
        self.longestGapMilliseconds = longestGapMilliseconds
        self.longestGapUntimedMilliseconds = longestGapUntimedMilliseconds
        self.parts = parts
    }

    /// The readout's lines under the frame rate: the longest frame and
    /// what of it was not timed, then each part's time a second and its
    /// longest, the costliest first, each with its pieces under it.
    public func lines(in language: DisplayLanguage) -> [String] {
        let gap = String(format: "%.0f ms", longestGapMilliseconds)
        let other = String(format: "%.0f ms", longestGapUntimedMilliseconds)
        func costliestFirst(_ parts: [Part]) -> [Part] {
            parts.sorted { ($0.millisecondsPerSecond, $1.part.rawValue) > ($1.millisecondsPerSecond, $0.part.rawValue) }
        }
        func line(_ part: Part, prefix: String = "") -> String {
            let reasons = MapRedrawReason.allCases.compactMap { reason in
                part.reasons[reason].map { " · \(reason.title(in: language)) ×\($0)" }
            }
            return prefix + String(
                format: "%@ %.1f ms/s · ×%d · max %.1f ms", part.part.title(in: language), part.millisecondsPerSecond, part.count, part.longestMilliseconds
            ) + reasons.joined()
        }
        return [language.text("longest frame \(gap) · other \(other)", "最長一幀 \(gap) · 其他 \(other)")]
            + costliestFirst(parts.filter { $0.part.parent == nil }).flatMap { part in
                [line(part)] + costliestFirst(parts.filter { $0.part.parent == part.part }).map { line($0, prefix: "  · ") }
            }
    }
}

/// Times the flat map's parts while the readout is on (decision 328). The
/// game loop times its tick off the main thread and the map its canvases
/// on it, so it takes a lock.
public final class FrameCostMeter: @unchecked Sendable {
    /// The one the session and the map share.
    public static let shared = FrameCostMeter()

    private struct Tally {
        var count = 0
        var total = 0.0
        var longest = 0.0
    }

    private let lock = NSLock()
    private var on = false
    private var tallies: [FrameCostPart: Tally] = [:]
    /// Decision 377: why each part was drawn again in this window.
    private var reasons: [FrameCostPart: [MapRedrawReason: Int]] = [:]
    private var frames = 0
    private var windowStart: Double?
    private var lastFrame: Double?
    private var longestGap = 0.0
    /// The main thread's timed time since the last frame, and of the
    /// longest gap, what was not timed (decision 330).
    private var timedSinceFrame = 0.0
    private var longestGapUntimed = 0.0

    public init() {}

    /// Whether the parts are timed; turning it on or off starts afresh.
    public var isOn: Bool {
        get { lock.withLock { on } }
        set {
            lock.withLock {
                on = newValue
                tallies = [:]
                reasons = [:]
                frames = 0
                windowStart = nil
                lastFrame = nil
                longestGap = 0
                timedSinceFrame = 0
                longestGapUntimed = 0
            }
        }
    }

    /// Counts `milliseconds` of `part`, while on.
    public func record(_ part: FrameCostPart, milliseconds: Double) {
        lock.withLock {
            guard on else { return }
            var tally = tallies[part] ?? Tally()
            tally.count += 1
            tally.total += milliseconds
            tally.longest = max(tally.longest, milliseconds)
            tallies[part] = tally
            if part.isOnMainThread, part.parent == nil { timedSinceFrame += milliseconds }
        }
    }

    /// Decision 377: counts that `part` is drawn again because of
    /// `reason`, while on.
    public func noteRedraw(_ part: FrameCostPart, because reason: MapRedrawReason) {
        lock.withLock {
            guard on else { return }
            reasons[part, default: [:]][reason, default: 0] += 1
        }
    }

    /// Does `work`, timed as `part` while on.
    public func measure<T>(_ part: FrameCostPart, _ work: () throws -> T) rethrows -> T {
        guard isOn else { return try work() }
        let start = ContinuousClock.now
        let result = try work()
        record(part, since: start)
        return result
    }

    /// Counts the time since `start` as `part`, while on: for work that
    /// cannot be put in a closure (a value let go).
    public func record(_ part: FrameCostPart, since start: ContinuousClock.Instant) {
        record(part, milliseconds: Self.milliseconds(ContinuousClock.now - start))
    }

    /// A frame drawn at `time` seconds (a display link's timestamp): once
    /// a second has passed since the window began, what the window spent,
    /// and a new window begins.
    public func frame(at time: Double) -> FrameCostReading? {
        lock.withLock {
            guard on else { return nil }
            if let lastFrame, time - lastFrame > longestGap {
                longestGap = time - lastFrame
                longestGapUntimed = max(0, longestGap * 1_000 - timedSinceFrame)
            }
            lastFrame = time
            timedSinceFrame = 0
            guard let start = windowStart else {
                windowStart = time
                return nil
            }
            frames += 1
            let seconds = time - start
            guard seconds >= 1 else { return nil }
            let reading = FrameCostReading(
                framesPerSecond: Double(frames) / seconds,
                longestGapMilliseconds: longestGap * 1_000,
                longestGapUntimedMilliseconds: longestGapUntimed,
                parts: FrameCostPart.allCases.compactMap { part in
                    tallies[part].map {
                        FrameCostReading.Part(
                            part: part, count: $0.count, millisecondsPerSecond: $0.total / seconds, longestMilliseconds: $0.longest,
                            reasons: reasons[part] ?? [:]
                        )
                    }
                }
            )
            tallies = [:]
            reasons = [:]
            frames = 0
            windowStart = time
            longestGap = 0
            longestGapUntimed = 0
            return reading
        }
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
}
