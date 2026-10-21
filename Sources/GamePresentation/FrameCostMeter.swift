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
    /// The track, the stations and traffic control.
    case track
    /// The player's trains.
    case trains
    /// Decision 304's real trains.
    case realTrains
    /// The stations' names and waiting counts.
    case labels
    /// Decision 182's rain and lightning.
    case weather

    /// Its short name in the readout.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .step: language.text("tick", "推進")
        case .afterStep: language.text("after tick", "推進後")
        case .ground: language.text("ground", "地面")
        case .track: language.text("track", "軌道")
        case .trains: language.text("trains", "列車")
        case .realTrains: language.text("real trains", "真實列車")
        case .labels: language.text("names", "站名")
        case .weather: language.text("weather", "天氣")
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
    }

    public let framesPerSecond: Double
    /// The longest time between two frames, in milliseconds: the main
    /// thread busy for that long.
    public let longestGapMilliseconds: Double
    /// The parts that ran, in ``FrameCostPart``'s order.
    public let parts: [Part]

    /// The readout's lines under the frame rate: each part's time a
    /// second and its longest, the costliest first.
    public func lines(in language: DisplayLanguage) -> [String] {
        let gap = String(format: "%.0f ms", longestGapMilliseconds)
        return [language.text("longest frame \(gap)", "最長一幀 \(gap)")]
            + parts.sorted { ($0.millisecondsPerSecond, $1.part.rawValue) > ($1.millisecondsPerSecond, $0.part.rawValue) }.map {
                String(format: "%@ %.1f ms/s · ×%d · max %.1f ms", $0.part.title(in: language), $0.millisecondsPerSecond, $0.count, $0.longestMilliseconds)
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
    private var frames = 0
    private var windowStart: Double?
    private var lastFrame: Double?
    private var longestGap = 0.0

    public init() {}

    /// Whether the parts are timed; turning it on or off starts afresh.
    public var isOn: Bool {
        get { lock.withLock { on } }
        set {
            lock.withLock {
                on = newValue
                tallies = [:]
                frames = 0
                windowStart = nil
                lastFrame = nil
                longestGap = 0
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
        }
    }

    /// Does `work`, timed as `part` while on.
    public func measure<T>(_ part: FrameCostPart, _ work: () throws -> T) rethrows -> T {
        guard isOn else { return try work() }
        let start = ContinuousClock.now
        let result = try work()
        record(part, milliseconds: Self.milliseconds(ContinuousClock.now - start))
        return result
    }

    /// A frame drawn at `time` seconds (a display link's timestamp): once
    /// a second has passed since the window began, what the window spent,
    /// and a new window begins.
    public func frame(at time: Double) -> FrameCostReading? {
        lock.withLock {
            guard on else { return nil }
            if let lastFrame { longestGap = max(longestGap, time - lastFrame) }
            lastFrame = time
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
                parts: FrameCostPart.allCases.compactMap { part in
                    tallies[part].map {
                        FrameCostReading.Part(part: part, count: $0.count, millisecondsPerSecond: $0.total / seconds, longestMilliseconds: $0.longest)
                    }
                }
            )
            tallies = [:]
            frames = 0
            windowStart = time
            longestGap = 0
            return reading
        }
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
}
