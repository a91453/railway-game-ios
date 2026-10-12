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
/// - The track is one line of cubic edges on the real alignment, flat and
///   on the ground: the game's track, not the real viaducts and tunnels.
/// - The twelve stations stand where the real ones do, each with a platform
///   for a set of twelve cars (16 m each).
/// - The line calls at all twelve; its two patterns are the real day's
///   nine-stop and five-stop expresses, every one a service of its own:
///   every 30, 20 and 30 minutes, with the sets that takes (see
///   ``services``).
/// - Its trains are high-speed sets (`TrainType.highSpeed`, twelve cars
///   rated 80 each), planned at `PERF_HSR`; the line is a high-speed line
///   (decision 168), so its stations draw the people round them and its
///   riders pay by the kilometre.
/// - The track is one track, which the trains of both ways share: traffic
///   control is off (the real line has two), so trains pass through one
///   another on the way.
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
    struct Layout {
        let plan: RealWorldDemo.TrackPlan
        let stops: [Stop]
        let platforms: [ClosedRange<Double>]
        let services: [Service]

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
            plan = RealWorldDemo.TrackPlan(
                path, forced: [0, path.length], avoiding: platforms, tolerance: HighSpeedDemo.tolerance, longestEdge: HighSpeedDemo.longestEdge
            )
        }

        /// What building it costs at `costs` (the prices of
        /// ``GameWorld/buildTrackEdge(from:to:curve:profile:structure:)``,
        /// ``GameWorld/buildStation(named:at:)``, ``GameWorld/purchaseTrain(named:)``
        /// and ``GameWorld/setTrainCars(_:to:)``; every track is on the
        /// ground).
        func cost(at costs: ConstructionCosts) -> Money {
            let track = plan.lengths.map { length in
                max(1, (length + ConstructionCosts.trackPricingLength - 1) / ConstructionCosts.trackPricingLength) * TrackStructure.surface.costFactor
            }.reduce(0, +) * costs.track.amount
            let stations = Int64(stops.count) * costs.station.amount
            return Money(track + stations + HighSpeedDemo.trainsCost(of: services, at: costs))
        }

        func build(in world: inout GameWorld, language: DisplayLanguage) throws(GameError) {
            let track = try plan.build(in: &world)
            var ids: [StationID] = []
            for (stop, zone) in zip(stops, platforms) {
                let middle = plan.path.point(at: (zone.lowerBound + zone.upperBound) / 2)
                let id = try world.buildStation(named: stop.station.name(in: language), at: middle.plan).id
                let (edge, offset) = track.edge(at: zone.lowerBound, in: world)
                try world.addTrackPlatform(id, on: edge, from: offset, to: offset + HighSpeedDemo.platformLength)
                ids.append(id)
            }
            try HighSpeedDemo.run(in: &world, language: language, services: services, stations: ids, track: track, firstPlatform: platforms[0])
        }
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
    static func run(
        in world: inout GameWorld, language: DisplayLanguage, services: [Service], stations: [StationID], track: RealWorldDemo.Track,
        firstPlatform: ClosedRange<Double>
    ) throws(GameError) {
        // Single track: the trains of both ways share it, and the sets wait
        // one behind another at the first platform. Under traffic control
        // the first set would hold it and the rest could not be placed.
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
            try world.setLineTargetHeadways(
                line, to: TargetHeadways(peak: service.headway, offPeak: service.headway, low: service.headway), pattern: pattern
            )
            for _ in 0..<service.sets {
                number += 1
                let train = try world.purchaseTrain(named: language.text("THSR \(number)", "高鐵 \(number)")).id
                try world.setTrainType(train, to: .highSpeed)
                try world.setTrainCars(train, to: cars)
                try world.setTrainPerformance(train, to: .highSpeed)
                let (edge, start) = track.edge(at: firstPlatform.lowerBound, in: world)
                let offset = start + platformLength
                try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: offset))
                try world.setTrainContinuation(train, along: [], stoppingAt: offset)
                try world.useTrainPerformanceForMovement(train)
                try world.assignTrain(train, to: line, pattern: pattern)
            }
        }
    }
}
