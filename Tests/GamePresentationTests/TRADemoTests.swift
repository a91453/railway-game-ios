import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The TRA demo (ARCHITECTURE decision 240): the Yilan Line from Toucheng
/// to Su'aoxin built as the game's own double track on its real alignment,
/// with a weekday's real trains running on eight lines, built as the
/// high-speed demo is.
final class TRADemoTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func railways() throws -> RealRailways {
        func file(_ name: String) throws -> Data {
            try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)"))
        }
        return try RealRailways(
            lines: file("track_lines.geojson"), stations: file("track_stations.geojson"), names: file("station_names.json"),
            operations: RealRailwayOperations(systems: [:], timetables: [:], schedules: [TRADemo.schedule: file("tra-yilan-schedule.json")]),
            structures: RealRailStructures(data: file("rail_structures.json"))
        )
    }

    /// The app's heights (decision 279: the demo is laid over them).
    static let heights = try? HeightGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_heights.dat")))

    static let metre = Double(WorldCoordinate.unitsPerMetre)

    /// The layout as the game builds it, over the app's heights, built on
    /// a world with what it costs on top of a new game's money, and not
    /// run.
    static let built: Result<(layout: HighSpeedDemo.Layout, world: GameWorld, tracks: HighSpeedDemoTests.Tracks), Error> = Result {
        let layout = try HighSpeedDemo.Layout(railways: railways(), spec: TRADemo.spec, heights: XCTUnwrap(heights))
        var world = HighSpeedDemo.newWorld(paying: layout.cost(eventSeed: 1), eventSeed: 1, ground: layout.ground)
        world.setKeepLeft(TRADemo.spec.keepLeft)
        let built = try layout.build(in: &world, language: .english)
        return (layout, world, HighSpeedDemoTests.Tracks(layout: layout, built: built))
    }

    /// The demo as the game opens it.
    static let opened: Result<GameWorld, Error> = Result {
        try TRADemo.make(
            in: .english, railways: railways(), population: HighSpeedDemoTests.population, places: HighSpeedDemoTests.places, heights: XCTUnwrap(heights)
        )
    }

    // MARK: - The track and the stations

    /// The ten stations trains call at, north to south, and the depots.
    func testItBuildsTheYilanLinesTenStations() throws {
        let world = try Self.built.get().world
        XCTAssertEqual(
            world.stations.filter { !$0.isDepot }.map(\.name),
            ["Toucheng", "Dingpu", "Jiaoxi", "Sicheng", "Yilan", "Erjie", "Zhongli (Yilan)", "Luodong", "Dongshan", "Su'aoxin"]
        )
        XCTAssertEqual(world.stations.filter(\.isDepot).map(\.name), ["North End Sidings", "Yilan Sidings", "Su'aoxin Sidings"])
    }

    func testItsStationsStandWhereTheRealOnesDo() throws {
        let (layout, world, _) = try Self.built.get()
        for (station, stop) in zip(world.stations.filter { !$0.isDepot }, layout.stops) {
            let east = Double(station.point.x) - stop.point.x
            let south = Double(station.point.y) - stop.point.y
            XCTAssertLessThan((east * east + south * south).squareRoot() / Self.metre, 200, station.name)
        }
    }

    /// Two tracks the length of the real line between the ends' run-ons,
    /// side by side, and every edge accounted for.
    func testItsTrackIsTheRealAlignmentsLength() throws {
        let (layout, world, tracks) = try Self.built.get()
        func length(_ edges: some Sequence<TrackEdgeID>) -> Int64 {
            edges.reduce(0) { $0 + (world.network.edge($1)?.length ?? 0) }
        }
        let track = Double(length(tracks.down))
        XCTAssertEqual(track, layout.plan.path.length, accuracy: layout.plan.path.length * 0.005)
        // Toucheng to Su'aoxin is some 34 km; 3 km more runs north of it
        // and 1.5 km south.
        XCTAssertEqual(track / Self.metre / 1_000, 38.6, accuracy: 1)
        XCTAssertEqual(Double(length(tracks.up)), Double(length(tracks.between)), accuracy: 30 * Self.metre)
        XCTAssertEqual(
            tracks.down.count + tracks.up.count + tracks.downLoops.count + tracks.upLoops.count + tracks.crossovers.count + tracks.sidings.count
                + tracks.ends.count,
            world.network.edges.count
        )
    }

    /// The ends' platform tracks: Toucheng five, Su'aoxin six; four at the
    /// stations between, six at Yilan, where sets turn back and wait.
    func testItsStationsPlatformTracks() throws {
        let world = try Self.built.get().world
        let counts = world.stations.filter { !$0.isDepot }.map { world.network.platforms(of: $0.id).count }
        XCTAssertEqual(counts, [5, 4, 4, 4, 6, 4, 4, 4, 4, 6])
    }

    /// The depots: the North End Sidings beyond Toucheng, the Yilan
    /// Sidings south of Yilan and the Su'aoxin Sidings north of Su'aoxin,
    /// each laid clear of the stations' own tracks; Yilan's and Su'aoxin's
    /// within a few kilometres of the real yards OpenStreetMap has there.
    func testItsDepotsStandWhereTheySay() throws {
        let (layout, world, _) = try Self.built.get()
        XCTAssertEqual(layout.depots.map(\.real.chinese), ["北端留置線", "宜蘭側線", "蘇澳新側線"])
        XCTAssertEqual(layout.depots.map { $0.serving.map { TRADemo.stationNames[$0] } }, [["頭城"], ["宜蘭", "羅東"], ["蘇澳新"]])
        XCTAssertLessThan(layout.depots[0].entry, layout.platforms[0].lowerBound, "beyond Toucheng")
        XCTAssertGreaterThan(min(layout.depots[1].entry, layout.depots[1].deadEnd), layout.platforms[4].upperBound + 500 * Self.metre, "south of Yilan's tracks")
        XCTAssertLessThan(max(layout.depots[2].entry, layout.depots[2].deadEnd), layout.platforms[9].lowerBound - 500 * Self.metre, "north of Su'aoxin's tracks")
        for depot in layout.depots.dropFirst() {
            let point = WorldVector(HighSpeedDemo.frame.worldPosition(latitude: depot.real.latitude, longitude: depot.real.longitude))
            let real = layout.plan.path.project(point)
            let span = min(depot.entry, depot.deadEnd)...max(depot.entry, depot.deadEnd)
            XCTAssertLessThan(max(0, span.lowerBound - real, real - span.upperBound) / Self.metre, 3_500, depot.real.english)
        }
        let depots = world.stations.filter(\.isDepot).map(\.id)
        for line in world.lines {
            XCTAssertEqual(line.depots, depots, line.name)
        }
    }

    // MARK: - The lines and their sets

    /// Eight lines, one for each kind of train and stopping pattern, with
    /// the weekday's 142 trains as runs and the positioning runs that
    /// bring each line's day back to where it began.
    func testItsLinesAreTheRealWeekdaysTrains() throws {
        let (layout, world, _) = try Self.built.get()
        XCTAssertEqual(world.lines.map(\.name), TRADemo.kinds.map(\.english))
        let ids = world.stations.map(\.id)
        XCTAssertEqual(world.lines.map { $0.stops.map { ids.firstIndex(of: $0)! } }, TRADemo.kinds.map(\.stops))
        for (line, planned) in zip(world.lines, layout.timetable.lines) {
            XCTAssertTrue(line.patterns.isEmpty, "a line with runs has no stopping patterns (decision 133)")
            XCTAssertFalse(line.isHighSpeed, line.name)
            XCTAssertEqual(line.runs, planned.runs)
        }
        XCTAssertEqual(layout.timetable.lines.reduce(0) { $0 + $1.runs.count - $1.positioning }, 142, "every train of the weekday")
        // A local express that turns back between the ends runs as a local
        // (decision 240): the local express line runs end to end.
        let localExpress = layout.timetable.lines[1]
        XCTAssertTrue(localExpress.runs.allSatisfy { Set([$0.from, $0.to]) == [0, localExpress.stops.count - 1] })
        XCTAssertFalse(world.isTrafficControlEnabled, "as in the high-speed demo (decision 228)")
        XCTAssertTrue(world.keepLeft, "the TRA's trains keep left (decision 202)")
    }

    func testEachLinesDayEndsWhereItBegan() throws {
        let timetable = try Self.built.get().layout.timetable
        for line in timetable.lines {
            var change = [Int: Int]()
            for run in line.runs {
                change[line.stops[run.from], default: 0] -= 1
                change[line.stops[run.to], default: 0] += 1
            }
            XCTAssertTrue(change.values.allSatisfy { $0 == 0 }, "\(line.english): \(change)")
        }
    }

    /// Each line's sets are its model's: the locals' and local expresses'
    /// EMU800s, the EMU3000s, the Puyumas, the Tarokos and push-pull sets
    /// for the other expresses.
    func testItsSetsAreTheRealModels() throws {
        let (layout, world, _) = try Self.built.get()
        XCTAssertEqual(world.trains.count, layout.sets)
        for (line, kind) in zip(world.lines, TRADemo.kinds) {
            XCTAssertFalse(line.trains.isEmpty, line.name)
            XCTAssertEqual(line.performance, kind.performance, line.name)
            for id in line.trains {
                let train = try XCTUnwrap(world.train(id: id))
                XCTAssertEqual(train.type, kind.type, train.name)
                XCTAssertEqual(train.cars, kind.cars, train.name)
                XCTAssertEqual(train.performance, kind.performance, train.name)
                XCTAssertTrue(train.name.hasPrefix(kind.set.english), train.name)
            }
        }
    }

    /// At midnight every set stands in a depot, on a siding of its own.
    func testEverySetStandsInADepotAtMidnight() throws {
        let world = try Self.built.get().world
        var edges: Set<TrackEdgeID> = []
        for train in world.trains {
            XCTAssertTrue(world.standsInADepot(train), train.name)
            guard case .onEdge(let traversal, _)? = train.position else { XCTFail("\(train.name) is not on the track"); continue }
            XCTAssertTrue(edges.insert(traversal.edge).inserted, "\(train.name): a siding of its own")
        }
    }

    func testItIsPaidForBeforeItStarts() throws {
        let world = try Self.built.get().world
        XCTAssertEqual(world.economy.balance, GameWorld.startingBalance)
    }

    func testItSavesAndLoads() throws {
        let world = try Self.opened.get()
        let loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
        XCTAssertEqual(loaded, world)
    }

    // MARK: - The game as it opens

    /// At 07:00 every run due by then has sent its set out.
    func testItOpensAtSevenWithTheSetsOnTheirWay() throws {
        let world = try Self.opened.get()
        XCTAssertEqual(world.clock.now.minute, 7 * 60)
        XCTAssertEqual(world.clock.speed, .normal)
        for line in world.lines {
            for (index, run) in line.runs.enumerated() where run.times[0].departure <= 7 * 3_600 - LineRun.latestDispatch {
                XCTAssertEqual(line.runDays[index], 0, "\(line.name): the run leaving at \(run.times[0].departure / 60) min has gone")
            }
        }
        XCTAssertGreaterThan(world.trains.count { $0.execution != nil }, 5, "sets on their way")
    }

    /// Decision 219: the stations ring the chime of what calls there:
    /// the interchanges where expresses call ring the metro chime, the
    /// small stations the local one.
    func testItsStationsRingTheirChimes() throws {
        let world = try Self.built.get().world
        let chimes = world.stations.filter { !$0.isDepot }.map { StationChime.of($0.id, in: world) }
        XCTAssertEqual(chimes, [.metro, .local, .metro, .local, .metro, .local, .local, .metro, .metro, .metro])
    }

    // MARK: - The game launcher

    @MainActor
    func testTheLauncherBuildsAndOpensIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TRADemoTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let railways = try Self.railways()
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        let task = launcher.openTRADemo(railways: railways)
        XCTAssertNil(launcher.openTRADemo(railways: railways), "one build at a time")
        // Nor the other demo meanwhile: the one tapped first would open,
        // or the other, whichever is built first.
        XCTAssertNil(launcher.openHighSpeedDemo(railways: railways), "one demo at a time")
        XCTAssertFalse(launcher.isOpeningHighSpeedDemo)
        XCTAssertTrue(launcher.isOpeningTRADemo)
        XCTAssertNil(launcher.session, "still on the start screen")
        await task?.value
        XCTAssertFalse(launcher.isOpeningTRADemo)
        XCTAssertEqual(launcher.session?.world.stations.count, 13, "the game is open: ten stations and three depots")
    }

    // MARK: - Over the ground (decision 279)

    /// Laid over the app's ground, as the real line is: up on its long
    /// viaducts (south of Yilan towards Erjie, and through Dongshan, whose
    /// station stands on its viaduct), on the ground elsewhere; Yilan's and
    /// Luodong's platforms on the ground. The game's ground is coarser than
    /// the real line's, so not every metre: the shares measured when it was
    /// made, less a margin.
    func testItsTrackFollowsTheRealStructures() throws {
        let (layout, world, tracks) = try Self.built.get()
        XCTAssertTrue(world.ground.isMapped)
        XCTAssertTrue(world.network.edges.allSatisfy { $0.structure == .automatic })
        // The down track's kind every 8 m, by where it is.
        var built: [(point: WorldVector, kind: TrackSectionKind)] = []
        for id in tracks.down {
            let edge = try XCTUnwrap(world.network.edge(id)), geometry = try XCTUnwrap(world.trackGeometry(of: id))
            for span in edge.sectionSpans where span.end > span.start {
                for point in geometry.points(from: span.start, to: span.end) {
                    built.append((WorldVector(x: Double(point.x), y: Double(point.y)), span.kind))
                }
            }
        }
        let path = layout.plan.path
        let structures = try XCTUnwrap(Self.railways().structures)
        let carried = structures.stretches(along: path, frame: HighSpeedDemo.frame, system: "tra_sched")
        var viaduct = (up: 0, all: 0), ground = (off: 0, all: 0)
        for distance in stride(from: 0, through: path.length, by: 64 * Self.metre) {
            let point = path.point(at: distance)
            guard let kind = built.min(by: { ($0.point - point).length < ($1.point - point).length })?.kind else { continue }
            if carried.contains(where: {
                $0.kind == .bridge && $0.range.upperBound - $0.range.lowerBound >= TrackRise.shortestCarried
                    && ($0.range.lowerBound + TrackRise.carriedInset...$0.range.upperBound - TrackRise.carriedInset).contains(distance)
            }) {
                viaduct.all += 1
                viaduct.up += [.viaduct, .bridge].contains(kind) ? 1 : 0
            } else if !carried.contains(where: { ($0.range.lowerBound - 200 * Self.metre...$0.range.upperBound + 200 * Self.metre).contains(distance) }) {
                ground.all += 1
                ground.off += [.viaduct, .tunnel].contains(kind) ? 1 : 0
            }
        }
        // Measured (decision 279): 123 of 123 samples on the real long
        // viaducts up on one, none of 357 on the real ground up on a
        // viaduct or down in a tunnel.
        XCTAssertGreaterThan(viaduct.all, 100)
        XCTAssertGreaterThanOrEqual(Double(viaduct.up), 0.95 * Double(viaduct.all), "\(viaduct)")
        XCTAssertGreaterThan(ground.all, 300)
        XCTAssertLessThanOrEqual(Double(ground.off), 0.01 * Double(ground.all), "\(ground)")
        // Dongshan's platforms up on its viaduct, Yilan's and Luodong's on
        // the ground.
        for (index, raised) in [(4, false), (7, false), (8, true)] {
            let name = layout.stops[index].station.name(in: .english)
            let station = try XCTUnwrap(world.stations.first { $0.name == name })
            for platform in world.trackPlatforms(of: station.id) {
                let edge = try XCTUnwrap(world.network.edge(platform.edge)), geometry = try XCTUnwrap(world.trackGeometry(of: platform.edge))
                let middle = (platform.start + platform.end) / 2
                let rail = geometry.height(at: middle)
                let under = try XCTUnwrap(world.groundHeight(at: geometry.location(at: middle).position.plan))
                let kind = try XCTUnwrap(edge.sectionSpans.first { $0.start <= middle && middle <= $0.end }).kind
                if raised {
                    XCTAssertEqual(kind, .viaduct, name)
                    XCTAssertGreaterThan(rail - under, TrackSectionRules.highestFill, "\(name) stands \((rail - under) / 64) m up")
                } else {
                    XCTAssertFalse([.viaduct, .tunnel].contains(kind), name)
                    XCTAssertLessThanOrEqual(abs(rail - under), TrackSectionRules.level, "\(name) stands \((rail - under) / 64) m off the ground")
                }
            }
        }
    }

    // MARK: - The map (decision 249)

    /// The owner, 2026-10-16, of the TRA demo's double track near the
    /// Lanyang Bridge: "明明是雙線，但快車跟慢車一起顯示好擠，也看不出來是
    /// 單線或雙線". Away from the stations, each track's lines are drawn off
    /// it on the side away from the other track, so the two tracks' lines
    /// stand apart with the two beds between them; each track's lines span
    /// at most ``LineMap/sharedWidth`` (eight lines, half a width each, 4);
    /// and its arrows are drawn once, on the track, clear of every line.
    func testADoubleTracksTwoWaysStandApartOnTheTRADemo() throws {
        let world = try Self.built.get().world
        XCTAssertEqual(world.lines.count, 8)
        let map = LineMap(world: world)
        let platformEdges = Set(world.network.platforms.map(\.edge))
        let byEdge = Dictionary(grouping: map.stretches, by: \.edge)
        // Each way's lines together are at most 4 widths wide, and those
        // ridden one way are off the track on the left of their way.
        for stretches in byEdge.values {
            for stretch in stretches {
                let over = stretches.filter { $0.start < stretch.end && stretch.start < $0.end }
                for side in [1.0, -1.0] {
                    let span = over.filter { $0.offset * side > 0 && $0.way != .both }.map(\.width).reduce(0, +)
                    XCTAssertLessThanOrEqual(span, LineMap.widestShared + 1e-9, "\(stretch.edge): \(over.count) lines")
                }
                guard stretch.way != .both else { continue }
                XCTAssertGreaterThanOrEqual(abs(stretch.offset) - stretch.width / 2, LineMap.trackClearance - 1e-9, "\(stretch)")
                XCTAssertEqual(stretch.offset > 0, stretch.way == .forward, "\(stretch)")
            }
        }
        // Away from the stations, the other track nearby, ridden the other
        // way, lies on the side away from the lines.
        let metre = Double(WorldCoordinate.unitsPerMetre)
        var geometries: [TrackEdgeID: TrackGeometry] = [:]
        for arrow in map.oneWay { geometries[arrow.edge] = world.trackGeometry(of: arrow.edge) }
        func travel(_ arrow: LineMap.OneWay, _ geometry: TrackGeometry) -> (x: Double, y: Double) {
            let first = geometry.points[0], last = geometry.points[geometry.points.count - 1]
            let sign = arrow.way == .forward ? 1.0 : -1.0
            return (Double(last.x - first.x) * sign, Double(last.y - first.y) * sign)
        }
        var checked = 0
        for arrow in map.oneWay where !platformEdges.contains(arrow.edge) {
            guard let geometry = geometries[arrow.edge] else { continue }
            let location = geometry.location(at: (arrow.start + arrow.end) / 2)
            let here = (x: Double(location.position.x), y: Double(location.position.y))
            let way = travel(arrow, geometry)
            let length = (way.x * way.x + way.y * way.y).squareRoot()
            // The lines' side: the left of the way they are ridden.
            let left = (x: way.y / length, y: -way.x / length)
            for other in map.oneWay where other.edge != arrow.edge {
                guard let otherGeometry = geometries[other.edge] else { continue }
                let otherWay = travel(other, otherGeometry)
                guard otherWay.x * way.x + otherWay.y * way.y < 0 else { continue }
                for point in otherGeometry.points {
                    let x = Double(point.x) - here.x, y = Double(point.y) - here.y
                    guard x * x + y * y < 144 * metre * metre else { continue }
                    XCTAssertLessThanOrEqual(x * left.x + y * left.y, 0.5 * metre, "\(arrow): its lines lie over \(other.edge), the other track")
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 0, "the demo has double track away from its stations")
        // Arrows: on the track, once, clear of the lines.
        XCTAssertFalse(map.oneWay.isEmpty)
        XCTAssertLessThan(LineMap.arrowSize * 0.95, LineMap.trackClearance, "an arrow spans less than the clearance either side")
        for arrow in map.oneWay {
            let over = map.stretches.filter { $0.edge == arrow.edge && $0.start < arrow.end && arrow.start < $0.end }
            XCTAssertFalse(over.isEmpty)
            XCTAssertTrue(over.allSatisfy { $0.way == arrow.way }, "\(arrow)")
            XCTAssertTrue(over.allSatisfy { abs($0.offset) - $0.width / 2 >= LineMap.trackClearance - 1e-9 }, "\(arrow)")
        }
    }
}
