import Foundation
import GameCore
import XCTest

/// Stages I–N together, differentially: generated command sequences run on
/// a `GameWorld` and on ``ReferenceWorld`` (the rules written a second way).
/// After every command both must give the same outcome (the same
/// `GameError`, in the documented order of checks) and the same observable
/// state: time, speed, money, stations, trains with their position and
/// movement, and station stops. Since Stage F3b the campaign runs on the
/// track network (``KernelNetwork``): its nodes, edges and platforms, every
/// train's path and body, and every train's way to every station are
/// compared too. (Stage F3c removed the grid, its operations and its
/// comparisons, ARCHITECTURE decision 51.)
///
/// The same run checks the Stage N stop transitions (decision 18): a train
/// starts or stops being stopped at a station only through the commands that
/// the decision names, and `advance` never moves a stopped train.
///
/// Operations are plain values, so a failing sequence is replayed and shrunk
/// (operations removed while it still fails) before it is reported, with
/// its seed and case. `PROPERTY_REPLAY=kernel.differential@<seed>@<case>`
/// runs one case; `PROPERTY_STRESS=<n>` adds derived seeds.
final class KernelDifferentialTests: XCTestCase {
    enum Operation: Equatable, CustomStringConvertible {
        case purchase(String)
        case place(TrainID, TrainPosition)
        case unplace(TrainID)
        case reverse(TrainID)
        case setRate(TrainID, Int64)
        /// Stage W2c.
        case setPerformance(TrainID, TrainPerformance)
        /// Never drawn by ``nextOperation(in:using:)``; the timetable
        /// campaigns (`TimetablePropertyTests`) add it, and the repeating
        /// service campaign (`ServicePropertyTests`) gives it a period, in
        /// seconds (Stage W2a).
        case setTimetable(TrainID, [ScheduledStop], period: Int64? = nil)
        /// Never drawn by ``nextOperation(in:using:)`` either; the service
        /// campaigns (`ServicePropertyTests`) add them.
        case startService(TrainID)
        case stopService(TrainID)
        /// The train tool's send to a station.
        case sendToStation(TrainID, StationID)
        /// Never drawn by ``nextOperation(in:using:)``; the line campaign
        /// (`ServiceLinePropertyTests`) adds them.
        case createLine(String, [StationID])
        case removeLine(LineID)
        case setLineStops(LineID, [StationID])
        case setLinePerformance(LineID, TrainPerformance)
        case setLineWindow(LineID, ServiceWindow)
        case setLineTrains(LineID, TrainsInService, pattern: Int? = nil)
        case setServiceDay(ServiceDay)
        /// Never drawn by ``nextOperation(in:using:)`` or the line campaign;
        /// the dispatch campaign (`LineDispatchPropertyTests`) adds them.
        case setLineTargets(LineID, TargetHeadways, pattern: Int? = nil)
        case assign(TrainID, LineID, pattern: Int? = nil)
        case unassign(TrainID)
        /// Only the pattern campaign (`LinePatternPropertyTests`) draws these,
        /// and a pattern for the three above.
        case addPattern(LineID, [Int])
        case removePattern(LineID, Int)
        /// Decision 49: only the dispatch campaign (`LineDispatchPropertyTests`)
        /// draws it.
        case setLineRing(LineID, Bool)
        case setCars(TrainID, Int)
        /// The train tool's send to a station for a train with cars: the
        /// route that pulls it along the platforms.
        case sendWholeTrainToStation(TrainID, StationID)
        /// Only the boarding campaign (`BoardingPropertyTests`) draws this.
        case setStationDemand(StationID, StationDemand?)
        /// Only the economy campaign (`EconomyPropertyTests`) draws these.
        case setEconomyMode(EconomyMode)
        case setFareRules(FareRules)
        case setFareBaseline(Money)
        /// The track network (Stage F3b): its track, stations at points and
        /// their platforms.
        case buildNode(WorldCoordinate)
        case buildEdge(TrackNodeID, TrackNodeID, TrackCurve)
        case removeEdge(TrackEdgeID)
        case removeNode(TrackNodeID)
        case buildStationAt(String, PlanPoint)
        case addPlatform(StationID, TrackEdgeID, Int64, Int64)
        case removePlatform(StationID, TrackEdgeID, Int64)
        /// A path by hand, stopping where it says.
        case stand(TrainID, [TrackTraversal], Int64?)
        /// The train tool's send to a node: the route from where the train
        /// is, committed unchanged.
        case sendToNode(TrainID, TrackNodeID)
        case advance(Int)
        case setSpeed(GameSpeed)
        case pause
        case resume
        case saveAndLoad

