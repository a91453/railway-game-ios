import GameCore

// Decision 261: scripted play. The report tests (BalanceReportTests,
// ChallengeReportTests, CoreLoopBaselineReportTests,
// RealWorldExpansionReportTests) each played a game without a player:
// built lines, ran days, read numbers. What they shared is here, once:
// the lines they build (`LineBuilder`, `CurvedOpening`), what to do on
// which day (`Policy`), and the days played with what went wrong noted
// (`PolicyPlayer`, `PlayAnomaly`). The reports read their numbers from the
// same worlds as before, so their tables are unchanged; GameSim plays a
// named policy (`play`), and the level session measures its targets with
// it. Everything works on a `GameWorld` directly, as the reports did, so
// a script's world moves exactly as the rules move it.
//
// Structure from ml-agents' `Agent` (Apache-2.0: an action at a decision
// period, a mask of the actions the world refuses): only the structure,
// no training and no code (docs/research/GAME_AI_TOOLS_2026-10-15.md §3.3).

/// The lines the scripts build: a player's simplest lines, of straight
/// edges with a platform beyond each end (decision 261).
public enum LineBuilder {
    /// A line through `points` (two or more): a straight edge from a
    /// platform beyond the first to a platform beyond the last through the
    /// points between, a station at each point, one train of four cars
    /// running all day from the first. The tests' `newGameLine(through:)`.
    public static func line(through points: [PlanPoint], in start: GameWorld) throws -> GameWorld {
        var world = start
        let cars = 4
        let platform = Int64(cars) * Train.carLength
        func beyond(_ from: PlanPoint, _ to: PlanPoint) -> WorldCoordinate {
            let dx = Double(to.x - from.x), dy = Double(to.y - from.y)
            let span = (dx * dx + dy * dy).squareRoot()
            return WorldCoordinate(x: to.x + Int64(dx / span * Double(platform)), y: to.y + Int64(dy / span * Double(platform)))
        }
        var nodes = [try world.buildTrackNode(at: beyond(points[1], points[0]))]
        for point in points.dropFirst().dropLast() {
            nodes.append(try world.buildTrackNode(at: WorldCoordinate(x: point.x, y: point.y)))
        }
        nodes.append(try world.buildTrackNode(at: beyond(points[points.count - 2], points[points.count - 1])))
        var edges: [TrackEdgeID] = []
        for (from, to) in zip(nodes, nodes.dropFirst()) {
            edges.append(try world.buildTrackEdge(from: from, to: to))
        }
        var stops: [StationID] = []
        for (index, point) in points.enumerated() {
            let station = try world.buildStation(named: "S\(index)", at: point).id
            if index == 0 {
                try world.addTrackPlatform(station, on: edges[0], from: platform / 2, to: platform + platform / 2)
            } else if index == points.count - 1 {
                let length = world.trackEdge(edges[index - 1])?.length ?? 0
                try world.addTrackPlatform(station, on: edges[index - 1], from: length - platform - platform / 2, to: length - platform / 2)
            } else {
                try world.addTrackPlatform(station, on: edges[index], from: 0, to: platform)
            }
            stops.append(station)
        }
        let line = try world.createLine(named: "Line 1", stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "Train 1").id
        try world.setTrainCars(train, to: cars)
        // Its head at the first platform's far end.
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edges[0], direction: .forward), offset: platform + platform / 2))
        try world.setTrainContinuation(train, along: [], stoppingAt: platform + platform / 2)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
        return world
    }

    /// A straight line of one edge from `from` to `to`, with a station at
    /// each (one already in `stations` is shared), one train of `cars`
    /// cars and all-day service: on the ground, or on a viaduct as low as
    /// clears the track already built (ChallengeReportTests' lines).
    public static func straightLine(
        _ world: inout GameWorld, from: PlanPoint, to: PlanPoint, cars: Int, stations: inout [PlanPoint: StationID]
    ) throws {
        let platform = Int64(cars) * Train.carLength
        func beyond(_ a: PlanPoint, _ b: PlanPoint, z: Int64) -> WorldCoordinate {
            let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let span = (dx * dx + dy * dy).squareRoot()
            return WorldCoordinate(x: b.x + Int64(dx / span * Double(platform)), y: b.y + Int64(dy / span * Double(platform)), z: z)
        }
        var built: (GameWorld, TrackEdgeID)?
        for level in Int64(0)...7 {
            var trial = world
            let z = level * TrackStructure.clearance
            do {
                let start = try trial.buildTrackNode(at: beyond(to, from, z: z))
                let end = try trial.buildTrackNode(at: beyond(from, to, z: z))
                let edge = try trial.buildTrackEdge(from: start, to: end, structure: level == 0 ? .surface : .elevated)
                built = (trial, edge)
                break
            } catch GameError.trackConflict, GameError.trackTooClose {
                continue
            }
        }
        guard let (next, edge) = built else { throw GameError.invalidTrackGeometry }
        world = next
        let length = world.trackEdge(edge)?.length ?? 0
        var stops: [StationID] = []
        // Each stop's point and the middle of its platform along the edge,
        // which runs a platform beyond `from` and `to`.
        let calls = [(from, platform), (to, length - platform)]
        for (point, middle) in calls {
            let start = middle - platform / 2
            let station = try stations[point] ?? world.buildStation(named: "S\(stations.count)", at: point).id
            stations[point] = station
            try world.addTrackPlatform(station, on: edge, from: start, to: start + platform)
            stops.append(station)
        }
        let line = try world.createLine(named: "Line \(world.lines.count + 1)", stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "Train \(world.trains.count + 1)").id
        try world.setTrainCars(train, to: cars)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: platform + platform / 2))
        try world.setTrainContinuation(train, along: [], stoppingAt: platform + platform / 2)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
    }

    /// A point 40,000 units (625 m) inside the map's edge nearest `point`.
    public static func nearestEdge(to point: PlanPoint, in bounds: WorldBounds) -> PlanPoint {
        let inset: Int64 = 40_000
        let sides = [
            (point.x, PlanPoint(x: inset, y: point.y)),
            (bounds.width - point.x, PlanPoint(x: bounds.width - inset, y: point.y)),
            (point.y, PlanPoint(x: point.x, y: inset)),
            (bounds.height - point.y, PlanPoint(x: point.x, y: bounds.height - inset)),
        ]
        return sides.min { $0.0 < $1.0 }!.1
    }
}

