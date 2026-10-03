import GameCore

/// A command of a replay fixture as it is recorded: its kind and the values
/// it takes, in plain numbers and strings. Commands are recorded whether
/// GameCore accepts them or not (a refused one must change nothing), so
/// their values are written out here rather than with GameCore's own
/// coding, which refuses values a world cannot hold.
///
/// Only commands of the track network have a recorded form; the network
/// campaigns draw no others. So removing the grid (Stage F3c) cannot change
/// what a fixture says.
struct ReplayCommand: Codable {
    struct Step: Codable {
        var edge: Int
        var forward: Bool
    }

    struct Performance: Codable {
        var acceleration: Int64
        var braking: Int64
        var topSpeed: Int64
        var alternativeAcceleration: Int64?
        var alternativeBraking: Int64?
        /// Deceleration and speed ratio.
        var coast: [Int64]?
    }

    struct Stop: Codable {
        var station: Int
        var arrival: Int64
        var departure: Int64
        var reverses: Bool
    }

    struct Window: Codable {
        /// Both `nil`: all day.
        var open: Int?
        var close: Int?
    }

    struct Counts: Codable {
        var peak: Int
        var offPeak: Int
        var low: Int
    }

    struct Targets: Codable {
        var peak: Int64?
        var offPeak: Int64?
        var low: Int64?
    }

    struct Band: Codable {
        var start: Int
        var level: String
    }

    struct Demand: Codable {
        var kind: String
        var dailyTrips: Int64
    }

    struct FareBandValues: Codable {
        var from: Int64
        var to: Int64?
        var fare: Int64
    }

    struct Rules: Codable {
        var flat: Int64?
        var bands: [FareBandValues]?
    }

    var kind: String
    var train: Int?
    var station: Int?
    var line: Int?
    var node: Int?
    var to: Int?
    var edge: Int?
    var name: String?
    /// Where a train is placed: on `at`, `offset` along it.
    var at: Step?
    var offset: Int64?
    var path: [Step]?
    var end: Int64?
    var start: Int64?
    var rate: Int64?
    var performance: Performance?
    var stops: [Stop]?
    var period: Int64?
    var stations: [Int]?
    var window: Window?
    var trains: Counts?
    var pattern: Int?
    var day: [Band]?
    var targets: Targets?
    var calls: [Int]?
    var ring: Bool?
    var cars: Int?
    var demand: Demand?
    var mode: String?
    var rules: Rules?
    var money: Int64?
    var ticks: Int?
    var speed: String?
    /// A plan point: x and y.
    var point: [Int64]?
    /// A world coordinate: x, y and z.
    var coordinate: [Int64]?
    /// A curve's two control points, x and y each; `nil` for a straight edge.
    var controls: [Int64]?

    init(kind: String) {
        self.kind = kind
    }

