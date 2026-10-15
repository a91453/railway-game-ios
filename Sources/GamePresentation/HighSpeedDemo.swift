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
///   other way's track. Each end has the real station's platform tracks
///   (decision 228, ``endPlatformTracks``, from OpenStreetMap): Nangang
///   six, Zuoying eight, the down track's and tracks beside it.
/// - Three depots stand where the real ones do (decision 221,
///   ``realDepots``, from OpenStreetMap): Nangang's sidings beyond its
///   station, Wuri's south of Taichung and Zuoying's north of its station,
///   each a ladder of dead-end sidings beside the down track, one for each
///   set that stands there at night (``Depot``). Every line keeps its sets
///   in them: a set goes into the nearest when no run wants it for two
///   hours, and comes out in time for its next run.
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
/// - Every leg says where it runs (``run(in:language:timetable:stations:platforms:ends:through:depots:)``):
///   southbound on the down track, northbound on the up track, so each way
///   keeps to its own track and the trains of the two ways meet only where
///   a set turns back. Every set calls on the loops, as at the real side
///   platforms, but the expresses at Taipei and Banqiao, whose island
///   platforms serve the through tracks (``islandStations``); an express
///   passes a station on its through track (decision 228).
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
///   a half to two hours late, at some 40 minutes of computing a game day.
///   Off, the sets of real runs keep apart by decision 228's rules: a set
///   takes a platform no other is due on while it is there, stops behind
///   the set ahead, waits for one coming the other way on the track they
///   share, and lets a faster one pass at a station. The depots, the
///   crossovers and the staggered platforms are what traffic control would
///   need when its rules allow it.
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
    /// How long each siding of a depot takes to move a track's width out
    /// from the one before.
    static let yardStep = 60.0 * RealWorldDemo.metre
    /// How far beyond a turnback station's loops its crossovers begin, and
    /// how long they are.
    static let crossoverReach = 100.0 * RealWorldDemo.metre
    /// How far apart a station's platforms are staggered along the line
    /// (decision 197): more than two tracks 5 m apart differ in length over
    /// any stretch of the line, the offset times the way it turns, at most
    /// a right angle on the High Speed Rail.
    static let platformStagger = Int64(10 * WorldCoordinate.unitsPerMetre)

    /// How many platform tracks each end has (decision 228): the real
    /// stations' from OpenStreetMap (`tools/hsr-platforms/hsr_platforms.json`,
    /// ODbL 1.0): Nangang's six tracks between three island platforms,
    /// Zuoying's six beside its three of its eight. One is the down
    /// track's; the others lie beside it, ``endTrackSides``.
    static let endPlatformTracks = (north: 6, south: 8)

    /// The stations between the ends whose real platforms are islands
    /// serving every track (`tools/hsr-platforms/hsr_platforms.json`):
    /// Taipei and Banqiao, by index. The others have side platforms beside
    /// their loops and through tracks without (decision 228).
    static let islandStations: Set<Int> = [1, 2]

    /// How many of an end's tracks beside the down track lie on each side
    /// of it (decision 228): east first, then west, nested, the outermost
    /// leaving the down track a ramp before the one inside it. Nangang's
    /// run through and join the down track again beyond the platform, by
    /// its depot; Zuoying's end with the line, past the platform.
    static func endTrackSides(_ tracks: Int) -> (east: Int, west: Int) {
        (tracks / 2, (tracks - 1) / 2)
    }

    /// How the stations are numbered by the real data: the High Speed Rail's
    /// station names, north to south.
    static let stationNames = ["南港", "台北", "板橋", "桃園", "新竹", "苗栗", "台中", "彰化", "雲林", "嘉義", "台南", "左營"]

    /// What the demo is built from (decision 240: the TRA demo is built
    /// the same way, from its own).
    static let spec = RealLineDemoSpec(
        path: { railways, frame in
            // The line's pieces, in the data's order, each beginning where
            // the one before ends.
            railways.lines.filter { $0.name == "高鐵" }.sorted { $0.id < $1.id }.flatMap { line in
                line.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) }
            }
        },
        stationNames: stationNames,
        stationIDPrefix: "thsr_sched|",
        schedule: "thsr",
        kinds: HighSpeedTimetable.kinds.map {
            RealLineDemoSpec.Kind(
                english: $0.english, chinese: $0.chinese, stops: $0.stops, models: nil,
                type: .highSpeed, cars: cars, performance: .highSpeed, set: ("THSR", "高鐵")
            )
        },
        endPlatformTracks: endPlatformTracks,
        islandStations: islandStations,
        depots: realDepots,
        tolerance: tolerance,
        longestEdge: longestEdge,
        landAt: landAt,
        opensAt: opensAt
    )

    /// The world's frame: Taiwan's, as the whole-Taiwan game lays it.
    static var frame: RealWorldFrame {
        RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)
    }

    /// Why the demo cannot be built from the real data (or the TRA demo,
    /// decision 240).
    public enum Failure: Error, Hashable, Sendable {
        /// The railways have no High Speed Rail line, or not its twelve
        /// stations (the TRA demo: not its line or stations).
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
        try make(spec, in: language, railways: railways, population: population, places: places, water: water, coverage: coverage, eventSeed: eventSeed)
    }

    /// A demo of `spec`'s line (decision 240): built as the high-speed
    /// demo is, and opened at `spec`'s minute of the first day.
    static func make(
        _ spec: RealLineDemoSpec, in language: DisplayLanguage, railways: RealRailways, population: PopulationGrid?, places: PlaceGrid?,
        water: WaterGrid?, coverage: CoverageGrid?, eventSeed: UInt32
    ) throws(Failure) -> GameWorld {
        let layout = try Layout(railways: railways, spec: spec)
        var world = newWorld(paying: layout.cost(at: ConstructionCosts.newGame), eventSeed: eventSeed)
        do throws(GameError) {
            try layout.build(in: &world, language: language)
            // Until the first sets leave (the High Speed Rail's at 05:50)
            // nothing runs and no one is waiting, so the night passes
            // before the land's people are read in; the game then opens
            // later in the morning.
            world.setSpeed(.fast)
            try world.advance(ticks: Int(spec.landAt / 10))
            GameSession.readLand(roundStationsOf: &world, population: population, places: places, water: water, coverage: coverage)
            try world.advance(ticks: Int((spec.opensAt - spec.landAt) / 10))
            world.setSpeed(.normal)
        } catch {
            preconditionFailure("The demo of \(spec.schedule) no longer builds: \(error)")
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
        // Decision 207: its timetables are as they were measured.
        world.setRealisticOperation(false)
        // Decision 212: its traffic control takes whole legs as measured.
        world.setBlockSections(false)
        world.setCurveSpeedLimits(false)
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

    /// A real depot (decision 221): its name and where OpenStreetMap has
    /// its yard tracks (`tools/hsr-depots/hsr_depots.json`, the centre of
    /// each cluster; ODbL 1.0).
    struct RealDepot: Sendable {
        let english: String
        let chinese: String
        let latitude: Double
        let longitude: Double
        /// How far along the line, south, the demo lays its sidings from
        /// where the real yard is (decision 240): beyond a station's own
        /// tracks, or a curve, where the yard lies by them.
        var shift: Double = 0
    }

    /// The High Speed Rail's depots the demo keeps its sets in: Nangang's
    /// sidings beyond its station (towards Xizhi), Wuri's south of Taichung
    /// and Zuoying's north of its station.
    static let realDepots = [
        RealDepot(english: "Nangang Depot", chinese: "南港機廠", latitude: 25.054203, longitude: 121.615057),
        RealDepot(english: "Wuri Depot", chinese: "烏日機廠", latitude: 24.093566, longitude: 120.624164),
        RealDepot(english: "Zuoying Depot", chinese: "左營機廠", latitude: 22.696992, longitude: 120.318536),
    ]

    /// The sidings a depot has beyond one for each set that stands there on
    /// the first night: one to spare. Over a week the sets stand each night
    /// where they stood the first.
    static let spareSidings = 1

    /// How long each siding of a depot runs beside the down track past its
    /// ladder: a set's platform with a margin either side, and a ramp.
    static let sidingRun = Double(platformLength) + 2 * RealWorldDemo.platformMargin + rampLength

    /// A depot as laid out (decision 221): a ladder of dead-end sidings
    /// beside the down track, on the side OpenStreetMap has the real one,
    /// centred where it lies along the line. Each side's first siding
    /// leaves the down track at ``entry``, each other from the one before
    /// it a `yardStep` further in and a track's width further out; all run
    /// beside the down track to ``deadEnd``, each with a platform for one
    /// set before its end. One siding for each set that stands there at
    /// night. A depot beyond the line's end (Nangang's) has sidings both
    /// sides of the down track.
    struct Depot {
        let real: RealDepot
        /// Where its sidings leave the down track and where they end, along
        /// the down track's path.
        let entry: Double
        let deadEnd: Double
        /// Each side's sidings, the nearest the down track first: east of
        /// it (the down track's side), then west.
        let east: [RealWorldDemo.TrackPlan]
        let west: [RealWorldDemo.TrackPlan]
        /// The station whose sets stand here, by index: the depot serves it
        /// from that way.
        let serving: [Int]
        /// How long each siding's platform is (``RealLineDemoSpec/platformLength``).
        let platformLength: Int64

        /// Whether the sidings run south of where they leave the down
        /// track, so that a set leaves them northbound.
        var southward: Bool { deadEnd > entry }

        /// Where the platform of each siding lies along the down track's
        /// path: before its dead end, a margin short of it.
        var platform: ClosedRange<Double> {
            let margin = RealWorldDemo.platformMargin, length = Double(platformLength)
            return southward ? (deadEnd - margin - length)...(deadEnd - margin) : (deadEnd + margin)...(deadEnd + margin + length)
        }
    }

    /// Where everything goes: worked out before anything is built, so the
    /// game can start with what it costs.
    ///
    /// Two tracks: ``plan``, the down track on the real alignment from
    /// Nangang's end to Zuoying's, and ``up``, the up track beside it,
    /// west of it as the real trains keep left, which leaves the down track
    /// at ``junctions`` a ramp beyond the ends' platforms.
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
        /// Each end's tracks beside the down track (decision 228), east
        /// then west, each with a platform: Nangang's from a ramp south of
        /// its platform to a ramp north of it, Zuoying's from a ramp north of
        /// its platform to past it, where they end.
        let endTracks: (north: [RealWorldDemo.TrackPlan], south: [RealWorldDemo.TrackPlan])
        /// The real depots (decision 221), north to south.
        let depots: [Depot]
        /// The crossovers from the up track to the down track north of a
        /// depot beside the line south of a station where sets turn back
        /// (Wuri's): a set that came in northbound there runs south along
        /// the up track and over to the down track to reach it.
        let depotCrossovers: [RealWorldDemo.TrackPlan]
        let stops: [Stop]
        let platforms: [ClosedRange<Double>]
        let timetable: HighSpeedTimetable
        /// Where the up track leaves the down track by Nangang and joins it
        /// again by Zuoying, along the down track's path.
        let junctions: (north: Double, south: Double)
        /// What it is built from (decision 240).
        let spec: RealLineDemoSpec

        init(railways: RealRailways, spec: RealLineDemoSpec = HighSpeedDemo.spec) throws(Failure) {
            self.spec = spec
            let frame = HighSpeedDemo.frame
            let points = spec.path(railways, frame)
            let stops = spec.stationNames.compactMap { name in
                railways.stations.first { $0.id == "\(spec.stationIDPrefix)\(name)" }.map {
                    Stop(station: $0, point: WorldVector(frame.worldPosition(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)))
                }
            }
            guard points.count > 1, stops.count == spec.stationNames.count else { throw .noHighSpeedRail }
            guard let schedule = railways.operations?.schedule(forSystem: spec.schedule) else { throw .noTimetable }
            let path = WorldPath(points)
            let platforms = stops.map { HighSpeedDemo.platformZone(on: path, at: $0.point, length: spec.platformLength) }
            self.stops = stops
            self.platforms = platforms
            let timetable = HighSpeedTimetable(
                schedule: schedule, names: spec.stationNames, distances: platforms.map { ($0.lowerBound + $0.upperBound) / 2 }, kinds: spec.kinds
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
            // Decision 221: the depots, where OpenStreetMap has them along
            // the line. The sets standing at a station at night stand in the
            // depot nearest it along the line, one siding each.
            let middles = platforms.map { ($0.lowerBound + $0.upperBound) / 2 }
            let places = spec.depots.map { depot -> (along: Double, side: Double) in
                let point = WorldVector(frame.worldPosition(latitude: depot.latitude, longitude: depot.longitude))
                let along = path.project(point)
                return (along + depot.shift, (point - path.point(at: along)).dot(path.tangent(at: along).normal))
            }
            var serving = places.map { _ in [Int]() }
            for station in standing.indices where standing[station] > 0 {
                let nearest = places.indices.min { abs(places[$0].along - middles[station]) < abs(places[$1].along - middles[station]) }!
                serving[nearest].append(station)
            }
            // Decision 228: a station between the ends whose sets stand at
            // night in the depot beyond Nangang (Taipei's) turns them north
            // there and back: a crossover beyond its north end, so a set on
            // its down side goes over to the up track at once rather than
            // north along the down track to Nangang.
            for (index, place) in places.enumerated() where place.along < platforms[0].lowerBound {
                for station in serving[index] where station != 0 && station != last {
                    turns[station] = (true, turns[station]?.south ?? false)
                }
            }
            let turnbacks = Set(turns.keys)
            let between = Array(platforms.indices.dropFirst().dropLast())
            // A turnback station with more sets at night than its loops
            // take has a second loop beside each.
            let outer = Set(turnbacks.filter { standing[$0] > 2 })

            let ramp = HighSpeedDemo.rampLength, margin = RealWorldDemo.platformMargin, step = HighSpeedDemo.yardStep
            let reach = HighSpeedDemo.crossoverReach
            // Decision 228: each end's tracks beside the down track, the
            // outermost on a side leaving it `reach` ramps from the
            // platform's margin.
            let sides = (north: HighSpeedDemo.endTrackSides(spec.endPlatformTracks.north), south: HighSpeedDemo.endTrackSides(spec.endPlatformTracks.south))
            let endReach = (north: Double(max(sides.north.east, sides.north.west)), south: Double(max(sides.south.east, sides.south.west)))
            // The turnouts a ramp beyond each end's tracks, the up track's
            // ramps a ramp long.
            let junctions = (north: platforms[0].upperBound + margin + (endReach.north + 1) * ramp, south: platforms[last].lowerBound - margin - (endReach.south + 1) * ramp)
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

            // Where each depot's sidings leave the down track and end, and
            // how many on each side.
            let ladders = places.indices.compactMap { index -> (real: RealDepot, entry: Double, deadEnd: Double, east: Int, west: Int, serving: [Int])? in
                let standingThere = serving[index].reduce(0) { $0 + standing[$1] }
                guard standingThere > 0 else { return nil }
                let sets = standingThere + HighSpeedDemo.spareSidings
                let place = places[index], real = spec.depots[index]
                if place.along < platforms[0].lowerBound {
                    // Beyond the north end: both sides of the down track,
                    // running north from a ramp short of the platform.
                    let east = (sets + 1) / 2, west = sets / 2
                    let entry = platforms[0].lowerBound - margin - (endReach.north + 1) * ramp
                    return (real, entry, entry - Double(east) * step - spec.sidingRun, east, west, serving[index])
                }
                // Beside the line: on the down track's side, east, where the
                // real ones are; entered from the way of the stations it
                // serves, and centred on the real one.
                precondition(place.side < 0, "\(real.english) is not on the down track's side")
                let away: Double = place.along > middles[serving[index][0]] ? 1 : -1
                let extent = Double(sets) * step + spec.sidingRun
                return (real, place.along - away * extent / 2, place.along + away * extent / 2, sets, 0, serving[index])
            }
            // A depot south of a station between the ends, entered from its
            // north (Wuri's): the crossover from the up track a reach and two
            // before its entry.
            // Decision 240: also one that serves an end as well (the TRA
            // demo's Yilan sidings keep Toucheng's sets too).
            let crossingInto = ladders.filter { $0.deadEnd > $0.entry && $0.serving.contains { between.contains($0) } }
                .map { [$0.entry - 2 * reach, $0.entry - reach] }
            func depotNodes(_ ladder: (real: RealDepot, entry: Double, deadEnd: Double, east: Int, west: Int, serving: [Int])) -> [Double] {
                let way: Double = ladder.deadEnd > ladder.entry ? 1 : -1
                let far = ladder.deadEnd - way * (2 * margin + Double(spec.platformLength))
                return (0...max(ladder.east, ladder.west)).map { ladder.entry + way * Double($0) * step } + [far, ladder.deadEnd]
            }
            var forced: [Double] = [0, path.length, junctions.north, upEnds.north, upEnds.south, junctions.south]
            forced += between.flatMap { loopNodes(platforms[$0]) }
            forced += outer.flatMap { [outerEnds($0).north, outerEnds($0).south] }
            forced += turnbacks.flatMap { crossoverNodes($0).flatMap { $0 } }
            // Decision 228: the ends' tracks' nodes, `k` ramps out for the
            // `k`th on a side.
            func endNodes(_ zone: ClosedRange<Double>, northward: Bool, reach: Double) -> [Double] {
                let nodes = (1...Int(reach)).map { zone.lowerBound - margin - Double($0) * ramp } + [zone.lowerBound - margin, zone.upperBound + margin]
                return northward ? nodes : nodes + (1...Int(reach)).map { zone.upperBound + margin + Double($0) * ramp }
            }
            forced += endNodes(platforms[0], northward: false, reach: endReach.north)
            forced += endNodes(platforms[last], northward: true, reach: endReach.south)
            forced += ladders.flatMap(depotNodes)
            forced += crossingInto.flatMap { $0 }
            let plan = RealWorldDemo.TrackPlan(
                path, forced: forced, avoiding: platforms, tolerance: spec.tolerance, longestEdge: spec.longestEdge
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
            // Decision 228: the ends' tracks, the `k`th on a side `k`
            // tracks' widths out (east is the down track's left: negative).
            func ends(_ zone: ClosedRange<Double>, sides: (east: Int, west: Int), through: Bool) -> [RealWorldDemo.TrackPlan] {
                [(sides.east, -1.0), (sides.west, 1.0)].flatMap { count, side -> [RealWorldDemo.TrackPlan] in
                    guard count > 0 else { return [] }
                    return (1...count).map { k in
                        let out = side * Double(k) * offset, away = Double(k) * ramp
                        let distances = [zone.lowerBound - margin - away, zone.lowerBound - margin, zone.upperBound + margin] + (through ? [zone.upperBound + margin + away] : [])
                        return RealWorldDemo.TrackPlan(beside: plan, at: distances.map(index), offsets: [0, out, out] + (through ? [0] : []))
                    }
                }
            }
            endTracks = (north: ends(platforms[0], sides: sides.north, through: true), south: ends(platforms[last], sides: sides.south, through: false))
            turnbackReach = Dictionary(uniqueKeysWithValues: turnbacks.map { station in
                let nodes = crossoverNodes(station).flatMap { $0 } + [outerEnds(station).north, outerEnds(station).south]
                return (station, nodes.min()!...nodes.max()!)
            })
            crossovers = Dictionary(uniqueKeysWithValues: turnbacks.map { station in
                (station, crossoverNodes(station).map { RealWorldDemo.TrackPlan(beside: plan, at: $0.map(index), offsets: [offset, 0]) })
            })
            depotCrossovers = crossingInto.map { RealWorldDemo.TrackPlan(beside: plan, at: $0.map(index), offsets: [offset, 0]) }
            // A depot's siding `k` (from 1) on a side (`way` 1 west, -1
            // east): from the one before it (the first from the down track)
            // `k - 1` steps in from the entry, out to its place a step on,
            // and beside the down track's every node from there to the dead
            // end; its nodes in order along the path.
            depots = ladders.map { ladder in
                let way: Double = ladder.deadEnd > ladder.entry ? 1 : -1
                func siding(_ k: Int, side: Double) -> RealWorldDemo.TrackPlan {
                    let branch = index(ladder.entry + way * Double(k - 1) * step), out = index(ladder.entry + way * Double(k) * step)
                    let end = index(ladder.deadEnd)
                    let beside = way > 0 ? Array(out...end) : Array((end...out).reversed())
                    let at = [branch] + beside
                    let offsets = [side * Double(k - 1) * offset] + beside.map { _ in side * Double(k) * offset }
                    return way > 0
                        ? RealWorldDemo.TrackPlan(beside: plan, at: at, offsets: offsets)
                        : RealWorldDemo.TrackPlan(beside: plan, at: at.reversed(), offsets: offsets.reversed())
                }
                return Depot(
                    real: ladder.real, entry: ladder.entry, deadEnd: ladder.deadEnd,
                    east: ladder.east > 0 ? (1...ladder.east).map { siding($0, side: -1) } : [],
                    west: ladder.west > 0 ? (1...ladder.west).map { siding($0, side: 1) } : [],
                    serving: ladder.serving,
                    platformLength: spec.platformLength
                )
            }
        }

        /// The sets the timetable needs, every line's.
        var sets: Int {
            timetable.lines.reduce(0) { $0 + $1.sets }
        }

        /// The cars of every set the timetable needs, all lines' (decision
        /// 240: each kind's own).
        var setCars: [Int] {
            zip(timetable.lines, spec.kinds).flatMap { line, kind in Array(repeating: kind.cars, count: line.sets) }
        }

        /// Every piece of track beside the down track.
        private var pieces: [RealWorldDemo.TrackPlan] {
            var pieces: [RealWorldDemo.TrackPlan] = [up]
            pieces += loops.values.flatMap { [$0.down, $0.up] }
            pieces += outerLoops.values.flatMap { [$0.down, $0.up] }
            pieces += crossovers.values.flatMap { $0 }
            pieces += depotCrossovers
            pieces += endTracks.north + endTracks.south
            pieces += depots.flatMap { $0.east + $0.west }
            return pieces
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
            let stations = Int64(stops.count + depots.count) * costs.station.amount
            let trains = setCars.map { costs.train.amount + Int64($0 - 1) * costs.car.amount }.reduce(0, +)
            return Money(track + stations + trains)
        }

        /// Builds it: the down track, the up track from turnout to turnout,
        /// the loops, the crossovers, the depots' sidings, the stations and
        /// their platforms, the depots, and the lines.
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
            // Decision 228: each end's tracks from the down track, through
            // Nangang's to it again, Zuoying's to their ends.
            let builtEnds = (
                north: try endTracks.north.map { track throws(GameError) in try track.build(in: &world, start: node(down, first(track)), end: node(down, last(track))) },
                south: try endTracks.south.map { track throws(GameError) in try track.build(in: &world, start: node(down, first(track))) }
            )
            for crossover in depotCrossovers {
                crossoverEdges += try crossover.build(in: &world, start: node(upTrack, first(crossover)), end: node(down, last(crossover))).edges
            }
            // Each siding from the one before it (the first from the down
            // track), at its branching node: the first node along the path
            // of a southward depot's sidings, the last of a northward one's.
            func build(_ side: [RealWorldDemo.TrackPlan], southward: Bool) throws(GameError) -> [RealWorldDemo.Track] {
                var tracks: [RealWorldDemo.Track] = []
                for plan in side {
                    let from = tracks.last ?? down
                    tracks.append(southward
                        ? try plan.build(in: &world, start: node(from, first(plan)))
                        : try plan.build(in: &world, end: node(from, last(plan))))
                }
                return tracks
            }
            let sidings = try depots.map { depot throws(GameError) in
                (east: try build(depot.east, southward: depot.southward), west: try build(depot.west, southward: depot.southward))
            }
            var ids: [StationID] = []
            var platformsOf: [Int: Built.Platforms] = [:]
            var ends: [Int: [TrackPlatform]] = [:]
            for (index, (stop, zone)) in zip(stops, platforms).enumerated() {
                let middle = plan.path.point(at: (zone.lowerBound + zone.upperBound) / 2)
                let id = try world.buildStation(named: stop.station.name(in: language), at: middle.plan).id
                func platform(on track: RealWorldDemo.Track, shift: Int64 = 0) throws(GameError) -> TrackPlatform {
                    let (edge, offset) = track.edge(at: zone.lowerBound, in: world)
                    try world.addTrackPlatform(id, on: edge, from: offset + shift, to: offset + shift + spec.platformLength)
                    return TrackPlatform(station: id, edge: edge, start: offset + shift, end: offset + shift + spec.platformLength)
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
                    // An end: a platform on the down track and one on each of
                    // its tracks beside it (decision 228).
                    ends[index] = [try platform(on: down)] + (try (index == 0 ? builtEnds.north : builtEnds.south).map { track throws(GameError) in try platform(on: track) })
                }
                ids.append(id)
            }
            // Decision 221: each depot, a station by its sidings with a
            // platform on each, the nearest the down track first, each side
            // by turns.
            var builtDepots: [Built.Depot] = []
            for (depot, tracks) in zip(depots, sidings) {
                let zone = depot.platform
                var order: [RealWorldDemo.Track] = []
                for k in 0..<max(tracks.east.count, tracks.west.count) {
                    if k < tracks.east.count { order.append(tracks.east[k]) }
                    if k < tracks.west.count { order.append(tracks.west[k]) }
                }
                let middle = plan.path.point(at: (depot.entry + depot.deadEnd) / 2)
                let id = try world.buildStation(named: language.text(depot.real.english, depot.real.chinese), at: middle.plan).id
                var berths: [TrackPlatform] = []
                for track in order {
                    let (edge, offset) = track.edge(at: zone.lowerBound, in: world)
                    try world.addTrackPlatform(id, on: edge, from: offset, to: offset + spec.platformLength)
                    berths.append(TrackPlatform(station: id, edge: edge, start: offset, end: offset + spec.platformLength))
                }
                try world.setStationDepot(id, to: true)
                builtDepots.append(Built.Depot(station: id, berths: berths, southward: depot.southward, serving: depot.serving))
            }
            let turnouts = (north: plan.distances.firstIndex { abs($0 - junctions.north) < 1 }!, south: plan.distances.firstIndex { abs($0 - junctions.south) < 1 }!)
            let through = Through(down: down, up: upTrack, loops: builtLoops, turnouts: turnouts)
            try HighSpeedDemo.run(
                in: &world, language: language, spec: spec, timetable: timetable, stations: ids, platforms: platformsOf, ends: ends, through: through, depots: builtDepots
            )
            return Built(
                down: down, up: upTrack, loops: builtLoops.keys.sorted().map { builtLoops[$0]! }, outerLoops: builtOuter.keys.sorted().map { builtOuter[$0]! },
                crossovers: crossoverEdges, depots: builtDepots, sidings: sidings.flatMap { $0.east + $0.west }, ends: builtEnds.north + builtEnds.south
            )
        }
    }

    /// The two through tracks and the loops beside them, for an express's
    /// way along them (decision 228): along the through track, and onto a
    /// station's loop only where it calls; `turnouts` are the down track's
    /// nodes where the up track leaves and joins it, by their place along
    /// it.
    struct Through {
        let down: RealWorldDemo.Track
        let up: RealWorldDemo.Track
        /// The loops of the stations between the ends, by station.
        let loops: [Int: (down: RealWorldDemo.Track, up: RealWorldDemo.Track)]
        let turnouts: (north: Int, south: Int)

        /// The edges of `track` from `a` to `b` along the path, north to
        /// south.
        private func piece(_ track: RealWorldDemo.Track, from a: Double, to b: Double) -> ArraySlice<TrackEdgeID> {
            let d = track.plan.distances
            guard let i = track.edges.indices.first(where: { d[$0] >= a - 1 }),
                  let j = track.edges.indices.last(where: { d[$0 + 1] <= b + 1 }), i <= j else { return [] }
            return track.edges[i...j]
        }

        /// Southbound from `start` to `end`, each a platform on the down
        /// track or on a down loop: off the loop it starts on, along the
        /// down track, and onto the loop it ends on.
        func southbound(from start: TrackPlatform, to end: TrackPlatform) -> [TrackTraversal] {
            var edges: [TrackEdgeID] = []
            let from: Double
            if let loop = loops.values.first(where: { $0.down.edges.contains(start.edge) })?.down {
                edges += loop.edges[loop.edges.firstIndex(of: start.edge)!...]
                from = loop.plan.distances[loop.plan.distances.count - 1]
            } else {
                guard let i = down.edges.firstIndex(of: start.edge) else { return [] }
                from = down.plan.distances[i]
            }
            if let loop = loops.values.first(where: { $0.down.edges.contains(end.edge) })?.down {
                edges += piece(down, from: from, to: loop.plan.distances[0])
                edges += loop.edges[...loop.edges.firstIndex(of: end.edge)!]
            } else {
                guard let j = down.edges.firstIndex(of: end.edge) else { return [] }
                edges += piece(down, from: from, to: down.plan.distances[j + 1])
            }
            return edges.map { TrackTraversal(edge: $0, direction: .forward) }
        }

        /// Northbound from `start` to `end`: from Zuoying's platform on the
        /// down track up to the south turnout first, or off the up loop it
        /// starts on; then along the up track; and onto the up loop it ends
        /// on, or on the down track again from the north turnout to
        /// Nangang's platform.
        func northbound(from start: TrackPlatform, to end: TrackPlatform) -> [TrackTraversal] {
            var edges: [TrackEdgeID] = []
            let from: Double
            if let loop = loops.values.first(where: { $0.up.edges.contains(start.edge) })?.up {
                edges += loop.edges[...loop.edges.firstIndex(of: start.edge)!].reversed()
                from = loop.plan.distances[0]
            } else if let i = down.edges.firstIndex(of: start.edge) {
                edges += down.edges[turnouts.south...i].reversed()
                from = up.plan.distances[up.plan.distances.count - 1]
            } else {
                guard let i = up.edges.firstIndex(of: start.edge) else { return [] }
                from = up.plan.distances[i + 1]
            }
            if let loop = loops.values.first(where: { $0.up.edges.contains(end.edge) })?.up {
                edges += piece(up, from: loop.plan.distances[loop.plan.distances.count - 1], to: from).reversed()
                edges += loop.edges[loop.edges.firstIndex(of: end.edge)!...].reversed()
            } else if let j = down.edges.firstIndex(of: end.edge) {
                edges += piece(up, from: up.plan.distances[0], to: from).reversed()
                edges += down.edges[j..<turnouts.north].reversed()
            } else {
                guard let j = up.edges.firstIndex(of: end.edge) else { return [] }
                edges += piece(up, from: up.plan.distances[j], to: from).reversed()
            }
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

        /// A depot as built (decision 221): its station, a berth on each
        /// siding, the nearest the down track first, whether its sidings run
        /// south, and the stations whose sets it keeps.
        struct Depot {
            let station: StationID
            let berths: [TrackPlatform]
            let southward: Bool
            let serving: [Int]
        }

        let down: RealWorldDemo.Track
        let up: RealWorldDemo.Track
        let loops: [(down: RealWorldDemo.Track, up: RealWorldDemo.Track)]
        let outerLoops: [(down: RealWorldDemo.Track, up: RealWorldDemo.Track)]
        /// The turnback stations' crossovers and the crossover into Wuri's
        /// depot.
        let crossovers: [TrackEdgeID]
        let depots: [Depot]
        /// Every depot's sidings.
        let sidings: [RealWorldDemo.Track]
        /// The ends' tracks beside the down track (decision 228),
        /// Nangang's then Zuoying's.
        let ends: [RealWorldDemo.Track]
    }

    /// Where a station's platforms lie along `path`, staggered: centred on
    /// the point of the path nearest the station, moved in from either end
    /// of the path so it keeps clear of it.
    static func platformZone(on path: WorldPath, at point: WorldVector, length: Int64 = platformLength) -> ClosedRange<Double> {
        let half = Double(length + 3 * platformStagger) / 2
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
    /// a set takes a free platform there, decision 228). An express names
    /// its whole way (``Through``): along the through track, and onto a
    /// loop only where it calls; only its platform, and it would take a
    /// loop it passes where the loop is on the inside of a curve, a little
    /// shorter.
    static func run(
        in world: inout GameWorld, language: DisplayLanguage, spec: RealLineDemoSpec = spec, timetable: HighSpeedTimetable, stations: [StationID], platforms: [Int: Built.Platforms],
        ends: [Int: [TrackPlatform]], through: Through, depots: [Built.Depot]
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
            let kindSpec = spec.kinds[kind]
            let line = try world.createLine(named: language.text(timetableLine.english, timetableLine.chinese), stops: stops.map { stations[$0] }).id
            try world.setLinePerformance(line, to: kindSpec.performance)
            try world.setLineRuns(line, to: timetableLine.runs)
            let calling = kind == 0
            // Decision 228: the sets call on the loops, as at the real
            // stations' side platforms beside their through tracks; but the
            // expresses at Taipei and Banqiao, whose island platforms serve
            // every track (``islandStations``), on the through tracks.
            func platform(of stop: Int, onDown: Bool) -> TrackPlatform? {
                platforms[stop].map { platforms in
                    let through = !calling && spec.islandStations.contains(stop)
                    return onDown ? (through ? platforms.down : platforms.downLoop) : (through ? platforms.up : platforms.upLoop)
                }
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
                // (one just out of a depot, turned round at an end) goes to
                // the nearest platform, its own way's through track's (see
                // ``platformStagger``).
                guard let south = platform(of: b, onDown: true) ?? endPlatform(of: b), let north = platform(of: a, onDown: false) ?? endPlatform(of: a),
                      let start = platform(of: a, onDown: true) ?? endPlatform(of: a), let end = platform(of: b, onDown: false) ?? endPlatform(of: b)
                else { continue }
                preferences.append(LineRoutePreference(from: from, to: to, tracks: through.southbound(from: start, to: south), platform: south))
                preferences.append(LineRoutePreference(from: to, to: from, tracks: through.northbound(from: end, to: north), platform: north))
            }
            try world.setLineRoutePreferences(line, to: preferences)
            // Decision 221: every line keeps its sets in the depots, each
            // going into the nearest.
            try world.setLineDepots(line, to: depots.map(\.station))
            for set in timetableLine.overnight {
                number += 1
                let train = try world.purchaseTrain(named: language.text("\(kindSpec.set.english) \(number)", "\(kindSpec.set.chinese) \(number)")).id
                try world.setTrainType(train, to: kindSpec.type)
                try world.setTrainCars(train, to: kindSpec.cars)
                try world.setTrainPerformance(train, to: kindSpec.performance)
                try world.assignTrain(train, to: line)
                placing[set.station, default: []].append((train, set.southbound, set.leaving))
            }
        }
        // At midnight each set stands in the depot of the station its first
        // run leaves, a siding each, facing the way out: the earliest to
        // leave nearest the down track. Each leaves the depot in time for
        // its run (decision 221).
        for depot in depots {
            let sets = depot.serving.flatMap { placing[$0] ?? [] }.sorted { ($0.leaving, $0.train) < ($1.leaving, $1.train) }
            for (set, berth) in zip(sets, depot.berths) {
                try place(set.train, at: berth, southbound: !depot.southward, in: &world)
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