/// A new player's opening as the tutorial and the run testers play it
/// (decision 254, CoreLoopBaselineReportTests): a first line drawn as one
/// curved edge, then the track run on to a third town with a second line
/// sharing the first's single track. Counts the player's commands: each
/// call to the world a tap or a confirmation would make.
public struct CurvedOpening: Sendable {
    public private(set) var commands = 0
    public private(set) var edges: [TrackEdgeID] = []
    public private(set) var stations: [StationID] = []
    private var firstEnd: End?

    private struct End: Sendable {
        let node: TrackNodeID
        let point: PlanPoint
        let heading: (Double, Double)
    }

    public init() {}

    /// Four cars of the longest real car (25 m), so any type fits.
    public static let platform: Int64 = 4 * 25 * WorldCoordinate.unitsPerMetre

    /// One curved edge from a platform beyond `from` to one beyond `to`,
    /// bowed sideways by a fifth of its span.
    public mutating func openFirstLine(_ world: inout GameWorld, from: PlanPoint, to: PlanPoint) throws {
        let platform = Self.platform
        let (dx, dy) = unit(from, to)
        let a = PlanPoint(x: from.x - Int64(dx * Double(platform)), y: from.y - Int64(dy * Double(platform)))
        let b = PlanPoint(x: to.x + Int64(dx * Double(platform)), y: to.y + Int64(dy * Double(platform)))
        let span = distance(a, b), bow = span / 5
        let c1 = PlanPoint(x: a.x + Int64(dx * span / 3 - dy * bow), y: a.y + Int64(dy * span / 3 + dx * bow))
        let c2 = PlanPoint(x: a.x + Int64(dx * span * 2 / 3 - dy * bow), y: a.y + Int64(dy * span * 2 / 3 + dx * bow))
        let start = try command { try world.buildTrackNode(at: WorldCoordinate(x: a.x, y: a.y)) }
        let end = try command { try world.buildTrackNode(at: WorldCoordinate(x: b.x, y: b.y)) }
        let edge = try command { try world.buildTrackEdge(from: start, to: end, curve: .cubic(c1, c2)) }
        edges.append(edge)
        let length = world.trackEdge(edge)?.length ?? 0
        let first = try command { try world.buildStation(named: "S0", at: from).id }
        try command { try world.addTrackPlatform(first, on: edge, from: platform / 2, to: platform + platform / 2) }
        let second = try command { try world.buildStation(named: "S1", at: to).id }
        try command { try world.addTrackPlatform(second, on: edge, from: length - platform - platform / 2, to: length - platform / 2) }
        stations = [first, second]
        firstEnd = End(node: start, point: a, heading: unit(c1, a))
        try openLine(&world, stops: stations, on: TrackTraversal(edge: edge, direction: .forward))
    }

