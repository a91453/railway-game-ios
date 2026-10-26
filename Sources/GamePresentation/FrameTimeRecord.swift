import Foundation
import GameCore

// Decision 421 (V1 of docs/research/FRAME_TIME_AND_ENGINE_SPIKE_PLAN_2026-10-26.md):
// what the screen's pace was on this device, kept small on the device for
// a problem report. The 3D map hands over when each of its frames reached
// the screen (the drawable's `presentedTime`); the flat map, when its main
// thread woke for the next frame (a display link's beat). The app only
// hands samples to ``FrameTimeMeter``; the statistics and the report's
// text are worked out here, where Linux tests them.
//
// The flat map's beat is not the time a frame reached the screen: it shows
// whether the main thread woke in time, not SwiftUI's and Core Animation's
// commit after it or the system putting it on screen. The report calls it
// "the 2D beat", never a frame time or a presentation time (the owner,
// 2026-10-26).
//
// The references have none to port (gap): their pages show an averaged
// frames-a-second counter (`commuter_journey` `HUD.js`, `OpenWorld`
// `hud.js`) and decision 418's long-task count.

/// Which screen a stretch of frames was on.
public enum FrameTimeScreen: String, Codable, CaseIterable, Hashable, Sendable {
    /// The flat map: its main thread's beat is what is timed.
    case map2D
    /// The 3D map, its camera free.
    case map3D
    /// The 3D map following a train.
    case follow3D

    /// Whether its intervals are when frames reached the screen (3D), not
    /// the main thread's beat (2D).
    public var isPresented: Bool { self != .map2D }

    func title(in language: DisplayLanguage) -> String {
        switch self {
        case .map2D: language.text("2D beat (the main thread waking for a frame, not when it reached the screen)",
                                   "2D 節拍（主執行緒醒來準備下一格的間隔，不是上螢幕的時間）")
        case .map3D: language.text("3D frames on screen", "3D 上螢幕間隔")
        case .follow3D: language.text("3D frames on screen, following a train", "3D 上螢幕間隔，跟車")
        }
    }
}

/// What the game was doing while frames were timed: a new stretch begins
/// when the screen or the speed changes (``key``); the rest is the latest.
public struct FrameTimeContext: Codable, Hashable, Sendable {
    public var screen: FrameTimeScreen
    /// The game's speed (``GameSpeed``'s raw value), or `nil` with no game.
    public var speed: String?
    public var stations: Int
    public var lines: Int
    /// Decision 417: the 3D look and the rung it climbed to
    /// (``Map3DLoadGovernor/report(_:)``), or `nil`.
    public var map3D: String?

    public init(screen: FrameTimeScreen, speed: String? = nil, stations: Int = 0, lines: Int = 0, map3D: String? = nil) {
        self.screen = screen
        self.speed = speed
        self.stations = stations
        self.lines = lines
        self.map3D = map3D
    }

    /// What starts a new stretch when it changes.
    var key: String { "\(screen.rawValue)|\(speed ?? "")" }

    func text(in language: DisplayLanguage) -> String {
        var parts: [String] = []
        if let speed { parts.append(GameSpeed(rawValue: speed).map { $0.label(in: language) } ?? speed) }
        parts.append(language.text("\(stations) stations, \(lines) lines", "\(stations) 站、\(lines) 線"))
        if screen.isPresented, let map3D { parts.append(language.text("look \(map3D)", "畫質 \(map3D)")) }
        return parts.joined(separator: " · ")
    }
}

/// How many milliseconds a sample of a stretch took, kept as counts in
/// fixed steps so a frame adds one and makes nothing new: to 0.1 ms under
/// 100 ms, to 1 ms under 2 s, and longer ones together (their longest
/// kept). Percentiles are by nearest rank: the smallest value at least
/// that share of the samples is no longer than.
public struct FrameTimeDistribution: Sendable {
    /// 0.0–99.9 ms by tenths, 100–1999 ms by whole ones, and one for the rest.
    static let fineSteps = 1_000
    static let coarseSteps = 1_900
    static let size = fineSteps + coarseSteps + 1