        var description: String {
            switch self {
            case .purchase(let name): ".purchase(\"\(name)\")"
            case .place(let id, let position): ".place(\(id.rawValue), \(position))"
            case .unplace(let id): ".unplace(\(id.rawValue))"
            case .reverse(let id): ".reverse(\(id.rawValue))"
            case .setRate(let id, let rate): ".setRate(\(id.rawValue), \(rate))"
            case .setPerformance(let id, let performance): ".setPerformance(\(id.rawValue), \(performance))"
            case .setTimetable(let id, let stops, let period):
                ".setTimetable(\(id.rawValue), [\(stops.map { "\($0.station.rawValue)@\($0.arrival.seconds)-\($0.departure.seconds)s\($0.reverses ? "R" : "")" }.joined(separator: ", "))]\(period.map { ", every \($0) s" } ?? ""))"
            case .startService(let id): ".startService(\(id.rawValue))"
            case .stopService(let id): ".stopService(\(id.rawValue))"
            case .sendToStation(let id, let station): ".sendToStation(\(id.rawValue), \(station.rawValue))"
            case .createLine(let name, let stops): ".createLine(\"\(name)\", \(stops.map(\.rawValue)))"
            case .removeLine(let id): ".removeLine(\(id.rawValue))"
            case .setLineStops(let id, let stops): ".setLineStops(\(id.rawValue), \(stops.map(\.rawValue)))"
            case .setLinePerformance(let id, let performance): ".setLinePerformance(\(id.rawValue), \(performance))"
            case .setLineWindow(let id, let window): ".setLineWindow(\(id.rawValue), \(window))"
            case .setLineTrains(let id, let trains, let pattern):
                ".setLineTrains(\(id.rawValue), \(trains.peak)/\(trains.offPeak)/\(trains.low)\(pattern.map { ", pattern \($0)" } ?? ""))"
            case .setServiceDay(let day): ".setServiceDay(\(day.bands.map { "\($0.start):\($0.level)" }))"
            case .setLineTargets(let id, let targets, let pattern):
                ".setLineTargets(\(id.rawValue), \([targets.peak, targets.offPeak, targets.low].map { $0.map(String.init) ?? "-" }.joined(separator: "/"))\(pattern.map { ", pattern \($0)" } ?? ""))"
            case .assign(let id, let line, let pattern): ".assign(\(id.rawValue), \(line.rawValue)\(pattern.map { ", pattern \($0)" } ?? ""))"
            case .addPattern(let id, let calls): ".addPattern(\(id.rawValue), \(calls))"
            case .removePattern(let id, let pattern): ".removePattern(\(id.rawValue), \(pattern))"
            case .setLineRing(let id, let ring): ".setLineRing(\(id.rawValue), \(ring))"
            case .setCars(let id, let cars): ".setCars(\(id.rawValue), \(cars))"
            case .sendWholeTrainToStation(let id, let station): ".sendWholeTrainToStation(\(id.rawValue), \(station.rawValue))"
            case .unassign(let id): ".unassign(\(id.rawValue))"
            case .setStationDemand(let id, let demand):
                ".setStationDemand(\(id.rawValue), \(demand.map { "\($0.kind) \($0.dailyTrips)" } ?? "none"))"
            case .setEconomyMode(let mode): ".setEconomyMode(.\(mode))"
            case .setFareRules(let rules): ".setFareRules(\(rules))"
            case .setFareBaseline(let baseline): ".setFareBaseline(\(baseline.amount))"
            case .buildNode(let point): ".buildNode(\(point.x), \(point.y))"
            case .buildEdge(let from, let to, let curve): ".buildEdge(\(from.number), \(to.number), \(curve))"
            case .removeEdge(let edge): ".removeEdge(\(edge.number))"
            case .removeNode(let node): ".removeNode(\(node.number))"
            case .buildStationAt(let name, let point): ".buildStationAt(\"\(name)\", \(point.x), \(point.y))"
            case .addPlatform(let id, let edge, let start, let end): ".addPlatform(\(id.rawValue), \(edge.number), \(start)...\(end))"
            case .removePlatform(let id, let edge, let start): ".removePlatform(\(id.rawValue), \(edge.number), \(start))"
            case .stand(let id, let path, let end):
                ".stand(\(id.rawValue), [\(path.map { "\($0.edge.number)\($0.direction == .forward ? "+" : "-")" }.joined(separator: " "))]\(end.map { " to \($0)" } ?? ""))"
            case .sendToNode(let id, let node): ".sendToNode(\(id.rawValue), \(node.number))"
            case .advance(let ticks): ".advance(\(ticks))"
            case .setSpeed(let speed): ".setSpeed(.\(speed))"
            case .pause: ".pause"
            case .resume: ".resume"
            case .saveAndLoad: ".saveAndLoad"
            }
        }
    }

    /// Everything a case starts from: a track network (Stage F3b), money,
    /// the clock and the speed.
    struct Setup {
        var network: KernelNetwork
        var width: Int
        var height: Int
        var extraBalance: Int64
        /// The clock, in seconds (Stage W2a).
        var seconds: Int64
        var speed: GameSpeed
        /// What each added car costs (decision 46); the campaigns before it
        /// add cars for nothing.
        var carPrice: Int64 = 0

        /// The map and what is built on it, for notes.
        var summary: String {
            "\(width)x\(height), \(network.nodes.count) nodes, \(network.edges.count) edges, \(network.stations.count) stations"
        }

        /// What the campaigns' track, stations, trains and cars cost.
        static let baseCosts = ConstructionCosts(track: 100, station: 1_000, train: 5_000)

        var costs: ConstructionCosts {
            var costs = Self.baseCosts
            costs.car = Money(carPrice)
            return costs
        }

        /// The same network built on both sides, each through its own
        /// commands, with just enough money plus `extraBalance`.
        func build() throws -> (GameWorld, ReferenceWorld) {
            try build(network)
        }

        /// A track network: its nodes, edges, stations and their platforms,
        /// in that order. What the edges cost depends on their lengths, so
        /// it is found by building them once with money to spare.
        private func build(_ network: KernelNetwork) throws -> (GameWorld, ReferenceWorld) {
            var priced = try GameWorld(width: width, height: height, economy: GameEconomy(balance: Money(Int64.max / 2), costs: costs))
            var none: ReferenceWorld?
            try Self.build(network, on: &priced, &none)
            let balance = Int64.max / 2 - priced.economy.balance.amount + extraBalance
            var world = try GameWorld(
                width: width, height: height,
                economy: GameEconomy(balance: Money(balance), costs: costs),
                clock: GameClock(now: GameTime(seconds: seconds), speed: speed)
            )
            var model: ReferenceWorld? = ReferenceWorld(width: width, height: height, balance: balance, costs: costs, seconds: seconds, speed: speed)
            try Self.build(network, on: &world, &model)
            return (world, model!)
        }

        /// Builds `network` on `world`, and on `model` too when there is one.
        private static func build(_ network: KernelNetwork, on world: inout GameWorld, _ model: inout ReferenceWorld?) throws {
            func both(_ operation: Operation) throws {
                guard KernelDifferentialTests.apply(operation, to: &world) == nil else { throw SetupError.refused("\(operation)") }
                guard var reference = model else { return }
                let refused = KernelDifferentialTests.apply(operation, to: &reference)
                model = reference
                if refused != nil { throw SetupError.modelRefused }
            }
            for node in network.nodes {
                try both(.buildNode(node))
            }
            for edge in network.edges {
                try both(.buildEdge(.node(edge.from + 1), .node(edge.to + 1), edge.curve))
            }
            for station in network.stations {
                try both(.buildStationAt(station.name, station.point))
            }
            for (index, station) in network.stations.enumerated() {
                for platform in station.platforms {
                    let edge = TrackEdgeID.edge(platform.edge + 1)
                    let span = platform.span(length: world.trackEdge(edge)?.length ?? 0)
                    try both(.addPlatform(StationID(rawValue: index + 1), edge, span.start, span.end))
                }
            }
        }
    }

    enum SetupError: Error {
        case modelRefused
        case refused(String)
    }

    // MARK: - Generation

