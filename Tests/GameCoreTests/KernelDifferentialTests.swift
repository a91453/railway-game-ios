import Foundation
import GameCore
import XCTest

/// Stages I–N together, differentially: generated command sequences run on
/// a `GameWorld` and on ``ReferenceWorld`` (the rules written a second way).
/// After every command both must give the same outcome (the same
/// `GameError`, in the documented order of checks) and the same observable
/// state: time, speed, money, every tile, stations, trains with their
/// position and movement, connectivity, platforms and station stops.
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
        case buildTrack(GridPosition, UInt8)
        case removeTrack(GridPosition)
        case buildStation(String, GridPosition)
        case purchase(String)
        case place(TrainID, TrainPosition)
        case unplace(TrainID)
        case reverse(TrainID)
        case setRate(TrainID, Int64)
        /// Stage W2c.
        case setPerformance(TrainID, TrainPerformance)
        case setContinuation(TrainID, [GridPosition])
        /// Never drawn by ``nextOperation(in:using:)``, so the Stage I–N
        /// campaigns and their digests are as before; the timetable
        /// campaigns (`TimetablePropertyTests`) add it, and the repeating
        /// service campaign (`ServicePropertyTests`) gives it a period, in
        /// seconds (Stage W2a).
        case setTimetable(TrainID, [ScheduledStop], period: Int64? = nil)
        /// Never drawn by ``nextOperation(in:using:)`` either; the service
        /// campaigns (`ServicePropertyTests`) add them.
        case startService(TrainID)
        case stopService(TrainID)
        /// The train tool's send to a tile: route from where the train is,
        /// committed unchanged.
        case sendToTile(TrainID, GridPosition)
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
        /// Only the track-resource campaign (`TrackResourcePropertyTests`)
        /// draws these.
        case buildTurnout(GridPosition, UInt8, TrackDirection)
        case buildCrossing(GridPosition)
        /// Only the station-facility campaign (`StationFacilityPropertyTests`)
        /// draws these.
        case extendStation(StationID, GridPosition)
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
        case advance(Int)
        case setSpeed(GameSpeed)
        case pause
        case resume
        case saveAndLoad

        var description: String {
            switch self {
            case .buildTrack(let p, let mask): ".buildTrack(\(p), \(mask))"
            case .removeTrack(let p): ".removeTrack(\(p))"
            case .buildStation(let name, let p): ".buildStation(\"\(name)\", \(p))"
            case .purchase(let name): ".purchase(\"\(name)\")"
            case .place(let id, let position): ".place(\(id.rawValue), \(position))"
            case .unplace(let id): ".unplace(\(id.rawValue))"
            case .reverse(let id): ".reverse(\(id.rawValue))"
            case .setRate(let id, let rate): ".setRate(\(id.rawValue), \(rate))"
            case .setPerformance(let id, let performance): ".setPerformance(\(id.rawValue), \(performance))"
            case .setContinuation(let id, let nodes): ".setContinuation(\(id.rawValue), \(nodes))"
            case .setTimetable(let id, let stops, let period):
                ".setTimetable(\(id.rawValue), [\(stops.map { "\($0.station.rawValue)@\($0.arrival.seconds)-\($0.departure.seconds)s\($0.reverses ? "R" : "")" }.joined(separator: ", "))]\(period.map { ", every \($0) s" } ?? ""))"
            case .startService(let id): ".startService(\(id.rawValue))"
            case .stopService(let id): ".stopService(\(id.rawValue))"
            case .sendToTile(let id, let p): ".sendToTile(\(id.rawValue), \(p))"
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
            case .buildTurnout(let p, let mask, let stem): ".buildTurnout(\(p), \(mask), stem \(stem))"
            case .buildCrossing(let p): ".buildCrossing(\(p))"
            case .extendStation(let id, let p): ".extendStation(\(id.rawValue), \(p))"
            case .setCars(let id, let cars): ".setCars(\(id.rawValue), \(cars))"
            case .sendWholeTrainToStation(let id, let station): ".sendWholeTrainToStation(\(id.rawValue), \(station.rawValue))"
            case .unassign(let id): ".unassign(\(id.rawValue))"
            case .setStationDemand(let id, let demand):
                ".setStationDemand(\(id.rawValue), \(demand.map { "\($0.kind) \($0.dailyTrips)" } ?? "none"))"
            case .setEconomyMode(let mode): ".setEconomyMode(.\(mode))"
            case .setFareRules(let rules): ".setFareRules(\(rules))"
            case .setFareBaseline(let baseline): ".setFareBaseline(\(baseline.amount))"
            case .advance(let ticks): ".advance(\(ticks))"
            case .setSpeed(let speed): ".setSpeed(.\(speed))"
            case .pause: ".pause"
            case .resume: ".resume"
            case .saveAndLoad: ".saveAndLoad"
            }
        }
    }

    /// Everything a case starts from.
    struct Setup {
        var specs: [TileSpec]
        var width: Int
        var height: Int
        var extraBalance: Int64
        /// The clock, in seconds (Stage W2a).
        var seconds: Int64
        var speed: GameSpeed

        var costs: ConstructionCosts { NetworkGenerator.costs }

        /// The same network built on both sides, each through its own
        /// commands, with just enough money plus `extraBalance`.
        func build() throws -> (GameWorld, ReferenceWorld) {
            let needed = specs.reduce(Int64(0)) { sum, spec in
                if case .track = spec.kind { return sum + costs.track.amount }
                return sum + costs.station.amount
            }
            let balance = needed + extraBalance
            var world = try GameWorld(
                width: width, height: height,
                economy: GameEconomy(balance: Money(balance), costs: costs),
                clock: GameClock(now: GameTime(seconds: seconds), speed: speed)
            )
            var model = ReferenceWorld(width: width, height: height, balance: balance, costs: costs, seconds: seconds, speed: speed)
            for spec in specs {
                switch spec.kind {
                case .track(let connections):
                    try world.buildTrack(at: spec.position, connections: connections)
                    guard model.buildTrack(at: spec.position, mask: connections.rawValue) == nil else { throw SetupError.modelRefused }
                case .station:
                    let name = "S\(spec.position.x)-\(spec.position.y)"
                    try world.buildStation(named: name, at: spec.position)
                    guard model.buildStation(named: name, at: spec.position) == nil else { throw SetupError.modelRefused }
                case .turnout(let connections, let stem):
                    try world.buildTurnout(at: spec.position, connections: connections, stem: stem)
                    guard model.buildTurnout(at: spec.position, mask: connections.rawValue, stem: stem) == nil else { throw SetupError.modelRefused }
                case .crossing:
                    try world.buildCrossing(at: spec.position)
                    guard model.buildCrossing(at: spec.position) == nil else { throw SetupError.modelRefused }
                }
            }
            return (world, model)
        }
    }

    enum SetupError: Error {
        case modelRefused
    }

    // MARK: - Generation

    /// A setup on a network of one of `shapes` (with repeats to weight
    /// them); the default draws exactly as the Stage I–N campaigns always
    /// have.
    static func makeSetup(shapes: [NetworkShape] = NetworkShape.allCases, using random: inout SplitMix64) -> Setup {
        let shape = random.element(of: shapes)
        var (specs, width, height) = NetworkGenerator.specs(shape, using: &random)
        // Stations beside the network, so that platforms are common.
        let occupied = Set(specs.map(\.position))
        for y in 0..<height {
            for x in 0..<width where !occupied.contains(GridPosition(x: x, y: y)) && random.chance(1, in: 4) {
                specs.append(TileSpec(position: GridPosition(x: x, y: y), kind: .station))
            }
        }
        let extra: Int64 = random.chance(1, in: 3) ? random.int64(in: 0...12_000) : 1_000_000
        // Sometimes near the end of time, so that advancing can overflow;
        // otherwise a whole minute, or for a quarter of the minutes a second
        // between two (Stage W2a). The second comes from the minute rather
        // than another draw, so the campaigns draw the same cases as before.
        let seconds: Int64
        if random.chance(1, in: 8) {
            seconds = Int64.max - random.int64(in: 0...2_400)
        } else {
            let minute = random.int64(in: 0...100_000)
            seconds = minute * 60 + (minute % 4 == 1 ? minute / 4 % 59 + 1 : 0)
        }
        let speed = random.element(of: GameSpeed.allCases)
        return Setup(specs: specs, width: width, height: height, extraBalance: extra, seconds: seconds, speed: speed)
    }

    private static func randomTile(_ world: GameWorld, _ random: inout SplitMix64) -> GridPosition {
        GridPosition(x: random.below(world.map.width + 2) - 1, y: random.below(world.map.height + 2) - 1)
    }

    /// The next operation, drawn with the current world in view: mostly
    /// sensible, sometimes invalid on purpose.
    static func nextOperation(in world: GameWorld, using random: inout SplitMix64) -> Operation {
        let trains = world.trains
        let unknownIDs = [0, -1, trains.count + 1, trains.count + 2, Int.max]
        let id = trains.isEmpty || random.chance(1, in: 12)
            ? TrainID(rawValue: random.element(of: unknownIDs))
            : random.element(of: trains).id
        let position = world.train(id: id)?.position
        switch random.below(100) {
        case 0..<5:
            return .purchase(random.chance(1, in: 10) ? random.element(of: ["", " ", "\n\t"]) : "T\(trains.count + 1)")
        case 5..<14:
            if random.chance(3, in: 4), let valid = PositionGenerator.validPosition(in: world, using: &random) {
                return .place(id, valid)
            }
            let tile = randomTile(world, &random)
            return random.chance(1, in: 2)
                ? .place(id, .atNode(tile, heading: random.element(of: TrackDirection.allCases)))
                : .place(id, .onLink(from: tile, to: step(tile, random.element(of: TrackDirection.allCases)), offset: random.element(of: [-1, 0, 1, 512, 1023, 1024])))
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
            guard let position else { return .setContinuation(id, []) }
            var walk = PositionGenerator.walk(in: world, from: position, length: random.below(8), using: &random)
            if !walk.isEmpty, random.chance(1, in: 4) {
                let index = random.below(walk.count)
                switch random.below(3) {
                case 0: walk.append(walk.count >= 2 ? walk[walk.count - 2] : ahead(of: position).node)
                case 1: walk[index] = GridPosition(x: walk[index].x + 1, y: walk[index].y + 1)
                default: walk[index] = GridPosition(x: -5, y: walk[index].y)
                }
            }
            return .setContinuation(id, walk)
        case 37..<44:
            let tracks = world.tracks.map(\.position)
            let destination = !tracks.isEmpty && random.chance(5, in: 6) ? random.element(of: tracks) : randomTile(world, &random)
            return .sendToTile(id, destination)
        case 44..<56:
            let stations = world.stations.map(\.id)
            let station = !stations.isEmpty && random.chance(9, in: 10)
                ? random.element(of: stations)
                : StationID(rawValue: random.element(of: [0, -1, stations.count + 1, Int.max]))
            return .sendToStation(id, station)
        case 56..<76:
            return .advance(random.below(10))
        case 76..<79:
            return .setSpeed(random.element(of: GameSpeed.allCases))
        case 79..<80:
            return random.chance(1, in: 2) ? .pause : .resume
        case 80..<86:
            let mask: UInt8 = random.chance(1, in: 10) ? random.element(of: [0, 16, 31, 255]) : UInt8(1 + random.below(15))
            return .buildTrack(randomTile(world, &random), mask)
        case 86..<92:
            if let position, random.chance(1, in: 3) {
                switch position {
                case .atNode(let tile, _): return .removeTrack(tile)
                case .onLink(let from, let to, _): return .removeTrack(random.chance(1, in: 2) ? from : to)
                case .onEdge: break
                }
            }
            if random.chance(1, in: 2), !world.stations.isEmpty {
                let station = random.element(of: world.stations)
                // A platform, or the station itself.
                let platforms = world.platforms(of: station.id)
                return .removeTrack(platforms.isEmpty || random.chance(1, in: 4) ? station.position : random.element(of: platforms))
            }
            return .removeTrack(randomTile(world, &random))
        case 92..<96:
            // Often beside a train, to make a stop appear under it.
            if let position, random.chance(1, in: 2) {
                let (node, _) = ahead(of: position)
                return .buildStation("B\(world.stations.count + 1)", step(node, random.element(of: TrackDirection.allCases)))
            }
            return .buildStation(random.chance(1, in: 10) ? " " : "B\(world.stations.count + 1)", randomTile(world, &random))
        default:
            return .saveAndLoad
        }
    }

    // MARK: - Applying

    /// Applies `operation` to the world, returning the refusal if any.
    static func apply(_ operation: Operation, to world: inout GameWorld) -> GameError? {
        do throws(GameError) {
            switch operation {
            case .buildTrack(let p, let mask): try world.buildTrack(at: p, connections: TrackConnections(rawValue: mask))
            case .removeTrack(let p): try world.removeTrack(at: p)
            case .buildStation(let name, let p): try world.buildStation(named: name, at: p)
            case .purchase(let name): try world.purchaseTrain(named: name)
            case .place(let id, let position): try world.placeTrain(id, at: position)
            case .unplace(let id): try world.unplaceTrain(id)
            case .reverse(let id): try world.reverseTrain(id)
            case .setRate(let id, let rate): try world.setTrainMovementRate(id, to: rate)
            case .setPerformance(let id, let performance): try world.setTrainPerformance(id, to: performance)
            case .setContinuation(let id, let nodes): try world.setTrainContinuation(id, to: nodes)
            case .setTimetable(let id, let stops, let period): try world.setTrainTimetable(id, to: stops, repeatingEvery: period)
            case .startService(let id): try world.startTrainService(id)
            case .stopService(let id): try world.stopTrainService(id)
            case .sendToTile(let id, let p):
                guard let position = world.train(id: id)?.position, let route = world.route(from: position, to: p) else { return nil }
                try world.setTrainContinuation(id, to: route)
            case .sendToStation(let id, let station):
                guard let position = world.train(id: id)?.position, let route = world.route(from: position, toStation: station) else { return nil }
                try world.setTrainContinuation(id, to: route)
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
            case .buildTurnout(let p, let mask, let stem): try world.buildTurnout(at: p, connections: TrackConnections(rawValue: mask), stem: stem)
            case .buildCrossing(let p): try world.buildCrossing(at: p)
            case .extendStation(let id, let p): try world.extendStation(id, to: p)
            case .setCars(let id, let cars): try world.setTrainCars(id, to: cars)
            case .sendWholeTrainToStation(let id, let station):
                guard let train = world.train(id: id), let position = train.position,
                      let route = world.route(from: position, toStation: station, length: train.length)
                else { return nil }
                try world.setTrainContinuation(id, to: route)
            case .setStationDemand(let id, let demand): try world.setStationDemand(id, to: demand)
            case .setEconomyMode(let mode): world.setEconomyMode(mode)
            case .setFareRules(let rules): try world.setFareRules(rules)
            case .setFareBaseline(let baseline): try world.setFareBaseline(baseline)
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
        case .buildTrack(let p, let mask): return model.buildTrack(at: p, mask: mask)
        case .removeTrack(let p): return model.removeTrack(at: p)
        case .buildStation(let name, let p): return model.buildStation(named: name, at: p)
        case .purchase(let name): return model.purchaseTrain(named: name)
        case .place(let id, let position): return model.placeTrain(id, at: position)
        case .unplace(let id): return model.unplaceTrain(id)
        case .reverse(let id): return model.reverseTrain(id)
        case .setRate(let id, let rate): return model.setRate(id, rate)
        case .setPerformance(let id, let performance): return model.setPerformance(id, performance)
        case .setContinuation(let id, let nodes): return model.setContinuation(id, nodes)
        case .setTimetable(let id, let stops, let period): return model.setTimetable(id, stops, period: period)
        case .startService(let id): return model.startService(id)
        case .stopService(let id): return model.stopService(id)
        case .sendToTile(let id, let p):
            guard let position = model.trains.first(where: { $0.id == id.rawValue })?.position,
                  let route = model.route(from: position, to: p)
            else { return nil }
            return model.setContinuation(id, route)
        case .sendToStation(let id, let station):
            guard let position = model.trains.first(where: { $0.id == id.rawValue })?.position,
                  let route = model.route(from: position, toStation: station)
            else { return nil }
            return model.setContinuation(id, route)
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
        case .buildTurnout(let p, let mask, let stem): return model.buildTurnout(at: p, mask: mask, stem: stem)
        case .buildCrossing(let p): return model.buildCrossing(at: p)
        case .extendStation(let id, let p): return model.extendStation(id, to: p)
        case .setCars(let id, let cars): return model.setCars(id, cars)
        case .sendWholeTrainToStation(let id, let station):
            guard let train = model.trains.first(where: { $0.id == id.rawValue }), let position = train.position,
                  let route = model.route(from: position, toStation: station, length: ReferenceWorld.length(train))
            else { return nil }
            return model.setContinuation(id, route)
        case .setStationDemand(let id, let demand): return model.setStationDemand(id, demand)
        case .setEconomyMode(let mode): model.setEconomyMode(mode); return nil
        case .setFareRules(let rules): return model.setFareRules(rules)
        case .setFareBaseline(let baseline): return model.setFareBaseline(baseline)
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
        // Stage S3A: the land holds stations; the railway network holds the
        // grid's track pieces.
        for tile in world.map.tiles {
            let expected: TileType = switch model.tiles[tile.position] {
            case .station(let id)?: .station(id: StationID(rawValue: id))
            default: .empty
            }
            check(tile.type == expected, "tile \(tile.position): \(tile.type) vs \(expected)")
            let track: Track? = switch model.tiles[tile.position] {
            case .track(let mask)?: Track(position: tile.position, connections: TrackConnections(rawValue: mask))
            case .turnout(let mask, let stem)?: Track(position: tile.position, connections: TrackConnections(rawValue: mask), layout: .turnout(stem: stem))
            case .crossing?: Track(position: tile.position, connections: [.north, .east, .south, .west], layout: .crossing)
            default: nil
            }
            check(world.track(at: tile.position) == track, "track \(tile.position): \(String(describing: world.track(at: tile.position))) vs \(String(describing: track))")
        }
        check(world.tracks.count == model.tiles.values.count { if case .station = $0 { false } else { true } }, "track count")
        check(
            world.stations.map { [$0.id.rawValue, $0.position.x, $0.position.y] } == model.stations.map { [$0.id, $0.position.x, $0.position.y] }
                && world.stations.map(\.name) == model.stations.map(\.name) && world.stations.map(\.annexes) == model.stations.map(\.annexes)
                && world.stations.map(\.point) == model.stations.map(\.point),
            "stations \(world.stations) vs \(model.stations)"
        )
        check(world.trains.map(\.id.rawValue) == model.trains.map(\.id), "train IDs \(world.trains.map(\.id.rawValue)) vs \(model.trains.map(\.id))")
        for (train, expected) in zip(world.trains, model.trains) {
            check(train.name == expected.name, "train \(expected.id) name")
            check(train.position == expected.position, "train \(expected.id) position \(String(describing: train.position)) vs \(String(describing: expected.position))")
            // Decision 27: its cars and body.
            check(train.cars == expected.cars, "train \(expected.id) cars \(train.cars) vs \(expected.cars)")
            check(train.trail == expected.trail, "train \(expected.id) trail \(train.trail) vs \(expected.trail)")
            check(train.movement.rate == expected.rate, "train \(expected.id) rate \(train.movement.rate) vs \(expected.rate)")
            check(train.performance == expected.performance, "train \(expected.id) performance")
            check(
                train.movement.continuation == expected.continuation && train.movement.cursor == expected.cursor,
                "train \(expected.id) continuation \(train.movement.continuation)@\(train.movement.cursor) vs \(expected.continuation)@\(expected.cursor)"
            )
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
                && world.lines.map { $0.lastDispatch?.minutes } == model.lines.map(\.lastDispatch),
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
            for level in ServiceLevel.allCases where patterns > 0 || raw == 0 {
                let loads = world.lineSegmentLoads(id, at: level)
                check(loads == all?.loads[level], "segment loads of line \(raw) at \(level): \(String(describing: loads)) vs \(String(describing: all?.loads[level]))")
            }
        }
        // Derived answers: connectivity (a ring outside the map included),
        // platforms and stops, for known and unknown IDs.
        for y in -1...world.map.height {
            for x in -1...world.map.width {
                let p = GridPosition(x: x, y: y)
                check(world.connectedNeighbors(of: p) == model.neighbors(of: p), "neighbours of \(p)")
            }
        }
        for raw in world.stations.map(\.id.rawValue) + [0, -1, Int.max] {
            let id = StationID(rawValue: raw)
            check(world.platforms(of: id) == model.platforms(of: id), "platforms of \(raw): \(world.platforms(of: id)) vs \(model.platforms(of: id))")
            check(
                world.platformTracks(of: id) == model.platformTracks(of: id),
                "platform tracks of \(raw): \(world.platformTracks(of: id)) vs \(model.platformTracks(of: id))"
            )
        }
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
    /// the train is on a line, which may send it out. Decision 27 two more:
    /// turning round a train with cars, and growing a station.
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
            // Decision 27: a train with cars turns round with its head at
            // its tail, which may be beside other stations or none.
            case .reverse(let id): isThis(id) && (was.isEmpty || train.cars > 0)
            case .unplace(let id): isThis(id) && now.isEmpty
            case .setContinuation(let id, _), .sendToTile(let id, _), .sendToStation(let id, _), .sendWholeTrainToStation(let id, _): isThis(id)
            // Decision 27: a station grown beside a stopped train is one it
            // is stopped at, as one built there is.
            case .buildStation, .extendStation: now.count == was.count + 1 && Set(was).isSubset(of: Set(now))
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
        let setup = makeSetup(using: &c.random)
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
        var digest = Digest()
        let ran = try runCampaign("kernel.differential", cases: 80) { c in
            let (setup, generated) = try Self.generate(&c, operations: 120)
            c.note("setup: \(setup.width)x\(setup.height), \(setup.specs.count) tiles, +\(setup.extraBalance), second \(setup.seconds), \(setup.speed)")
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
                if Self.apply(operation, to: &world) != nil { refused += 1 }
                let after = world.trains.map { world.stationsStoppedAt(by: $0.id) }
                stopEvents += zip(before, after).filter { $0 != $1 }.count
                operations += 1
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            digest.add(String(decoding: try encoder.encode(world), as: UTF8.self))
        }
        print("[digest] kernel.differential \(digest.hex) (\(operations) operations, \(refused) refused, \(stopEvents) stop changes)")
        assertVolume(ran == 80 * PropertySeeds.active.count, "every case should run")
        assertVolume(operations == 80 * 120 * PropertySeeds.active.count, "every operation should run")
        assertVolume(refused > 5_000 && stopEvents > 400, "too few refusals (\(refused)) or stop changes (\(stopEvents)) to mean much")
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
