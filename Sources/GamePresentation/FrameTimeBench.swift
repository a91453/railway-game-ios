import Foundation
import GameCore

// Decision 421 (V2 of docs/research/FRAME_TIME_AND_ENGINE_SPIKE_PLAN_2026-10-26.md):
// a fixed test of the screen's pace, the same on every device. A demo game
// at Taipei Main Station on the real-world map, its real lines laid by the
// demo mode's own steps (decision 351, ``GameSession/layDemoRealLines(in:routes:)``)
// to 1, 5, 10 or 20 lines; then 60 seconds of the flat map panned and
// zoomed, the 3D map circled, or the 3D map following a train, each along
// a fixed path. Each scenario is run three times on a device, after the
// app is started afresh, and the three runs are summed up; runs that
// differ too much are marked unsteady and not compared.
//
// The references have no such test (gap).

/// The fixed test (decision 421, V2): its scenarios, the camera's paths
/// and the game it runs on.
public enum FrameTimeBench {
    /// Taipei Main Station, the middle of the map and of the lines laid.
    public static let anchor: GeoAnchor = {
        guard let anchor = GeoAnchor(latitude: 250_478_000, longitude: 1_215_170_000) else {
            preconditionFailure("Taipei Main Station is not on the Earth")
        }
        return anchor
    }()

    /// The game's seed, the same every run.
    public static let eventSeed: UInt32 = 421
    /// How long a run is timed, and how long the game runs before it is,
    /// for the first frames' loading not to count.
    public static let seconds = 60.0
    public static let settleSeconds = 5.0
    /// Runs of each scenario on a device that are summed up.
    public static let runs = 3
    public static let lineCounts = [1, 5, 10, 20]

    /// What the run's card says when the test game did not start: when
    /// the real railways were still being read, that trying again soon
    /// will do.
    public static func notStarted(railwaysLoading: Bool, in language: DisplayLanguage) -> String {
        let failed = language.text("The test game could not start.", "測試遊戲沒辦法開始。")
        guard railwaysLoading else { return failed }
        return failed + language.text(
            " The railway data is still loading; try again in a few seconds.", "鐵路資料還在讀，請過幾秒再試。"
        )
    }
    /// How far round Taipei Main Station the real lines are laid from.
    static let reach = 6_000.0
    /// Where the 2D runs' zoom is and how far they pan, in metres.
    static let panReach = 1_000.0

    /// What a run does with the camera.
    public enum View: String, Codable, CaseIterable, Hashable, Sendable {
        /// The flat map, panned round and zoomed out and in.
        case pan2D
        /// The 3D map, circled round Taipei Main Station.
        case orbit3D
        /// The 3D map following a train from behind.
        case follow3D

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .pan2D: language.text("2D pan and zoom", "2D 平移縮放")
            case .orbit3D: language.text("3D circling", "3D 環繞")
            case .follow3D: language.text("3D following a train", "3D 跟車")
            }
        }
    }

    /// One scenario: how many lines, and what the camera does.
    public struct Scenario: Codable, Hashable, Sendable, Identifiable {
        public let lines: Int
        public let view: View

        public init(lines: Int, view: View) {
            self.lines = lines
            self.view = view
        }

        public var id: String { "\(lines)-\(view.rawValue)" }

        public func title(in language: DisplayLanguage) -> String {
            language.text("Taipei, \(lines) lines · \(view.title(in: language))", "台北 \(lines) 線 · \(view.title(in: language))")
        }
    }

    /// Every scenario, fewest lines first.
    public static let scenarios: [Scenario] = lineCounts.flatMap { lines in View.allCases.map { Scenario(lines: lines, view: $0) } }

    /// The new game a run starts: Taipei on the real-world map, its ground
    /// read in when the app has the heights, unlimited funds, the seed
    /// fixed. The lines are laid once it is open
    /// (``GameSession/layFrameTimeBench(lines:)``).
    public static func world(groundFrom heights: HeightGrid?) -> GameWorld {
        var world = GameWorld.newGame(anchor: anchor, eventSeed: eventSeed)
        world.setUnlimitedFunds(true)
        if heights != nil { try? world.mapGround() }
        return world
    }

    /// The flat map's camera `seconds` into a run, from `start` (the map
    /// opened on Taipei): a figure of eight ``panReach`` either way every
    /// 20 s, zoomed out to half the scale and back every 15 s.
    public static func camera2D(from start: PlanCamera, at seconds: Double) -> PlanCamera {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let turn = 2 * Double.pi * seconds / 20
        let x = start.centerX + panReach * metre * sin(turn)
        let y = start.centerY + panReach / 2 * metre * sin(2 * turn)
        let zoom = 1 + (1 - cos(2 * Double.pi * seconds / 15)) / 2
        let centre = ScreenPoint(x: start.viewport.width / 2, y: start.viewport.height / 2)
        return start.centered(atX: x, y: y).zoomed(by: zoom, around: centre)
    }

    /// The 3D map's camera `seconds` into a circling run, from `start`:
    /// once round every 30 s, half as far again out and back every 20 s.
    public static func camera3D(from start: Map3DCamera, at seconds: Double) -> Map3DCamera {
        var camera = start
        camera.heading = start.heading + Float(2 * Double.pi * seconds / 30)
        camera.distance = start.distance * Float(1 + 0.25 * (1 - cos(2 * Double.pi * seconds / 20)))
        return camera
    }

    /// The train a following run follows: the first of the first line's
    /// trains on the track.
    public static func followed(in world: GameWorld) -> TrainID? {
        for line in world.lines {
            if let id = line.assignedTrains.first(where: { world.train(id: $0)?.position != nil }) { return id }
        }
        return nil
    }
}