    /// A setup on a track network of one of `shapes` (with repeats to
    /// weight them; Stage F3b), with the money, clock and speed drawn as the
    /// grid's campaigns drew them before Stage F3c: sometimes near the end
    /// of time, so that advancing can overflow; otherwise a whole minute, or
    /// for a quarter of the minutes a second between two (Stage W2a).
    static func makeNetworkSetup(shapes: [KernelNetwork.Shape] = KernelNetwork.Shape.allCases, using random: inout SplitMix64) -> Setup {
        let network = KernelNetwork.generate(random.element(of: shapes), using: &random)
        let extra: Int64 = random.chance(1, in: 3) ? random.int64(in: 0...12_000) : 1_000_000
        let seconds: Int64
        if random.chance(1, in: 8) {
            seconds = Int64.max - random.int64(in: 0...2_400)
        } else {
            let minute = random.int64(in: 0...100_000)
            seconds = minute * 60 + (minute % 4 == 1 ? minute / 4 % 59 + 1 : 0)
        }
        let speed = random.element(of: GameSpeed.allCases)
        return Setup(network: network, width: network.width, height: network.height, extraBalance: extra, seconds: seconds, speed: speed)
    }

    /// The next operation on a track network (Stage F3b), drawn with the
    /// current world in view: mostly sensible, sometimes invalid on
    /// purpose: the network's track, stations at points and their
    /// platforms, positions along edges, and paths by hand, to a node or to
    /// a station, in the shares the grid's operations had before Stage F3c.
    static func nextOperation(in world: GameWorld, using random: inout SplitMix64) -> Operation {
        let trains = world.trains
        let network = world.network
        let unknownIDs = [0, -1, trains.count + 1, trains.count + 2, Int.max]
        let id = trains.isEmpty || random.chance(1, in: 12)
            ? TrainID(rawValue: random.element(of: unknownIDs))
            : random.element(of: trains).id
        let position = world.train(id: id)?.position
        let width = world.map.width
        let height = world.map.height
        func anyNode() -> TrackNodeID {
            network.nodes.isEmpty || random.chance(1, in: 10) ? .node(random.element(of: [0, 99, Int.max])) : random.element(of: network.nodes).id
        }
        func anyStation() -> StationID {
            world.stations.isEmpty || random.chance(1, in: 10)
                ? StationID(rawValue: random.element(of: [0, -1, world.stations.count + 1, Int.max]))
                : random.element(of: world.stations).id
        }
        func anyPoint() -> PlanPoint {
            // A tile centre, and now and then a point off the map.
            random.chance(1, in: 10)
                ? PlanPoint(x: random.element(of: [-1, Int64(width) * 1_024]), y: Int64(random.below(height)) * 1_024)
                : KernelNetwork.centre(random.below(width), random.below(height)).plan
        }
        switch random.below(100) {
        case 0..<5:
            return .purchase(random.chance(1, in: 10) ? random.element(of: ["", " ", "\n\t"]) : "T\(trains.count + 1)")
        case 5..<14:
            // Along an edge either way: at either end, at a berth, or
            // anywhere; now and then off its edge or on an edge that does
            // not exist.
            guard let edge = network.edges.isEmpty ? nil : random.element(of: network.edges), random.chance(7, in: 8) else {
                return .place(id, .onEdge(TrackTraversal(edge: .edge(random.element(of: [0, 99, Int.max])), direction: random.chance(1, in: 2) ? .forward : .backward), offset: 0))
            }
            let direction: TrackEdgeDirection = random.chance(1, in: 2) ? .forward : .backward
            let platforms = network.platforms.filter { $0.edge == edge.id }
            let offset: Int64 = switch random.below(6) {
            case 0: 0
            case 1, 2: edge.length
            case 3:
                if let platform = platforms.first {
                    direction == .forward ? platform.end : edge.length - platform.start
                } else {
                    edge.length / 2
                }
            case 4: random.int64(in: 0...edge.length)
            default: random.element(of: [-1, edge.length + 1])
            }
            return .place(id, .onEdge(TrackTraversal(edge: edge.id, direction: direction), offset: offset))
        case 14..<16:
            return .unplace(id)
        case 16..<20:
            return .reverse(id)
        case 20..<30:
            if random.chance(1, in: 5) {
                return .setPerformance(id, random.element(of: PerformanceSamples.valid + PerformanceSamples.invalid))
            }
            let rate: Int64 = random.chance(1, in: 20)
                ? -random.int64(in: 1...5)
                : random.element(of: [0, 1, 511, 1023, 1024, 1025, 3_000, random.int64(in: 0...4_096), .max])
            return .setRate(id, rate)
        case 30..<37:
            // A walk by the transitions, stopping along its last edge or not
            // at all; now and then with a wrong step.
            guard case .onEdge(let traversal, let offset)? = position else { return .stand(id, [], nil) }
            var walk: [TrackTraversal] = []
            var last = traversal
            for _ in 0..<random.below(5) {
                let options = world.transitions(after: last)
                guard !options.isEmpty else { break }
                last = random.element(of: options)
                walk.append(last)
            }
            if random.chance(1, in: 6), !network.edges.isEmpty {
                walk.insert(TrackTraversal(edge: random.element(of: network.edges).id, direction: .forward), at: random.below(walk.count + 1))
            }
            let length = world.trackEdge(last.edge)?.length ?? 0
            let end: Int64? = random.chance(1, in: 3) ? nil : random.int64(in: (walk.isEmpty ? offset - 10 : -10)...(length + 10))
            return .stand(id, walk, end)
        case 37..<44:
            return .sendToNode(id, anyNode())
        case 44..<56:
            return random.chance(1, in: 3) ? .sendWholeTrainToStation(id, anyStation()) : .sendToStation(id, anyStation())
        case 56..<76:
            return .advance(random.below(10))
        case 76..<79:
            return .setSpeed(random.element(of: GameSpeed.allCases))
        case 79..<80:
            return random.chance(1, in: 2) ? .pause : .resume
        case 80..<86:
            // A node at a tile centre (sometimes where one stands, or off
            // the map), or an edge between two nodes, straight or curved.
            if random.chance(1, in: 2) {
                let point = anyPoint()
                return .buildNode(WorldCoordinate(x: point.x, y: point.y))
            }
            let from = anyNode()
            let to = anyNode()
            guard random.chance(1, in: 2) else { return .buildEdge(from, to, .straight) }
            return .buildEdge(from, to, .cubic(anyPoint(), anyPoint()))
        case 86..<92:
            // Often the edge a train is on, or one with a platform; or a
            // platform; or a node.
            if case .onEdge(let traversal, _)? = position, random.chance(1, in: 3) {
                return .removeEdge(traversal.edge)
            }
            switch random.below(4) {
            case 0, 1:
                return .removeEdge(network.edges.isEmpty || random.chance(1, in: 10) ? .edge(99) : random.element(of: network.edges).id)
            case 2:
                guard let platform = network.platforms.isEmpty ? nil : random.element(of: network.platforms) else { return .removeNode(anyNode()) }
                return random.chance(1, in: 8)
                    ? .removePlatform(platform.station, platform.edge, platform.start + 1)
                    : .removePlatform(platform.station, platform.edge, platform.start)
            default:
                return .removeNode(anyNode())
            }
        case 92..<96:
            // Often a platform under a train, to make a stop appear under
            // it; or a new station.
            if case .onEdge(let traversal, let offset)? = position, let edge = world.trackEdge(traversal.edge), random.chance(1, in: 2) {
                let chainage = traversal.direction == .forward ? offset : edge.length - offset
                let start = max(0, chainage - Int64(random.below(3)) * 512)
                return .addPlatform(anyStation(), edge.id, start, min(edge.length, start + Int64(1 + random.below(3)) * 512))
            }
            if random.chance(1, in: 2), let edge = network.edges.isEmpty ? nil : random.element(of: network.edges) {
                let start = random.int64(in: -1...edge.length)
                return .addPlatform(anyStation(), edge.id, start, start + random.int64(in: 0...2_048))
            }
            return .buildStationAt(random.chance(1, in: 10) ? " " : "B\(world.stations.count + 1)", anyPoint())
        default:
            return .saveAndLoad
        }
    }

