import Foundation
import GameCore

/// Station along an operating railway line.
public struct RealOperationStation: Hashable, Sendable, Codable {
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let distanceKm: Double?
    public let dwellSec: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case latitude = "lat"
        case longitude = "lon"
        case distanceKm = "d"
        case dwellSec = "dwell"
    }

    public init(name: String, latitude: Double, longitude: Double, distanceKm: Double? = nil, dwellSec: Int? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.distanceKm = distanceKm
        self.dwellSec = dwellSec
    }
}

/// Operational parameters of an operating line (headways, stations, dwell times).
public struct RealOperationLine: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let color: String?
    public let peakHeadwaySec: Int?
    public let offpeakHeadwaySec: Int?
    public let isHeadwayEstimated: Bool
    public let stations: [RealOperationStation]
    public let dwellSec: [Int]?
    /// Each segment's run time in seconds, from station `i` to `i + 1`
    /// (`segs[i].run`), kept aligned with the file's segments: a segment
    /// without a run time is `nil`, never dropped, so index `i` is always
    /// segment `i`.
    public let segmentRunSec: [Int?]?
    /// Whether the line is a ring (`loop`): its last station runs on to
    /// the first.
    public let isLoop: Bool

    public init(
        id: String,
        name: String,
        color: String? = nil,
        peakHeadwaySec: Int? = nil,
        offpeakHeadwaySec: Int? = nil,
        isHeadwayEstimated: Bool = false,
        stations: [RealOperationStation] = [],
        dwellSec: [Int]? = nil,
        segmentRunSec: [Int?]? = nil,
        isLoop: Bool = false
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.peakHeadwaySec = peakHeadwaySec
        self.offpeakHeadwaySec = offpeakHeadwaySec
        self.isHeadwayEstimated = isHeadwayEstimated
        self.stations = stations
        self.dwellSec = dwellSec
        self.segmentRunSec = segmentRunSec
        self.isLoop = isLoop
    }

    /// The site's `runBetween(ln, a, b)`: the run time in seconds from
    /// station index `a` to `b` along the segments (the shorter way round a
    /// ring), or `nil` when a segment on the way has no run time.
    public func runSeconds(from a: Int, to b: Int) -> Int? {
        guard let segs = segmentRunSec else { return nil }
        let n = stations.count
        guard n > 0, stations.indices.contains(a), stations.indices.contains(b) else { return nil }
        let forward: Bool, steps: Int
        if isLoop {
            let f = (b - a + n) % n, r = (a - b + n) % n
            forward = f <= r
            steps = forward ? f : r
        } else {
            forward = b > a
            steps = abs(b - a)
        }
        var total = 0, current = a
        for _ in 0 ..< steps {
            let segment = forward ? current : (current - 1 + n) % n
            guard segs.indices.contains(segment), let run = segs[segment], run > 0 else { return nil }
            total += run
            current = forward ? (current + 1) % n : (current - 1 + n) % n
        }
        return total
    }
}

/// An operating railway system (TRA, TRTC, KRTC, etc.) with its operational lines.
public struct RealOperationSystem: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let lines: [RealOperationLine]

    public init(id: String, name: String, lines: [RealOperationLine]) {
        self.id = id
        self.name = name
        self.lines = lines
    }

    public func line(id: String) -> RealOperationLine? {
        lines.first { $0.id == id }
    }
}


/// Operational railway data across Taiwan: station sequences, peak/off-peak
/// headways, dwell times, run times, and timetables.
///
/// The systems are read when it is made; each file that cannot be read is
/// left out and listed in ``loadIssues`` instead of being dropped silently.
/// The timetables are only read, and parsed, the first time one is asked
/// for (``timetable(forSystem:)``): they are most of the data's size.
public struct RealRailwayOperations: Sendable {
    /// Each system's file key (`tra`, `trtc`, `thsr`, …) and the site's
    /// system it belongs to (``RealRailways/System``; `index.html`
    /// `SYS_DEFS`: `trtc.json` is `mrt`, `tra.json` `tra_sched`).
    public static let siteSystems: [String: String] = [
        "tra": "tra_sched", "thsr": "thsr_sched", "afr": "afr_sched", "trtc": "mrt",
        "tymc": "tymc", "ntdlrt": "ntdlrt", "ntalrt": "ntalrt", "sanying": "sanying",
        "krtc": "krtc", "tmrt": "tmrt",
    ]

