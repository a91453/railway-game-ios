import Foundation
import GameCore

// The high-speed demo (ARCHITECTURE decision 170, the owner's idea): the
// real Taiwan High Speed Rail, Nangang to Zuoying, built as the game's own
// track on its real alignment over the whole of Taiwan, with its twelve
// stations, its high-speed sets and the real day's trains running (decision
// 197), so that high-speed rail (decision 168) can be tried on a device at once, not
// after laying 350 km of track by hand. It is built like ``RealWorldDemo``,
// the Pingxi Line's: the real railways' own centre line (``RealRailways``),
// projected onto the world, fitted with cubic edges, and ordinary
// `GameWorld` commands that charge their usual costs; the game starts with
// what they cost on top of a new game's money.

/// A whole-Taiwan game with the Taiwan High Speed Rail built and running
/// (decision 170), on the real day's timetable (decision 197).
///
/// - The track is double, as on the real line, flat and on the ground (the
///   game's track, not the real viaducts and tunnels): the down track
///   (southbound) is one line of cubic edges on the real alignment, the up
///   track (northbound) runs ``trackOffset`` beside it and joins it by a
///   turnout short of each end's yard, where the sets turn back.
/// - The twelve stations stand where the real ones do. Each between the
///   ends has four platforms for a set of twelve cars (16 m each): one on
///   each through track and one on a loop beside each, outside it, as the
///   real stations have side platforms and through tracks. Taichung has a
///   second loop beside each, for the sets that turn back there; Taipei and
///   Taichung a crossover beyond each end, where those sets go over to the
///   other way's track. Each end has its platform on the down track and a
///   yard of dead-end tracks either side of it, each with a platform, where
///   the sets stand on the first night (``Yard``); with traffic control off
///   a set coming in stops at the end's own platform, on any there, as
///   before.
/// - A station's platforms are staggered (decision 197), each
///   ``platformStagger`` beyond the one before, north to south: the down
///   through track's, the down loop's, the up loop's, the up through
///   track's. A set that cannot have the whole way to the platform its line
///   names, or has no way of its line's to it, goes to the nearest
///   (decisions 57 and 61): so always one on its way's own track, never the
///   other's reached along the wrong track, which the stagger keeps further
///   than any difference the curves make between the two tracks' lengths;
///   and the through track's first, as an express, whose way of a hundred
///   kilometres is seldom all free, follows the set ahead to it.
/// - Three lines, each the real day's trains of one kind as runs (decision
///   133, ``HighSpeedTimetable``): the all-stops line calls at all twelve,
///   the nine-stop and five-stop lines at theirs. A run calls at every stop
///   of its line between its ends, so each kind is a line of its own; each
///   line has its positioning runs and its own sets, at midnight where its
///   first runs leave.
/// - Every leg says where it runs (``run(in:language:timetable:stations:platforms:ends:through:)``):
///   southbound on the down track, northbound on the up track, so each way
///   keeps to its own track and the trains of the two ways meet only where
///   a set turns back. The all-stops sets stop on the loops; the expresses
///   keep to the through tracks and pass them there.
/// - Its trains are high-speed sets (`TrainType.highSpeed`, twelve cars
///   rated 80 each), planned at `PERF_HSR`; the lines are high-speed lines
///   (decision 168), so their stations draw the people round them and their
///   riders pay by the kilometre.
/// - Traffic control is off (decision 197): under it the real day cannot
///   be run. A set takes the whole of its way to its next stop before it
///   leaves, follows a set ahead only on the shortest way and never one
///   that stops on its way; an express's way runs 30 to 180 km past
///   stations where other sets stand, so it seldom leaves on time, and on
///   the real day 97 of the 191 runs were dropped and the rest ran one and
///   a half to two hours late, at some 40 minutes of computing a game day. Off, a
///   set may still run into one going its own way ahead of it; on the real
///   timetable, with the expresses passing the all-stops sets at the loops,
///   that is seldom. The yards, the crossovers and the staggered platforms
///   are what traffic control would need when its rules allow it.
public enum HighSpeedDemo {
    /// Cars of every set.
    static let cars = 12
    /// A platform takes a car more than the set has.
    static let platformLength = Int64(cars + 1) * Train.carLength
    /// How far the track may stray from the real alignment, and how long
    /// an edge may be (``RealWorldDemo/TrackPlan``): the real line is
    /// straight or curves gently, and every edge costs the game its time to
    /// build (each is checked against all before it), so the edges are long
    /// and the fit loose.
    static let tolerance = 10.0 * RealWorldDemo.metre
    static let longestEdge = 4_000.0 * RealWorldDemo.metre
    /// How far apart the two tracks' centre lines are: the real line's
    /// 4.5 m and a little, clear of the game's 4 m
    /// (``RailwayNetwork/trackSpacing``) on every curve.
    static let trackOffset = 5.0 * RealWorldDemo.metre
    /// How long the up track's ramps from the down track are, and the
    /// loops'.
    static let rampLength = 100.0 * RealWorldDemo.metre
    /// How long each track of a yard takes to move a track's width out from
    /// the one before.
    static let yardStep = 60.0 * RealWorldDemo.metre
    /// How far beyond a turnback station's loops its crossovers begin, and
    /// how long they are.
    static let crossoverReach = 100.0 * RealWorldDemo.metre
    /// How far apart a station's platforms are staggered along the line
    /// (decision 197): more than two tracks 5 m apart differ in length over
    /// any stretch of the line, the offset times the way it turns, at most
    /// a right angle on the High Speed Rail.
    static let platformStagger = Int64(10 * WorldCoordinate.unitsPerMetre)