    private var counts: [UInt32]
    public private(set) var count = 0
    /// The longest sample, in milliseconds.
    public private(set) var longest = 0.0

    public init() {
        counts = Array(repeating: 0, count: Self.size)
    }

    static func step(_ milliseconds: Double) -> Int {
        let tenths = (milliseconds * 10).rounded()
        if tenths < Double(fineSteps) { return Int(tenths) }
        let whole = milliseconds.rounded()
        if whole < 2_000 { return fineSteps + Int(whole) - 100 }
        return size - 1
    }

    func value(ofStep step: Int) -> Double {
        if step < Self.fineSteps { return Double(step) / 10 }
        if step < Self.size - 1 { return Double(step - Self.fineSteps + 100) }
        return longest
    }

    /// Counts a sample; a negative one as 0, one that is not a number not.
    public mutating func add(_ milliseconds: Double) {
        guard !milliseconds.isNaN else { return }
        let ms = max(0, milliseconds)
        counts[Self.step(ms)] &+= 1
        count += 1
        longest = max(longest, ms)
    }

    /// The `share` (0–1) percentile by nearest rank, or `nil` with no
    /// sample.
    public func percentile(_ share: Double) -> Double? {
        guard count > 0 else { return nil }
        let rank = max(1, Int((share * Double(count)).rounded(.up)))
        var seen = 0
        for step in counts.indices {
            seen += Int(counts[step])
            if seen >= rank { return value(ofStep: step) }
        }
        return longest
    }

    /// The median, 95th and 99th percentiles and the longest, or `nil`
    /// with no sample.
    public var summary: FrameTimeStats? {
        guard let median = percentile(0.5), let p95 = percentile(0.95), let p99 = percentile(0.99) else { return nil }
        return FrameTimeStats(count: count, median: median, p95: p95, p99: p99, longest: FrameTimeStats.tenth(longest))
    }
}

/// A distribution's summary, in milliseconds.
public struct FrameTimeStats: Codable, Hashable, Sendable {
    public let count: Int
    public let median: Double
    public let p95: Double
    public let p99: Double
    public let longest: Double

    public init(count: Int, median: Double, p95: Double, p99: Double, longest: Double) {
        self.count = count
        self.median = median
        self.p95 = p95
        self.p99 = p99
        self.longest = longest
    }

    static func tenth(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}

/// How many intervals were stalls, by length: 50 up to 100 ms, 100 up to
/// 250 ms, and 250 ms or more, the severe ones (decision 418's freezes
/// start there).
public struct FrameTimeStalls: Codable, Hashable, Sendable {
    public static let shortest = 50.0
    public static let long = 100.0
    public static let severe = 250.0

    public var short = 0
    public var long = 0
    public var severe = 0

    public init(short: Int = 0, long: Int = 0, severe: Int = 0) {
        self.short = short
        self.long = long
        self.severe = severe
    }

    /// Counts an interval of `milliseconds`; whether it was a stall.
    @discardableResult
    mutating func add(_ milliseconds: Double) -> Bool {
        if milliseconds >= Self.severe {
            severe += 1
        } else if milliseconds >= Self.long {
            long += 1
        } else if milliseconds >= Self.shortest {
            short += 1
        } else {
            return false
        }
        return true
    }

    public var total: Int { short + long + severe }
}

/// The longest stall of a stretch: how long, how far into the stretch,
/// and, on the flat map, what the main thread was timed doing in it
/// (decision 328's parts, the longest first, and the rest untimed).
public struct FrameTimeStall: Codable, Hashable, Sendable {
    public struct Part: Codable, Hashable, Sendable {
        /// ``FrameCostPart``'s raw value, or ``untimed``.
        public let part: String
        public let milliseconds: Double

        public static let untimed = "untimed"

        public init(part: String, milliseconds: Double) {
            self.part = part
            self.milliseconds = milliseconds
        }

        func title(in language: DisplayLanguage) -> String {
            if part == Self.untimed { return language.text("other", "其他") }
            return FrameCostPart(rawValue: part)?.title(in: language) ?? part
        }
    }