    /// `operation`'s recorded form, or `nil` for a grid command.
    init?(_ operation: KernelDifferentialTests.Operation) {
        switch operation {
        case .purchase(let name): self.init(kind: "purchase"); self.name = name
        case .place(let id, let position):
            guard case .onEdge(let traversal, let offset) = position else { return nil }
            self.init(kind: "place"); train = id.rawValue; at = Self.step(traversal); self.offset = offset
        case .unplace(let id): self.init(kind: "unplace"); train = id.rawValue
        case .reverse(let id): self.init(kind: "reverse"); train = id.rawValue
        case .setRate(let id, let rate): self.init(kind: "setRate"); train = id.rawValue; self.rate = rate
        case .setPerformance(let id, let performance): self.init(kind: "setPerformance"); train = id.rawValue; self.performance = Self.record(performance)
        case .setTimetable(let id, let stops, let period):
            self.init(kind: "setTimetable"); train = id.rawValue; self.period = period
            self.stops = stops.map { Stop(station: $0.station.rawValue, arrival: $0.arrival.seconds, departure: $0.departure.seconds, reverses: $0.reverses) }
        case .startService(let id): self.init(kind: "startService"); train = id.rawValue
        case .stopService(let id): self.init(kind: "stopService"); train = id.rawValue
        case .sendToStation(let id, let station): self.init(kind: "sendToStation"); train = id.rawValue; self.station = station.rawValue
        case .sendWholeTrainToStation(let id, let station): self.init(kind: "sendWholeTrainToStation"); train = id.rawValue; self.station = station.rawValue
        case .createLine(let name, let stops): self.init(kind: "createLine"); self.name = name; stations = stops.map(\.rawValue)
        case .removeLine(let id): self.init(kind: "removeLine"); line = id.rawValue
        case .setLineStops(let id, let stops): self.init(kind: "setLineStops"); line = id.rawValue; stations = stops.map(\.rawValue)
        case .setLinePerformance(let id, let performance): self.init(kind: "setLinePerformance"); line = id.rawValue; self.performance = Self.record(performance)
        case .setLineWindow(let id, let window):
            self.init(kind: "setLineWindow"); line = id.rawValue
            switch window {
            case .allDay: self.window = Window()
            case .hours(let open, let close): self.window = Window(open: open, close: close)
            }
        case .setLineTrains(let id, let trains, let pattern):
            self.init(kind: "setLineTrains"); line = id.rawValue; self.pattern = pattern
            self.trains = Counts(peak: trains.peak, offPeak: trains.offPeak, low: trains.low)
        case .setServiceDay(let day): self.init(kind: "setServiceDay"); self.day = day.bands.map { Band(start: $0.start, level: $0.level.rawValue) }
        case .setLineTargets(let id, let targets, let pattern):
            self.init(kind: "setLineTargets"); line = id.rawValue; self.pattern = pattern
            self.targets = Targets(peak: targets.peak, offPeak: targets.offPeak, low: targets.low)
        case .assign(let id, let line, let pattern): self.init(kind: "assign"); train = id.rawValue; self.line = line.rawValue; self.pattern = pattern
        case .unassign(let id): self.init(kind: "unassign"); train = id.rawValue
        case .addPattern(let id, let calls): self.init(kind: "addPattern"); line = id.rawValue; self.calls = calls
        case .removePattern(let id, let pattern): self.init(kind: "removePattern"); line = id.rawValue; self.pattern = pattern
        case .setLineRing(let id, let ring): self.init(kind: "setLineRing"); line = id.rawValue; self.ring = ring
        case .setCars(let id, let cars): self.init(kind: "setCars"); train = id.rawValue; self.cars = cars
        case .setStationDemand(let id, let demand):
            self.init(kind: "setStationDemand"); station = id.rawValue
            self.demand = demand.map { Demand(kind: $0.kind.rawValue, dailyTrips: $0.dailyTrips) }
        case .setEconomyMode(let mode): self.init(kind: "setEconomyMode"); self.mode = mode.rawValue
        case .setFareRules(let rules):
            self.init(kind: "setFareRules")
            switch rules {
            case .flat(let fare): self.rules = Rules(flat: fare.amount)
            case .distance(let bands): self.rules = Rules(bands: bands.map { FareBandValues(from: $0.fromMeters, to: $0.toMeters, fare: $0.fare.amount) })
            }
        case .setFareBaseline(let baseline): self.init(kind: "setFareBaseline"); money = baseline.amount
        case .buildNode(let coordinate): self.init(kind: "buildNode"); self.coordinate = [coordinate.x, coordinate.y, coordinate.z]
        case .buildEdge(let from, let to, let curve):
            self.init(kind: "buildEdge"); node = from.number; self.to = to.number
            if case .cubic(let a, let b) = curve { controls = [a.x, a.y, b.x, b.y] }
        case .removeEdge(let edge): self.init(kind: "removeEdge"); self.edge = edge.number
        case .removeNode(let node): self.init(kind: "removeNode"); self.node = node.number
        case .buildStationAt(let name, let point): self.init(kind: "buildStationAt"); self.name = name; self.point = [point.x, point.y]
        case .addPlatform(let id, let edge, let start, let end):
            self.init(kind: "addPlatform"); station = id.rawValue; self.edge = edge.number; self.start = start; self.end = end
        case .removePlatform(let id, let edge, let start): self.init(kind: "removePlatform"); station = id.rawValue; self.edge = edge.number; self.start = start
        case .stand(let id, let path, let end): self.init(kind: "stand"); train = id.rawValue; self.path = path.map(Self.step); self.end = end
        case .sendToNode(let id, let node): self.init(kind: "sendToNode"); train = id.rawValue; self.node = node.number
        case .advance(let ticks): self.init(kind: "advance"); self.ticks = ticks
        case .setSpeed(let speed): self.init(kind: "setSpeed"); self.speed = speed.rawValue
        case .pause: self.init(kind: "pause")
        case .resume: self.init(kind: "resume")
        case .saveAndLoad: self.init(kind: "saveAndLoad")
        case .buildTrack, .removeTrack, .buildStation, .setContinuation, .sendToTile, .buildTurnout, .buildCrossing, .extendStation:
            return nil
        }
    }