    /// How the stations are numbered by the real data: the High Speed Rail's
    /// station names, north to south.
    static let stationNames = ["南港", "台北", "板橋", "桃園", "新竹", "苗栗", "台中", "彰化", "雲林", "嘉義", "台南", "左營"]

    /// The world's frame: Taiwan's, as the whole-Taiwan game lays it.
    static var frame: RealWorldFrame {
        RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)
    }

    /// Why the demo cannot be built from the real data.
    public enum Failure: Error, Hashable, Sendable {
        /// The railways have no High Speed Rail line, or not its twelve
        /// stations.
        case noHighSpeedRail
        /// The railways have no day of High Speed Rail trains
        /// (`thsr-schedule.json`).
        case noTimetable
    }

    /// The minute of the first day the game opens at: 07:00, an hour after
    /// the first sets leave (at 05:50), when the first sets of each line are
    /// on their way.
    static let opensAt: Int64 = 7 * 60
    /// The minute the land round the stations is read in, before the first
    /// set leaves.
    static let landAt: Int64 = 5 * 60 + 30

    /// The demo: a new whole-Taiwan game with the railway built, running
    /// from 07:00. `population`, `places`, `water` and `coverage` are the
    /// app's real-world data; the land round the high-speed stations is read
    /// in from them (``GameSession/readLand(roundStationsOf:population:places:water:coverage:)``).
    /// Without the population the stations have no hinterland, and so no
    /// intercity trips.
    ///
    /// - Throws: ``Failure/noHighSpeedRail`` when `railways` has no High
    ///   Speed Rail, ``Failure/noTimetable`` when it has no day of its
    ///   trains.
    public static func make(
        in language: DisplayLanguage, railways: RealRailways, population: PopulationGrid? = nil, places: PlaceGrid? = nil,
        water: WaterGrid? = nil, coverage: CoverageGrid? = nil, eventSeed: UInt32 = 1
    ) throws(Failure) -> GameWorld {
        let layout = try Layout(railways: railways)
        var world = newWorld(paying: layout.cost(at: ConstructionCosts.newGame), eventSeed: eventSeed)
        do throws(GameError) {
            try layout.build(in: &world, language: language)
            // The first sets leave at 05:50. Until then nothing runs and no
            // one is waiting, so the night passes before the land's people
            // are read in; the game then opens an hour into the day.
            world.setSpeed(.fast)
            try world.advance(ticks: Int(landAt / 10))
            GameSession.readLand(roundStationsOf: &world, population: population, places: places, water: water, coverage: coverage)
            try world.advance(ticks: Int((opensAt - landAt) / 10))
            world.setSpeed(.normal)
        } catch {
            preconditionFailure("The high-speed demo no longer builds: \(error)")
        }
        return world
    }

    /// The world the demo is built in: a new whole-Taiwan game with `cost`,
    /// what the layout costs, on top of its money, and its land read in as
    /// it is needed.
    static func newWorld(paying cost: Money, eventSeed: UInt32) -> GameWorld {
        var world = GameWorld.newGame(
            anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds, balance: GameWorld.startingBalance + cost, eventSeed: eventSeed, land: []
        )
        world.setLandOnDemand()
        // Decision 169: nor do its dwells lengthen in a crowd; the service
        // levels were measured without.
        world.setDoorCrowding(false)
        world.setRollingStockEconomics(false)
        world.setFlexDispatch(false)
        // Decision 202: its routes are as they were measured.
        world.setKeepLeft(false)
        // Decision 206: its timetables are as they were measured.
        world.setRealisticOperation(false)
        // Decision 174: nor do tourists come to its sights.
        world.setTourism(nil)
        // Decision 183: nor does the city ask it for anything.
        world.setCityRequests(seed: nil)
        return world
    }

    // MARK: - The layout

    /// A real station: the data's, and where it is in the world.
    struct Stop {
        let station: RealRailways.Station
        let point: WorldVector
    }

    /// An end's yard: dead-end tracks either side of the down track beyond
    /// the end's platform, each `yardStep` further out than the one before
    /// and branching from it, the first from the down track, a track's width
    /// apart, each with a platform beside the end's.
    struct Yard {
        /// Each side's tracks, the nearest first: east of the down track,
        /// then west.
        let east: [RealWorldDemo.TrackPlan]
        let west: [RealWorldDemo.TrackPlan]

        /// How many tracks a side needs for `sets` standing at the end at
        /// night: the end's own platform takes one, the yard the rest, and
        /// a track to spare on each side for the sets coming and going.
        static func tracks(for sets: Int) -> Int {
            (max(0, sets - 1) + 1) / 2 + 1
        }
    }

    /// Where everything goes: worked out before anything is built, so the
    /// game can start with what it costs.
    ///
    /// Two tracks: ``plan``, the down track on the real alignment from
    /// Nangang's end to Zuoying's, and ``up``, the up track beside it,
    /// west of it as the real trains keep left, which leaves the down track
    /// at ``junctions`` just beyond the ends' yards.
    struct Layout {
        let plan: RealWorldDemo.TrackPlan
        let up: RealWorldDemo.TrackPlan
        /// Each station's loops between the ends, by the station's index:
        /// one beside the down track on its east, one beside the up track
        /// on its west, each with the station's platform for the sets that
        /// call at every station, so the expresses pass them on the
        /// through tracks.
        let loops: [Int: (down: RealWorldDemo.TrackPlan, up: RealWorldDemo.TrackPlan)]
        /// The second loops outside them, where sets turn back and stand.
        let outerLoops: [Int: (down: RealWorldDemo.TrackPlan, up: RealWorldDemo.TrackPlan)]
        /// The crossovers of the stations where sets turn back, from the up
        /// track to the down track: beyond the station's north end where a
        /// line sends more sets north from it than come in northbound (so
        /// some that came southbound leave northbound), beyond its south end
        /// the other way round. Only those: a crossover also makes a way
        /// along the other way's track, which a set's route could take where
        /// it is a little shorter.
        let crossovers: [Int: [RealWorldDemo.TrackPlan]]
        /// Where along the down track's path each station where sets turn
        /// back reaches, from its north crossover to its south one: the
        /// track there is run both ways.
        let turnbackReach: [Int: ClosedRange<Double>]
        /// The two ends' yards.
        let yards: (north: Yard, south: Yard)
        let stops: [Stop]
        let platforms: [ClosedRange<Double>]
        let timetable: HighSpeedTimetable
        /// Where the up track leaves the down track by Nangang and joins it
        /// again by Zuoying, along the down track's path.
        let junctions: (north: Double, south: Double)

        init(railways: RealRailways) throws(Failure) {
            let frame = HighSpeedDemo.frame
            // The line's pieces, in the data's order, each beginning where
            // the one before ends.
            var points: [WorldVector] = []
            for line in railways.lines.filter({ $0.name == "高鐵" }).sorted(by: { $0.id < $1.id }) {
                for point in line.points {
                    points.append(WorldVector(frame.worldPosition(latitude: point.latitude, longitude: point.longitude)))
                }
            }
            let stops = HighSpeedDemo.stationNames.compactMap { name in
                railways.stations.first { $0.id == "thsr_sched|\(name)" }.map {
                    Stop(station: $0, point: WorldVector(frame.worldPosition(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)))
                }
            }
            guard points.count > 1, stops.count == HighSpeedDemo.stationNames.count else { throw .noHighSpeedRail }
            guard let schedule = railways.operations?.schedule(forSystem: "thsr") else { throw .noTimetable }
            let path = WorldPath(points)
            let platforms = stops.map { HighSpeedDemo.platformZone(on: path, at: $0.point) }
            self.stops = stops
            self.platforms = platforms
            let timetable = HighSpeedTimetable(
                schedule: schedule, names: HighSpeedDemo.stationNames, distances: platforms.map { ($0.lowerBound + $0.upperBound) / 2 }
            )
            self.timetable = timetable
            let last = platforms.count - 1
            // The sets each station has at night, and where sets turn back.
            var standing = [Int](repeating: 0, count: platforms.count)
            for line in timetable.lines {
                for set in line.overnight { standing[set.station] += 1 }
            }
            // Where a line's sets turn back between the ends: north (more of
            // its runs leave northbound than end there northbound) and south.
            var turns: [Int: (north: Bool, south: Bool)] = [:]
            for line in timetable.lines {
                for station in line.stops.indices {
                    func count(_ runs: [LineRun], southbound: Bool) -> Int { runs.count { $0.isOutbound == southbound } }
                    let ending = line.runs.filter { $0.to == station }, leaving = line.runs.filter { $0.from == station }
                    let north = count(leaving, southbound: false) > count(ending, southbound: false)
                    let south = count(leaving, southbound: true) > count(ending, southbound: true)
                    guard north || south, ![0, last].contains(line.stops[station]) else { continue }
                    let turn = turns[line.stops[station]] ?? (false, false)
                    turns[line.stops[station]] = (turn.north || north, turn.south || south)
                }
            }
            let turnbacks = Set(turns.keys)
            let between = Array(platforms.indices.dropFirst().dropLast())
            // A turnback station with more sets at night than its loops
            // take has a second loop beside each.
            let outer = Set(turnbacks.filter { standing[$0] > 2 })

            let ramp = HighSpeedDemo.rampLength, margin = RealWorldDemo.platformMargin, step = HighSpeedDemo.yardStep
            let reach = HighSpeedDemo.crossoverReach
            // Each end's yard from a ramp beyond its platform's margin; the
            // turnouts a ramp beyond the yards, the up track's ramps a ramp
            // long.
            let sides = (north: Yard.tracks(for: standing[0]), south: Yard.tracks(for: standing[last]))
            let yardEnds = (north: platforms[0].upperBound + margin, south: platforms[last].lowerBound - margin)
            let junctions = (
                north: yardEnds.north + Double(sides.north) * step + ramp, south: yardEnds.south - Double(sides.south) * step - ramp
            )
            self.junctions = junctions
            let upEnds = (north: junctions.north + ramp, south: junctions.south - ramp)
            // Each loop leaves its track a ramp before the platform's margin
            // and is beside it from there to the far margin; a second loop
            // leaves a ramp before that; the crossovers lie beyond.
            func loopNodes(_ zone: ClosedRange<Double>) -> [Double] {
                [zone.lowerBound - margin - ramp, zone.lowerBound - margin, zone.upperBound + margin, zone.upperBound + margin + ramp]
            }
            func outerEnds(_ station: Int) -> (north: Double, south: Double) {
                let nodes = loopNodes(platforms[station])
                return outer.contains(station) ? (nodes[0] - ramp, nodes[3] + ramp) : (nodes[0], nodes[3])
            }
            func crossoverNodes(_ station: Int) -> [[Double]] {
                let ends = outerEnds(station), turn = turns[station]!
                return (turn.north ? [[ends.north - 2 * reach, ends.north - reach]] : []) + (turn.south ? [[ends.south + reach, ends.south + 2 * reach]] : [])
            }
            // The yards' tracks end at the far margin of the ends' platforms.
            let buffers = (north: platforms[0].lowerBound - margin, south: platforms[last].upperBound + margin)
            let yardNodes = [buffers.north, buffers.south] + (0...sides.north).map { yardEnds.north + Double($0) * step }
                + (0...sides.south).map { yardEnds.south - Double($0) * step }
            let plan = RealWorldDemo.TrackPlan(
                path,
                forced: [0, path.length, junctions.north, upEnds.north, upEnds.south, junctions.south] + yardNodes
                    + between.flatMap { loopNodes(platforms[$0]) } + outer.flatMap { [outerEnds($0).north, outerEnds($0).south] }
                    + turnbacks.flatMap { crossoverNodes($0).flatMap { $0 } },
                avoiding: platforms, tolerance: HighSpeedDemo.tolerance, longestEdge: HighSpeedDemo.longestEdge
            )
            self.plan = plan
            func index(_ distance: Double) -> Int {
                guard let index = plan.distances.firstIndex(where: { abs($0 - distance) < 1 }) else {
                    preconditionFailure("No node of the down track at \(distance)")
                }
                return index
            }
            // Beside every node of the down track from the end of one ramp
            // to the start of the other.
            let inner = Array(index(upEnds.north)...index(upEnds.south))
            let offset = HighSpeedDemo.trackOffset
            up = RealWorldDemo.TrackPlan(
                beside: plan, at: [index(junctions.north)] + inner + [index(junctions.south)], offsets: [0] + inner.map { _ in offset } + [0]
            )
            loops = Dictionary(uniqueKeysWithValues: between.map { station in
                let at = loopNodes(platforms[station]).map(index)
                return (station, (
                    down: RealWorldDemo.TrackPlan(beside: plan, at: at, offsets: [0, -offset, -offset, 0]),
                    up: RealWorldDemo.TrackPlan(beside: plan, at: at, offsets: [offset, 2 * offset, 2 * offset, offset])
                ))
            })
            outerLoops = Dictionary(uniqueKeysWithValues: outer.map { station in
                let nodes = loopNodes(platforms[station]), ends = outerEnds(station)
                let at = [ends.north, nodes[1], nodes[2], ends.south].map(index)
                return (station, (
                    down: RealWorldDemo.TrackPlan(beside: plan, at: at, offsets: [0, -2 * offset, -2 * offset, 0]),
                    up: RealWorldDemo.TrackPlan(beside: plan, at: at, offsets: [offset, 3 * offset, 3 * offset, offset])
                ))
            })
            turnbackReach = Dictionary(uniqueKeysWithValues: turnbacks.map { station in
                let nodes = crossoverNodes(station).flatMap { $0 } + [outerEnds(station).north, outerEnds(station).south]
                return (station, nodes.min()!...nodes.max()!)
            })
            crossovers = Dictionary(uniqueKeysWithValues: turnbacks.map { station in
                (station, crossoverNodes(station).map { RealWorldDemo.TrackPlan(beside: plan, at: $0.map(index), offsets: [offset, 0]) })
            })
            // A yard's track `k` (from 1) on a side (`way` 1 west, -1 east):
            // from the track before it, `k - 1` steps short of the platform's
            // margin, out to its place a step on, and beside the down track's
            // every node from there to the far margin of the end's platform.
            func yard(count: Int, at end: Double, outward: Double, terminal: Int) -> Yard {
                func track(_ k: Int, way: Double) -> RealWorldDemo.TrackPlan {
                    let branch = index(end + outward * Double(count - k + 1) * step), out = index(end + outward * Double(count - k) * step)
                    let beside = outward < 0 ? Array(out...terminal) : Array((terminal...out).reversed())
                    let at = [branch] + beside
                    let offsets = [way * Double(k - 1) * offset] + beside.map { _ in way * Double(k) * offset }
                    // Nodes in order along the path.
                    return outward < 0
                        ? RealWorldDemo.TrackPlan(beside: plan, at: at, offsets: offsets)
                        : RealWorldDemo.TrackPlan(beside: plan, at: at.reversed(), offsets: offsets.reversed())
                }
                return Yard(east: (1...count).map { track($0, way: -1) }, west: (1...count).map { track($0, way: 1) })
            }
            yards = (
                north: yard(count: sides.north, at: yardEnds.north, outward: 1, terminal: index(buffers.north)),
                south: yard(count: sides.south, at: yardEnds.south, outward: -1, terminal: index(buffers.south))
            )
        }

        /// The sets the timetable needs, every line's.
        var sets: Int {
            timetable.lines.reduce(0) { $0 + $1.sets }
        }

        /// Every piece of track beside the down track.
        private var pieces: [RealWorldDemo.TrackPlan] {
            [up] + loops.values.flatMap { [$0.down, $0.up] } + outerLoops.values.flatMap { [$0.down, $0.up] }
                + crossovers.values.flatMap { $0 } + yards.north.east + yards.north.west + yards.south.east + yards.south.west
        }

        /// What building it costs at `costs` (the prices of
        /// ``GameWorld/buildTrackEdge(from:to:curve:profile:structure:)``,
        /// ``GameWorld/buildStation(named:at:)``, ``GameWorld/purchaseTrain(named:)``
        /// and ``GameWorld/setTrainCars(_:to:)``; every track is on the
        /// ground).
        func cost(at costs: ConstructionCosts) -> Money {
            let track = (plan.lengths + pieces.flatMap(\.lengths)).map { length in
                max(1, (length + ConstructionCosts.trackPricingLength - 1) / ConstructionCosts.trackPricingLength) * TrackStructure.surface.costFactor
            }.reduce(0, +) * costs.track.amount
            let stations = Int64(stops.count) * costs.station.amount
            return Money(track + stations + Int64(sets) * (costs.train.amount + Int64(cars - 1) * costs.car.amount))
        }

        /// Builds it: the down track, the up track from turnout to turnout,
        /// the loops, the crossovers, the yards, the stations and their
        /// platforms, and the lines.
        @discardableResult
        func build(in world: inout GameWorld, language: DisplayLanguage) throws(GameError) -> Built {
            let down = try plan.build(in: &world)
            func node(_ track: RealWorldDemo.Track, _ distance: Double) -> TrackNodeID {
                guard let node = track.node(at: distance) else { preconditionFailure("No node at \(distance)") }
                return node
            }
            func first(_ plan: RealWorldDemo.TrackPlan) -> Double { plan.distances[0] }
            func last(_ plan: RealWorldDemo.TrackPlan) -> Double { plan.distances[plan.distances.count - 1] }
            let upTrack = try up.build(in: &world, start: node(down, junctions.north), end: node(down, junctions.south))
            var builtLoops: [Int: (down: RealWorldDemo.Track, up: RealWorldDemo.Track)] = [:]
            for station in loops.keys.sorted() {
                let (downLoop, upLoop) = loops[station]!
                builtLoops[station] = (
                    try downLoop.build(in: &world, start: node(down, first(downLoop)), end: node(down, last(downLoop))),
                    try upLoop.build(in: &world, start: node(upTrack, first(upLoop)), end: node(upTrack, last(upLoop)))
                )
            }
            var builtOuter: [Int: (down: RealWorldDemo.Track, up: RealWorldDemo.Track)] = [:]
            for station in outerLoops.keys.sorted() {
                let (downLoop, upLoop) = outerLoops[station]!
                builtOuter[station] = (
                    try downLoop.build(in: &world, start: node(down, first(downLoop)), end: node(down, last(downLoop))),
                    try upLoop.build(in: &world, start: node(upTrack, first(upLoop)), end: node(upTrack, last(upLoop)))
                )
            }
            var crossoverEdges: [TrackEdgeID] = []
            for station in crossovers.keys.sorted() {
                for crossover in crossovers[station]! {
                    crossoverEdges += try crossover.build(in: &world, start: node(upTrack, first(crossover)), end: node(down, last(crossover))).edges
                }
            }
            // Each yard track from the one before it (the first from the
            // down track), at its branching node.
            func build(_ side: [RealWorldDemo.TrackPlan], north: Bool) throws(GameError) -> [RealWorldDemo.Track] {
                var tracks: [RealWorldDemo.Track] = []
                for plan in side {
                    let from = tracks.last ?? down
                    tracks.append(north
                        ? try plan.build(in: &world, end: node(from, last(plan)))
                        : try plan.build(in: &world, start: node(from, first(plan))))
                }
                return tracks
            }
            let yardTracks = (
                north: try build(yards.north.east, north: true) + build(yards.north.west, north: true),
                south: try build(yards.south.east, north: false) + build(yards.south.west, north: false)
            )
            var ids: [StationID] = []
            var platformsOf: [Int: Built.Platforms] = [:]
            var ends: [Int: [TrackPlatform]] = [:]
            for (index, (stop, zone)) in zip(stops, platforms).enumerated() {
                let middle = plan.path.point(at: (zone.lowerBound + zone.upperBound) / 2)
                let id = try world.buildStation(named: stop.station.name(in: language), at: middle.plan).id
                func platform(on track: RealWorldDemo.Track, shift: Int64 = 0) throws(GameError) -> TrackPlatform {
                    let (edge, offset) = track.edge(at: zone.lowerBound, in: world)
                    try world.addTrackPlatform(id, on: edge, from: offset + shift, to: offset + shift + HighSpeedDemo.platformLength)
                    return TrackPlatform(station: id, edge: edge, start: offset + shift, end: offset + shift + HighSpeedDemo.platformLength)
                }
                if let loop = builtLoops[index] {
                    var outer: (down: TrackPlatform, up: TrackPlatform)?
                    if let tracks = builtOuter[index] {
                        outer = (try platform(on: tracks.down, shift: HighSpeedDemo.platformStagger), try platform(on: tracks.up, shift: 2 * HighSpeedDemo.platformStagger))
                    }
                    // Staggered north to south: down, down loop, up loop, up
                    // (decision 197).
                    let stagger = HighSpeedDemo.platformStagger
                    platformsOf[index] = Built.Platforms(
                        down: try platform(on: down), up: try platform(on: upTrack, shift: 3 * stagger),
                        downLoop: try platform(on: loop.down, shift: stagger), upLoop: try platform(on: loop.up, shift: 2 * stagger),
                        outer: outer
                    )
                } else {
                    // An end: its own platform, then its yard's, the nearest
                    // first, each side by turns.
                    let yard = index == 0 ? yardTracks.north : yardTracks.south
                    let half = yard.count / 2
                    let order = (0..<half).flatMap { [yard[$0], yard[half + $0]] }
                    var berths = [try platform(on: down)]
                    for track in order { berths.append(try platform(on: track)) }
                    ends[index] = berths
                }
                ids.append(id)
            }
            let turnouts = (north: plan.distances.firstIndex { abs($0 - junctions.north) < 1 }!, south: plan.distances.firstIndex { abs($0 - junctions.south) < 1 }!)
            let through = Through(down: down.edges, up: upTrack.edges, turnouts: turnouts)
            try HighSpeedDemo.run(in: &world, language: language, timetable: timetable, stations: ids, platforms: platformsOf, ends: ends, through: through)
            return Built(
                down: down, up: upTrack, loops: builtLoops.keys.sorted().map { builtLoops[$0]! }, outerLoops: builtOuter.keys.sorted().map { builtOuter[$0]! },
                crossovers: crossoverEdges, yards: yardTracks.north + yardTracks.south
            )
        }
    }

    /// The two through tracks' edges in order, north to south, for an
    /// express's way along them; `turnouts` are the down track's nodes
    /// where the up track leaves and joins it, by their place along it.
    struct Through {
        let down: [TrackEdgeID]
        let up: [TrackEdgeID]
        let turnouts: (north: Int, south: Int)

        /// Southbound along the down track, from the edge of `start` to
        /// that of `end`.
        func southbound(from start: TrackEdgeID, to end: TrackEdgeID) -> [TrackTraversal] {
            guard let i = down.firstIndex(of: start), let j = down.firstIndex(of: end) else { return [] }
            return down[i...j].map { TrackTraversal(edge: $0, direction: .forward) }
        }

        /// Northbound from `start` to `end`: from Zuoying's platform on the
        /// down track up to the south turnout first, then along the up
        /// track, and on the down track again from the north turnout to
        /// Nangang's platform.
        func northbound(from start: TrackEdgeID, to end: TrackEdgeID) -> [TrackTraversal] {
            var edges: [TrackEdgeID] = []
            let first: Int
            if let i = down.firstIndex(of: start) {
                edges += down[turnouts.south...i].reversed()
                first = up.count - 1
            } else {
                guard let i = up.firstIndex(of: start) else { return [] }
                first = i
            }
            let last = down.contains(end) ? 0 : up.firstIndex(of: end) ?? 0
            edges += up[last...first].reversed()
            if let j = down.firstIndex(of: end) { edges += down[j..<turnouts.north].reversed() }
            return edges.map { TrackTraversal(edge: $0, direction: .backward) }
        }
    }

    /// The tracks as built, and the platforms of the stations between the
    /// ends.
    struct Built {
        /// A station's platforms: on the two through tracks, on its two
        /// loops and on its second loops if it has them.
        struct Platforms {
            let down: TrackPlatform
            let up: TrackPlatform
            let downLoop: TrackPlatform
            let upLoop: TrackPlatform
            let outer: (down: TrackPlatform, up: TrackPlatform)?
        }

        let down: RealWorldDemo.Track
        let up: RealWorldDemo.Track
        let loops: [(down: RealWorldDemo.Track, up: RealWorldDemo.Track)]
        let outerLoops: [(down: RealWorldDemo.Track, up: RealWorldDemo.Track)]
        let crossovers: [TrackEdgeID]
        let yards: [RealWorldDemo.Track]
    }

    /// Where a station's platforms lie along `path`, staggered: centred on
    /// the point of the path nearest the station, moved in from either end
    /// of the path so it keeps clear of it.
    static func platformZone(on path: WorldPath, at point: WorldVector) -> ClosedRange<Double> {
        let half = Double(platformLength + 3 * platformStagger) / 2
        let room = half + RealWorldDemo.platformMargin
        let middle = min(max(path.project(point), room), path.length - room)
        return (middle - half)...(middle + half)
    }

    // MARK: - The lines

    /// The three lines with their runs, the sets of each standing where its
    /// first runs leave; and the rules that make them high-speed lines
    /// (``ServiceLine/isHighSpeed``).
    ///
    /// Every leg says where it runs
    /// (``GameWorld/setLineRoutePreferences(_:to:pattern:)``), so each way
    /// keeps to its own track: the shortest way would at times run on the
    /// other's, against its trains. The all-stops line names the platforms
    /// it calls at between the ends, on the down track's loop southbound
    /// and the up track's northbound (the legs into the two ends name none:
    /// a set takes the nearest free platform there). An express names its
    /// whole way along the through track (``Through``): only its platform,
    /// and it would take a loop it passes where the loop is on the inside
    /// of a curve, a little shorter.
    static func run(
        in world: inout GameWorld, language: DisplayLanguage, timetable: HighSpeedTimetable, stations: [StationID], platforms: [Int: Built.Platforms],
        ends: [Int: [TrackPlatform]], through: Through
    ) throws(GameError) {
        // Traffic control is off (see ``HighSpeedDemo``).
        try world.setTrafficControl(false)
        func endPlatform(of stop: Int) -> TrackPlatform? {
            ends[stop]?.first
        }
        var placing: [Int: [(train: TrainID, southbound: Bool, leaving: Int64)]] = [:]
        var number = 0
        for (kind, timetableLine) in timetable.lines.enumerated() {
            let stops = timetableLine.stops
            let line = try world.createLine(named: language.text(timetableLine.english, timetableLine.chinese), stops: stops.map { stations[$0] }).id
            try world.setLinePerformance(line, to: .highSpeed)
            try world.setLineRuns(line, to: timetableLine.runs)
            let calling = kind == 0
            func platform(of stop: Int, onDown: Bool) -> TrackPlatform? {
                platforms[stop].map { onDown ? (calling ? $0.downLoop : $0.down) : (calling ? $0.upLoop : $0.up) }
            }
            var preferences: [LineRoutePreference] = []
            for (from, to) in zip(stops.indices, stops.indices.dropFirst()) {
                let (a, b) = (stops[from], stops[to])
                if calling {
                    if let southbound = platform(of: b, onDown: true) {
                        preferences.append(LineRoutePreference(from: from, to: to, platform: southbound))
                    }
                    if let northbound = platform(of: a, onDown: false) {
                        preferences.append(LineRoutePreference(from: to, to: from, platform: northbound))
                    }
                    continue
                }
                // An express's leg passes stations whose loops may be the
                // shorter way on the inside of a curve: it names its whole
                // way along the through track. A set that is not on the way
                // (one in an end's yard) goes to the nearest platform, its
                // own way's through track's (see ``platformStagger``).
                guard let south = platform(of: b, onDown: true) ?? endPlatform(of: b), let north = platform(of: a, onDown: false) ?? endPlatform(of: a),
                      let start = platform(of: a, onDown: true) ?? endPlatform(of: a), let end = platform(of: b, onDown: false) ?? endPlatform(of: b)
                else { continue }
                preferences.append(LineRoutePreference(from: from, to: to, tracks: through.southbound(from: start.edge, to: south.edge), platform: south))
                preferences.append(LineRoutePreference(from: to, to: from, tracks: through.northbound(from: end.edge, to: north.edge), platform: north))
            }
            try world.setLineRoutePreferences(line, to: preferences)
            for set in timetableLine.overnight {
                number += 1
                let train = try world.purchaseTrain(named: language.text("THSR \(number)", "高鐵 \(number)")).id
                try world.setTrainType(train, to: .highSpeed)
                try world.setTrainCars(train, to: cars)
                try world.setTrainPerformance(train, to: .highSpeed)
                try world.assignTrain(train, to: line)
                placing[set.station, default: []].append((train, set.southbound, set.leaving))
            }
        }
        // At midnight each set stands where its first run leaves, facing
        // the way it goes: at an end the earliest to leave nearest the line;
        // at a station between, the last to leave on the loops and the
        // first on the through tracks, clear of the expresses before they
        // come.
        for station in placing.keys.sorted() {
            let sets = placing[station]!.sorted { ($0.leaving, $0.train) < ($1.leaving, $1.train) }
            if let berths = ends[station] {
                for (set, berth) in zip(sets, berths) {
                    try place(set.train, at: berth, southbound: set.southbound, in: &world)
                }
                continue
            }
            guard let p = platforms[station] else { continue }
            var loops = [p.downLoop, p.upLoop] + (p.outer.map { [$0.down, $0.up] } ?? [])
            var throughs = [p.down, p.up]
            for set in sets.reversed() {
                // The set's own way's track first.
                func pick(_ berths: inout [TrackPlatform]) -> TrackPlatform? {
                    let own = berths.firstIndex { ($0 == p.downLoop || $0 == p.down || $0 == p.outer?.down) == set.southbound } ?? 0
                    return berths.isEmpty ? nil : berths.remove(at: own)
                }
                guard let berth = pick(&loops) ?? pick(&throughs) else { break }
                try place(set.train, at: berth, southbound: set.southbound, in: &world)
            }
        }
    }

    /// Puts `train` at `platform`, facing the way it leaves: southbound at
    /// its far end along the edge, northbound at its near end, the edge
    /// run the other way.
    static func place(_ train: TrainID, at platform: TrackPlatform, southbound: Bool, in world: inout GameWorld) throws(GameError) {
        guard let length = world.trackEdge(platform.edge)?.length else { return }
        let offset = southbound ? platform.end : length - platform.start
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: platform.edge, direction: southbound ? .forward : .backward), offset: offset))
        try world.setTrainContinuation(train, along: [], stoppingAt: offset)
        try world.useTrainPerformanceForMovement(train)
    }
}