    /// On from the first edge's start to a platform beyond `town`,
    /// leaving the way the first edge runs there and curving round to
    /// it; a second line calling at every station with a train of its
    /// own, from the far end.
    public mutating func extend(_ world: inout GameWorld, to town: PlanPoint) throws {
        let platform = Self.platform
        guard let firstEnd else { return }
        let (node, point, heading) = (firstEnd.node, firstEnd.point, firstEnd.heading)
        let (dx, dy) = unit(point, town)
        let b = PlanPoint(x: town.x + Int64(dx * Double(platform)), y: town.y + Int64(dy * Double(platform)))
        let span = distance(point, b)
        let c1 = PlanPoint(x: point.x + Int64(heading.0 * span / 3), y: point.y + Int64(heading.1 * span / 3))
        let c2 = PlanPoint(x: b.x - Int64(dx * span / 3), y: b.y - Int64(dy * span / 3))
        let end = try command { try world.buildTrackNode(at: WorldCoordinate(x: b.x, y: b.y)) }
        let edge = try command { try world.buildTrackEdge(from: node, to: end, curve: .cubic(c1, c2)) }
        edges.append(edge)
        let length = world.trackEdge(edge)?.length ?? 0
        let third = try command { try world.buildStation(named: "S2", at: town).id }
        try command { try world.addTrackPlatform(third, on: edge, from: length - platform - platform / 2, to: length - platform / 2) }
        stations.append(third)
        try openLine(&world, stops: [third, stations[0], stations[1]], on: TrackTraversal(edge: edge, direction: .backward))
    }