    public let milliseconds: Double
    /// Seconds from the stretch's start.
    public let at: Double
    public let parts: [Part]

    public init(milliseconds: Double, at: Double, parts: [Part]) {
        self.milliseconds = milliseconds
        self.at = at
        self.parts = parts
    }
}

/// One stretch of frames on one screen in one context, summed up.
public struct FrameTimeSegment: Codable, Hashable, Sendable {
    public var context: FrameTimeContext
    /// When it began (seconds since 1970) and how long it ran, in seconds.
    public var began: Double
    public var seconds: Double
    /// The intervals between frames (3D: on screen; 2D: the beat).
    public var intervals: FrameTimeStats?
    /// 3D frames the system says never reached the screen
    /// (`presentedTime` 0); not among the intervals.
    public var notPresented: Int
    public var stalls: FrameTimeStalls
    public var longest: FrameTimeStall?
    /// The 3D map's CPU and GPU time a frame.
    public var cpu: FrameTimeStats?
    public var gpu: FrameTimeStats?
    /// The 3D map's most triangles, draw calls and scene chunks in view in
    /// a frame.
    public var triangles: Int
    public var drawCalls: Int
    public var chunks: Int
    /// The app's memory: the most it used (`phys_footprint`) and the least
    /// left to it (`os_proc_available_memory`), in megabytes, and how many
    /// low-memory warnings came.
    public var memoryPeak: Int?
    public var memoryLeast: Int?
    public var memoryWarnings: Int
    /// The phone's heat (`ProcessInfo.ThermalState`'s names): the first and
    /// each change, at most ``FrameTimeMeter/mostThermalStates``.
    public var thermal: [String]

    public init(
        context: FrameTimeContext, began: Double, seconds: Double, intervals: FrameTimeStats?, notPresented: Int = 0,
        stalls: FrameTimeStalls = FrameTimeStalls(), longest: FrameTimeStall? = nil, cpu: FrameTimeStats? = nil, gpu: FrameTimeStats? = nil,
        triangles: Int = 0, drawCalls: Int = 0, chunks: Int = 0, memoryPeak: Int? = nil, memoryLeast: Int? = nil, memoryWarnings: Int = 0,
        thermal: [String] = []
    ) {
        self.context = context
        self.began = began
        self.seconds = seconds
        self.intervals = intervals
        self.notPresented = notPresented
        self.stalls = stalls
        self.longest = longest
        self.cpu = cpu
        self.gpu = gpu
        self.triangles = triangles
        self.drawCalls = drawCalls
        self.chunks = chunks
        self.memoryPeak = memoryPeak
        self.memoryLeast = memoryLeast
        self.memoryWarnings = memoryWarnings
        self.thermal = thermal
    }