    // MARK: - Applying

    /// Applies `operation` to the world, returning the refusal if any.
    static func apply(_ operation: Operation, to world: inout GameWorld) -> GameError? {
        do throws(GameError) {
            switch operation {
            case .purchase(let name): try world.purchaseTrain(named: name)
            case .place(let id, let position): try world.placeTrain(id, at: position)
            case .unplace(let id): try world.unplaceTrain(id)
            case .reverse(let id): try world.reverseTrain(id)
            case .setRate(let id, let rate): try world.setTrainMovementRate(id, to: rate)
            case .setPerformance(let id, let performance): try world.setTrainPerformance(id, to: performance)
            case .setTimetable(let id, let stops, let period): try world.setTrainTimetable(id, to: stops, repeatingEvery: period)
            case .startService(let id): try world.startTrainService(id)
            case .stopService(let id): try world.stopTrainService(id)
            case .sendToStation(let id, let station):
                // Stage F3b: a path to a berth.
                guard let position = world.train(id: id)?.position, let path = world.path(from: position, toStation: station) else { return nil }
                try world.setTrainContinuation(id, along: path.traversals, stoppingAt: path.end)
            case .createLine(let name, let stops): try world.createLine(named: name, stops: stops)
            case .removeLine(let id): try world.removeLine(id)
            case .setLineStops(let id, let stops): try world.setLineStops(id, to: stops)
            case .setLinePerformance(let id, let performance): try world.setLinePerformance(id, to: performance)
            case .setLineWindow(let id, let window): try world.setLineServiceWindow(id, to: window)
            case .setLineTrains(let id, let trains, let pattern): try world.setLineTrainsInService(id, to: trains, pattern: pattern)
            case .setServiceDay(let day): try world.setServiceDay(day)
            case .setLineTargets(let id, let targets, let pattern): try world.setLineTargetHeadways(id, to: targets, pattern: pattern)
            case .assign(let id, let line, let pattern): try world.assignTrain(id, to: line, pattern: pattern)
            case .unassign(let id): try world.unassignTrain(id)
            case .addPattern(let id, let calls): try world.addLinePattern(id, calling: calls)
            case .removePattern(let id, let pattern): try world.removeLinePattern(id, at: pattern)
            case .setLineRing(let id, let ring): try world.setLineRing(id, to: ring)
            case .setCars(let id, let cars): try world.setTrainCars(id, to: cars)
            case .sendWholeTrainToStation(let id, let station):
                guard let train = world.train(id: id), let position = train.position,
                      let path = world.path(from: position, toStation: station, length: train.length)
                else { return nil }
                try world.setTrainContinuation(id, along: path.traversals, stoppingAt: path.end)
            case .setStationDemand(let id, let demand): try world.setStationDemand(id, to: demand)
            case .setEconomyMode(let mode): world.setEconomyMode(mode)
            case .setFareRules(let rules): try world.setFareRules(rules)
            case .setFareBaseline(let baseline): try world.setFareBaseline(baseline)
            case .buildNode(let point): try world.buildTrackNode(at: point)
            case .buildEdge(let from, let to, let curve): try world.buildTrackEdge(from: from, to: to, curve: curve)
            case .removeEdge(let edge): try world.removeTrackEdge(edge)
            case .removeNode(let node): try world.removeTrackNode(node)
            case .buildStationAt(let name, let point): try world.buildStation(named: name, at: point)
            case .addPlatform(let id, let edge, let start, let end): try world.addTrackPlatform(id, on: edge, from: start, to: end)
            case .removePlatform(let id, let edge, let start): try world.removeTrackPlatform(id, on: edge, from: start)
            case .stand(let id, let path, let end): try world.setTrainContinuation(id, along: path, stoppingAt: end)
            case .sendToNode(let id, let node):
                guard let position = world.train(id: id)?.position, let route = world.route(from: position, to: node) else { return nil }
                try world.setTrainContinuation(id, along: route)
            case .advance(let ticks): try world.advance(ticks: ticks)
            case .setSpeed(let speed): world.setSpeed(speed)
            case .pause: world.pause()
            case .resume: world.resume()
            case .saveAndLoad:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                guard let data = try? encoder.encode(world), let loaded = try? JSONDecoder().decode(GameWorld.self, from: data) else {
                    // Reported by the caller as a difference.
                    world = try GameWorld(width: 1, height: 1, economy: GameEconomy(balance: 0))
                    return nil
                }
                world = loaded
            }
            return nil
        } catch {
            return error
        }
    }

