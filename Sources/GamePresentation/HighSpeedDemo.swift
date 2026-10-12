import Foundation
import GameCore

// The high-speed demo (ARCHITECTURE decision 170, the owner's idea): the
// real Taiwan High Speed Rail, Nangang to Zuoying, built as the game's own
// track on its real alignment over the whole of Taiwan, with its twelve
// stations, its high-speed sets and its three stopping patterns running, so
// that high-speed rail (decision 168) can be tried on a device at once, not
// after laying 350 km of track by hand. It is built like ``RealWorldDemo``,
// the Pingxi Line's: the real railways' own centre line (``RealRailways``),
// projected onto the world, fitted with cubic edges, and ordinary
// `GameWorld` commands that charge their usual costs; the game starts with
// what they cost on top of a new game's money.

/// A whole-Taiwan game with the Taiwan High Speed Rail built and running
/// (decision 170).
///
/// - The track is double, as on the real line, flat and on the ground (the
///   game's track, not the real viaducts and tunnels): the down track
///   (southbound) is one line of cubic edges on the real alignment, the up
///   track (northbound) runs ``trackOffset`` beside it and joins it by a
///   turnout just short of each end's platform, where the sets turn back.
/// - The twelve stations stand where the real ones do. Each between the
///   ends has four platforms for a set of twelve cars (16 m each): one on
///   each through track and one on a loop beside each, outside it, as the
///   real stations have side platforms and through tracks; the two ends one
///   on the down track.
/// - The line calls at all twelve; its two patterns are the real day's
///   nine-stop and five-stop expresses, every one a service of its own:
///   every 30, 20 and 30 minutes, with the sets that takes (see
///   ``services``).
/// - Every leg says where it runs (``run(in:language:services:stations:platforms:down:through:firstPlatform:)``):
///   southbound on the down track, northbound on the up track, so each way
///   keeps to its own track and the trains of the two ways never meet. The
///   sets that call at every station stop on the loops; the expresses keep
///   to the through tracks and pass them there.
/// - Its trains are high-speed sets (`TrainType.highSpeed`, twelve cars
///   rated 80 each), planned at `PERF_HSR`; the line is a high-speed line
///   (decision 168), so its stations draw the people round them and its
///   riders pay by the kilometre.
/// - Traffic control is off: a set may still run into one going its own
///   way ahead of it (an express that catches up with another between
///   stations, or two expresses at a station both call at), and the sets
///   wait one behind another at Nangang's platform. Under
///   traffic control the game's route reservation takes the thousands of
///   spans of a 30 to 180 km leg, and a day of 24 sets would take it
///   minutes of every game hour (decision 170).
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
    /// How long the up track's ramps from the down track are, and how far
    /// beyond an end's platform the first begins.
    static let rampLength = 100.0 * RealWorldDemo.metre

    /// A stopping pattern of the real day, by station index (the twelve
    /// stations in order, Nangang first), and how often a train leaves.
    struct Service {
        let english: String
        let chinese: String
        let stops: [Int]
        let headway: Int64
        /// The sets it needs for that headway: its round trip shared out,
        /// rounded up (a test checks it against the track as built).
        let sets: Int
    }

    /// The real day's three commonest kinds of train: the schedule
    /// (`thsr-schedule.json`, 169 trains) has 32 that call at all twelve
    /// stations, 58 at nine and 28 at five, 118 of them. The real day runs
    /// four to six trains an hour through Taipei southbound and five to
    /// nine northbound, all kinds together; these run seven an hour each
    /// way, two, three and two, all day.
    static let services: [Service] = [
        Service(english: "THSR All Stops", chinese: "高鐵 各站停車", stops: Array(0..<12), headway: 30, sets: 8),
        Service(english: "THSR Nine Stops", chinese: "高鐵 九站停車", stops: [0, 1, 2, 3, 4, 6, 9, 10, 11], headway: 20, sets: 10),
        Service(english: "THSR Five Stops", chinese: "高鐵 五站停車", stops: [0, 1, 2, 6, 11], headway: 30, sets: 6),
    ]

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
    }

    /// The minute of the first day the game opens at: 07:00, an hour after
    /// the day's first train (``ServiceWindow/standard`` opens at 06:00),
    /// when the first sets of each service are on their way.
    static let opensAt: Int64 = 7 * 60

    /// The demo: a new whole-Taiwan game with the railway built, running
    /// from 07:00. `population`, `places`, `water` and `coverage` are the
    /// app's real-world data; the land round the high-speed stations is read
    /// in from them (``GameSession/readLand(roundStationsOf:population:places:water:coverage:)``).
    /// Without the population the stations have no hinterland, and so no
    /// intercity trips.
    ///
    /// - Throws: ``Failure/noHighSpeedRail`` when `railways` has no High
    ///   Speed Rail.
    public static func make(
        in language: DisplayLanguage, railways: RealRailways, population: PopulationGrid? = nil, places: PlaceGrid? = nil,
        water: WaterGrid? = nil, coverage: CoverageGrid? = nil, eventSeed: UInt32 = 1
    ) throws(Failure) -> GameWorld {
        let layout = try Layout(railways: railways)
        var world = newWorld(paying: layout.cost(at: ConstructionCosts.newGame), eventSeed: eventSeed)
        do throws(GameError) {
            try layout.build(in: &world, language: language)
            // The first set leaves at 06:00. Until then nothing runs and no
            // one is waiting, so the night passes before the land's people
            // are read in; the game then opens an hour into the day.
            world.setSpeed(.fast)
            try world.advance(ticks: Int((opensAt - 60) / 10))
            GameSession.readLand(roundStationsOf: &world, population: population, places: places, water: water, coverage: coverage)
            try world.advance(ticks: 6)
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

    /// Where everything goes: worked out before anything is built, so the
    /// game can start with what it costs.
    ///
    /// Two tracks: ``plan``, the down track on the real alignment from
    /// Nangang's end to Zuoying's, and ``up``, the up track beside it,
    /// west of it as the real trains keep left, which leaves the down track
    /// at ``junctions`` just past the two ends' platforms.
    struct Layout {
        let plan: RealWorldDemo.TrackPlan
        let up: RealWorldDemo.TrackPlan
        /// Each station's loops between the ends, by the station's index:
        /// one beside the down track on its east, one beside the up track
        /// on its west, each with the station's platform for the sets that
        /// call at every station, so the expresses pass them on the
        /// through tracks.
        let loops: [Int: (down: RealWorldDemo.TrackPlan, up: RealWorldDemo.TrackPlan)]
        let stops: [Stop]
        let platforms: [ClosedRange<Double>]
        let services: [Service]
        /// Where the up track leaves the down track by Nangang and joins it
        /// again by Zuoying, along the down track's path.
        let junctions: (north: Double, south: Double)

        init(railways: RealRailways, services: [Service] = HighSpeedDemo.services) throws(Failure) {
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
            let path = WorldPath(points)
            let platforms = stops.map { HighSpeedDemo.platformZone(on: path, at: $0.point) }
            self.stops = stops
            self.platforms = platforms
            self.services = services
            // The turnouts a ramp beyond the ends' platforms, on the line's
            // side, and the ramps a ramp long.
            let ramp = HighSpeedDemo.rampLength, margin = RealWorldDemo.platformMargin
            let junctions = (north: platforms[0].upperBound + margin + ramp, south: platforms[platforms.count - 1].lowerBound - margin - ramp)
            self.junctions = junctions
            let upEnds = (north: junctions.north + ramp, south: junctions.south - ramp)
            // Each loop leaves its track a ramp before the platform's margin
            // and is beside it from there to the far margin.
            let between = Array(platforms.indices.dropFirst().dropLast())
            func loopNodes(_ zone: ClosedRange<Double>) -> [Double] {
                [zone.lowerBound - margin - ramp, zone.lowerBound - margin, zone.upperBound + margin, zone.upperBound + margin + ramp]
            }
            let plan = RealWorldDemo.TrackPlan(
                path, forced: [0, path.length, junctions.north, upEnds.north, upEnds.south, junctions.south] + between.flatMap { loopNodes(platforms[$0]) },
                avoiding: platforms, tolerance: HighSpeedDemo.tolerance, longestEdge: HighSpeedDemo.longestEdge
            )
            self.plan = plan
            // Beside every node of the down track from the end of one ramp
            // to the start of the other.
            func index(_ distance: Double) -> Int {
                guard let index = plan.distances.firstIndex(where: { abs($0 - distance) < 1 }) else {
                    preconditionFailure("No node of the down track at \(distance)")
                }
                return index
            }
            let inner = Array(index(upEnds.north)...index(upEnds.south))
            up = RealWorldDemo.TrackPlan(
                beside: plan, at: [index(junctions.north)] + inner + [index(junctions.south)],
                offsets: [0] + inner.map { _ in HighSpeedDemo.trackOffset } + [0]
            )
            let offset = HighSpeedDemo.trackOffset
            loops = Dictionary(uniqueKeysWithValues: between.map { station in
                let at = loopNodes(platforms[station]).map(index)
                return (station, (
                    down: RealWorldDemo.TrackPlan(beside: plan, at: at, offsets: [0, -offset, -offset, 0]),
                    up: RealWorldDemo.TrackPlan(beside: plan, at: at, offsets: [offset, 2 * offset, 2 * offset, offset])
                ))
            })
        }

        /// What building it costs at `costs` (the prices of
        /// ``GameWorld/buildTrackEdge(from:to:curve:profile:structure:)``,
        /// ``GameWorld/buildStation(named:at:)``, ``GameWorld/purchaseTrain(named:)``
        /// and ``GameWorld/setTrainCars(_:to:)``; every track is on the
        /// ground).
        func cost(at costs: ConstructionCosts) -> Money {
            let loopLengths = loops.values.flatMap { $0.down.lengths + $0.up.lengths }
            let track = (plan.lengths + up.lengths + loopLengths).map { length in
                max(1, (length + ConstructionCosts.trackPricingLength - 1) / ConstructionCosts.trackPricingLength) * TrackStructure.surface.costFactor
            }.reduce(0, +) * costs.track.amount
            let stations = Int64(stops.count) * costs.station.amount
            return Money(track + stations + HighSpeedDemo.trainsCost(of: services, at: costs))
        }

        /// Builds it: the down track, the up track from turnout to turnout,
        /// the loops, the stations and their platforms, and the line.
        @discardableResult
        func build(in world: inout GameWorld, language: DisplayLanguage) throws(GameError) -> Built {
            let down = try plan.build(in: &world)
            func node(_ track: RealWorldDemo.Track, _ distance: Double) -> TrackNodeID {
                guard let node = track.node(at: distance) else { preconditionFailure("No node at \(distance)") }
                return node
            }
            let upTrack = try up.build(in: &world, start: node(down, junctions.north), end: node(down, junctions.south))
            var builtLoops: [Int: (down: RealWorldDemo.Track, up: RealWorldDemo.Track)] = [:]
            for station in loops.keys.sorted() {
                let (downLoop, upLoop) = loops[station]!
                let (first, last) = (downLoop.distances[0], downLoop.distances[downLoop.distances.count - 1])
                builtLoops[station] = (
                    try downLoop.build(in: &world, start: node(down, first), end: node(down, last)),
                    try upLoop.build(in: &world, start: node(upTrack, first), end: node(upTrack, last))
                )
            }
            var ids: [StationID] = []
            var platformsOf: [Int: Built.Platforms] = [:]
            for (index, (stop, zone)) in zip(stops, platforms).enumerated() {
                let middle = plan.path.point(at: (zone.lowerBound + zone.upperBound) / 2)
                let id = try world.buildStation(named: stop.station.name(in: language), at: middle.plan).id
                func platform(on track: RealWorldDemo.Track) throws(GameError) -> TrackPlatform {
                    let (edge, offset) = track.edge(at: zone.lowerBound, in: world)
                    try world.addTrackPlatform(id, on: edge, from: offset, to: offset + HighSpeedDemo.platformLength)
                    return TrackPlatform(station: id, edge: edge, start: offset, end: offset + HighSpeedDemo.platformLength)
                }
                let main = try platform(on: down)
                if let loop = builtLoops[index] {
                    platformsOf[index] = Built.Platforms(
                        down: main, up: try platform(on: upTrack), downLoop: try platform(on: loop.down), upLoop: try platform(on: loop.up)
                    )
                }
                ids.append(id)
            }
            let turnouts = (north: plan.distances.firstIndex { abs($0 - junctions.north) < 1 }!, south: plan.distances.firstIndex { abs($0 - junctions.south) < 1 }!)
            let through = Through(down: down.edges, up: upTrack.edges, turnouts: turnouts)
            try HighSpeedDemo.run(
                in: &world, language: language, services: services, stations: ids, platforms: platformsOf, down: down, through: through,
                firstPlatform: platforms[0]
            )
            return Built(down: down, up: upTrack, loops: builtLoops.keys.sorted().map { builtLoops[$0]! })
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
        /// A station's platforms: on the two through tracks and on its two
        /// loops.
        struct Platforms {
            let down: TrackPlatform
            let up: TrackPlatform
            let downLoop: TrackPlatform
            let upLoop: TrackPlatform
        }

        let down: RealWorldDemo.Track
        let up: RealWorldDemo.Track
        let loops: [(down: RealWorldDemo.Track, up: RealWorldDemo.Track)]
    }

    /// Where a station's platform lies along `path`: centred on the point of
    /// the path nearest the station, moved in from either end of the path
    /// so it keeps clear of it.
    static func platformZone(on path: WorldPath, at point: WorldVector) -> ClosedRange<Double> {
        let half = Double(platformLength) / 2
        let room = half + RealWorldDemo.platformMargin
        let middle = min(max(path.project(point), room), path.length - room)
        return (middle - half)...(middle + half)
    }

    // MARK: - The services

    /// How many sets a service needs for its headway: its round trip shared
    /// out, rounded up, at least one.
    static func sets(roundTripMinutes: Int64, headway: Int64) -> Int {
        Int(max(1, (roundTripMinutes + headway - 1) / headway))
    }

    /// What the sets of `services` cost, for the money the game starts with.
    static func trainsCost(of services: [Service], at costs: ConstructionCosts) -> Int64 {
        Int64(services.reduce(0) { $0 + $1.sets }) * (costs.train.amount + Int64(cars - 1) * costs.car.amount)
    }

    /// The line, its patterns and the sets of each, every set at the first
    /// platform facing the way it leaves; and the rules that make it a
    /// high-speed line's (``ServiceLine/isHighSpeed``).
    ///
    /// Every leg says where it runs
    /// (``GameWorld/setLineRoutePreferences(_:to:pattern:)``), so each way
    /// keeps to its own track: the shortest way would at times run on the
    /// other's, against its trains. The service calling at every station
    /// names the platforms it ends at, on the down track's loop southbound
    /// and the up track's northbound (the legs into the two ends name none:
    /// each has one platform). An express names its whole way along the
    /// through track (``Through``): only its platform, and it would take a
    /// loop it passes where the loop is on the inside of a curve, a little
    /// shorter.
    static func run(
        in world: inout GameWorld, language: DisplayLanguage, services: [Service], stations: [StationID], platforms: [Int: Built.Platforms],
        down: RealWorldDemo.Track, through: Through, firstPlatform: ClosedRange<Double>
    ) throws(GameError) {
        // Traffic control is off: the sets wait one behind another at the
        // first platform, and a set may run into one ahead going its way
        // (see ``HighSpeedDemo``).
        try world.setTrafficControl(false)
        let all = services[0]
        let line = try world.createLine(named: language.text(all.english, all.chinese), stops: all.stops.map { stations[$0] }).id
        try world.setLinePerformance(line, to: .highSpeed)
        var patterns: [Int?] = [nil]
        for service in services.dropFirst() {
            let calls = service.stops.compactMap { stop in all.stops.firstIndex(of: stop) }
            patterns.append(try world.addLinePattern(line, calling: calls))
        }
        var number = 0
        for (service, pattern) in zip(services, patterns) {
            // The service that calls at every station stops on the loops;
            // the expresses keep to the through tracks all the way, and pass
            // it there.
            let calling = pattern == nil
            func platform(of stop: Int, onDown: Bool) -> TrackPlatform? {
                platforms[stop].map { onDown ? (calling ? $0.downLoop : $0.down) : (calling ? $0.upLoop : $0.up) }
            }
            func endPlatform(of stop: Int) -> TrackPlatform? {
                world.trackPlatforms(of: stations[stop]).first { through.down.contains($0.edge) }
            }
            try world.setLineTargetHeadways(
                line, to: TargetHeadways(peak: service.headway, offPeak: service.headway, low: service.headway), pattern: pattern
            )
            let calls = service.stops.compactMap { stop in all.stops.firstIndex(of: stop) }
            var preferences: [LineRoutePreference] = []
            for (from, to) in zip(calls, calls.dropFirst()) {
                if calling {
                    if let southbound = platform(of: to, onDown: true) {
                        preferences.append(LineRoutePreference(from: from, to: to, platform: southbound))
                    }
                    if let northbound = platform(of: from, onDown: false) {
                        preferences.append(LineRoutePreference(from: to, to: from, platform: northbound))
                    }
                    continue
                }
                // An express's leg passes stations whose loops may be the
                // shorter way on the inside of a curve: it names its whole
                // way along the through track.
                guard let south = platform(of: to, onDown: true) ?? endPlatform(of: to), let north = platform(of: from, onDown: false) ?? endPlatform(of: from),
                      let start = platform(of: from, onDown: true) ?? endPlatform(of: from), let end = platform(of: to, onDown: false) ?? endPlatform(of: to)
                else { continue }
                preferences.append(LineRoutePreference(from: from, to: to, tracks: through.southbound(from: start.edge, to: south.edge), platform: south))
                preferences.append(LineRoutePreference(from: to, to: from, tracks: through.northbound(from: end.edge, to: north.edge), platform: north))
            }
            try world.setLineRoutePreferences(line, to: preferences, pattern: pattern)
            for _ in 0..<service.sets {
                number += 1
                let train = try world.purchaseTrain(named: language.text("THSR \(number)", "高鐵 \(number)")).id
                try world.setTrainType(train, to: .highSpeed)
                try world.setTrainCars(train, to: cars)
                try world.setTrainPerformance(train, to: .highSpeed)
                let (edge, start) = down.edge(at: firstPlatform.lowerBound, in: world)
                let offset = start + platformLength
                try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: offset))
                try world.setTrainContinuation(train, along: [], stoppingAt: offset)
                try world.useTrainPerformanceForMovement(train)
                try world.assignTrain(train, to: line, pattern: pattern)
            }
        }
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
