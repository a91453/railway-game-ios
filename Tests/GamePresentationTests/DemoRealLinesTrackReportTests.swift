import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 401's sequel: how true the track the demo lays (decision 351)
/// is to the real lines. At a real station the real lines in view are
/// laid, then each line's centre line, from its first station in view to
/// its last, is walked every 20 m: where no track runs along it (a gap),
/// where only one does on a double line (single track), and how far the
/// nearest track lies from it.
@MainActor
final class DemoRealLinesTrackReportTests: XCTestCase {
    nonisolated static let metre = Double(WorldCoordinate.unitsPerMetre)

    /// What the walk along one route found.
    struct Measure {
        let route: DemoRealLines.Route
        /// Each stretch with no track, its start and end along the route
        /// in metres; only those longer than 60 m.
        var gaps: [ClosedRange<Double>] = []
        /// Each stretch with one track only, its start and end in metres;
        /// only those longer than 200 m.
        var singles: [ClosedRange<Double>] = []
        var samples = 0
        var single = 0
        var offsets: [Double] = []
        /// Its stations with no station of the game there.
        var missed: [String] = []

        var singleShare: Double { samples == 0 ? 0 : Double(single) / Double(samples) }
        var deviation95: Double {
            let sorted = offsets.sorted()
            return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        }
        func stations(at range: ClosedRange<Double>) -> String {
            let before = route.stops.last { $0.along <= range.lowerBound * DemoRealLinesTrackReportTests.metre }?.chinese ?? "…"
            let after = route.stops.first { $0.along >= range.upperBound * DemoRealLinesTrackReportTests.metre }?.chinese ?? "…"
            return "\(before)–\(after)"
        }
    }

    /// A demo game at `station` of `system` over its real ground with
    /// unlimited funds, and the view `half` metres each way round it.
    static func game(at station: String, in system: String, half: Double = 6_000) throws -> (session: GameSession, view: WorldRegion) {
        let real = try BundledRealData.station(station, in: system)
        var world = GameWorld.newGame(anchor: try XCTUnwrap(real.anchor))
        try world.mapGround()
        world.setUnlimitedFunds(true)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.heights = try HeightGrid(
            data: Data(contentsOf: BundledRealData.directory.deletingLastPathComponent().appendingPathComponent("RealWorld/taiwan_heights.dat"))
        )
        session.railways = try BundledRealData.railways()
        session.news.isDemo = true
        let centre = try BundledRealData.point(real.coordinate, in: world)
        let x = Double(centre.x), y = Double(centre.y), reach = half * metre
        return (session, WorldRegion(minX: x - reach, minY: y - reach, maxX: x + reach, maxY: y + reach))
    }

    /// The routes the demo plans in `view`.
    static func routes(in session: GameSession, view: WorldRegion) throws -> [DemoRealLines.Route] {
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        return DemoRealLines.plan(
            railways: try XCTUnwrap(session.railways), frame: frame, bounds: session.world.bounds, view: view,
            carLength: session.world.platformCarLength
        ).routes
    }