    private static func step(_ traversal: TrackTraversal) -> Step {
        Step(edge: traversal.edge.number, forward: traversal.direction == .forward)
    }

    private static func traversal(_ step: Step) -> TrackTraversal {
        TrackTraversal(edge: .edge(step.edge), direction: step.forward ? .forward : .backward)
    }

    private static func record(_ performance: TrainPerformance) -> Performance {
        Performance(
            acceleration: performance.acceleration, braking: performance.braking, topSpeed: performance.topSpeed,
            alternativeAcceleration: performance.alternativeAcceleration, alternativeBraking: performance.alternativeBraking,
            coast: performance.coast.map { [$0.deceleration, $0.speedRatio] }
        )
    }

    private static func performance(_ values: Performance) -> TrainPerformance? {
        var coast: TrainPerformance.Coast?
        if let values = values.coast {
            guard values.count == 2 else { return nil }
            coast = TrainPerformance.Coast(deceleration: values[0], speedRatio: values[1])
        }
        return TrainPerformance(
            acceleration: values.acceleration, braking: values.braking, topSpeed: values.topSpeed,
            alternativeAcceleration: values.alternativeAcceleration, alternativeBraking: values.alternativeBraking, coast: coast
        )
    }

    /// The command it records, or `nil` when a value it needs is missing.
    var operation: KernelDifferentialTests.Operation? {
        let train = self.train.map(TrainID.init(rawValue:))
        let station = self.station.map(StationID.init(rawValue:))
        let line = self.line.map(LineID.init(rawValue:))
        let performance = self.performance.flatMap(Self.performance)
        switch kind {
        case "purchase": return name.map { .purchase($0) }
        case "place":
            guard let train, let at, let offset else { return nil }
            return .place(train, .onEdge(Self.traversal(at), offset: offset))
        case "unplace": return train.map { .unplace($0) }
        case "reverse": return train.map { .reverse($0) }
        case "setRate": guard let train, let rate else { return nil }; return .setRate(train, rate)
        case "setPerformance": guard let train, let performance else { return nil }; return .setPerformance(train, performance)
        case "setTimetable":
            guard let train, let stops else { return nil }
            return .setTimetable(train, stops.map {
                ScheduledStop(station: StationID(rawValue: $0.station), arrival: GameTime(seconds: $0.arrival), departure: GameTime(seconds: $0.departure), reverses: $0.reverses)
            }, period: period)
        case "startService": return train.map { .startService($0) }
        case "stopService": return train.map { .stopService($0) }
        case "sendToStation": guard let train, let station else { return nil }; return .sendToStation(train, station)
        case "sendWholeTrainToStation": guard let train, let station else { return nil }; return .sendWholeTrainToStation(train, station)
        case "createLine": guard let name, let stations else { return nil }; return .createLine(name, stations.map(StationID.init(rawValue:)))
        case "removeLine": return line.map { .removeLine($0) }
        case "setLineStops": guard let line, let stations else { return nil }; return .setLineStops(line, stations.map(StationID.init(rawValue:)))
        case "setLinePerformance": guard let line, let performance else { return nil }; return .setLinePerformance(line, performance)
        case "setLineWindow":
            guard let line, let window else { return nil }
            if let open = window.open, let close = window.close { return .setLineWindow(line, .hours(open: open, close: close)) }
            return window.open == nil && window.close == nil ? .setLineWindow(line, .allDay) : nil
        case "setLineTrains":
            guard let line, let trains else { return nil }
            return .setLineTrains(line, TrainsInService(peak: trains.peak, offPeak: trains.offPeak, low: trains.low), pattern: pattern)
        case "setServiceDay":
            guard let day else { return nil }
            let bands = day.compactMap { band in ServiceLevel(rawValue: band.level).map { ServiceDay.Band(start: band.start, level: $0) } }
            return bands.count == day.count ? .setServiceDay(ServiceDay(bands: bands)) : nil
        case "setLineTargets":
            guard let line, let targets else { return nil }
            return .setLineTargets(line, TargetHeadways(peak: targets.peak, offPeak: targets.offPeak, low: targets.low), pattern: pattern)
        case "assign": guard let train, let line else { return nil }; return .assign(train, line, pattern: pattern)
        case "unassign": return train.map { .unassign($0) }
        case "addPattern": guard let line, let calls else { return nil }; return .addPattern(line, calls)
        case "removePattern": guard let line, let pattern else { return nil }; return .removePattern(line, pattern)
        case "setLineRing": guard let line, let ring else { return nil }; return .setLineRing(line, ring)
        case "setCars": guard let train, let cars else { return nil }; return .setCars(train, cars)
        case "setStationDemand":
            guard let station else { return nil }
            guard let demand else { return .setStationDemand(station, nil) }
            return StationDemandKind(rawValue: demand.kind).map { .setStationDemand(station, StationDemand(kind: $0, dailyTrips: demand.dailyTrips)) }
        case "setEconomyMode": return mode.flatMap(EconomyMode.init(rawValue:)).map { .setEconomyMode($0) }
        case "setFareRules":
            guard let rules else { return nil }
            if let flat = rules.flat { return .setFareRules(.flat(Money(flat))) }
            return rules.bands.map { .setFareRules(.distance($0.map { FareBand(fromMeters: $0.from, toMeters: $0.to, fare: Money($0.fare)) })) }
        case "setFareBaseline": return money.map { .setFareBaseline(Money($0)) }
        case "buildNode":
            guard let coordinate, coordinate.count == 3 else { return nil }
            return .buildNode(WorldCoordinate(x: coordinate[0], y: coordinate[1], z: coordinate[2]))
        case "buildEdge":
            guard let node, let to else { return nil }
            guard let controls else { return .buildEdge(.node(node), .node(to), .straight) }
            guard controls.count == 4 else { return nil }
            return .buildEdge(.node(node), .node(to), .cubic(PlanPoint(x: controls[0], y: controls[1]), PlanPoint(x: controls[2], y: controls[3])))
        case "removeEdge": return edge.map { .removeEdge(.edge($0)) }
        case "removeNode": return node.map { .removeNode(.node($0)) }
        case "buildStationAt":
            guard let name, let point, point.count == 2 else { return nil }
            return .buildStationAt(name, PlanPoint(x: point[0], y: point[1]))
        case "addPlatform": guard let station, let edge, let start, let end else { return nil }; return .addPlatform(station, .edge(edge), start, end)
        case "removePlatform": guard let station, let edge, let start else { return nil }; return .removePlatform(station, .edge(edge), start)
        case "stand": guard let train, let path else { return nil }; return .stand(train, path.map(Self.traversal), end)
        case "sendToNode": guard let train, let node else { return nil }; return .sendToNode(train, .node(node))
        case "advance": return ticks.map { .advance($0) }
        case "setSpeed": return speed.flatMap(GameSpeed.init(rawValue:)).map { .setSpeed($0) }
        case "pause": return .pause
        case "resume": return .resume
        case "saveAndLoad": return .saveAndLoad
        default: return nil
        }
    }
}