    /// A line calling at `stops`, all day, one train of four cars whose
    /// head is at the far end of the first stop's platform on `traversal`.
    public mutating func openLine(_ world: inout GameWorld, stops: [StationID], on traversal: TrackTraversal) throws {
        let platform = Self.platform
        let line = try command { try world.createLine(named: "Line \(world.lines.count + 1)", stops: stops).id }
        try command { try world.setLineServiceWindow(line, to: .allDay) }
        try command { try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1)) }
        let train = try command { try world.purchaseTrain(named: "Train \(world.trains.count + 1)").id }
        try command { try world.setTrainCars(train, to: 4) }
        try command { try world.placeTrain(train, at: .onEdge(traversal, offset: platform + platform / 2)) }
        try command { try world.setTrainContinuation(train, along: [], stoppingAt: platform + platform / 2) }
        try command { try world.setTrainMovementRate(train, to: 512) }
        try command { try world.assignTrain(train, to: line) }
    }

    @discardableResult
    private mutating func command<T>(_ body: () throws -> T) throws -> T {
        commands += 1
        return try body()
    }

    private func unit(_ from: PlanPoint, _ to: PlanPoint) -> (Double, Double) {
        let span = distance(from, to)
        return (Double(to.x - from.x) / span, Double(to.y - from.y) / span)
    }

    private func distance(_ a: PlanPoint, _ b: PlanPoint) -> Double {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// A way to play: what to build on which day (decision 261).
public struct Policy {
    /// What a script remembers between its actions: the stations it put
    /// in towns (shared by every line calling there) and its opening.
    public struct Memory: Sendable {
        public var stations: [PlanPoint: StationID] = [:]
        public var opening = CurvedOpening()

        public init() {}
    }

    /// Something to build from a day on.
    public struct Action {
        /// The day it is due (0 is before the first day is played).
        public let day: Int64
        /// Whether a refusal for want of money waits for the money, a day
        /// at a time, holding back the actions after it; otherwise every
        /// refusal stops the play.
        public let waitsForMoney: Bool
        public let run: (inout GameWorld, inout Memory) throws -> Void

        public init(day: Int64, waitsForMoney: Bool = false, run: @escaping (inout GameWorld, inout Memory) throws -> Void) {
            self.day = day
            self.waitsForMoney = waitsForMoney
            self.run = run
        }
    }

    public let name: String
    public let actions: [Action]

    public init(name: String, actions: [Action]) {
        self.name = name
        self.actions = actions
    }

    /// Nothing built: the world as it is.
    public static var none: Policy { Policy(name: "none", actions: []) }

    /// The tutorial's opening (decision 254): a curved line from the first
    /// town to the second on day 0.
    public static func twoTowns(_ towns: [PlanPoint]) -> Policy {
        Policy(name: "two-towns", actions: [
            Action(day: 0) { world, memory in try memory.opening.openFirstLine(&world, from: towns[0], to: towns[1]) },
        ])
    }

    /// ``twoTowns(_:)`` and on day 3 the track run on to the third town,
    /// with a second line sharing the first's single track (the opening
    /// CoreLoopBaselineReportTests measures, decision 254 §1.2).
    public static func thirdTown(_ towns: [PlanPoint]) -> Policy {
        Policy(name: "third-town", actions: twoTowns(towns).actions + [
            Action(day: 3) { world, memory in try memory.opening.extend(&world, to: towns[2]) },
        ])
    }

    /// The challenges' ways to play (decision 145, ChallengeReportTests),
    /// each line built as soon as the money allows.
    public enum ChallengePlay: String, CaseIterable, Sendable {
        /// A line from the first town to the second and one from the first
        /// to the third, one train of four cars each, from day 0.
        case linked
        /// The same lines with trains of eight cars.
        case longTrains
        /// Long trains, and from day 30 a line from the second town to the
        /// third and one from each town to the nearest edge of the map.
        case grown
    }

    public static func challenge(_ play: ChallengePlay, towns: [PlanPoint], bounds: WorldBounds) -> Policy {
        let linked = [(towns[0], towns[1]), (towns[0], towns[2])]
        let grown = [(towns[1], towns[2])] + towns.map { ($0, LineBuilder.nearestEdge(to: $0, in: bounds)) }
        let lines: [(day: Int64, from: PlanPoint, to: PlanPoint, cars: Int)] = switch play {
        case .linked: linked.map { (0, $0.0, $0.1, 4) }
        case .longTrains: linked.map { (0, $0.0, $0.1, 8) }
        case .grown: linked.map { (0, $0.0, $0.1, 8) } + grown.map { (30, $0.0, $0.1, 8) }
        }
        return Policy(name: play.rawValue, actions: lines.map { line in
            Action(day: line.day, waitsForMoney: true) { world, memory in
                try LineBuilder.straightLine(&world, from: line.from, to: line.to, cars: line.cars, stations: &memory.stations)
            }
        })
    }

    /// The policies GameSim plays by name, on a new game of `seed`.
    public static let names = ["none", "two-towns", "third-town"] + ChallengePlay.allCases.map(\.rawValue)

    /// The policy `name` on a world of `bounds` whose towns were drawn
    /// from `seed`, or `nil` for a name not in ``names``.
    public static func named(_ name: String, seed: UInt32, bounds: WorldBounds) -> Policy? {
        let towns = Land.townCentres(seed: seed, in: bounds)
        switch name {
        case "none": return Policy.none
        case "two-towns": return twoTowns(towns)
        case "third-town": return thirdTown(towns)
        default: return ChallengePlay(rawValue: name).map { challenge($0, towns: towns, bounds: bounds) }
        }
    }
}

/// Something that went wrong while a policy played (decision 261).
public struct PlayAnomaly: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Trains only waiting for each other at the end of the day.
        case deadlock
        /// The network carried no one all day.
        case zeroTrips
        /// The cash below zero at the end of the day.
        case inTheRed
        /// The challenge failed.
        case failed
        /// A train on a line where it stood a day ago, having arrived
        /// nowhere since.
        case trainStopped
    }

    public let day: Int64
    public let kind: Kind
    /// The trains it concerns, if any.
    public let trains: [Int]

    public init(day: Int64, kind: Kind, trains: [Int] = []) {
        self.day = day
        self.kind = kind
        self.trains = trains
    }
}

