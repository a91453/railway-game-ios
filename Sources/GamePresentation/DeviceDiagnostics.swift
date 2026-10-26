import Foundation

/// What the system recorded about this app on this device (decision 418):
/// each time the game froze (the main thread stuck for about 250 ms or
/// more), closed unexpectedly, used the processor or storage heavily or
/// was slow to start, with the call stack where it was, and, a day at a
/// time, how often the app ended on screen and in the background, and why.
///
/// The app hands it each payload's `jsonRepresentation()` as the system
/// delivers it (``record(diagnostics:)``, ``record(metrics:)``); this
/// keeps only what a problem report needs, the newest few, within a size,
/// and writes it out as the report's text (``reportText(in:)``). It stays
/// in the app's own files on the device: it goes nowhere but in the note
/// the player chooses to send. No save holds it.
///
/// The formats are Apple's (`MXDiagnosticPayload`, `MXMetricPayload`);
/// every field is optional, and one this cannot read is skipped rather
/// than losing the rest. The references have none to port (gap).
public struct DeviceDiagnostics: Codable, Hashable, Sendable {
    /// The file the app keeps it in, in its Application Support folder.
    public static let fileName = "device-diagnostics.json"
    /// At most this many events are kept, the newest.
    public static let mostEvents = 12
    /// At most this many days of exits are kept, the newest.
    public static let mostDays = 3
    /// At most this many frames of each call stack, from the innermost.
    public static let mostFrames = 48
    /// The file stays within this many bytes: the oldest events go first.
    public static let mostBytes = 256 * 1024
    /// A report shows this many events, the newest.
    public static let shownEvents = 5

    /// Newest first; those with no time last, in the order they came.
    public private(set) var events: [Event] = []
    /// Newest first.
    public private(set) var days: [Day] = []

    public init() {}

    /// One thing the system recorded.
    public struct Event: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Sendable {
            /// The main thread was stuck (`hangDiagnostics`).
            case hang
            /// The app ended on an error (`crashDiagnostics`).
            case crash
            /// Too much processor time (`cpuExceptionDiagnostics`).
            case cpu
            /// Too much written to storage (`diskWriteExceptionDiagnostics`).
            case diskWrites
            /// A slow start (`appLaunchDiagnostics`).
            case launch
        }

        public let kind: Kind
        /// When (seconds since 1970), from the payload's end; `nil` when
        /// it gives none this can read.
        public let time: Double?
        /// How long, in seconds: a hang's or a start's.
        public let duration: Double?
        /// What else it says, in its own words: a crash's exception,
        /// signal and reason; the processor time; how much was written; a
        /// duration this could not read.
        public let detail: String?
        /// The app's version and build, and the system, it happened in.
        public let app: String?
        public let system: String?
        /// The stack of the thread it was attributed to, innermost first,
        /// along its most sampled path; at most ``mostFrames``.
        public let frames: [Frame]
        /// How many frames further out than ``mostFrames`` were not kept.
        public let framesLeft: Int