extension RealWorldDemo.TrackPlan {
    /// Track beside `plan` (the high-speed demo's up track): a node at each
    /// of `plan`'s nodes `at`, `offsets` from it to the side
    /// (``WorldVector/normal`` of the way the track runs there), and cubic
    /// edges that leave and reach each node along that way, as
    /// ``init(_:forced:avoiding:looseUntil:close:start:end:rise:structure:tolerance:longestEdge:)``
    /// lays them, flat on the ground. Where two nodes in a row stand off by
    /// the same, the edge between runs beside `plan`'s that far off it;
    /// where they differ, it is a ramp from the one to the other.
    init(beside plan: RealWorldDemo.TrackPlan, at indices: [Int], offsets: [Double]) {
        let distances = indices.map { plan.distances[$0] }
        let nodes = zip(indices, offsets).map { index, offset in
            let node = plan.nodes[index], direction = node.direction.unit
            return (point: (WorldVector(node.point) + direction.normal * offset).plan, direction: direction)
        }
        path = plan.path
        structure = .surface
        self.distances = distances
        self.nodes = nodes
        heights = distances.map { _ in 0 }
        curves = distances.indices.dropLast().map { index in
            let handle = (distances[index + 1] - distances[index]) / 3
            let c1 = WorldVector(nodes[index].point) + nodes[index].direction * handle
            let c2 = WorldVector(nodes[index + 1].point) - nodes[index + 1].direction * handle
            return .cubic(c1.plan, c2.plan)
        }
    }
}