    static func apply(_ operation: Operation, to model: inout ReferenceWorld) -> GameError? {
        switch operation {
        case .purchase(let name): return model.purchaseTrain(named: name)
        case .place(let id, let position): return model.placeTrain(id, at: position)
        case .unplace(let id): return model.unplaceTrain(id)
        case .reverse(let id): return model.reverseTrain(id)
        case .setRate(let id, let rate): return model.setRate(id, rate)
        case .setPerformance(let id, let performance): return model.setPerformance(id, performance)
        case .setTimetable(let id, let stops, let period): return model.setTimetable(id, stops, period: period)
        case .startService(let id): return model.startService(id)
        case .stopService(let id): return model.stopService(id)
        case .sendToStation(let id, let station):
            guard let position = model.trains.first(where: { $0.id == id.rawValue })?.position,
                  let path = model.pathToStation(from: position, station: station, length: 0)
            else { return nil }
            return model.setContinuation(id, along: path.traversals, stoppingAt: path.end)
        case .createLine(let name, let stops): return model.createLine(named: name, stops: stops)
        case .removeLine(let id): return model.removeLine(id)
        case .setLineStops(let id, let stops): return model.setLineStops(id, stops)
        case .setLinePerformance(let id, let performance): return model.setLinePerformance(id, performance)
        case .setLineWindow(let id, let window): return model.setLineWindow(id, window)
        case .setLineTrains(let id, let trains, let pattern): return model.setLineTrains(id, trains, pattern: pattern)
        case .setServiceDay(let day): return model.setServiceDay(day)
        case .setLineTargets(let id, let targets, let pattern): return model.setLineTargets(id, targets, pattern: pattern)
        case .assign(let id, let line, let pattern): return model.assign(id, to: line, pattern: pattern)
        case .unassign(let id): return model.unassign(id)
        case .addPattern(let id, let calls): return model.addPattern(id, calls)
        case .removePattern(let id, let pattern): return model.removePattern(id, pattern)
        case .setLineRing(let id, let ring): return model.setLineRing(id, ring)
        case .setCars(let id, let cars): return model.setCars(id, cars)
        case .sendWholeTrainToStation(let id, let station):
            guard let train = model.trains.first(where: { $0.id == id.rawValue }), let position = train.position,
                  let path = model.pathToStation(from: position, station: station, length: ReferenceWorld.length(train))
            else { return nil }
            return model.setContinuation(id, along: path.traversals, stoppingAt: path.end)
        case .setStationDemand(let id, let demand): return model.setStationDemand(id, demand)
        case .setEconomyMode(let mode): model.setEconomyMode(mode); return nil
        case .setFareRules(let rules): return model.setFareRules(rules)
        case .setFareBaseline(let baseline): return model.setFareBaseline(baseline)
        case .buildNode(let point): return model.buildNetworkNode(at: point)
        case .buildEdge(let from, let to, let curve): return model.buildNetworkEdge(from: from, to: to, curve: curve)
        case .removeEdge(let edge): return model.removeNetworkEdge(edge)
        case .removeNode(let node): return model.removeNetworkNode(node)
        case .buildStationAt(let name, let point): return model.buildStation(named: name, at: point)
        case .addPlatform(let id, let edge, let start, let end): return model.addTrackPlatform(id, on: edge, from: start, to: end)
        case .removePlatform(let id, let edge, let start): return model.removeTrackPlatform(id, on: edge, from: start)
        case .stand(let id, let path, let end): return model.setContinuation(id, along: path, stoppingAt: end)
        case .sendToNode(let id, let node):
            guard let position = model.trains.first(where: { $0.id == id.rawValue })?.position,
                  let route = model.networkRoute(from: position, to: node)
            else { return nil }
            return model.setContinuation(id, along: route)
        case .advance(let ticks): return model.advance(ticks: ticks)
        case .setSpeed(let speed): model.setSpeed(speed); return nil
        case .pause: model.pause(); return nil
        case .resume: model.resume(); return nil
        case .saveAndLoad: return nil
        }
    }

    // MARK: - Comparing