        public init(
            kind: Kind, time: Double?, duration: Double?, detail: String?, app: String?, system: String?, frames: [Frame], framesLeft: Int
        ) {
            self.kind = kind
            self.time = time
            self.duration = duration
            self.detail = detail
            self.app = app
            self.system = system
            self.frames = frames
            self.framesLeft = framesLeft
        }
    }

    /// One frame of a call stack, as the system gives it, unsymbolicated:
    /// the binary, its UUID (which dSYM), the address and the offset into
    /// the binary's text segment (decision 418 says how to read them).
    public struct Frame: Codable, Hashable, Sendable {
        public let binary: String
        public let uuid: String
        public let address: UInt64
        public let offset: UInt64

        public init(binary: String, uuid: String, address: UInt64, offset: UInt64) {
            self.binary = binary
            self.uuid = uuid
            self.address = address
            self.offset = offset
        }
    }

    /// A day of the app's exits and freezes (`MXMetricPayload`, which
    /// covers about 24 hours).
    public struct Day: Codable, Hashable, Sendable {
        /// When it begins and ends (seconds since 1970).
        public let begin: Double?
        public let end: Double?
        /// How many times the app ended on screen and in the background,
        /// by Apple's names for the reasons (``exitReasons``); only those
        /// above zero.
        public let foreground: [String: Int]
        public let background: [String: Int]
        /// The freezes of the day, by length (`histogrammedAppHangTime`).
        public let hangs: [Bucket]

        public init(begin: Double?, end: Double?, foreground: [String: Int], background: [String: Int], hangs: [Bucket]) {
            self.begin = begin
            self.end = end
            self.foreground = foreground
            self.background = background
            self.hangs = hangs
        }
    }

    /// How many freezes were from `start` to `end` long, in the system's
    /// own words ("250 ms").
    public struct Bucket: Codable, Hashable, Sendable {
        public let start: String
        public let end: String
        public let count: Int

        public init(start: String, end: String, count: Int) {
            self.start = start
            self.end = end
            self.count = count
        }
    }

    // MARK: Recording

    /// Adds what an `MXDiagnosticPayload`'s `jsonRepresentation()` holds;
    /// nothing when it is not one. An event already kept is not added again
    /// (the app also reads past payloads at each start).
    public mutating func record(diagnostics json: Data) {
        guard let payload = try? JSONDecoder().decode(RawDiagnosticPayload.self, from: json) else { return }
        let time = Self.time(payload.timeStampEnd) ?? Self.time(payload.timeStampBegin)
        let groups: [(Event.Kind, [RawDiagnostic]?)] = [
            (.hang, payload.hangDiagnostics), (.crash, payload.crashDiagnostics), (.cpu, payload.cpuExceptionDiagnostics),
            (.diskWrites, payload.diskWriteExceptionDiagnostics), (.launch, payload.appLaunchDiagnostics),
        ]
        var added = false
        for (kind, diagnostics) in groups {
            for diagnostic in diagnostics ?? [] {
                let event = Self.event(kind, diagnostic, time: time)
                if !events.contains(event) {
                    events.append(event)
                    added = true
                }
            }
        }
        if added { trim() }
    }

    /// Adds the exits and freezes of an `MXMetricPayload`'s
    /// `jsonRepresentation()`; a day already kept is replaced.
    public mutating func record(metrics json: Data) {
        guard let payload = try? JSONDecoder().decode(RawMetricPayload.self, from: json) else { return }
        let exits = payload.applicationExitMetrics
        let foreground = Self.counts(exits?.foregroundExitData)
        let background = Self.counts(exits?.backgroundExitData)
        let buckets = (payload.applicationResponsivenessMetrics?.histogrammedAppHangTime?.histogramValue ?? [:])
            .sorted { (Int($0.key) ?? 0, $0.key) < (Int($1.key) ?? 0, $1.key) }
            .compactMap { _, bucket -> Bucket? in
                guard let count = bucket.bucketCount, count > 0 else { return nil }
                return Bucket(start: bucket.bucketStart ?? "?", end: bucket.bucketEnd ?? "?", count: count)
            }
        guard exits != nil || !buckets.isEmpty else { return }
        let day = Day(
            begin: Self.time(payload.timeStampBegin), end: Self.time(payload.timeStampEnd), foreground: foreground, background: background,
            hangs: buckets
        )
        days.removeAll { $0.begin == day.begin && $0.end == day.end }
        days.append(day)
        trim()
    }

    /// Keeps the newest ``mostEvents`` events and ``mostDays`` days, in
    /// order, and drops the oldest events until it fits ``mostBytes``.
    private mutating func trim() {
        events = Self.newestFirst(events, time: \.time)
        if events.count > Self.mostEvents { events.removeLast(events.count - Self.mostEvents) }
        days = Self.newestFirst(days, time: \.end)
        if days.count > Self.mostDays { days.removeLast(days.count - Self.mostDays) }
        while !events.isEmpty, let size = try? encoded().count, size > Self.mostBytes {
            events.removeLast()
        }
    }

    private static func newestFirst<T>(_ items: [T], time: KeyPath<T, Double?>) -> [T] {
        items.enumerated().sorted { a, b in
            switch (a.element[keyPath: time], b.element[keyPath: time]) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    // MARK: The file

    /// As the file: JSON, its keys sorted.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// What a file holds; empty when it holds nothing this can read.
    public static func decoded(_ data: Data) -> DeviceDiagnostics {
        (try? JSONDecoder().decode(DeviceDiagnostics.self, from: data)) ?? DeviceDiagnostics()
    }

    // MARK: The report

    /// The part of a problem report it writes: the newest
    /// ``shownEvents`` events, each with its stack, then the newest day's
    /// exits and freezes; `nil` when nothing was recorded.
    public func reportText(in language: DisplayLanguage) -> String? {
        guard !events.isEmpty || !days.isEmpty else { return nil }
        var lines = [language.text("Freezes and exits recorded on this device:", "這台裝置記下的卡住與結束：")]
        for event in events.prefix(Self.shownEvents) {
            lines.append(Self.headline(of: event, in: language))
            for (index, frame) in event.frames.enumerated() {
                lines.append("  \(index) \(frame.binary) \(Self.hex(frame.address)) +\(Self.hex(frame.offset)) \(frame.uuid)")
            }
            if event.framesLeft > 0 {
                lines.append(language.text("  … \(event.framesLeft) more frames further out", "  …外面還有 \(event.framesLeft) 層"))
            }
        }
        if events.count > Self.shownEvents {
            let older = events.count - Self.shownEvents
            lines.append(language.text("\(older) older ones not shown.", "另有 \(older) 筆較早的沒有列出。"))
        }
        if let day = days.first {
            let span = "\(Self.timeText(day.begin)) – \(Self.timeText(day.end))"
            lines.append(language.text(
                "Exits \(span): on screen: \(Self.countsText(day.foreground, in: language)); in the background: \(Self.countsText(day.background, in: language)).",
                "結束 \(span)：畫面上：\(Self.countsText(day.foreground, in: language))；背景：\(Self.countsText(day.background, in: language))。"
            ))
            if !day.hangs.isEmpty {
                let buckets = day.hangs.map { "\($0.start)–\($0.end) ×\($0.count)" }.joined(separator: language.text(", ", "、"))
                lines.append(language.text("Freezes that day by length: \(buckets).", "那天的卡住，依長度：\(buckets)。"))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func headline(of event: Event, in language: DisplayLanguage) -> String {
        let when = timeText(event.time)
        let length = event.duration.map(secondsText) ?? ""
        let what: String
        switch event.kind {
        case .hang:
            what = language.text("Froze \(length) at \(when)", "\(when) 卡住 \(length)")
        case .crash:
            what = language.text("Closed unexpectedly at \(when)", "\(when) 意外關閉")
        case .cpu:
            what = language.text("Used the processor heavily at \(when)", "\(when) 處理器用量過高")
        case .diskWrites:
            what = language.text("Wrote a lot to storage at \(when)", "\(when) 寫入儲存空間過多")
        case .launch:
            what = language.text("Started slowly (\(length)) at \(when)", "\(when) 啟動很慢（\(length)）")
        }
        var text = what.replacingOccurrences(of: "  ", with: " ")
        if let detail = event.detail { text += ": \(detail)" }
        let context = [event.app, event.system].compactMap { $0 }
        if !context.isEmpty { text += " (\(context.joined(separator: ", ")))" }
        return text
    }

    /// Apple's names for the reasons an app ends (`MXForegroundExitData`,
    /// `MXBackgroundExitData`), in the order a report lists them, and what
    /// each means.
    public static let exitReasons: [(key: String, english: String, chinese: String)] = [
        ("cumulativeNormalAppExitCount", "normal", "正常"),
        ("cumulativeMemoryResourceLimitExitCount", "over the memory limit", "超過記憶體上限"),
        ("cumulativeMemoryPressureExitCount", "reclaimed for memory", "被系統收回記憶體"),
        ("cumulativeAppWatchdogExitCount", "stuck too long (watchdog)", "卡太久被系統結束"),
        ("cumulativeBadAccessExitCount", "bad memory access", "記憶體存取錯誤"),
        ("cumulativeIllegalInstructionExitCount", "illegal instruction", "非法指令"),
        ("cumulativeAbnormalExitCount", "abnormal", "異常"),
        ("cumulativeCPUResourceLimitExitCount", "over the processor limit", "超過處理器上限"),
        ("cumulativeSuspendedWithLockedFileExitCount", "suspended holding a locked file", "暫停時還鎖著檔案"),
        ("cumulativeBackgroundTaskAssertionTimeoutExitCount", "background task ran too long", "背景工作逾時"),
    ]

    private static func countsText(_ counts: [String: Int], in language: DisplayLanguage) -> String {
        let listed = exitReasons.compactMap { reason -> String? in
            guard let count = counts[reason.key] else { return nil }
            return "\(language.text(reason.english, reason.chinese)) \(count)"
        }
        return listed.isEmpty ? language.text("none", "沒有") : listed.joined(separator: language.text(", ", "、"))
    }

    // MARK: Reading Apple's format

    private static func event(_ kind: Event.Kind, _ diagnostic: RawDiagnostic, time: Double?) -> Event {
        let meta = diagnostic.diagnosticMetaData
        var duration: Double?
        var details: [String] = []
        switch kind {
        case .hang, .launch:
            let text = kind == .hang ? meta?.hangDuration : meta?.launchDuration
            duration = text.flatMap(seconds)
            if duration == nil, let text { details.append(text) }
        case .crash:
            if let type = meta?.exceptionType { details.append(exceptionName(type)) }
            if let signal = meta?.signal { details.append(signalName(signal)) }
            if let code = meta?.exceptionCode { details.append("code \(code)") }
            if let reason = meta?.terminationReason { details.append(reason) }
            if let message = meta?.exceptionReason?.composedMessage { details.append(message) }
        case .cpu:
            if let total = meta?.totalCPUTime { details.append("CPU \(total)" + (meta?.totalSampledTime.map { " / \($0)" } ?? "")) }
        case .diskWrites:
            if let writes = meta?.writesCaused { details.append(writes) }
        }
        let app = meta?.appVersion.map { version in meta?.appBuildVersion.map { "\(version) (\($0))" } ?? version }
        let path = heaviestPath(diagnostic.callStackTree)
        return Event(
            kind: kind, time: time, duration: duration, detail: details.isEmpty ? nil : details.joined(separator: ", "), app: app,
            system: meta?.osVersion, frames: Array(path.prefix(mostFrames)), framesLeft: max(0, path.count - mostFrames)
        )
    }

    /// The stack of the thread the event is attributed to (the first when
    /// none is), innermost first. The tree's roots are the outermost
    /// frames, each frame's sub-frames what it called; this follows from
    /// the root the frame with the most samples (the first of those tied)
    /// down to the innermost, leaving out the kernel's frames (no binary
    /// to symbolicate them with).
    private static func heaviestPath(_ tree: RawCallStackTree?) -> [Frame] {
        guard let stacks = tree?.callStacks, !stacks.isEmpty else { return [] }
        let stack = stacks.first { $0.threadAttributed == true } ?? stacks[0]
        var path: [Frame] = []
        var next = heaviest(stack.callStackRootFrames)
        var depth = 0
        while let frame = next, depth < 4096 {
            let address = frame.address ?? 0
            if address < kernelAddresses {
                path.append(Frame(
                    binary: frame.binaryName ?? "?", uuid: frame.binaryUUID ?? "?", address: address,
                    offset: frame.offsetIntoBinaryTextSegment ?? 0
                ))
            }
            next = heaviest(frame.subFrames)
            depth += 1
        }
        return path.reversed()
    }

    /// Where the kernel's addresses begin on Apple's 64-bit systems.
    private static let kernelAddresses: UInt64 = 0xFFFF_0000_0000_0000

    private static func heaviest(_ frames: [RawFrame]?) -> RawFrame? {
        guard let frames, var best = frames.first else { return nil }
        for frame in frames.dropFirst() where (frame.sampleCount ?? 0) > (best.sampleCount ?? 0) {
            best = frame
        }
        return best
    }

    private static func counts(_ data: [String: Int]?) -> [String: Int] {
        (data ?? [:]).filter { $0.value > 0 }
    }

    /// "2026-10-25 21:03:00 +0000", as MetricKit writes its times.
    static func time(_ text: String?) -> Double? {
        guard let text else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: text)?.timeIntervalSince1970
    }

    static func timeText(_ time: Double?) -> String {
        guard let time else { return "?" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: time)) + " UTC"
    }

    /// A duration as MetricKit writes it ("1.25 sec", "1,250 ms",
    /// "2 min"), in seconds; `nil` when it is none of those.
    static func seconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        guard let value = Double(parts[0].replacingOccurrences(of: ",", with: "")) else { return nil }
        switch parts[1].lowercased() {
        case "ms": return value / 1000
        case "s", "sec", "secs", "second", "seconds": return value
        case "min", "mins", "minute", "minutes": return value * 60
        default: return nil
        }
    }

    static func secondsText(_ seconds: Double) -> String {
        seconds < 10 ? String(format: "%.2f s", seconds) : String(format: "%.0f s", seconds)
    }

    static func hex(_ value: UInt64) -> String {
        "0x" + String(value, radix: 16)
    }

    private static func exceptionName(_ type: Int) -> String {
        let names = [
            1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC", 4: "EXC_EMULATION", 5: "EXC_SOFTWARE", 6: "EXC_BREAKPOINT",
            10: "EXC_CRASH", 11: "EXC_RESOURCE", 12: "EXC_GUARD",
        ]
        return names[type].map { "\($0) (\(type))" } ?? "exception \(type)"
    }

    private static func signalName(_ signal: Int) -> String {
        let names = [4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV", 13: "SIGPIPE"]
        return names[signal].map { "\($0) (\(signal))" } ?? "signal \(signal)"
    }
}

// MARK: Apple's JSON, every field optional and read leniently

private struct RawDiagnosticPayload: Decodable {
    var timeStampBegin: String?
    var timeStampEnd: String?
    var hangDiagnostics: [RawDiagnostic]?
    var crashDiagnostics: [RawDiagnostic]?
    var cpuExceptionDiagnostics: [RawDiagnostic]?
    var diskWriteExceptionDiagnostics: [RawDiagnostic]?
    var appLaunchDiagnostics: [RawDiagnostic]?

    enum CodingKeys: String, CodingKey {
        case timeStampBegin, timeStampEnd, hangDiagnostics, crashDiagnostics, cpuExceptionDiagnostics, diskWriteExceptionDiagnostics
        case appLaunchDiagnostics
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timeStampBegin = c.lenient(.timeStampBegin)
        timeStampEnd = c.lenient(.timeStampEnd)
        hangDiagnostics = c.lenient(.hangDiagnostics)
        crashDiagnostics = c.lenient(.crashDiagnostics)
        cpuExceptionDiagnostics = c.lenient(.cpuExceptionDiagnostics)
        diskWriteExceptionDiagnostics = c.lenient(.diskWriteExceptionDiagnostics)
        appLaunchDiagnostics = c.lenient(.appLaunchDiagnostics)
    }
}

private struct RawDiagnostic: Decodable {
    var callStackTree: RawCallStackTree?
    var diagnosticMetaData: RawMetaData?

    enum CodingKeys: String, CodingKey { case callStackTree, diagnosticMetaData }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        callStackTree = c.lenient(.callStackTree)
        diagnosticMetaData = c.lenient(.diagnosticMetaData)
    }
}

private struct RawMetaData: Decodable {
    var appVersion, appBuildVersion, osVersion: String?
    var hangDuration, launchDuration, totalCPUTime, totalSampledTime, writesCaused, terminationReason: String?
    var exceptionType, exceptionCode, signal: Int?
    var exceptionReason: RawExceptionReason?

    enum CodingKeys: String, CodingKey {
        case appVersion, appBuildVersion, osVersion, hangDuration, launchDuration, totalCPUTime, totalSampledTime, writesCaused
        case terminationReason, exceptionType, exceptionCode, signal, exceptionReason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appVersion = c.lenient(.appVersion)
        appBuildVersion = c.lenient(.appBuildVersion)
        osVersion = c.lenient(.osVersion)
        hangDuration = c.lenient(.hangDuration)
        launchDuration = c.lenient(.launchDuration)
        totalCPUTime = c.lenient(.totalCPUTime)
        totalSampledTime = c.lenient(.totalSampledTime)
        writesCaused = c.lenient(.writesCaused)
        terminationReason = c.lenient(.terminationReason)
        exceptionType = c.lenient(.exceptionType)
        exceptionCode = c.lenient(.exceptionCode)
        signal = c.lenient(.signal)
        exceptionReason = c.lenient(.exceptionReason)
    }
}

private struct RawExceptionReason: Decodable {
    var composedMessage: String?
}

private struct RawCallStackTree: Decodable {
    var callStacks: [RawCallStack]?

    enum CodingKeys: String, CodingKey { case callStacks }

    init(from decoder: Decoder) throws {
        callStacks = try decoder.container(keyedBy: CodingKeys.self).lenient(.callStacks)
    }
}

private struct RawCallStack: Decodable {
    var threadAttributed: Bool?
    var callStackRootFrames: [RawFrame]?

    enum CodingKeys: String, CodingKey { case threadAttributed, callStackRootFrames }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threadAttributed = c.lenient(.threadAttributed)
        callStackRootFrames = c.lenient(.callStackRootFrames)
    }
}