    /// Walks each of `routes` along the track `world` has.
    static func measure(_ routes: [DemoRealLines.Route], in world: GameWorld) -> [Measure] {
        // Every edge's drawn polyline, in cells of 50 m.
        let cell = 50 * metre
        var segments: [(a: WorldVector, b: WorldVector)] = []
        var grid: [Int64: [Int]] = [:]
        func key(_ x: Double, _ y: Double) -> Int64 { Int64((x / cell).rounded(.down)) &* 1_000_003 &+ Int64((y / cell).rounded(.down)) }
        for edge in world.network.edges {
            guard let geometry = world.trackGeometry(of: edge.id) else { continue }
            for index in geometry.points.indices.dropLast() {
                let a = WorldVector(geometry.points[index].plan), b = WorldVector(geometry.points[index + 1].plan)
                let id = segments.count
                segments.append((a, b))
                var seen: Set<Int64> = []
                for t in stride(from: 0.0, through: 1.0, by: 0.1) {
                    let p = a + (b - a) * t
                    let k = key(p.x, p.y)
                    if seen.insert(k).inserted { grid[k, default: []].append(id) }
                }
            }
        }
        var measures: [Measure] = []
        for route in routes {
            var measure = Measure(route: route)
            guard let first = route.stops.first, let last = route.stops.last else { continue }
            let path = route.path
            let step = 20 * metre
            var gapStart: Double?, singleStart: Double?
            var along = first.platform.lowerBound
            let double = DemoRealLines.isDouble(system: route.system.id)
            while along <= last.platform.upperBound {
                let centre = path.point(at: along), tangent = path.tangent(at: along)
                let normal = WorldVector(x: -tangent.y, y: tangent.x)
                // The lateral offsets of the track running along here.
                var lateral: [Double] = []
                let cx = Int64((centre.x / cell).rounded(.down)), cy = Int64((centre.y / cell).rounded(.down))
                var candidates: Set<Int> = []
                for dx in -1...1 {
                    for dy in -1...1 { grid[(cx + Int64(dx)) &* 1_000_003 &+ (cy + Int64(dy))].map { candidates.formUnion($0) } }
                }
                for id in candidates {
                    let (a, b) = segments[id]
                    let d = b - a
                    let span = d.x * d.x + d.y * d.y
                    guard span > 0 else { continue }
                    let direction = d * (1 / span.squareRoot())
                    guard abs(direction.x * tangent.x + direction.y * tangent.y) > 0.9 else { continue }
                    let t = min(1, max(0, ((centre - a).x * d.x + (centre - a).y * d.y) / span))
                    let near = a + d * t - centre
                    guard near.length <= 12 * metre else { continue }
                    lateral.append(near.x * normal.x + near.y * normal.y)
                }
                // Tracks: offsets more than 2 m apart.
                lateral.sort()
                var tracks: [Double] = []
                for offset in lateral where tracks.last.map({ offset - $0 > 2 * metre }) ?? true { tracks.append(offset) }
                let here = along / metre
                if tracks.isEmpty {
                    if gapStart == nil { gapStart = here }
                } else {
                    if let start = gapStart, here - start > 60 { measure.gaps.append(start...here) }
                    gapStart = nil
                    measure.offsets.append(tracks.map(abs).min()! / metre)
                }
                measure.samples += 1
                if double && tracks.count == 1 {
                    measure.single += 1
                    if singleStart == nil { singleStart = here }
                } else {
                    if let start = singleStart, here - start > 200 { measure.singles.append(start...here) }
                    singleStart = nil
                }
                along += step
            }
            let end = last.platform.upperBound / metre
            if let start = gapStart, end - start > 60 { measure.gaps.append(start...end) }
            if let start = singleStart, end - start > 200 { measure.singles.append(start...end) }
            for stop in route.stops {
                let point = path.point(at: stop.along)
                if !world.stations.contains(where: { $0.name == stop.chinese && (WorldVector($0.location) - point).length <= 450 * metre }) {
                    measure.missed.append(stop.chinese)
                }
            }
            measures.append(measure)
        }
        return measures
    }

    /// A line of the report, on standard error: unbuffered, so none is
    /// lost when the tests end.
    static func report(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    /// The places the report lays the demo at (decision 401's twelve).
    static let places: [(station: String, system: String)] = [
        ("臺北", "tra_sched"), ("板橋", "tra_sched"), ("竹南", "tra_sched"), ("新竹", "tra_sched"),
        ("臺中", "tra_sched"), ("嘉義", "tra_sched"), ("新左營", "tra_sched"), ("高雄", "tra_sched"),
        ("牡丹", "tra_sched"), ("花蓮", "tra_sched"), ("大直", "mrt"), ("夢時代", "krtc"),
    ]

    /// The report: `DEMO_TRACK_REPORT=1 swift test --skip-build --filter
    /// DemoRealLinesTrackReportTests`; `DEMO_TRACK_REPORT=臺北,竹南` for
    /// some of the places only.
    func testReport() async throws {
        guard let wanted = ProcessInfo.processInfo.environment["DEMO_TRACK_REPORT"] else {
            throw XCTSkip("DEMO_TRACK_REPORT not set")
        }
        let names = Set(wanted.split(separator: ",").map(String.init))
        for place in Self.places where wanted == "1" || names.contains(place.station) {
            let (session, view) = try Self.game(at: place.station, in: place.system)
            let routes = try Self.routes(in: session, view: view)
            let started = Date()
            let outcome = await session.layDemoRealLines(in: view)
            Self.report("== \(place.station): \(outcome.map { "\($0.lines) lines, \($0.stations) stations, \($0.missed) missed" } ?? "nothing") in \(Int(Date().timeIntervalSince(started))) s")
            for measure in Self.measure(routes, in: session.world) {
                let gaps = measure.gaps.map { "\(Int($0.upperBound - $0.lowerBound)) m \(measure.stations(at: $0))" }
                let singles = measure.singles.map { "\(Int($0.upperBound - $0.lowerBound)) m \(measure.stations(at: $0))" }
                Self.report("  \(measure.route.lineKey) \(measure.route.stops.first!.chinese)–\(measure.route.stops.last!.chinese): single \(Int((measure.singleShare * 100).rounded()))%, p95 \(String(format: "%.1f", measure.deviation95)) m, gaps \(gaps), singles \(singles), missed \(measure.missed)")
            }
        }
    }
}