    /// The order systems are searched in: the site's (`SYS_DEFS`).
    public static let systemOrder = ["tra", "thsr", "afr", "trtc", "tymc", "ntdlrt", "ntalrt", "sanying", "krtc", "tmrt"]

    public let systems: [String: RealOperationSystem]
    /// The files that could not be read, and why.
    public let loadIssues: [RealDataLoadIssue]
    private let timetables: LazyFiles<RealSystemTimetable>
    private let schedules: LazyFiles<RealDailySchedule>

    /// `systems` is each system's `<key>.json` by key; `timetables` each
    /// system's `<key>_times.json` (keyed by `<key>` or `<key>_times`),
    /// read when first needed; `schedules` a scheduled system's day of
    /// trains (`thsr`: `thsr-schedule.json`).
    public init(
        systems systemsData: [String: Data],
        timetables: [String: @Sendable () throws -> Data] = [:],
        schedules: [String: @Sendable () throws -> Data] = [:]
    ) {
        var issues: [RealDataLoadIssue] = []
        var parsed: [String: RealOperationSystem] = [:]
        for key in systemsData.keys.sorted() {
            do {
                parsed[key] = try Self.system(key, from: systemsData[key]!)
            } catch {
                issues.append(RealDataLoadIssue(file: key == "thsr" ? "thsr_track.json" : "\(key).json", error: error))
            }
        }
        self.systems = parsed
        self.loadIssues = issues
        var keyed: [String: @Sendable () throws -> Data] = [:]
        for (key, source) in timetables {
            keyed[key.hasSuffix("_times") ? String(key.dropLast("_times".count)) : key] = source
        }
        self.timetables = LazyFiles(sources: keyed, fileName: { "\($0)_times.json" }, parse: { try RealSystemTimetable(data: $0) })
        self.schedules = LazyFiles(sources: schedules, fileName: { "\($0)-schedule.json" }, parse: { try RealDailySchedule(data: $0) })
    }

    /// The same from data already read.
    public init(systems systemsData: [String: Data], timetables: [String: Data], schedules: [String: Data] = [:]) {
        func source(_ data: Data) -> @Sendable () throws -> Data { { data } }
        self.init(systems: systemsData, timetables: timetables.mapValues(source), schedules: schedules.mapValues(source))
    }

    private static func system(_ key: String, from data: Data) throws -> RealOperationSystem {
        struct RawStation: Decodable {
            let name: String
            let lat: Double
            let lon: Double
            let d: Double?
            let dwell: Int?
        }
        struct RawSeg: Decodable {
            let run: Int?
        }
        struct RawLine: Decodable {
            let id: String
            let name: String
            let color: String?
            let peakHeadwaySec: Int?
            let offpeakHeadwaySec: Int?
            let headway_estimated: Bool?
            let stations: [RawStation]
            let dwellSec: [Int]?
            let segs: [RawSeg]?
            let loop: Bool?
        }
        struct RawSystem: Decodable {
            let system: String?
            let lines: [RawLine]
        }
        let raw = try JSONDecoder().decode(RawSystem.self, from: data)
        let lines = raw.lines.map { line in
            RealOperationLine(
                id: line.id,
                name: line.name,
                color: line.color,
                peakHeadwaySec: line.peakHeadwaySec,
                offpeakHeadwaySec: line.offpeakHeadwaySec,
                isHeadwayEstimated: line.headway_estimated ?? false,
                stations: line.stations.map {
                    RealOperationStation(name: $0.name, latitude: $0.lat, longitude: $0.lon, distanceKm: $0.d, dwellSec: $0.dwell)
                },
                dwellSec: line.dwellSec,
                segmentRunSec: line.segs?.map(\.run),
                isLoop: line.loop ?? false
            )
        }
        return RealOperationSystem(id: key, name: raw.system ?? key.uppercased(), lines: lines)
    }

