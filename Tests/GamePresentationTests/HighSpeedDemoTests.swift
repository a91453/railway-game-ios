import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The high-speed demo (ARCHITECTURE decision 170, the author's idea of
/// 2026-10-11): the real Taiwan High Speed Rail built as the game's own
/// track on its real alignment, with its twelve stations and three stopping
/// patterns running at once.
final class HighSpeedDemoTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func railways() throws -> RealRailways {
        func file(_ name: String) throws -> Data {
            try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)"))
        }
        let schedule = try file("thsr-schedule.json")
        return try RealRailways(
            lines: file("track_lines.geojson"), stations: file("track_stations.geojson"), names: file("station_names.json"),
            operations: RealRailwayOperations(systems: [:], timetables: [:], schedules: ["thsr": schedule]),
            structures: RealRailStructures(data: file("rail_structures.json"))
        )
    }

    /// The app's heights (decision 281: the demo is laid over them).
    static let heights = try? HeightGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_heights.dat")))

    static let population = try? PopulationGrid(
        data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json"))
    )

    static let places = try? PlaceGrid(
        data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_places.json"))
    )

    static let metre = Double(WorldCoordinate.unitsPerMetre)

    /// The layout as the game builds it, over the app's heights (decision
    /// 281), then built on a world with just what it costs on top of a new
    /// game's money, and not run: the tracks, the stations and the sets as
    /// they stand at midnight. Built once for every test that needs it: it
    /// takes two or three minutes in a debug build.
    static let built: Result<(layout: HighSpeedDemo.Layout, world: GameWorld, tracks: Tracks), Error> = Result {
        let layout = try HighSpeedDemo.Layout(railways: railways(), heights: XCTUnwrap(heights))
        var world = HighSpeedDemo.newWorld(paying: layout.cost(eventSeed: 1), eventSeed: 1, ground: layout.ground)
        let built = try layout.build(in: &world, language: .english)
        return (layout, world, Tracks(layout: layout, built: built))
    }

    /// The tracks' edges, as built (the demo's game builds the same).
    struct Tracks {
        let down: [TrackEdgeID]
        let upInOrder: [TrackEdgeID]
        let up: Set<TrackEdgeID>
        /// The down track's edges between the two turnouts, where only
        /// southbound sets run: beyond them are the ends' platforms, where
        /// the sets turn back.
        let between: Set<TrackEdgeID>
        /// Every loop beside the down track and the up track, the second
        /// loops too.
        let downLoops: Set<TrackEdgeID>
        let upLoops: Set<TrackEdgeID>
        let crossovers: Set<TrackEdgeID>
        /// The depots' sidings (decision 221).
        let sidings: Set<TrackEdgeID>
        /// The ends' tracks beside the down track (decision 228).
        let ends: Set<TrackEdgeID>
        /// Each station's loops, both ways', by its index.
        let loopsOf: [Int: Set<TrackEdgeID>]
        /// The track run both ways: at the stations where sets turn back,
        /// everything from one crossover to the other (decision 197); the
        /// depots' sidings, and the track between each depot and the
        /// stations it serves, which the sets run into and out of it either
        /// way (decision 221).
        let bothWays: Set<TrackEdgeID>

        init(layout: HighSpeedDemo.Layout, built: HighSpeedDemo.Built) {
            down = built.down.edges
            upInOrder = built.up.edges
            up = Set(built.up.edges)
            let distances = layout.plan.distances
            between = Set(down.indices.filter {
                distances[$0] >= layout.junctions.north - 1 && distances[$0 + 1] <= layout.junctions.south + 1
            }.map { built.down.edges[$0] })
            downLoops = Set((built.loops + built.outerLoops).flatMap(\.down.edges))
            upLoops = Set((built.loops + built.outerLoops).flatMap(\.up.edges))
            crossovers = Set(built.crossovers)
            sidings = Set(built.sidings.flatMap(\.edges))
            ends = Set(built.ends.flatMap(\.edges))
            var loopsOf: [Int: Set<TrackEdgeID>] = [:]
            for (station, loop) in zip(layout.loops.keys.sorted(), built.loops) { loopsOf[station, default: []].formUnion(loop.down.edges + loop.up.edges) }
            for (station, loop) in zip(layout.outerLoops.keys.sorted(), built.outerLoops) { loopsOf[station, default: []].formUnion(loop.down.edges + loop.up.edges) }
            self.loopsOf = loopsOf
            var bothWays = crossovers.union(sidings)
            var reaches = Array(layout.turnbackReach.values)
            // Not along the down track to a depot with its own lead
            // (Zuoying's, decision 281): the sets reach it from the end's
            // throat, beyond the turnout.
            for depot in layout.depots where depot.lead == nil {
                for station in depot.serving {
                    let zone = layout.platforms[station]
                    let near = depot.entry < zone.lowerBound ? zone.lowerBound : zone.upperBound
                    reaches.append(min(near, depot.entry)...max(near, depot.entry))
                }
            }
            for reach in reaches {
                func within(_ track: RealWorldDemo.Track) -> [TrackEdgeID] {
                    let d = track.plan.distances
                    return track.edges.indices.filter { reach.contains(d[$0]) && reach.contains(d[$0 + 1]) }.map { track.edges[$0] }
                }
                bothWays.formUnion(within(built.down))
                bothWays.formUnion(within(built.up))
                for loop in built.loops + built.outerLoops {
                    bothWays.formUnion(within(loop.down))
                    bothWays.formUnion(within(loop.up))
                }
            }
            self.bothWays = bothWays
        }

        /// The edges only southbound sets run on, and only northbound.
        var southbound: Set<TrackEdgeID> { between.union(downLoops).subtracting(bothWays) }
        var northbound: Set<TrackEdgeID> { up.union(upLoops).subtracting(bothWays) }

        /// Whether a set travelling `traversal` runs against its track: on
        /// a southbound edge northbound or the other way round (every edge
        /// runs north to south).
        func isAgainst(_ traversal: TrackTraversal) -> Bool {
            (southbound.contains(traversal.edge) && traversal.direction == .backward)
                || (northbound.contains(traversal.edge) && traversal.direction == .forward)
        }
    }

    /// The demo as the game opens it, with the people round its stations.
    static let opened: Result<GameWorld, Error> = Result {
        try HighSpeedDemo.make(in: .english, railways: railways(), population: population, places: places, heights: XCTUnwrap(heights))
    }

    // MARK: - The track and the stations

    func testItBuildsTheRealHighSpeedRailsTwelveStations() throws {
        let world = try Self.built.get().world
        XCTAssertEqual(
            world.stations.filter { !$0.isDepot }.map(\.name),
            ["Nangang", "Taipei", "Banqiao", "Taoyuan", "Hsinchu", "Miaoli", "Taichung", "Changhua", "Yunlin", "Chiayi", "Tainan", "Zuoying"]
        )
        XCTAssertEqual(world.stations.filter(\.isDepot).map(\.name), ["Nangang Depot", "Wuri Depot", "Zuoying Depot"])
    }

    /// Decision 221: the depots stand where OpenStreetMap has the real
    /// ones along the line (`tools/hsr-depots/hsr_depots.json`), on their
    /// side of it: Nangang's beyond its station, Wuri's south of Taichung,
    /// Zuoying's north of its station, the sidings within a kilometre
    /// either way of the real yard's middle along the line; each a siding
    /// for each set that stands there on the first night and one to spare,
    /// every line keeping its sets in all three.
    func testItsDepotsStandWhereTheRealOnesDo() throws {
        let (layout, world, _) = try Self.built.get()
        XCTAssertEqual(layout.depots.map(\.real.chinese), ["南港機廠", "烏日機廠", "左營機廠"])
        let names = layout.depots.map { $0.serving.map { HighSpeedDemo.stationNames[$0] } }
        XCTAssertEqual(names, [["南港", "台北"], ["台中"], ["左營"]])
        XCTAssertLessThan(layout.depots[0].entry, layout.platforms[0].lowerBound, "beyond Nangang's platform")
        XCTAssertGreaterThan(layout.depots[1].entry, layout.platforms[6].upperBound, "south of Taichung")
        XCTAssertLessThan(layout.depots[2].entry, layout.platforms[11].lowerBound, "north of Zuoying")
        for depot in layout.depots {
            let point = WorldVector(HighSpeedDemo.frame.worldPosition(latitude: depot.real.latitude, longitude: depot.real.longitude))
            let real = layout.plan.path.project(point)
            let span = min(depot.entry, depot.deadEnd)...max(depot.entry, depot.deadEnd)
            XCTAssertLessThan(max(0, span.lowerBound - real, real - span.upperBound) / Self.metre, 1_000, depot.real.english)
        }
        XCTAssertEqual(layout.depots.map { $0.east.count + $0.west.count }, [11, 7, 20], "10, 6 and 19 sets, and one to spare")
        let depots = world.stations.filter(\.isDepot).map(\.id)
        for line in world.lines {
            XCTAssertEqual(line.depots, depots, line.name)
        }
        for (depot, count) in zip(depots, [11, 7, 20]) {
            XCTAssertEqual(world.network.platforms(of: depot).count, count, "a platform on each siding")
        }
    }

    /// Decision 281: Zuoying's depot has its own track from the south
    /// end's throat, beside the down track on its east, so its sets never
    /// run against the trains coming in along the down track: its sidings
    /// and its lead meet the down track at one node only, the lead's
    /// turnout beyond the up track's.
    func testZuoyingsDepotHasItsOwnTrack() throws {
        let (layout, world, tracks) = try Self.built.get()
        XCTAssertNil(layout.depots[0].lead, "Nangang's")
        XCTAssertNil(layout.depots[1].lead, "Wuri's")
        let lead = try XCTUnwrap(layout.depots[2].lead, "Zuoying's")
        let turnout = lead.distances[lead.distances.count - 1]
        XCTAssertGreaterThan(turnout, layout.junctions.south, "beyond the up track's turnout")
        XCTAssertLessThan(turnout, layout.platforms[11].lowerBound, "in the throat, north of the platforms")
        XCTAssertEqual(lead.distances[0], layout.depots[2].entry, accuracy: 1, "on to where the sidings begin")
        // Every node of Zuoying's depot's tracks the down track has.
        let downNodes = Set(tracks.down.flatMap { id in world.network.edge(id).map { [$0.from, $0.to] } ?? [] })
        let edges = Self.zuoyingDepotEdges(layout: layout, world: world, tracks: tracks)
        let shared = Set(edges.flatMap { id in world.network.edge(id).map { [$0.from, $0.to] } ?? [] }).intersection(downNodes)
        XCTAssertEqual(shared.count, 1, "the lead's turnout only")
        // The down track from the depot to the end's turnout is run only
        // southbound: the sets no longer run north along it into the depot.
        let distances = layout.plan.distances
        let approach = tracks.down.indices.filter {
            distances[$0] >= layout.depots[2].entry - 1 && distances[$0 + 1] <= layout.junctions.south + 1
        }.map { tracks.down[$0] }
        XCTAssertFalse(approach.isEmpty)
        XCTAssertTrue(Set(approach).isSubset(of: tracks.southbound), "only southbound from the depot to the turnout")
    }

    /// The edges of Zuoying's depot's sidings and lead: the depots' track
    /// joined to its platforms' sidings.
    private static func zuoyingDepotEdges(layout: HighSpeedDemo.Layout, world: GameWorld, tracks: Tracks) -> Set<TrackEdgeID> {
        let depot = world.stations.filter(\.isDepot)[2].id
        var edges: Set<TrackEdgeID> = [], frontier = Set(world.network.platforms(of: depot).map(\.edge))
        while let id = frontier.popFirst() {
            guard edges.insert(id).inserted, let edge = world.network.edge(id) else { continue }
            for other in tracks.sidings where !edges.contains(other) {
                guard let next = world.network.edge(other), !Set([next.from, next.to]).isDisjoint(with: [edge.from, edge.to]) else { continue }
                frontier.insert(other)
            }
        }
        return edges
    }

    func testItsStationsStandWhereTheRealOnesDo() throws {
        let (layout, world, _) = try Self.built.get()
        for (station, stop) in zip(world.stations.filter { !$0.isDepot }, layout.stops) {
            let east = Double(station.point.x) - stop.point.x
            let south = Double(station.point.y) - stop.point.y
            // The platform is on the track, which passes the real station
            // within a few hundred metres.
            XCTAssertLessThan((east * east + south * south).squareRoot() / Self.metre, 500, station.name)
        }
    }

    /// Decision 281: laid over the app's heights at the heights the real
    /// line's structures ask for (`rail_structures.json`, the High Speed
    /// Rail's): up on the real viaducts, down in the real tunnels, and on
    /// the ground away from them; Nangang, Taipei, Banqiao and Taoyuan under
    /// the ground, Hsinchu to Tainan up on the viaduct.
    func testItsTrackFollowsTheRealStructures() throws {
        let (layout, world, tracks) = try Self.built.get()
        XCTAssertTrue(world.ground.isMapped)
        XCTAssertTrue(world.network.edges.allSatisfy { $0.structure == .automatic })
        // The down track's kind every 8 m, by the 256 m square it is in.
        let square = 256 * Self.metre
        func key(_ point: WorldVector) -> [Int] { [Int((point.x / square).rounded(.down)), Int((point.y / square).rounded(.down))] }
        var built: [[Int]: [(point: WorldVector, kind: TrackSectionKind)]] = [:]
        for id in tracks.down {
            let edge = try XCTUnwrap(world.network.edge(id)), geometry = try XCTUnwrap(world.trackGeometry(of: id))
            for span in edge.sectionSpans where span.end > span.start {
                for point in geometry.points(from: span.start, to: span.end) {
                    let vector = WorldVector(x: Double(point.x), y: Double(point.y))
                    built[key(vector), default: []].append((vector, span.kind))
                }
            }
        }
        func kind(at point: WorldVector) -> TrackSectionKind? {
            let (x, y) = (key(point)[0], key(point)[1])
            let near = (x - 1...x + 1).flatMap { i in (y - 1...y + 1).flatMap { j in built[[i, j]] ?? [] } }
            return near.min { ($0.point - point).length < ($1.point - point).length }?.kind
        }
        let path = layout.plan.path
        let carried = try XCTUnwrap(Self.railways().structures).stretches(along: path, frame: HighSpeedDemo.frame, system: "thsr_sched")
        var viaduct = (up: 0, all: 0), tunnel = (down: 0, all: 0), ground = (off: 0, all: 0)
        for distance in stride(from: 0, through: path.length, by: 64 * Self.metre) {
            guard let kind = kind(at: path.point(at: distance)) else { continue }
            let inside = carried.first {
                $0.range.upperBound - $0.range.lowerBound >= TrackRise.shortestCarried
                    && ($0.range.lowerBound + TrackRise.carriedInset...$0.range.upperBound - TrackRise.carriedInset).contains(distance)
            }
            switch inside?.kind {
            case .bridge?:
                viaduct.all += 1
                viaduct.up += [.viaduct, .bridge].contains(kind) ? 1 : 0
            case .tunnel?:
                tunnel.all += 1
                tunnel.down += kind == .tunnel ? 1 : 0
            case nil:
                guard !carried.contains(where: { ($0.range.lowerBound - 200 * Self.metre...$0.range.upperBound + 200 * Self.metre).contains(distance) }) else { continue }
                ground.all += 1
                ground.off += [.viaduct, .tunnel].contains(kind) ? 1 : 0
            }
        }
        // Measured every 256 m (decision 281): 1,059 of 1,081 on the real
        // viaducts up on one, 209 of 229 in the real tunnels down in one,
        // none of 22 on the real ground up or down.
        XCTAssertGreaterThan(viaduct.all, 4_000)
        XCTAssertGreaterThanOrEqual(Double(viaduct.up), 0.95 * Double(viaduct.all), "\(viaduct)")
        XCTAssertGreaterThan(tunnel.all, 800)
        XCTAssertGreaterThanOrEqual(Double(tunnel.down), 0.85 * Double(tunnel.all), "\(tunnel)")
        XCTAssertGreaterThan(ground.all, 50)
        XCTAssertLessThanOrEqual(Double(ground.off), 0.05 * Double(ground.all), "\(ground)")
        // The stations' platforms: the four in the north under the ground,
        // the next seven up on the viaduct.
        for index in 0...10 {
            let name = layout.stops[index].station.name(in: .english)
            let station = try XCTUnwrap(world.stations.first { $0.name == name })
            for platform in world.trackPlatforms(of: station.id) {
                let edge = try XCTUnwrap(world.network.edge(platform.edge)), geometry = try XCTUnwrap(world.trackGeometry(of: platform.edge))
                let middle = (platform.start + platform.end) / 2
                let rail = geometry.height(at: middle)
                let under = try XCTUnwrap(world.groundHeight(at: geometry.location(at: middle).position.plan))
                let kind = try XCTUnwrap(edge.sectionSpans.first { $0.start <= middle && middle <= $0.end }).kind
                if index <= 3 {
                    XCTAssertEqual(kind, .tunnel, name)
                    XCTAssertLessThan(rail - under, -TrackSectionRules.deepestCutting, "\(name) stands \((rail - under) / 64) m down")
                } else {
                    XCTAssertEqual(kind, .viaduct, name)
                    XCTAssertGreaterThan(rail - under, TrackSectionRules.highestFill, "\(name) stands \((rail - under) / 64) m up")
                }
            }
        }
    }

    func testItsTrackIsTheRealAlignmentsLength() throws {
        let (layout, world, tracks) = try Self.built.get()
        func length(_ edges: some Sequence<TrackEdgeID>) -> Int64 {
            edges.reduce(0) { $0 + (world.network.edge($1)?.length ?? 0) }
        }
        let track = length(tracks.down)
        let real = layout.plan.path.length
        // From Nangang's end to Zuoying's: about 352 km; the cubic edges
        // are a few metres either side of the polyline.
        XCTAssertEqual(Double(track) / Self.metre / 1_000, 352.2, accuracy: 2)
        XCTAssertEqual(Double(track), real, accuracy: real * 0.005)
        // Fitted loosely: every edge is checked against all before it. Over
        // the ground, at the heights of the real structures, it takes about
        // three times the edges it took flat (decision 281).
        XCTAssertLessThan(tracks.down.count, 1_000, "the track is fitted loosely: every edge is checked against all before it")
        // The up track runs beside it from turnout to turnout: as long
        // within a few metres (the inside of a curve is shorter), and the
        // two make up the whole network.
        XCTAssertEqual(Double(length(tracks.up)), Double(length(tracks.between)), accuracy: 30 * Self.metre)
        // A loop beside each track at each of the ten stations between the
        // ends, a second at Taichung, a crossover north of Taichung and one
        // south of Taipei, where sets turn back, one north of Taipei, whose
        // sets stand at night in Nangang's depot (decision 228), one south
        // of Taichung into Wuri's depot, the three depots' sidings, and the
        // ends' tracks beside the down track (decision 228): with them, the
        // whole network.
        XCTAssertEqual(tracks.downLoops.count, 33)
        XCTAssertEqual(tracks.upLoops.count, 33)
        XCTAssertEqual(tracks.crossovers.count, 4)
        XCTAssertEqual(
            tracks.down.count + tracks.up.count + tracks.downLoops.count + tracks.upLoops.count + tracks.crossovers.count + tracks.sidings.count
                + tracks.ends.count,
            world.network.edges.count
        )
    }

    /// Double track: between its ramps the up track runs 5 m beside the
    /// down track, the middle of each of its edges about that far from the
    /// middle of the down track's edge beside it (on a curve the two
    /// middles are a little apart along the track too, and the inner edge
    /// bows a little); the game would refuse track closer than 4 m
    /// (``GameError/trackTooClose(_:)``).
    func testItsTwoTracksRunSideBySide() throws {
        let (layout, world, tracks) = try Self.built.get()
        func middle(_ id: TrackEdgeID) throws -> WorldCoordinate {
            let geometry = try XCTUnwrap(world.network.geometry(of: id))
            return geometry.location(at: geometry.length / 2).position
        }
        var apart: [Double] = []
        for index in 1..<(tracks.upInOrder.count - 1) {
            let twin = try XCTUnwrap(layout.plan.distances.firstIndex(of: layout.up.distances[index]))
            let (a, b) = (try middle(tracks.upInOrder[index]), try middle(tracks.down[twin]))
            let (dx, dy) = (Double(a.x - b.x), Double(a.y - b.y))
            apart.append((dx * dx + dy * dy).squareRoot() / Self.metre)
        }
        XCTAssertGreaterThan(apart.count, 200)
        XCTAssertGreaterThan(apart.min() ?? 0, 4.0)
        XCTAssertLessThan(apart.max() ?? .infinity, 5.5)
    }

    // MARK: - The lines and their sets

    /// The real day's three kinds of train (decision 197): a line each,
    /// calling at its stations, with the day's trains as runs.
    func testItsLinesAreTheRealDaysThreeKindsOfTrain() throws {
        let (layout, world, _) = try Self.built.get()
        let ids = world.stations.map(\.id)
        XCTAssertEqual(world.lines.map { $0.stops.map { ids.firstIndex(of: $0)! } }, [Array(0..<12), [0, 1, 2, 3, 4, 6, 9, 10, 11], [0, 1, 2, 6, 11]])
        for (line, planned) in zip(world.lines, layout.timetable.lines) {
            XCTAssertTrue(line.patterns.isEmpty, "a line with runs has no stopping patterns (decision 133)")
            XCTAssertTrue(line.isHighSpeed, "planned at PERF_HSR: a high-speed line (decision 168)")
            XCTAssertEqual(line.runs, planned.runs)
        }
        // The 169 real trains and the positioning runs.
        XCTAssertEqual(layout.timetable.lines.map { $0.runs.count - $0.positioning }, [59, 60, 50])
        XCTAssertEqual(layout.timetable.lines.map(\.positioning), [7, 4, 11])
        XCTAssertFalse(world.isTrafficControlEnabled, "decision 197: under traffic control the real day cannot be run")
        XCTAssertFalse(world.doorCrowding, "dwells do not lengthen in a crowd, as in the other demos (decision 169)")
        XCTAssertFalse(world.keepLeft, "its routes are as they were measured; its up line is laid west of the down line already (decision 202)")
        XCTAssertFalse(world.realisticOperation, "it runs the real timetable, whose times its trains keep to (decision 207)")
        XCTAssertFalse(world.blockSections, "with traffic control off, as measured; turning both on waits for its own measure (decision 212)")
        XCTAssertFalse(world.curveSpeedLimits, "it runs the real timetable as measured (decision 217)")
    }

    /// Each line runs the same day again and again: the day's runs and
    /// positioning runs leave as many sets at each station as it began
    /// with, and the first run of each set leaves from where it stands.
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
        XCTAssertEqual(timetable.lines.map(\.sets), [14, 11, 10], "35 sets; the real High Speed Rail has 34")
    }

    func testItsSetsAreTwelveCarHighSpeedSets() throws {
        let (layout, world, _) = try Self.built.get()
        XCTAssertEqual(world.trains.count, layout.sets)
        for train in world.trains {
            XCTAssertEqual(train.type, .highSpeed, train.name)
            XCTAssertEqual(train.cars, 12, train.name)
            XCTAssertEqual(train.performance, .highSpeed, train.name)
            XCTAssertEqual(train.capacity, 960, "12 cars of 80, not overloaded")
        }
    }

    /// At midnight every set stands in the depot of the station its first
    /// run leaves (decision 221), on a siding of its own, facing the way out.
    func testEverySetStandsInTheDepotOfWhereItsFirstRunLeaves() throws {
        let (layout, world, _) = try Self.built.get()
        let depots = world.stations.filter(\.isDepot).map(\.id)
        var edges: Set<TrackEdgeID> = []
        for (line, planned) in zip(world.lines, layout.timetable.lines) {
            XCTAssertEqual(line.trains.count, planned.sets, planned.english)
            var expected = planned.overnight.map { set in layout.depots.firstIndex { $0.serving.contains(set.station) }! }.sorted()
            var found: [Int] = []
            for id in line.trains {
                let train = try XCTUnwrap(world.train(id: id))
                guard case .onEdge(let traversal, _)? = train.position, let station = world.stationsStoppedAt(by: id).first,
                      let index = depots.firstIndex(of: station)
                else { XCTFail("\(train.name) stands in no depot"); continue }
                XCTAssertTrue(edges.insert(traversal.edge).inserted, "\(train.name): a siding of its own")
                XCTAssertEqual(traversal.direction == .forward, !layout.depots[index].southward, "\(train.name) faces the way out")
                found.append(index)
            }
            found.sort()
            expected.sort()
            XCTAssertEqual(found, expected, planned.english)
        }
    }

    /// Each way keeps to its own track (the author saw the sets of the two
    /// ways run through each other on what was one track): every leg of
    /// every line, as the game drives it, runs southbound on the down
    /// track (and its loops) only and northbound on the up track, but where
    /// sets turn back. Every set calls on the loops, as at the real side
    /// platforms, but the expresses at Taipei and Banqiao, whose island
    /// platforms serve the through tracks too; an express passes a station
    /// on its through track (decision 228).
    func testEveryLegKeepsToItsWaysTrack() throws {
        let (_, world, tracks) = try Self.built.get()
        let stations = world.stations.filter { !$0.isDepot }.map(\.id)
        for (index, line) in world.lines.enumerated() {
            let journey = try XCTUnwrap(world.lineJourney(line.id, pattern: nil), line.name)
            XCTAssertEqual(journey.legs.count, 2 * (line.stops.count - 1), line.name)
            for leg in journey.legs {
                let southbound = leg.to > leg.from
                let (from, to) = (stations.firstIndex(of: line.stops[leg.from])!, stations.firstIndex(of: line.stops[leg.to])!)
                let calling = (tracks.loopsOf[from] ?? []).union(tracks.loopsOf[to] ?? [])
                for traversal in leg.path.traversals {
                    let place = "\(line.name), \(leg.from) to \(leg.to)"
                    XCTAssertFalse(tracks.isAgainst(traversal), place)
                    XCTAssertFalse((southbound ? tracks.northbound : tracks.southbound).contains(traversal.edge), "\(place): on the other way's track")
                    if index > 0 {
                        XCTAssertFalse(tracks.downLoops.union(tracks.upLoops).subtracting(calling).contains(traversal.edge), "\(place): an express on the loop of a station it passes")
                    }
                }
                guard to != 0, to != 11, index == 0 || !HighSpeedDemo.islandStations.contains(to), let last = leg.path.traversals.last else { continue }
                XCTAssertTrue((southbound ? tracks.downLoops : tracks.upLoops).contains(last.edge), "\(line.name), \(leg.from) to \(leg.to): stops on the loop")
            }
        }
    }

    /// Decision 228: the ends have their real stations' platform tracks
    /// (`tools/hsr-platforms/hsr_platforms.json`, from OpenStreetMap):
    /// Nangang six, Zuoying eight; the others four, and Taichung six.
    func testItsStationsHaveTheRealPlatformTracks() throws {
        let world = try Self.built.get().world
        let counts = world.stations.filter { !$0.isDepot }.map { world.network.platforms(of: $0.id).count }
        XCTAssertEqual(counts, [6, 4, 4, 4, 4, 4, 6, 4, 4, 4, 4, 8])
    }

    /// Decision 217 (the owner's condition): with the curve limits on, the
    /// sets keep to the real day as well as they do with them off: no set
    /// is ever later (but by the seconds a set held up behind another
    /// loses, decision 228), over an hour and a half from 07:00. Where a real leg's time
    /// fits only without the limits (the drawn curves tighter than the real
    /// ones), the run does without them. The legs' margins (the least real
    /// time against the least time with the limits) go to the log.
    func testWithCurveLimitsTheSetsKeepToTheRealDayAsWell() throws {
        var latest: [Bool: [TrainID: Int64]] = [:]
        for limits in [false, true] {
            var world = try Self.opened.get()
            world.setCurveSpeedLimits(limits)
            var worst: [TrainID: Int64] = [:]
            for _ in 0..<90 {
                try world.advance(ticks: 1)
                // The runs: a set out of a depot runs empty at its own pace.
                for train in world.trains where train.execution != nil && !train.isDeadheading {
                    worst[train.id] = max(worst[train.id] ?? 0, world.lateness(of: train.id) ?? 0)
                }
            }
            latest[limits] = worst
        }
        let off = try XCTUnwrap(latest[false]), on = try XCTUnwrap(latest[true])
        XCTAssertFalse(on.isEmpty)
        // Decision 228: where a set is held up behind another, the two days
        // part by some seconds.
        for (train, late) in on {
            XCTAssertLessThanOrEqual(late, (off[train] ?? 0) + GameTime.secondsPerMinute, "train \(train.rawValue)")
        }

        var (_, world, _) = try Self.built.get()
        world.setCurveSpeedLimits(true)
        var rows: [(String, Int64, Int64, Int64)] = []
        for line in world.lines {
            let journey = try XCTUnwrap(world.lineJourney(line.id, pattern: nil), line.name)
            for leg in journey.legs where leg.path.distance > 0 {
                let real = line.runs.compactMap { run -> Int64? in
                    let calls = run.calls
                    guard let at = calls.firstIndex(of: leg.from), at + 1 < calls.count, calls[at + 1] == leg.to else { return nil }
                    return run.times[at + 1].arrival - run.times[at].departure
                }.min()
                guard let real, let free = RunningCurve.leastSeconds(length: leg.path.distance, performance: line.performance) else { continue }
                rows.append(("\(line.name) \(leg.from)→\(leg.to)", real, free, leg.seconds))
            }
        }
        let report = rows.sorted { $0.1 - $0.3 < $1.1 - $1.3 }.map { row in
            let note = row.3 > row.1 ? (row.2 > row.1 ? " (over even without the limits)" : " (fits only without the limits: relaxed)") : ""
            return "\(row.0): real \(row.1) s, least \(row.2) s off, \(row.3) s with limits, margin \(row.1 - row.3) s\(note)"
        }
        FileHandle.standardError.write(Data(("curve limits, least margins first:\n" + report.joined(separator: "\n") + "\n").utf8))
    }

    /// The game starts with the money of a new game: what the track, the
    /// stations and the sets cost was added to it.
    func testItIsPaidForBeforeItStarts() throws {
        let world = try Self.built.get().world
        XCTAssertEqual(world.economy.balance, GameWorld.startingBalance)
    }

    func testItSavesAndLoads() throws {
        let world = try Self.built.get().world
        let loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
        XCTAssertEqual(loaded, world)
    }

    // MARK: - The game as it opens

    /// At 07:00 every run due by then has sent its set out, both ways.
    func testItOpensAtSevenWithTheSetsOnTheirWay() throws {
        let world = try Self.opened.get()
        let tracks = try Self.built.get().tracks
        XCTAssertEqual(world.clock.now.minute, 7 * 60)
        XCTAssertEqual(world.clock.speed, .normal, "it runs at once, like the other demos")
        XCTAssertFalse(world.doorCrowding)
        XCTAssertEqual(world.stations.count, 15, "twelve and the three depots")
        for line in world.lines {
            for (index, run) in line.runs.enumerated() where run.times[0].departure <= 7 * 3_600 {
                XCTAssertEqual(line.runDays[index], 0, "\(line.name): the run leaving at \(run.times[0].departure / 60) min has gone")
            }
        }
        var ways = (south: 0, north: 0)
        for train in world.trains where train.execution != nil {
            guard case .onEdge(let traversal, _)? = train.position else { continue }
            if tracks.southbound.contains(traversal.edge) { ways.south += 1 }
            if tracks.northbound.contains(traversal.edge) { ways.north += 1 }
        }
        XCTAssertGreaterThanOrEqual(ways.south, 4, "sets on their way south")
        XCTAssertGreaterThanOrEqual(ways.north, 4, "and north")
    }

    func testPeopleLiveRoundItsStationsAndTravelBetweenThem() throws {
        try XCTSkipIf(Self.population == nil, "The population file is not here.")
        let world = try Self.opened.get()
        var total: Int64 = 0
        for station in world.stations where !station.isDepot {
            let hinterland = try XCTUnwrap(world.stationDemand(of: station.id)?.hinterland, station.name)
            XCTAssertGreaterThan(hinterland, 100_000, "\(station.name): the people within 8 km")
            total += hinterland
        }
        XCTAssertGreaterThan(total, 10_000_000, "Taipei, Taichung and Kaohsiung's towns are in it")
        // An hour of the day has passed with the people there: passengers
        // were released at the stations and some have arrived.
        XCTAssertGreaterThan(world.passengers.reduce(0) { $0 + $1.released }, 0)
        XCTAssertGreaterThan(world.passengers.reduce(0) { $0 + $1.arrived }, 0)
    }

    // MARK: - The game launcher

    /// The launcher builds it off the main actor, says so while it does,
    /// and opens the game when it is built.
    @MainActor
    func testTheLauncherBuildsAndOpensIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HighSpeedDemoTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let railways = try Self.railways()
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.population = Self.population
        launcher.places = Self.places
        let task = launcher.openHighSpeedDemo(railways: railways)
        // A second tap while it builds does nothing.
        XCTAssertNil(launcher.openHighSpeedDemo(railways: railways), "one build at a time")
        XCTAssertTrue(launcher.isOpeningHighSpeedDemo)
        XCTAssertNil(launcher.session, "still on the start screen")
        await task?.value
        XCTAssertFalse(launcher.isOpeningHighSpeedDemo)
        XCTAssertEqual(launcher.session?.world.stations.count, 15, "the game is open")
        XCTAssertEqual(launcher.session?.world.lines.first?.isHighSpeed, true)
        try XCTSkipIf(Self.population == nil, "The population file is not here.")
        let taipei = try XCTUnwrap(launcher.session?.world.stations.first { $0.name == "Taipei" })
        XCTAssertGreaterThan(launcher.session?.world.stationDemand(of: taipei.id)?.hinterland ?? 0, 1_000_000, "the people were handed to the build")
    }

    /// A game the player starts while it builds is not taken over by it.
    @MainActor
    func testAGameStartedWhileItBuildsStays() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HighSpeedDemoTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        let task = launcher.openHighSpeedDemo(railways: try Self.railways())
        launcher.openDemo()
        let simple = try XCTUnwrap(launcher.session?.world)
        await task?.value
        XCTAssertFalse(launcher.isOpeningHighSpeedDemo)
        XCTAssertEqual(launcher.session?.world, simple, "the simple demo is still the game being played")
    }

    // MARK: - Report

    /// What the demo is, measured: the track, what it costs, the services
    /// and two days' accounts. Printed, and only on request:
    ///
    ///     HSR_DEMO_REPORT=1 swift test -c release -Xswiftc -enable-testing --filter HighSpeedDemoTests/testReport
    func testReport() throws {
        guard ProcessInfo.processInfo.environment["HSR_DEMO_REPORT"] != nil else { throw XCTSkip("Set HSR_DEMO_REPORT=1.") }
        func say(_ text: String) {
            FileHandle.standardError.write(Data((text + "\n").utf8))
        }
        var clock = Date()
        func lap(_ what: String) {
            say("\(what): \(String(format: "%.2f", Date().timeIntervalSince(clock))) s")
            clock = Date()
        }
        let railways = try Self.railways()
        let heights = try XCTUnwrap(Self.heights)
        let layout = try HighSpeedDemo.Layout(railways: railways, heights: heights)
        say("\(layout.plan.curves.count) edges, \(Int(layout.plan.path.length / Self.metre / 1_000)) km; costs \(layout.cost(eventSeed: 1).moneyText)")
        clock = Date()
        var world = try HighSpeedDemo.make(in: .english, railways: railways, population: Self.population, places: Self.places, heights: heights)
        lap("make")
        say("at \(world.clock.now.minute / 60):00, balance \(world.economy.balance.moneyText); stations \(world.stations.count), sets \(world.trains.count), edges \(world.network.edges.count), land cells \(world.land.cells.count)")
        for line in world.lines {
            let journey = world.lineJourney(line.id, pattern: nil)
            say("\(line.name): \(line.stops.count) calls, \(line.runs.count) runs, \(line.trains.count) sets, round trip \(journey?.roundTripMinutes ?? -1) min")
        }
        say("hinterlands \(world.stations.map { world.stationDemand(of: $0.id)?.hinterland ?? 0 })")
        let ordinary = world.stations.map { world.stationDemand(of: $0.id)?.dailyTrips ?? 0 }
        say("stations' own daily trips \(ordinary), together \(ordinary.reduce(0, +))")
        // To midnight, then two whole days.
        try world.advance(ticks: Int(1_440 - world.clock.now.minute % 1_440))
        for _ in 1...2 {
            try world.advance(ticks: 1_440)
            lap("day")
            if let last = world.accounts.days.last {
                say("day \(last.day): trips \(last.fareTrips), fares \(last.fareRevenue.moneyText), costs \(last.totalCost.moneyText), balance \(world.economy.balance.moneyText)")
            }
        }
        let released = world.passengers.reduce(0) { $0 + $1.released }
        let arrived = world.passengers.reduce(0) { $0 + $1.arrived }
        let overflowed = world.passengers.reduce(0) { $0 + $1.overflowed }
        let abandoned = world.passengers.reduce(0) { $0 + $1.abandoned }
        say("released \(released), arrived \(arrived), overflowed \(overflowed), abandoned \(abandoned)")
        let data = try JSONEncoder().encode(SavedGame(world: world))
        lap("encode \(data.count / 1_000) kB")
        _ = try JSONDecoder().decode(SavedGame.self, from: data)
        lap("decode")
    }
}