extension GameSession {
    /// Lays the fixed test's `lines` lines (decision 421): the real lines
    /// round Taipei Main Station, as the demo mode lays them, the first
    /// ones by their key; past the real lines in reach, a line calling at
    /// the stations of each line but its ends (a short working), the first
    /// lines first; and surplus lines taken off again, the newest first.
    /// The number of lines it has.
    @discardableResult
    public func layFrameTimeBench(lines count: Int) async -> Int {
        guard let frame = RealWorldFrame(world: world) else { return world.lines.count }
        let centre = frame.worldPosition(latitude: FrameTimeBench.anchor.latitudeDegrees, longitude: FrameTimeBench.anchor.longitudeDegrees)
        let reach = FrameTimeBench.reach * Double(WorldCoordinate.unitsPerMetre)
        let view = WorldRegion(minX: centre.x - reach, minY: centre.y - reach, maxX: centre.x + reach, maxY: centre.y + reach)
        _ = await layDemoRealLines(in: view, routes: count)
        while world.lines.count > count, let newest = world.lines.last {
            guard (try? performCommand(.edit(.removeLineSellingTrains(newest.id)))) != nil else { break }
        }
        var index = 0
        while world.lines.count < count, index < world.lines.count {
            let line = world.lines[index]
            index += 1
            let stops = Array(line.stops.dropFirst().dropLast())
            guard stops.count >= 2 else { continue }
            let name = "\(line.name) \(language.text("short", "區間"))"
            guard let short = try? performCommand(.edit(.createLine(name: name, stops: stops, targets: nil))).line else { continue }
            if let color = line.color { _ = try? performCommand(.edit(.setLineColor(short.id, color))) }
            _ = try? performCommand(.edit(.staffLine(short.id, headway: 12, type: nil, cars: 4, language: language)))
        }
        return world.lines.count
    }
}

/// One run of a scenario on a device (decision 421, V2).
public struct FrameTimeBenchRun: Codable, Hashable, Sendable {
    public let scenario: FrameTimeBench.Scenario
    /// The device's model identifier ("iPhone17,1").
    public let device: String
    /// Whether it ran on the Simulator: its GPU is the Mac's, so only its
    /// CPU side means anything.
    public let simulator: Bool
    /// Whether it was the first run since the app started.
    public let cold: Bool
    public let segment: FrameTimeSegment

    public init(scenario: FrameTimeBench.Scenario, device: String, simulator: Bool, cold: Bool, segment: FrameTimeSegment) {
        self.scenario = scenario
        self.device = device
        self.simulator = simulator
        self.cold = cold
        self.segment = segment
    }

    public var p95: Double { segment.intervals?.p95 ?? 0 }
    public var median: Double { segment.intervals?.median ?? 0 }
    public var severe: Int { segment.stalls.severe }
    public var longest: Double { segment.longest?.milliseconds ?? segment.intervals?.longest ?? 0 }
}

/// A scenario's runs on a device, summed up (decision 421, V2): each run's
/// median, p95, severe stalls and longest stall, then the three runs'
/// middle value and spread (largest less smallest) of each.
public struct FrameTimeBenchSummary: Hashable, Sendable {
    /// More than this between the runs' largest and smallest p95, as a
    /// share of the smallest, and the runs are unsteady.
    public static let steadyP95 = 0.2

    /// Oldest first.
    public let runs: [FrameTimeBenchRun]

    public init(runs: [FrameTimeBenchRun]) {
        self.runs = runs
    }

    public var isComplete: Bool { runs.count >= FrameTimeBench.runs }

    /// The middle value of `values` (of an even count, the lower middle).
    static func middle(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[(sorted.count - 1) / 2]
    }

    static func spread(_ values: [Double]) -> Double {
        (values.max() ?? 0) - (values.min() ?? 0)
    }

    public var median: (middle: Double, spread: Double) { (Self.middle(runs.map(\.median)), Self.spread(runs.map(\.median))) }
    public var p95: (middle: Double, spread: Double) { (Self.middle(runs.map(\.p95)), Self.spread(runs.map(\.p95))) }
    public var severe: (middle: Double, spread: Double) {
        (Self.middle(runs.map { Double($0.severe) }), Self.spread(runs.map { Double($0.severe) }))
    }
    public var longest: (middle: Double, spread: Double) { (Self.middle(runs.map(\.longest)), Self.spread(runs.map(\.longest))) }