    public func system(id: String) -> RealOperationSystem? {
        systems[id]
    }

    public func line(id: String, inSystem systemId: String) -> RealOperationLine? {
        systems[systemId]?.line(id: id)
    }

    public func lines(inSystem systemId: String) -> [RealOperationLine] {
        systems[systemId]?.lines ?? []
    }

    /// Every line, system by system in the site's order.
    public var allLines: [RealOperationLine] {
        orderedSystems.flatMap(\.lines)
    }

    /// The systems in the site's order, then any others by key.
    public var orderedSystems: [RealOperationSystem] {
        let known = Self.systemOrder.compactMap { systems[$0] }
        let others = systems.keys.filter { !Self.systemOrder.contains($0) }.sorted().compactMap { systems[$0] }
        return known + others
    }

    /// The line's headway in seconds at the peak or off it. A line whose
    /// file has none (the High Speed Rail) takes it from its system's day
    /// of trains (``RealDailySchedule/headwaySeconds(peak:)``).
    public func headway(forLine id: String, inSystem systemId: String, peak: Bool) -> Int? {
        guard let line = line(id: id, inSystem: systemId) else { return nil }
        if let own = peak ? line.peakHeadwaySec : line.offpeakHeadwaySec { return own }
        return schedule(forSystem: systemId)?.headwaySeconds(peak: peak)
    }

    /// The systems with a timetable file, by key.
    public var timetableSystemIDs: [String] {
        timetables.keys
    }

    /// System `id`'s timetables (`<id>_times.json`), read and parsed the
    /// first time they are asked for; `nil` without a file, or when it
    /// cannot be read (``timetableIssues``).
    public func timetable(forSystem id: String) -> RealSystemTimetable? {
        timetables.value(id)
    }

    /// The day of trains of scheduled system `id` (`thsr`), read the first
    /// time it is asked for.
    public func schedule(forSystem id: String) -> RealDailySchedule? {
        schedules.value(id)
    }

    /// The timetables and schedules read so far that could not be.
    public var timetableIssues: [RealDataLoadIssue] {
        timetables.issues + schedules.issues
    }
}

/// Files read and parsed the first time each is asked for, then kept.
/// Shared by copies of the value that holds it; the lock makes it safe to
/// ask from any thread.
final class LazyFiles<Value: Sendable>: @unchecked Sendable {
    private let sources: [String: @Sendable () throws -> Data]
    private let fileName: @Sendable (String) -> String
    private let parse: @Sendable (Data) throws -> Value
    private let lock = NSLock()
    private var parsed: [String: Value] = [:]
    private var failed: [String: RealDataLoadIssue] = [:]

    init(sources: [String: @Sendable () throws -> Data], fileName: @escaping @Sendable (String) -> String, parse: @escaping @Sendable (Data) throws -> Value) {
        self.sources = sources
        self.fileName = fileName
        self.parse = parse
    }

    var keys: [String] { sources.keys.sorted() }

    var issues: [RealDataLoadIssue] {
        lock.lock()
        defer { lock.unlock() }
        return failed.keys.sorted().compactMap { failed[$0] }
    }

    func value(_ key: String) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        if let value = parsed[key] { return value }
        guard failed[key] == nil, let source = sources[key] else { return nil }
        do {
            let value = try parse(try source())
            parsed[key] = value
            return value
        } catch {
            failed[key] = RealDataLoadIssue(file: fileName(key), error: error)
            return nil
        }
    }
}