    /// Every observable difference between the world and the model. Without
    /// `lineAnswers`, what is derived for each line (its levels, journey,
    /// trains and headways) is left out: the line campaign compares it, and
    /// the reference drives every line from scratch to answer it.
    static func differences(_ world: GameWorld, _ model: ReferenceWorld, lineAnswers: Bool = true) -> [String] {
        var found: [String] = []
        func check(_ ok: Bool, _ what: @autoclosure () -> String) {
            if !ok { found.append(what()) }
        }
        check(world.clock.now.seconds == model.clockSeconds, "seconds \(world.clock.now.seconds) vs \(model.clockSeconds)")
        check(world.clock.pendingTenths == model.pendingTenths, "pending tenths \(world.clock.pendingTenths) vs \(model.pendingTenths)")
        check(world.clock.speed == model.speed, "speed \(world.clock.speed) vs \(model.speed)")
        check(world.economy.balance.amount == model.balance, "balance \(world.economy.balance.amount) vs \(model.balance)")
        check(world.map.width == model.width && world.map.height == model.height, "map size")
        // The land holds nothing since Stage F3c: stations stand at points.
        check(world.map.tiles.allSatisfy { $0.type == .empty }, "a tile is taken")
        check(
            world.stations.map { [$0.id.rawValue, $0.position.x, $0.position.y] } == model.stations.map { [$0.id, $0.position.x, $0.position.y] }
                && world.stations.map(\.name) == model.stations.map(\.name) && world.stations.map(\.point) == model.stations.map(\.point),
            "stations \(world.stations) vs \(model.stations)"
        )
        check(world.trains.map(\.id.rawValue) == model.trains.map(\.id), "train IDs \(world.trains.map(\.id.rawValue)) vs \(model.trains.map(\.id))")
        for (train, expected) in zip(world.trains, model.trains) {
            check(train.name == expected.name, "train \(expected.id) name")
            check(train.position == expected.position, "train \(expected.id) position \(String(describing: train.position)) vs \(String(describing: expected.position))")
            // Decision 27: its cars.
            check(train.cars == expected.cars, "train \(expected.id) cars \(train.cars) vs \(expected.cars)")
            check(train.movement.rate == expected.rate, "train \(expected.id) rate \(train.movement.rate) vs \(expected.rate)")
            check(train.performance == expected.performance, "train \(expected.id) performance")
            check(train.movement.cursor == expected.cursor, "train \(expected.id) cursor \(train.movement.cursor) vs \(expected.cursor)")
            check(train.timetable == expected.timetable, "train \(expected.id) timetable \(train.timetable) vs \(expected.timetable)")
            check(
                train.timetablePeriod == expected.period,
                "train \(expected.id) period \(String(describing: train.timetablePeriod)) vs \(String(describing: expected.period))"
            )
            check(
                train.execution == expected.service?.execution,
                "train \(expected.id) service \(String(describing: train.execution)) vs \(String(describing: expected.service?.execution))"
            )
            // Stage W2b: its service's times.
            check(
                train.times == expected.service?.times,
                "train \(expected.id) times \(String(describing: train.times)) vs \(String(describing: expected.service?.times))"
            )
            // Stage F3b: on the track network, its path, where it stops and
            // its body's edges.
            check(
                train.movement.edges.map(\.number) == expected.edges && train.movement.end == expected.end && train.trailEdges.map(\.number) == expected.trailEdges,
                "train \(expected.id) path \(train.movement.edges) to \(String(describing: train.movement.end)), body \(train.trailEdges) vs \(expected.edges) to \(String(describing: expected.end)), body \(expected.trailEdges)"
            )
        }
        // Stage F3b: the track network, its platforms, and every train's
        // way to every station (and to an unknown one).
        let nodes = Dictionary(uniqueKeysWithValues: world.network.nodes.map { ($0.id.number, $0.position) })
        check(nodes == model.networkNodes, "nodes \(nodes) vs \(model.networkNodes)")
        check(world.network.edges.map(\.id.number) == model.networkEdges.keys.sorted(), "edges \(world.network.edges.map(\.id.number)) vs \(model.networkEdges.keys.sorted())")
        for edge in world.network.edges {
            guard let expected = model.networkEdges[edge.id.number] else { continue }
            check(
                edge.from.number == expected.from && edge.to.number == expected.to && edge.curve == expected.curve && edge.length == expected.length,
                "edge \(edge.id.number): \(edge) vs \(expected)"
            )
        }
        check(world.network.platforms == model.allTrackPlatforms, "platforms \(world.network.platforms) vs \(model.allTrackPlatforms)")
        for train in world.trains {
            guard let position = train.position else { continue }
            for raw in world.stations.map(\.id.rawValue) + [Int.max] {
                let station = StationID(rawValue: raw)
                for length in Set([0, train.length]).sorted() {
                    let path = world.path(from: position, toStation: station, length: length)
                    let expected = model.pathToStation(from: position, station: station, length: length)
                    check(path == expected, "train \(train.id.rawValue)'s path to \(raw) for \(length): \(String(describing: path)) vs \(String(describing: expected))")
                }
            }
        }
        // Decision 22: lines and the service day, and what is derived for
        // each line (and an unknown one) at the current minute. Decision 23:
        // each line's targets, trains and last dispatch.
        check(
            world.lines.map { [$0.id.rawValue] } == model.lines.map { [$0.id] }
                && world.lines.map(\.name) == model.lines.map(\.name) && world.lines.map(\.stops) == model.lines.map(\.stops)
                && world.lines.map(\.performance) == model.lines.map(\.performance) && world.lines.map(\.window) == model.lines.map(\.window)
                && world.lines.map(\.trainsInService) == model.lines.map(\.trainsInService)
                && world.lines.map(\.targetHeadways) == model.lines.map(\.targetHeadways)
                && world.lines.map { $0.trains.map(\.rawValue) } == model.lines.map(\.roster)
                && world.lines.map { $0.lastDispatch?.minutes } == model.lines.map(\.lastDispatch)
                && world.lines.map(\.isRing) == model.lines.map(\.ring)
                && world.lines.map { $0.outerLastDispatch?.minutes } == model.lines.map(\.outerLastDispatch),
            "lines \(world.lines) vs \(model.lines)"
        )
        // Decision 24: each line's patterns.
        check(
            world.lines.map { $0.patterns.map(\.calls) } == model.lines.map { $0.patterns.map(\.calls) }
                && world.lines.map { $0.patterns.map(\.trainsInService) } == model.lines.map { $0.patterns.map(\.trainsInService) }
                && world.lines.map { $0.patterns.map(\.targetHeadways) } == model.lines.map { $0.patterns.map(\.targetHeadways) }
                && world.lines.map { $0.patterns.map { $0.trains.map(\.rawValue) } } == model.lines.map { $0.patterns.map(\.roster) }
                && world.lines.map { $0.patterns.map { $0.lastDispatch?.minutes } } == model.lines.map { $0.patterns.map(\.lastDispatch) },
            "patterns \(world.lines.map(\.patterns)) vs \(model.lines.map(\.patterns))"
        )
        // Decisions 34 and 35: every station's passengers and every train's
        // riders.
        let passengers = world.passengers.filter { $0.demand != nil || $0.released > 0 }.map(PassengerSummary.init)
        check(passengers == model.passengerSummaries, "passengers \(passengers) vs \(model.passengerSummaries)")
        let riders = world.riders.map { RiderSummary(train: $0.train.rawValue, groups: $0.groups.map(RidingGroupSummary.init)) }
        check(riders == model.riderSummaries, "riders \(riders) vs \(model.riderSummaries)")
        // Decision 36: the accounts, and every pair's fare and report.
        let accounts = AccountsSummary(world.accounts)
        check(accounts == model.accountsSummary, "accounts \(accounts) vs \(model.accountsSummary)")
        check(world.accounts.fareBaseline.amount == model.accounts.baseline, "fare baseline \(world.accounts.fareBaseline) vs \(model.accounts.baseline)")
        for period in FinancePeriod.allCases {
            let report = ReportSummary(world.financeReport(period))
            check(report == model.reportSummary(period), "\(period) report \(report) vs \(model.reportSummary(period))")
        }
        for origin in world.stations.prefix(4) {
            for destination in world.stations.prefix(4) {
                let fare = world.tripFare(from: origin.id, to: destination.id)?.amount
                check(fare == model.tripFare(from: origin.id.rawValue, to: destination.id.rawValue), "fare \(origin.id.rawValue)→\(destination.id.rawValue)")
            }
        }
        for station in world.stations {
            let ledger = world.passengerLedger(of: station.id)
            check(ledger == model.ledger(of: station.id.rawValue), "ledger of \(station.id.rawValue) \(ledger) vs \(model.ledger(of: station.id.rawValue))")
        }
        check(
            world.serviceDay.bands.map(\.start) == model.serviceDay.map(\.start) && world.serviceDay.bands.map(\.level) == model.serviceDay.map(\.level),
            "service day \(world.serviceDay) vs \(model.serviceDay)"
        )
        for raw in world.lines.map(\.id.rawValue) + [0, Int.max] where lineAnswers {
            let id = LineID(rawValue: raw)
            for offset: Int64 in [0, 1, 700] {
                let (time, overflow) = world.clock.now.seconds.addingReportingOverflow(offset * 60)
                guard !overflow else { continue }
                check(
                    world.serviceLevel(of: id, at: GameTime(seconds: time)) == model.serviceLevel(of: id, at: GameTime(seconds: time)),
                    "level of line \(raw) at \(time)"
                )
            }
            // The reference drives each service once and derives the rest.
            let patterns = world.line(id: id)?.patterns.count ?? 0
            let all = model.allLineAnswers(id)
            let none = ReferenceWorld.LineAnswers(journey: nil, maximum: nil, trains: [:], headways: [:])
            for pattern in [nil] + (0...patterns).map(Optional.some) {
                let service = pattern.map { $0 + 1 } ?? 0
                let expected = all.flatMap { service < $0.services.count ? $0.services[service] : nil } ?? none
                let name = "line \(raw)\(pattern.map { " pattern \($0)" } ?? "")"
                let journey = world.lineJourney(id, pattern: pattern)
                check(journey == expected.journey, "journey of \(name): \(String(describing: journey)) vs \(String(describing: expected.journey))")
                check(world.lineMaximumTrains(id, pattern: pattern) == expected.maximum, "maximum trains of \(name)")
                for level in ServiceLevel.allCases {
                    check(world.lineTrainsInService(id, at: level, pattern: pattern) == expected.trains[level], "trains of \(name) at \(level)")
                    check(world.lineHeadway(id, at: level, pattern: pattern) == expected.headways[level], "headway of \(name) at \(level)")
                }
            }
            for level in ServiceLevel.allCases where patterns > 0 || raw == 0 || world.line(id: id)?.isRing == true {
                let loads = world.lineSegmentLoads(id, at: level)
                check(loads == all?.loads[level], "segment loads of line \(raw) at \(level): \(String(describing: loads)) vs \(String(describing: all?.loads[level]))")
            }
        }
        // Derived answers: stops, for known and unknown IDs.
        for raw in world.trains.map(\.id.rawValue) + [0, Int.max] {
            let id = TrainID(rawValue: raw)
            check(
                world.stationsStoppedAt(by: id) == model.stationsStoppedAt(by: id),
                "stops of train \(raw): \(world.stationsStoppedAt(by: id)) vs \(model.stationsStoppedAt(by: id))"
            )
            check(
                world.stationsBesideWholeTrain(id) == model.stationsBesideWholeTrain(id),
                "whole-train stops of train \(raw): \(world.stationsBesideWholeTrain(id)) vs \(model.stationsBesideWholeTrain(id))"
            )
        }
        return found
    }