    /// The report's lines for it.
    public func lines(in language: DisplayLanguage) -> [String] {
        func ms(_ value: Double) -> String { String(format: "%.1f ms", value) }
        var lines = [
            "\(context.screen.title(in: language)) · \(context.text(in: language)) · "
                + language.text("from \(DeviceDiagnostics.timeText(began)), \(Int(seconds.rounded())) s",
                                "\(DeviceDiagnostics.timeText(began)) 起 \(Int(seconds.rounded())) 秒"),
        ]
        if let intervals {
            var counted = language.text("\(intervals.count) intervals", "\(intervals.count) 個間隔")
            if context.screen.isPresented {
                counted += language.text(", \(notPresented) frames not on screen", "，沒上螢幕 \(notPresented) 格")
            }
            lines.append("  " + counted + language.text(
                "; median \(ms(intervals.median)), p95 \(ms(intervals.p95)), p99 \(ms(intervals.p99))",
                "；中位數 \(ms(intervals.median))、p95 \(ms(intervals.p95))、p99 \(ms(intervals.p99))"
            ))
        } else {
            lines.append("  " + language.text("no intervals", "沒有間隔"))
        }
        var stallLine = language.text(
            "stalls 50–100 ms ×\(stalls.short), 100–250 ms ×\(stalls.long), 250 ms or more (severe) ×\(stalls.severe)",
            "停頓 50–100 ms ×\(stalls.short)、100–250 ms ×\(stalls.long)、250 ms 以上（嚴重）×\(stalls.severe)"
        )
        if let longest {
            stallLine += language.text("; longest \(ms(longest.milliseconds)) at \(String(format: "%.1f", longest.at)) s",
                                       "；最長 \(ms(longest.milliseconds))（第 \(String(format: "%.1f", longest.at)) 秒）")
            if !longest.parts.isEmpty {
                stallLine += language.text(": ", "：") + longest.parts.map { "\($0.title(in: language)) \(ms($0.milliseconds))" }
                    .joined(separator: language.text(", ", "、"))
            }
        }
        lines.append("  " + stallLine)
        if context.screen.isPresented {
            var work: [String] = []
            if let cpu { work.append("CPU \(ms(cpu.median)) / p95 \(ms(cpu.p95))") }
            if let gpu { work.append("GPU \(ms(gpu.median)) / p95 \(ms(gpu.p95))") }
            work.append(language.text("most \(triangles) triangles, \(drawCalls) draw calls, \(chunks) chunks",
                                      "最多 \(triangles) 三角形、\(drawCalls) draw call、\(chunks) 場景塊"))
            lines.append("  " + work.joined(separator: " · "))
        }
        var memory: [String] = []
        if let memoryPeak { memory.append(language.text("memory up to \(memoryPeak) MB", "記憶體最高 \(memoryPeak) MB")) }
        if let memoryLeast { memory.append(language.text("least left \(memoryLeast) MB", "最少剩 \(memoryLeast) MB")) }
        memory.append(language.text("warnings \(memoryWarnings)", "警告 \(memoryWarnings) 次"))
        if !thermal.isEmpty {
            memory.append(language.text("heat ", "溫度 ") + thermal.map { Self.thermalTitle($0, in: language) }.joined(separator: "→"))
        }
        lines.append("  " + memory.joined(separator: " · "))
        return lines
    }

    static func thermalTitle(_ state: String, in language: DisplayLanguage) -> String {
        switch state {
        case "nominal": language.text("normal", "正常")
        case "fair": language.text("warm", "微溫")
        case "serious": language.text("hot", "偏高")
        case "critical": language.text("critical", "過熱")
        default: state
        }
    }
}

/// The stretches kept on the device (decision 421), the newest first,
/// within a count and a size: the oldest go first, as decision 418's
/// ``DeviceDiagnostics`` keeps its events.
public struct FrameTimeLog: Codable, Hashable, Sendable {
    /// The file the app keeps it in, beside decision 418's.
    public static let fileName = "frame-times.json"
    public static let mostSegments = 24
    public static let mostBytes = 64 * 1024
    /// A report shows this many, the newest.
    public static let shownSegments = 6

    public private(set) var segments: [FrameTimeSegment] = []

    public init() {}