private struct RawFrame: Decodable {
    var binaryUUID, binaryName: String?
    var address, offsetIntoBinaryTextSegment: UInt64?
    var sampleCount: Int?
    var subFrames: [RawFrame]?

    enum CodingKeys: String, CodingKey { case binaryUUID, binaryName, address, offsetIntoBinaryTextSegment, sampleCount, subFrames }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        binaryUUID = c.lenient(.binaryUUID)
        binaryName = c.lenient(.binaryName)
        address = c.lenient(.address)
        offsetIntoBinaryTextSegment = c.lenient(.offsetIntoBinaryTextSegment)
        sampleCount = c.lenient(.sampleCount)
        subFrames = c.lenient(.subFrames)
    }
}

private struct RawMetricPayload: Decodable {
    var timeStampBegin, timeStampEnd: String?
    var applicationExitMetrics: RawExitMetrics?
    var applicationResponsivenessMetrics: RawResponsiveness?

    enum CodingKeys: String, CodingKey { case timeStampBegin, timeStampEnd, applicationExitMetrics, applicationResponsivenessMetrics }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timeStampBegin = c.lenient(.timeStampBegin)
        timeStampEnd = c.lenient(.timeStampEnd)
        applicationExitMetrics = c.lenient(.applicationExitMetrics)
        applicationResponsivenessMetrics = c.lenient(.applicationResponsivenessMetrics)
    }
}