    /// Whether the runs differ too much to compare: their p95 by more than
    /// ``steadyP95`` of the smallest, or their counts of severe stalls at
    /// all. One run alone is not.
    public var isUnsteady: Bool {
        guard runs.count > 1 else { return false }
        let p95s = runs.map(\.p95)
        // In tenths of a millisecond, the report's precision, so that
        // exactly 20% apart is not tipped over by a binary fraction.
        let least = (p95s.min() ?? 0) * 10, most = (p95s.max() ?? 0) * 10
        let p95Differs = (most - least).rounded() > (least * Self.steadyP95).rounded()
        return p95Differs || Set(runs.map(\.severe)).count > 1
    }

    /// The report's lines for `scenario`.
    func lines(of scenario: FrameTimeBench.Scenario, in language: DisplayLanguage) -> [String] {
        func ms(_ value: Double) -> String { String(format: "%.1f ms", value) }
        let colds = runs.filter(\.cold).count
        var lines = [scenario.title(in: language) + language.text(
            ": \(runs.count) of \(FrameTimeBench.runs) runs (\(colds) after a fresh start)",
            "：\(runs.count)／\(FrameTimeBench.runs) 次（冷啟動後 \(colds) 次）"
        )]
        for (index, run) in runs.enumerated() {
            lines.append("  " + language.text(
                "run \(index + 1): median \(ms(run.median)), p95 \(ms(run.p95)), severe \(run.severe), longest \(ms(run.longest))",
                "第 \(index + 1) 次：中位數 \(ms(run.median))、p95 \(ms(run.p95))、嚴重 \(run.severe)、最長 \(ms(run.longest))"
            ))
        }
        if runs.count > 1 {
            lines.append("  " + language.text(
                "middle (spread): median \(ms(median.middle)) (\(ms(median.spread))), p95 \(ms(p95.middle)) (\(ms(p95.spread))), severe \(Int(severe.middle)) (\(Int(severe.spread))), longest \(ms(longest.middle)) (\(ms(longest.spread)))",
                "中間值（最大最小差）：中位數 \(ms(median.middle))（\(ms(median.spread))）、p95 \(ms(p95.middle))（\(ms(p95.spread))）、嚴重 \(Int(severe.middle))（\(Int(severe.spread))）、最長 \(ms(longest.middle))（\(ms(longest.spread))）"
            ))
        }
        if isUnsteady {
            lines.append("  " + language.text(
                "UNSTEADY: the runs differ too much to compare; look for heat, downloads or a first load first.",
                "不穩定：三次差太多，不拿來比較；先查發燙、背景下載或第一次載入。"
            ))
        }
        if runs.contains(where: \.simulator) {
            lines.append("  " + language.text(
                "Simulator: a reference for the CPU side only, not GPU figures.",
                "模擬器：只當 CPU 端的參考，不是 GPU 數字。"
            ))
        }
        if let last = runs.last {
            lines += last.segment.lines(in: language).map { "  " + $0 }
        }
        return lines
    }
}

/// The fixed test's runs kept on the device (decision 421, V2): the newest
/// ``FrameTimeBench/runs`` of each scenario on each device.
public struct FrameTimeBenchResults: Codable, Hashable, Sendable {
    public static let fileName = "frame-time-bench.json"

    /// Newest first.
    public private(set) var runs: [FrameTimeBenchRun] = []

    public init() {}

    /// Keeps `run`, dropping the oldest of its scenario and device past
    /// ``FrameTimeBench/runs``.
    public mutating func add(_ run: FrameTimeBenchRun) {
        runs.insert(run, at: 0)
        var seen: [String: Int] = [:]
        runs = runs.filter { kept in
            let key = "\(kept.device)|\(kept.scenario.id)"
            seen[key, default: 0] += 1
            return seen[key]! <= FrameTimeBench.runs
        }
    }

    /// Forgets the runs on `device`.
    public mutating func clear(device: String) {
        runs.removeAll { $0.device == device }
    }

    /// The runs of `scenario` on `device`, oldest first.
    public func summary(of scenario: FrameTimeBench.Scenario, on device: String) -> FrameTimeBenchSummary {
        FrameTimeBenchSummary(runs: runs.filter { $0.device == device && $0.scenario == scenario }.reversed())
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decoded(_ data: Data) -> FrameTimeBenchResults {
        (try? JSONDecoder().decode(FrameTimeBenchResults.self, from: data)) ?? FrameTimeBenchResults()
    }

    /// Every scenario run on `device`, in ``FrameTimeBench/scenarios``'
    /// order, or `nil` with none.
    public func reportText(on device: String, in language: DisplayLanguage) -> String? {
        let summaries = FrameTimeBench.scenarios.map { ($0, summary(of: $0, on: device)) }.filter { !$0.1.runs.isEmpty }
        guard !summaries.isEmpty else { return nil }
        var lines = [language.text("Screen pace test on \(device):", "畫面節奏測試（\(device)）：")]
        for (scenario, summary) in summaries {
            lines += summary.lines(of: scenario, in: language)
        }
        return lines.joined(separator: "\n")
    }
}
