import Foundation

/// Decision 517 續 (BUILD3D-3, PR 3b's measurement): how long the 3D
/// map's scene takes to build on this device, for a problem report. PR 3b
/// (rebuilding only the chunks new track passes) waits on this number from
/// real devices: a session cannot measure it, and Linux's debug build is
/// some ten times slower than a release build on a phone. Nothing is
/// changed by it; it only times.
///
/// Each build keeps why it was built, how big the world and the scene
/// were, and three times: reading what it is built from (the files, the
/// snapshot, the skyline), building the scene, and handing it to the GPU
/// on the main thread. The last ``capacity`` builds are kept, in memory
/// only, and leave the device only in the note the player sends.
public struct Map3DSceneBuildTime: Hashable, Sendable {
    /// Why a scene was built.
    public enum Why: Hashable, Sendable {
        /// The first scene of a game (or after the last was let go).
        case first
        /// Built again because the track changed (PR 3b's case).
        case track
        /// Built again for anything else: the place looked at, the
        /// buildings, the week, the lines' colours.
        case other
    }

    public let why: Why
    public let realWorld: Bool
    /// The world's track edges, and the scene's chunks and triangles.
    public let edges: Int
    public let chunks: Int
    public let triangles: Int
    /// Seconds reading what it is built from, and building it.
    public let readSeconds: Double
    public let buildSeconds: Double
    /// Seconds handing it to the GPU; `nil` until shown (a build the 2D
    /// map started ahead may never be).
    public internal(set) var showSeconds: Double?
    /// When it was built, in seconds since 1970.
    public let wall: Double

    public init(why: Why, realWorld: Bool, edges: Int, chunks: Int, triangles: Int, readSeconds: Double, buildSeconds: Double,
                wall: Double) {
        self.why = why
        self.realWorld = realWorld
        self.edges = edges
        self.chunks = chunks
        self.triangles = triangles
        self.readSeconds = readSeconds
        self.buildSeconds = buildSeconds
        self.wall = wall
    }

    /// Its line in a problem report.
    public func reportLine(in language: DisplayLanguage) -> String {
        let why = switch self.why {
        case .first: language.text("first", "第一次")
        case .track: language.text("track changed", "軌道變了")
        case .other: language.text("rebuilt", "重蓋")
        }
        let map = realWorld ? language.text("real-world map", "實景地圖") : language.text("generated map", "產生的地圖")
        func s(_ seconds: Double) -> String { String(format: "%.2f s", seconds) }
        var times = language.text("read \(s(readSeconds)), built \(s(buildSeconds))", "讀取 \(s(readSeconds))、建造 \(s(buildSeconds))")
        times += showSeconds.map { language.text(", shown \(s($0))", "、上 GPU \(s($0))") } ?? language.text(", not shown", "、沒顯示")
        let total = readSeconds + buildSeconds + (showSeconds ?? 0)
        times += language.text(" (total \(s(total)))", "（共 \(s(total))）")
        let size = language.text("\(edges) edges, \(chunks) chunks, \(triangles) triangles", "\(edges) 段軌道、\(chunks) 區塊、\(triangles) 三角形")
        return "\(DeviceDiagnostics.timeText(wall)) \(why), \(map), \(size): \(times)"
    }
}

/// The builds kept (``Map3DSceneBuildTime``), shared by the threads that
/// build and the main thread that shows.
public final class Map3DSceneBuildLog: @unchecked Sendable {
    public static let shared = Map3DSceneBuildLog()
    /// How many builds are kept, the newest.
    public static let capacity = 8

    private let lock = NSLock()
    private var kept: [(number: Int, time: Map3DSceneBuildTime)] = []
    private var next = 0

    public init() {}

    /// Keeps `time`, and returns its number for ``shown(_:seconds:)``.
    @discardableResult
    public func add(_ time: Map3DSceneBuildTime) -> Int {
        lock.lock()
        defer { lock.unlock() }
        next += 1
        kept.append((next, time))
        if kept.count > Self.capacity { kept.removeFirst(kept.count - Self.capacity) }
        return next
    }

    /// Build `number` took `seconds` to hand to the GPU; the first time
    /// counts (a scene shown again is already there).
    public func shown(_ number: Int, seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = kept.firstIndex(where: { $0.number == number }), kept[index].time.showSeconds == nil else { return }
        kept[index].time.showSeconds = seconds
    }

    /// The builds kept, the oldest first.
    public var times: [Map3DSceneBuildTime] {
        lock.lock()
        defer { lock.unlock() }
        return kept.map(\.time)
    }

    /// A problem report's part; `nil` when nothing was built.
    public func reportText(in language: DisplayLanguage) -> String? {
        let times = times
        guard !times.isEmpty else { return nil }
        return ([language.text("3D scene builds (oldest first):", "3D 場景建造（舊的在前）：")]
            + times.map { "  " + $0.reportLine(in: language) }).joined(separator: "\n")
    }
}