private struct RawExitMetrics: Decodable {
    var foregroundExitData: [String: Int]?
    var backgroundExitData: [String: Int]?

    enum CodingKeys: String, CodingKey { case foregroundExitData, backgroundExitData }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        foregroundExitData = c.lenient(.foregroundExitData)
        backgroundExitData = c.lenient(.backgroundExitData)
    }
}

private struct RawResponsiveness: Decodable {
    var histogrammedAppHangTime: RawHistogram?

    enum CodingKeys: String, CodingKey { case histogrammedAppHangTime }

    init(from decoder: Decoder) throws {
        histogrammedAppHangTime = try decoder.container(keyedBy: CodingKeys.self).lenient(.histogrammedAppHangTime)
    }
}

private struct RawHistogram: Decodable {
    var histogramValue: [String: RawBucket]?

    enum CodingKeys: String, CodingKey { case histogramValue }

    init(from decoder: Decoder) throws {
        histogramValue = try decoder.container(keyedBy: CodingKeys.self).lenient(.histogramValue)
    }
}

private struct RawBucket: Decodable {
    var bucketStart, bucketEnd: String?
    var bucketCount: Int?

    enum CodingKeys: String, CodingKey { case bucketStart, bucketEnd, bucketCount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bucketStart = c.lenient(.bucketStart)
        bucketEnd = c.lenient(.bucketEnd)
        bucketCount = c.lenient(.bucketCount)
    }
}

private extension KeyedDecodingContainer {
    /// The value, or `nil` when it is missing or of another type.
    func lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}