    /// Decision 18's transitions: whose stop an operation may begin or end.
    /// Decision 20 adds one: `advance` may move a stopped train, and so end
    /// its stop, when a service was running it. Decision 23 another: when
    /// the train is on a line, which may send it out. On the track network
    /// (Stage F3b) turning a train round, and adding or removing a platform
    /// under it.
    static func stopTransitionProblems(
        _ operation: Operation,
        before: GameWorld,
        after: GameWorld,
        refused: Bool
    ) -> [String] {
        var found: [String] = []
        for train in after.trains {
            let was = before.stationsStoppedAt(by: train.id)
            let now = after.stationsStoppedAt(by: train.id)
            let wasInService = before.train(id: train.id)?.execution != nil || before.assignedLine(of: train.id) != nil
            if case .advance = operation, !was.isEmpty, !wasInService, let old = before.train(id: train.id),
               old.position != train.position || old.movement != train.movement {
                found.append("advance moved train \(train.id.rawValue), stopped at \(was)")
            }
            guard was != now else { continue }
            let isThis: (TrainID) -> Bool = { $0 == train.id }
            let allowed: Bool = switch operation {
            case _ where refused: false
            case .advance: was.isEmpty || wasInService
            case .place(let id, _): isThis(id) && was.isEmpty
            // Stage F3b: on the track network a train turned round runs on to
            // the end of its edge, so it is no longer stopped.
            case .reverse(let id): isThis(id)
            case .unplace(let id): isThis(id) && now.isEmpty
            case .sendToStation(let id, _), .sendWholeTrainToStation(let id, _), .stand(let id, _, _), .sendToNode(let id, _): isThis(id)
            // Stage F3b: a platform added under a stopped train is one it is
            // stopped at.
            case .addPlatform: now.count == was.count + 1 && Set(was).isSubset(of: Set(now))
            // Stage F3b: a platform removed from under a train that no
            // service needs it for ends its stop there.
            case .removePlatform: now.count == was.count - 1 && Set(now).isSubset(of: Set(was))
            default: false
            }
            if !allowed {
                found.append("\(operation)\(refused ? " (refused)" : "") changed train \(train.id.rawValue)'s stops from \(was) to \(now)")
            }
        }
        return found
    }

    // MARK: - Running

    /// Runs `operations` from `setup`; returns the first problem and the
    /// step it happened at, or `nil`.
    static func firstProblem(_ setup: Setup, _ operations: [Operation], lineAnswers: Bool = true) -> (step: Int, problem: String)? {
        guard let built = try? setup.build() else { return (-1, "the setup did not build") }
        var (world, model) = built
        let initial = differences(world, model, lineAnswers: lineAnswers)
        if !initial.isEmpty { return (-1, "initial: \(initial)") }
        for (index, operation) in operations.enumerated() {
            let before = world
            let error = apply(operation, to: &world)
            let expectedError = apply(operation, to: &model)
            if error != expectedError {
                return (index, "\(operation): GameCore \(String(describing: error)), reference \(String(describing: expectedError))")
            }
            if error != nil, world != before {
                return (index, "\(operation) was refused with \(String(describing: error)) but changed the world")
            }
            if case .saveAndLoad = operation, world != before {
                return (index, "the world did not survive saving and loading")
            }
            let found = differences(world, model, lineAnswers: lineAnswers) + stopTransitionProblems(operation, before: before, after: world, refused: error != nil)
            if !found.isEmpty {
                return (index, "after \(operation): " + found.prefix(4).joined(separator: "; "))
            }
        }
        return nil
    }

    /// Removes items while `stillFails` holds: chunks first, then single
    /// items, until no single removal keeps it failing (a 1-minimal list).
    static func shrink<T>(_ items: [T], stillFails: ([T]) -> Bool) -> [T] {
        var current = items
        var chunk = max(1, current.count / 2)
        while chunk >= 1 {
            var start = 0
            var removedAny = false
            while start < current.count {
                var candidate = current
                candidate.removeSubrange(start..<min(start + chunk, candidate.count))
                if stillFails(candidate) {
                    current = candidate
                    removedAny = true
                } else {
                    start += chunk
                }
            }
            if !removedAny { chunk /= 2 }
        }
        return current
    }