/// A policy played on a world, a day at a time (decision 261): the due
/// actions first, then the day, then what went wrong noted. Only reads
/// the world besides advancing it and running the policy's actions.
public struct PolicyPlayer {
    public private(set) var world: GameWorld
    public private(set) var memory = Policy.Memory()
    /// The days played.
    public private(set) var day: Int64 = 0
    /// The actions not yet run, in order.
    public var pending: [Policy.Action]
    /// Each kind of anomaly the first day it was seen, and how many days
    /// it was seen on.
    public private(set) var anomalies: [PlayAnomaly] = []
    public private(set) var anomalyDays: [PlayAnomaly.Kind: Int] = [:]
    private var positions: [TrainID: Standing] = [:]

    /// Where a train stood and when it last arrived somewhere.
    private struct Standing: Hashable {
        let position: TrainPosition
        let times: ServiceTimes?
    }

    public init(world: GameWorld, policy: Policy) {
        self.world = world
        pending = policy.actions
    }

    /// Runs, in order, each pending action due by `day` (by ``day``
    /// unless given). One that waits for money and is refused for it is
    /// tried again next time, and the ones after it wait too; any other
    /// refusal is thrown. An action changes the world only if it succeeds.
    public mutating func runDue(onDay day: Int64? = nil) throws {
        let today = day ?? self.day
        while let next = pending.first, next.day <= today {
            var trial = world, known = memory
            do {
                try next.run(&trial, &known)
            } catch GameError.insufficientFunds where next.waitsForMoney {
                break
            }
            world = trial
            memory = known
            pending.removeFirst()
        }
    }

    /// Advances the world `ticks` ticks.
    public mutating func advance(ticks: Int) throws {
        try world.advance(ticks: ticks)
    }

    /// The due actions, a day of game time (1,440 ticks, a minute each at
    /// 600×) and what went wrong in it.
    public mutating func playDay() throws {
        try runDue()
        try world.advance(ticks: 1_440)
        day += 1
        observe()
    }

    /// Notes what went wrong in the day just played.
    private mutating func observe() {
        func note(_ kind: PlayAnomaly.Kind, _ trains: [TrainID] = []) {
            anomalyDays[kind, default: 0] += 1
            if !anomalies.contains(where: { $0.kind == kind }) {
                anomalies.append(PlayAnomaly(day: day, kind: kind, trains: trains.map(\.rawValue)))
            }
        }
        let deadlocked = world.deadlockedTrains()
        if !deadlocked.isEmpty { note(.deadlock, deadlocked) }
        // The first day's trips start from an empty network.
        if day >= 2, !world.lines.isEmpty, world.lastDayTrips() == 0 { note(.zeroTrips) }
        if world.economy.balance < .zero { note(.inTheRed) }
        if case .failed? = world.scenario?.outcome { note(.failed) }
        var stopped: [TrainID] = []
        var now: [TrainID: Standing] = [:]
        for train in world.trains where world.assignedLine(of: train.id) != nil {
            guard let position = train.position else { continue }
            let standing = Standing(position: position, times: train.times)
            if positions[train.id] == standing { stopped.append(train.id) }
            now[train.id] = standing
        }
        positions = now
        if !stopped.isEmpty { note(.trainStopped, stopped) }
    }
}