    /// Keeps `segment` as the newest, dropping the oldest past the count
    /// or the size.
    public mutating func add(_ segment: FrameTimeSegment) {
        segments.insert(segment, at: 0)
        if segments.count > Self.mostSegments { segments.removeLast(segments.count - Self.mostSegments) }
        while segments.count > 1, let size = try? encoded().count, size > Self.mostBytes {
            segments.removeLast()
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// What `data` holds, or an empty log when it holds nothing this reads.
    public static func decoded(_ data: Data) -> FrameTimeLog {
        (try? JSONDecoder().decode(FrameTimeLog.self, from: data)) ?? FrameTimeLog()
    }

    /// The problem report's part (``shownSegments``, the newest, and how
    /// many more and their longest stall), or `nil` with nothing kept;
    /// `going` is the stretch still running, shown first and not kept.
    public func reportText(in language: DisplayLanguage, going: FrameTimeSegment? = nil) -> String? {
        let segments = (going.map { [$0] } ?? []) + segments
        guard !segments.isEmpty else { return nil }
        var lines = [language.text("The screen's pace on this device lately:", "這台裝置最近的畫面節奏：")]
        for segment in segments.prefix(Self.shownSegments) {
            lines += segment.lines(in: language)
        }
        let older = segments.dropFirst(Self.shownSegments)
        if !older.isEmpty {
            let severe = older.reduce(0) { $0 + $1.stalls.severe }
            let longest = older.compactMap { $0.longest?.milliseconds }.max() ?? 0
            lines.append(language.text(
                "\(older.count) earlier: \(severe) severe stalls, the longest \(String(format: "%.1f ms", longest)).",
                "更早 \(older.count) 段：嚴重停頓 \(severe) 次，最長 \(String(format: "%.1f ms", longest))。"
            ))
        }
        return lines.joined(separator: "\n")
    }
}

/// Takes the samples of the stretch being timed and sums it up when it
/// ends (decision 421). Each sample adds to fixed counts, under a lock:
/// the 3D map's GPU and screen times come on other threads. Nothing is
/// made for a frame but a stall longer than any before it in the stretch.
public final class FrameTimeMeter: @unchecked Sendable {
    /// A stretch ends after this many seconds, and a new one begins.
    public static let longestSegment = 300.0
    /// A stretch with fewer intervals than this is not kept.
    public static let fewestIntervals = 10
    /// The parts of the longest stall kept, the longest first.
    public static let shownParts = 3
    public static let mostThermalStates = 6

    private struct Tally {
        var context: FrameTimeContext
        var start: Double
        var began: Double
        var intervals = FrameTimeDistribution()
        var cpu = FrameTimeDistribution()
        var gpu = FrameTimeDistribution()
        var last: Double?
        var lastTime: Double
        var notPresented = 0
        var stalls = FrameTimeStalls()
        var longest: FrameTimeStall?
        var triangles = 0
        var drawCalls = 0
        var chunks = 0
        var memoryPeak: Int?
        var memoryLeast: Int?
        var memoryWarnings = 0
        var thermal: [String] = []
    }

    private let lock = NSLock()
    private var tally: Tally?
    /// The flat map's parts timed for the longest stall, when given.
    private let costs: FrameCostMeter?

    public init(costs: FrameCostMeter? = nil) {
        self.costs = costs
    }

    /// The stretch being timed, if any.
    public var context: FrameTimeContext? { lock.withLock { tally?.context } }

    /// Begins a stretch in `context` at `time` (seconds on the frames'
    /// clock) and `wall` (seconds since 1970), ending the one before.
    @discardableResult
    public func begin(_ context: FrameTimeContext, at time: Double, wall: Double) -> FrameTimeSegment? {
        lock.withLock {
            let ended = endLocked(at: time)
            tally = Tally(context: context, start: time, began: wall, lastTime: time)
            costs?.startFrame()
            return ended
        }
    }

    /// Ends the stretch at `time`: its summary, or `nil` when there was
    /// none or it had fewer than ``fewestIntervals`` intervals.
    @discardableResult
    public func end(at time: Double) -> FrameTimeSegment? {
        lock.withLock { endLocked(at: time) }
    }

    /// The stretch so far, summed up as if it ended at `time`, going on:
    /// for a report written while it runs.
    public func current(at time: Double) -> FrameTimeSegment? {
        lock.withLock { tally.flatMap { Self.summary(of: $0, at: time) } }
    }

    /// Once a second or so: the stretch ended and a new one begun when the
    /// screen or speed of `context` differs or the stretch has run
    /// ``longestSegment``; else the rest of `context` is taken as the
    /// latest. With no stretch, one begins.
    @discardableResult
    public func update(_ context: FrameTimeContext, at time: Double, wall: Double) -> FrameTimeSegment? {
        lock.withLock {
            if var current = tally, current.context.key == context.key, time - current.start < Self.longestSegment {
                current.context = context
                tally = current
                return nil
            }
            let ended = endLocked(at: time)
            tally = Tally(context: context, start: time, began: wall, lastTime: time)
            costs?.startFrame()
            return ended
        }
    }

    /// A frame at `time` seconds: on screen (3D, `presentedTime`) or the
    /// main thread's beat (2D, the display link's timestamp). A time of 0
    /// is a frame that never reached the screen. Whether its interval was
    /// a stall.
    @discardableResult
    public func frame(at time: Double) -> Bool {
        lock.withLock {
            // Changed where it is, as `drew` and `gpu` do: a copy would
            // copy the interval counts each frame (review J, J2).
            guard tally != nil else { return false }
            guard time > 0 else {
                tally!.notPresented += 1
                return false
            }
            defer {
                if tally!.context.screen == .map2D { costs?.startFrame() }
            }
            guard let last = tally!.last else {
                tally!.last = time
                tally!.lastTime = time
                return false
            }
            guard time > last else { return false }
            // To a microsecond: the clocks' sums are not exact.
            let milliseconds = ((time - last) * 1_000_000).rounded() / 1_000
            tally!.last = time
            tally!.lastTime = time
            tally!.intervals.add(milliseconds)
            guard tally!.stalls.add(milliseconds) else { return false }
            if milliseconds > tally!.longest?.milliseconds ?? 0 {
                let parts = tally!.context.screen == .map2D ? (costs?.frameParts(over: milliseconds, top: Self.shownParts) ?? []) : []
                tally!.longest = FrameTimeStall(
                    milliseconds: FrameTimeStats.tenth(milliseconds), at: FrameTimeStats.tenth(time - tally!.start), parts: parts
                )
            }
            return true
        }
    }

    /// The 3D map's CPU time for a frame and what it drew.
    public func drew(cpuMilliseconds: Double, triangles: Int, drawCalls: Int, chunks: Int) {
        lock.withLock {
            guard tally != nil else { return }
            tally!.cpu.add(cpuMilliseconds)
            tally!.triangles = max(tally!.triangles, triangles)
            tally!.drawCalls = max(tally!.drawCalls, drawCalls)
            tally!.chunks = max(tally!.chunks, chunks)
        }
    }

    /// The GPU's time for a 3D frame.
    public func gpu(milliseconds: Double) {
        lock.withLock {
            guard tally != nil else { return }
            tally!.gpu.add(milliseconds)
        }
    }

    /// The app's memory now, in bytes: what it uses and what is left to it.
    public func memory(footprint: UInt64?, available: UInt64?) {
        lock.withLock {
            guard tally != nil else { return }
            if let footprint {
                let mb = Int(footprint / 1_048_576)
                tally!.memoryPeak = max(tally!.memoryPeak ?? 0, mb)
            }
            if let available, available > 0 {
                let mb = Int(available / 1_048_576)
                tally!.memoryLeast = min(tally!.memoryLeast ?? .max, mb)
            }
        }
    }

    public func memoryWarning() {
        lock.withLock {
            guard tally != nil else { return }
            tally!.memoryWarnings += 1
        }
    }

    /// The phone's heat (`nominal`, `fair`, `serious`, `critical`): kept
    /// when it differs from the last.
    public func thermal(_ state: String) {
        lock.withLock {
            guard tally != nil, tally!.thermal.last != state, tally!.thermal.count < Self.mostThermalStates else { return }
            tally!.thermal.append(state)
        }
    }

    private func endLocked(at time: Double) -> FrameTimeSegment? {
        guard let ended = tally else { return nil }
        tally = nil
        return Self.summary(of: ended, at: time)
    }

    private static func summary(of ended: Tally, at time: Double) -> FrameTimeSegment? {
        guard ended.intervals.count >= Self.fewestIntervals else { return nil }
        let isPresented = ended.context.screen.isPresented
        return FrameTimeSegment(
            context: ended.context, began: ended.began, seconds: FrameTimeStats.tenth(max(time, ended.lastTime) - ended.start),
            intervals: ended.intervals.summary, notPresented: ended.notPresented, stalls: ended.stalls, longest: ended.longest,
            cpu: isPresented ? ended.cpu.summary : nil, gpu: isPresented ? ended.gpu.summary : nil,
            triangles: ended.triangles, drawCalls: ended.drawCalls, chunks: ended.chunks,
            memoryPeak: ended.memoryPeak, memoryLeast: ended.memoryLeast, memoryWarnings: ended.memoryWarnings, thermal: ended.thermal
        )
    }
}