    /// The failing prefix of `operations`, shrunk.
    static func minimalFailure(_ setup: Setup, _ operations: [Operation], lineAnswers: Bool = true) -> [Operation] {
        guard let failure = firstProblem(setup, operations, lineAnswers: lineAnswers) else { return operations }
        let prefix = Array(operations.prefix(max(0, failure.step) + 1))
        return shrink(prefix) { firstProblem(setup, $0, lineAnswers: lineAnswers) != nil }
    }

    /// Generates one case's setup and operations (the world is stepped
    /// while generating, so operations fit the state they will meet).
    static func generate(_ c: inout PropertyCase, operations count: Int) throws -> (Setup, [Operation]) {
        let setup = makeNetworkSetup(using: &c.random)
        var (world, _) = try setup.build()
        var operations: [Operation] = []
        for _ in 0..<count {
            let operation = nextOperation(in: world, using: &c.random)
            operations.append(operation)
            _ = apply(operation, to: &world)
        }
        return (setup, operations)
    }

    func testTheKernelMatchesTheReferenceAndStopsChangeOnlyAsDocumented() throws {
        var operations = 0
        var refused = 0
        var stopEvents = 0
        var tally: [String: Int] = [:]
        var digest = Digest()
        let ran = try runCampaign("kernel.differential", cases: 80) { c in
            let (setup, generated) = try Self.generate(&c, operations: 120)
            c.note("setup: \(setup.summary), +\(setup.extraBalance), second \(setup.seconds), \(setup.speed)")
            if let failure = Self.firstProblem(setup, generated) {
                let minimal = Self.minimalFailure(setup, generated)
                c.fail("step \(failure.step): \(failure.problem)\n  minimal (\(minimal.count) of \(generated.count)): [\(minimal.map(\.description).joined(separator: ", "))]\n  still: \(Self.firstProblem(setup, minimal)?.problem ?? "passes")")
                return
            }
            // Volume and digest, from a second run of the same case.
            guard let built = try? setup.build() else { return }
            var world = built.0
            for operation in generated {
                let before = world.trains.map { world.stationsStoppedAt(by: $0.id) }
                let moved = world.trains.map(\.position)
                let paths = world.trains.map(\.movement)
                let error = Self.apply(operation, to: &world)
                if error != nil { refused += 1 }
                let after = world.trains.map { world.stationsStoppedAt(by: $0.id) }
                stopEvents += zip(before, after).filter { $0 != $1 }.count
                operations += 1
                let name = operation.description.dropFirst().components(separatedBy: "(")[0]
                tally["\(error.map { "\($0)".components(separatedBy: "(")[0] } ?? "ok") \(name)", default: 0] += 1
                let isSend = switch operation {
                case .sendToStation, .sendWholeTrainToStation, .sendToNode: true
                default: false
                }
                if case .advance = operation, zip(moved, world.trains.map(\.position)).contains(where: { $0 != $1 }) {
                    tally["advances that move a train", default: 0] += 1
                }
                if isSend, zip(paths, world.trains.map(\.movement)).contains(where: { $0 != $1 }) {
                    tally["sends that give a path", default: 0] += 1
                }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            digest.add(String(decoding: try encoder.encode(world), as: UTF8.self))
        }
        print("[digest] kernel.differential \(digest.hex) (\(operations) operations, \(refused) refused, \(stopEvents) stop changes)")
        print("[volume] kernel.differential \(tally.keys.sorted().map { "\($0) \(tally[$0]!)" }.joined(separator: ", "))")
        assertVolume(ran == 80 * PropertySeeds.active.count, "every case should run")
        assertVolume(operations == 80 * 120 * PropertySeeds.active.count, "every operation should run")
        assertVolume(refused > 5_000 && stopEvents > 400, "too few refusals (\(refused)) or stop changes (\(stopEvents)) to mean much")
        // Stage F3b: the network's own commands do their work.
        for (what, least) in [
            ("advances that move a train", 300), ("sends that give a path", 200), ("ok stand", 250), ("ok place", 350), ("ok buildEdge", 200),
            ("ok removeEdge", 200), ("ok addPlatform", 100), ("ok removePlatform", 200), ("ok buildStationAt", 200), ("trackEdgeInUse removeEdge", 100),
        ] {
            assertVolume(tally[what, default: 0] >= least, "\(what): \(tally[what, default: 0])")
        }
    }

    /// The shrinker itself: a sequence that fails only because of two of its
    /// operations is cut down to those two, in order.
    func testTheShrinkerKeepsOnlyTheOperationsAFailureNeeds() throws {
        let noise: [Operation] = (0..<30).map { .advance($0 % 4) }
        let needle: [Operation] = [.purchase("A"), .setRate(TrainID(rawValue: 1), 7)]
        let sequence = Array(noise.prefix(12)) + [needle[0]] + Array(noise[12...]) + [needle[1]] + Array(noise.prefix(5))
        // A stand-in failure: a purchase followed later by a rate.
        let fails: ([Operation]) -> Bool = { operations in
            guard let buy = operations.firstIndex(of: needle[0]) else { return false }
            return operations[buy...].contains(needle[1])
        }

        XCTAssertEqual(Self.shrink(sequence, stillFails: fails), needle)
        XCTAssertEqual(Self.shrink([Operation](), stillFails: { _ in true }), [])
        XCTAssertEqual(Self.shrink(needle, stillFails: { _ in false }), needle, "nothing is removed that the failure needs")
    }

    /// The same case gives the same operations and worlds in every run.
    func testGeneratedCasesReplayExactly() throws {
        try runCampaign("kernel.replay", cases: 10) { c in
            var first = PropertyCase(suite: c.suite, seed: c.seed, index: c.index)
            var second = PropertyCase(suite: c.suite, seed: c.seed, index: c.index)
            let (setupA, operationsA) = try Self.generate(&first, operations: 60)
            let (setupB, operationsB) = try Self.generate(&second, operations: 60)
            c.expect(operationsA == operationsB, "the same case generated different operations")
            var (a, _) = try setupA.build()
            var (b, _) = try setupB.build()
            for (x, y) in zip(operationsA, operationsB) {
                _ = Self.apply(x, to: &a)
                _ = Self.apply(y, to: &b)
            }
            c.expect(a == b, "the same operations gave different worlds")
        }
    }
}
