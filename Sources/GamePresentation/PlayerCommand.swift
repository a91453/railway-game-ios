import GameCore

/// A command of the player's as a value (ARCHITECTURE decision 193): what
/// a tool asks of the world, with everything it was worked out from, so
/// the command log (``CommandLog``) can keep it and a problem report can be
/// replayed from it on Linux. ``GameSession/perform(_:caller:message:)``
/// runs it through ``GameSession/apply(_:to:)``, the same edit the tool
/// made before as a closure, and records it.
///
/// The network tool's commands have cases of their own; the panels' and
/// the other tools' are ``Edit``s. An edit still made as a closure is
/// logged as not recorded (``CommandLog/Action/unrecorded(_:)``).
///
/// The reference's desync log does the same (`docs/debugging_desyncs.md`,
/// `docs/desync.md` §3.1): every command goes through one entry
/// (`DoCommandP`) as an ID and its values, and is written with the game
/// time to `commands-out.log`.
public enum PlayerCommand: Hashable, Sendable {
    /// A stretch of track from the network tool (``GameSession/buildNetworkTrack()``).
    case buildTrack(TrackStretch)
    /// A stretch and the track beside it, as one (decision 204, the tool's
    /// double-track option): the stretch first, then the parallel, then
    /// the crossovers joining the parallel to the track the stretch joins
    /// (``GameSession/doubleTrackCrossovers(main:parallel:mainEdge:parallelEdge:before:in:)``).
    case buildDoubleTrack(TrackStretch, parallel: TrackStretch, crossovers: [TrackStretch] = [])
    /// A platform, on a new station or an existing one
    /// (``GameSession/addNetworkPlatform()`` on level track).
    case addPlatform(PlatformAddition)
    /// ``GameSession/removeNetworkPlatform(_:)``.
    case removePlatform(TrackPlatform)
    /// An edge and each of its end nodes no other edge ends at
    /// (``GameSession/removeNetworkEdge()``).
    case removeTrack(TrackEdgeID)
    /// An X crossover between two tracks (``GameSession/buildNetworkScissors()``),
    /// as the tool planned it.
    case buildCrossover(ScissorsPlan, structure: TrackStructure)
    /// A track beside a platform, with a platform of its own
    /// (``GameSession/addPlatformTrack(beside:layout:side:)``), as planned.
    case addPlatformTrack(PlatformTrackPlan)
    /// A passing loop with its signal station (``GameSession/addPassingLoop()``),
    /// as planned (decision 204).
    case addPassingLoop(PassingLoopPlan)
    /// A depot's sidings and the depot (``GameSession/addDepotYard()``), as
    /// planned (decision 214).
    case buildDepotYard(DepotYardPlan)
    /// An edit from a panel or another tool (``Edit``).
    case edit(Edit)
    /// Stretches one after another, each starting at the node the one
    /// before ended at (its own start is then not read): the track the
    /// network tool traces along a real line (decision 213,
    /// ``GameSession/tracePlan(from:to:)``), all of it or none.
    case buildTrackChain([TrackStretch])
    /// A second track beside a chain (decision 247): `main` laid first as
    /// a chain (empty for track already there), then `parallel` as a chain,
    /// its `platforms`, then the `crossovers` joining it to the first track
    /// (``GameSession/planDoubleChain(main:run:parallel:platforms:wantsCrossover:in:)``),
    /// all of it or none.
    case buildDoubleTrackChain(main: [TrackStretch], parallel: [TrackStretch], platforms: [ChainPlatform], crossovers: [TrackStretch])
    /// Simple rules' service (decision 264, ``GameSession/addTrainToSelectedLine()``):
    /// a line made or one already there, the passing loops it needs, and
    /// its trains, all or none.
    case autoService(AutoService)
    /// A real branch line bought (decision 315, ``GameSession/realLineOffer(for:)``):
    /// its track, stations, trains and real timetable, and the purchase
    /// GameCore records, all or none.
    case acquireRealLine(RealLineAcquisition)

    /// A stretch of track as the network tool lays it: a node for each new
    /// end (splitting an edge for an end on one), then the edge, with the
    /// ground under its way read in first (decision 124).
    public struct TrackStretch: Hashable, Sendable {
        public let start: NetworkAnchor
        public let end: NetworkAnchor
        public let from: WorldCoordinate
        public let to: WorldCoordinate
        public let curve: TrackCurve
        public let profile: TrackProfile
        public let structure: TrackStructure
        /// Where the ground is read in: both ends, then the points GameCore
        /// surveys under the edge (``NetworkBuilding/surveyedPoints(of:)``).
        public let ground: [PlanPoint]

        public init(
            start: NetworkAnchor, end: NetworkAnchor, from: WorldCoordinate, to: WorldCoordinate, curve: TrackCurve,
            profile: TrackProfile, structure: TrackStructure, ground: [PlanPoint]
        ) {
            self.start = start
            self.end = end
            self.from = from
            self.to = to
            self.curve = curve
            self.profile = profile
            self.structure = structure
            self.ground = ground
        }

        /// Builds it in `world`, reading ground from `heights`: the edge,
        /// and the node it ends at.
        func build(in world: inout GameWorld, heights: HeightGrid?) throws(GameError) -> (edge: TrackEdgeID, to: TrackNodeID) {
            try world.readGround(under: ground, from: heights)
            let first = try node(for: start, at: from, in: &world)
            let last = try node(for: end, at: to, in: &world)
            let edge = try world.buildTrackEdge(from: first, to: last, curve: curve, profile: profile, structure: structure)
            return (edge, last)
        }

        private func node(for anchor: NetworkAnchor, at position: WorldCoordinate, in world: inout GameWorld) throws(GameError) -> TrackNodeID {
            switch anchor {
            case .node(let id): return id
            case .point: return try world.buildTrackNode(at: position)
            case .track(let point):
                // The other end may have split the same edge: find the place
                // again where it lies now.
                let now = world.network.edge(point.edge) != nil ? point : world.trackEdgePoint(near: position.plan, within: 16)
                guard let now else { throw .unknownTrackEdge(point.edge) }
                return try world.splitTrackEdge(now.edge, at: now.distance)
            }
        }
    }

    /// A platform on `edge` from `start` to `end`, for `station`, or for a
    /// new station; on a grade, on the level edge `levelling` builds first
    /// (decision 190). Decision 285: with `beside`, the same station's
    /// platform on the other track of a double line, built after it.
    public struct PlatformAddition: Hashable, Sendable {
        public let edge: TrackEdgeID
        public let start: Int64
        public let end: Int64
        public let station: PlatformStation
        public let levelling: PlatformLevelling?
        public let beside: BesidePlatform?

        public init(
            edge: TrackEdgeID, start: Int64, end: Int64, station: PlatformStation, levelling: PlatformLevelling? = nil,
            beside: BesidePlatform? = nil
        ) {
            self.edge = edge
            self.start = start
            self.end = end
            self.station = station
            self.levelling = levelling
            self.beside = beside
        }
    }

    /// A platform on `edge` from `start` to `end` beside another, for the
    /// same station; on a grade, on the level edge `levelling` builds
    /// first (``GameSession/besidePlatform(of:)``).
    public struct BesidePlatform: Hashable, Sendable {
        public let edge: TrackEdgeID
        public let start: Int64
        public let end: Int64
        public let levelling: PlatformLevelling?
    }

    /// Whose platform it is: a station's that stands, or a new one's,
    /// built by its name at `at`, with `demand` as its ridership where a
    /// managed company sets it rather than the land (Phase 6b).
    public enum PlatformStation: Hashable, Sendable {
        case existing(StationID)
        case new(name: String, at: PlanPoint, demand: StationDemand)
    }

    /// What a command made, for the tool's message and what it does next.
    public struct Outcome: Sendable {
        /// The edge built, and the node it ends at.
        public var track: (edge: TrackEdgeID, to: TrackNodeID)?
        /// The station the platform went to.
        public var station: Station?
        /// The platform's stretch, on the level edge once levelled, and
        /// what levelling it cost.
        public var stretch: (edge: TrackEdgeID, start: Int64, end: Int64)?
        public var levellingCost: Money?
        /// The platform track built beside a platform.
        public var platform: TrackPlatform?
        /// The train bought.
        public var train: Train?
        /// The line made.
        public var line: ServiceLine?
        /// The building put up, and the sale of one.
        public var building: PlacedBuilding?
        public var sale: PlacedBuildingSaleQuote?
        /// A count the edit made: the new pattern's index, the cells zoned,
        /// the city buildings cleared, the trains a service now runs.
        public var number = 0
        /// Whether the line now plans at high speed (decision 168).
        public var highSpeed = false
        /// The edge a train was placed on, and whether it faces along it.
        public var placed: (edge: TrackEdgeID, forward: Bool)?
        /// The trains bought for a line left off the track: the berth held,
        /// or too long to stand there.
        public var held = 0
        public var unfit = 0
        /// The trains left as they were, and why.
        public var left: [String] = []
    }

    /// The name the log gives it.
    public var name: String {
        switch self {
        case .buildTrack: "buildTrack"
        case .buildDoubleTrack: "buildDoubleTrack"
        case .addPlatform: "addPlatform"
        case .removePlatform: "removePlatform"
        case .removeTrack: "removeTrack"
        case .buildCrossover: "buildCrossover"
        case .addPlatformTrack: "addPlatformTrack"
        case .addPassingLoop: "addPassingLoop"
        case .buildDepotYard: "buildDepotYard"
        case .edit(let edit): edit.name
        case .buildTrackChain: "buildTrackChain"
        case .buildDoubleTrackChain: "buildDoubleTrackChain"
        case .autoService: "autoService"
        case .acquireRealLine: "acquireRealLine"
        }
    }
}

extension GameSession {
    /// Runs `command` on `world`, as the tool it comes from did: all of it
    /// or, throwing, none (the caller's copy is dropped). Reads the land
    /// and ground the session has (decision 88, 124), so a replay needs the
    /// same data.
    func apply(_ command: PlayerCommand, to world: inout GameWorld) throws(GameError) -> PlayerCommand.Outcome {
        var outcome = PlayerCommand.Outcome()
        switch command {
        case .buildTrack(let stretch):
            outcome.track = try stretch.build(in: &world, heights: heights)
        case .buildDoubleTrack(let stretch, let parallel, let crossovers):
            outcome.track = try stretch.build(in: &world, heights: heights)
            _ = try parallel.build(in: &world, heights: heights)
            for crossover in crossovers {
                _ = try crossover.build(in: &world, heights: heights)
            }
        case .addPlatform(let addition):
            // The platform's stretch, on the level edge once levelled.
            var stretch = (edge: addition.edge, start: addition.start, end: addition.end)
            if let levelling = addition.levelling {
                let balance = world.economy.balance
                let edge = try build(levelling, in: &world)
                stretch = (edge, 0, world.network.edge(edge)?.length ?? 0)
                outcome.levellingCost = Money(balance.amount - world.economy.balance.amount)
            }
            let station: Station
            switch addition.station {
            case .existing(let id):
                guard let existing = world.station(id: id) else { throw .unknownStation(id) }
                station = existing
            case .new(let name, let point, let demand):
                station = try world.buildStation(named: name, at: point)
                // With demand from land (Phase 6b) GameCore gives it the
                // ridership of the land round it.
                if world.accounts.mode == .management, !world.landDemand {
                    try world.setStationDemand(station.id, to: demand)
                }
            }
            try world.addTrackPlatform(station.id, on: stretch.edge, from: stretch.start, to: stretch.end)
            outcome.stretch = stretch
            if let beside = addition.beside {
                var other = (edge: beside.edge, start: beside.start, end: beside.end)
                if let levelling = beside.levelling {
                    let balance = world.economy.balance
                    let edge = try build(levelling, in: &world)
                    other = (edge, 0, world.network.edge(edge)?.length ?? 0)
                    outcome.levellingCost = Money((outcome.levellingCost?.amount ?? 0) + balance.amount - world.economy.balance.amount)
                }
                try world.addTrackPlatform(station.id, on: other.edge, from: other.start, to: other.end)
            }
            // Decision 88: the land round a new station is read in after the
            // edit; read it now, so the opening message counts who it reaches.
            Self.readLand(roundStationsOf: &world, population: population, places: places, water: water, coverage: coverage)
            outcome.station = station
        case .removePlatform(let platform):
            try world.removeTrackPlatform(platform.station, on: platform.edge, from: platform.start)
        case .buildCrossover(let plan, let structure):
            // The diagonals joined at the middle: the tool says so before it
            // asks, so on the world it planned on this never happens.
            guard try build(plan, in: &world, structure: structure) != nil else { throw .invalidTrackGeometry }
        case .addPlatformTrack(let plan):
            outcome.platform = try build(plan, in: &world)
        case .addPassingLoop(let plan):
            outcome.station = try build(plan, in: &world)
        case .buildDepotYard(let plan):
            outcome.station = try build(plan, in: &world)
        case .edit(let edit):
            return try apply(edit, to: &world)
        case .buildTrackChain(let stretches):
            guard !stretches.isEmpty else { throw .invalidTrackGeometry }
            var previous: TrackNodeID?
            for stretch in stretches {
                let built = try stretch.starting(at: previous).build(in: &world, heights: heights)
                outcome.track = built
                previous = built.to
            }
        case .buildDoubleTrackChain(let main, let parallel, let platforms, let crossovers):
            outcome.track = try buildDoubleChain(main: main, parallel: parallel, platforms: platforms, in: &world).last
            for crossover in crossovers {
                _ = try crossover.build(in: &world, heights: heights)
            }
        case .autoService(let plan):
            return try apply(plan, to: &world)
        case .acquireRealLine(let acquisition):
            try build(acquisition, in: &world)
            outcome.line = world.acquisition(of: acquisition.realLine).flatMap { world.line(id: $0.line) }
        case .removeTrack(let id):
            guard let edge = world.network.edge(id) else { throw .unknownTrackEdge(id) }
            try world.removeTrackEdge(id)
            for node in Set([edge.from, edge.to]).sorted() where world.network.node(node)?.ends.isEmpty == true {
                try world.removeTrackNode(node)
            }
        }
        return outcome
    }
}

// MARK: - Plain values

extension PlayerCommand: Codable {
    /// A command written out in plain numbers and strings, as a replay
    /// fixture writes its commands (`ReplayFixtures/README.md`): a refused
    /// command is logged too, and GameCore's own coding refuses values a
    /// world cannot hold.
    private struct Record: Codable {
        struct Anchor: Codable {
            /// "node", "point" or "track".
            var kind: String
            var node: Int?
            var point: [Int64]?
            var edge: Int?
            var distance: Int64?
        }

        struct Demand: Codable {
            var kind: String
            var dailyTrips: Int64
            var hinterland: Int64
        }

        struct Beside: Codable {
            var edge: Int
            var startDistance: Int64
            var endDistance: Int64
            var levelling: PlatformLevelling?
        }

        var kind: String
        var start: Anchor?
        var end: Anchor?
        /// World coordinates: x, y and z.
        var from: [Int64]?
        var to: [Int64]?
        /// A curve's two control points, x and y each; `nil` for a straight edge.
        var controls: [Int64]?
        /// The profile's transitions at the start and the end.
        var transitions: [Int64]?
        var structure: String?
        /// Plan points, x and y each.
        var ground: [Int64]?
        var edge: Int?
        var station: Int?
        var name: String?
        var point: [Int64]?
        var demand: Demand?
        var startDistance: Int64?
        var endDistance: Int64?
        var edit: Edit?
        var crossover: ScissorsPlan?
        var platformTrack: PlatformTrackPlan?
        var passingLoop: PassingLoopPlan?
        /// Decision 264.
        var autoService: AutoService?
        /// Decision 315.
        var acquisition: RealLineAcquisition?
        var depotYard: DepotYardPlan?
        var levelling: PlatformLevelling?
        /// Decision 285: the platform's twin on the track beside it;
        /// absent for none (and in logs from before it).
        var beside: Beside?
        /// The double track's parallel, as a `buildTrack` of its own.
        var parallel: PlayerCommand?
        /// The double track's crossovers, each a `buildTrack`; absent for
        /// none (and in logs from before them).
        var crossovers: [PlayerCommand]?
        /// A chain's stretches, each a `buildTrack`.
        var stretches: [PlayerCommand]?
        /// A double-track chain's second track, each a `buildTrack`, and
        /// its platforms.
        var parallelChain: [PlayerCommand]?
        var platforms: [ChainPlatform]?
    }

    public init(from decoder: any Decoder) throws {
        let record = try Record(from: decoder)
        func invalid(_ what: String) -> DecodingError {
            .dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "\(record.kind): \(what)"))
        }
        func coordinate(_ values: [Int64]?) throws -> WorldCoordinate {
            guard let values, values.count == 3 else { throw invalid("a coordinate needs x, y and z") }
            return WorldCoordinate(x: values[0], y: values[1], z: values[2])
        }
        func points(_ values: [Int64]?) throws -> [PlanPoint] {
            guard let values, values.count.isMultiple(of: 2) else { throw invalid("plan points need x and y each") }
            return stride(from: 0, to: values.count, by: 2).map { PlanPoint(x: values[$0], y: values[$0 + 1]) }
        }
        func anchor(_ value: Record.Anchor?) throws -> NetworkAnchor {
            switch value?.kind {
            case "node":
                guard let node = value?.node else { throw invalid("a node anchor needs its node") }
                return .node(.node(node))
            case "point":
                guard let point = try points(value?.point).first else { throw invalid("a point anchor needs its point") }
                return .point(point)
            case "track":
                guard let edge = value?.edge, let distance = value?.distance else { throw invalid("a track anchor needs its edge and distance") }
                return .track(NetworkEdgePoint(edge: .edge(edge), distance: distance))
            default:
                throw invalid("unknown anchor")
            }
        }
        func stretch() throws -> TrackStretch {
            let controls = try points(record.controls ?? [])
            let curve: TrackCurve
            switch controls.count {
            case 0: curve = .straight
            case 2: curve = .cubic(controls[0], controls[1])
            default: throw invalid("a curve has two control points")
            }
            guard let transitions = record.transitions, transitions.count == 2 else { throw invalid("a profile has two transitions") }
            guard let structure = record.structure.flatMap(TrackStructure.init(rawValue:)) else { throw invalid("unknown structure") }
            return TrackStretch(
                start: try anchor(record.start), end: try anchor(record.end), from: try coordinate(record.from), to: try coordinate(record.to),
                curve: curve, profile: TrackProfile(startTransition: transitions[0], endTransition: transitions[1]),
                structure: structure, ground: try points(record.ground)
            )
        }
        switch record.kind {
        case "buildTrack":
            self = .buildTrack(try stretch())
        case "buildDoubleTrack":
            guard case .buildTrack(let parallel)? = record.parallel else { throw invalid("a double track needs its parallel") }
            let crossovers = try (record.crossovers ?? []).map { command in
                guard case .buildTrack(let crossover) = command else { throw invalid("a crossover is a stretch") }
                return crossover
            }
            self = .buildDoubleTrack(try stretch(), parallel: parallel, crossovers: crossovers)
        case "addPlatform":
            guard let edge = record.edge, let start = record.startDistance, let end = record.endDistance else {
                throw invalid("a platform needs its edge, start and end")
            }
            let station: PlatformStation
            if let id = record.station {
                station = .existing(StationID(rawValue: id))
            } else {
                guard let name = record.name, let point = try points(record.point).first, let demand = record.demand,
                      let kind = StationDemandKind(rawValue: demand.kind) else {
                    throw invalid("a new station needs its name, point and demand")
                }
                station = .new(name: name, at: point, demand: StationDemand(kind: kind, dailyTrips: demand.dailyTrips, hinterland: demand.hinterland))
            }
            let beside = record.beside.map {
                BesidePlatform(edge: .edge($0.edge), start: $0.startDistance, end: $0.endDistance, levelling: $0.levelling)
            }
            self = .addPlatform(PlatformAddition(
                edge: .edge(edge), start: start, end: end, station: station, levelling: record.levelling, beside: beside
            ))
        case "removePlatform":
            guard let station = record.station, let edge = record.edge, let start = record.startDistance, let end = record.endDistance else {
                throw invalid("a platform needs its station, edge, start and end")
            }
            self = .removePlatform(TrackPlatform(station: StationID(rawValue: station), edge: .edge(edge), start: start, end: end))
        case "buildCrossover":
            guard let plan = record.crossover, let structure = record.structure.flatMap(TrackStructure.init(rawValue:)) else {
                throw invalid("a crossover needs its plan and structure")
            }
            self = .buildCrossover(plan, structure: structure)
        case "addPlatformTrack":
            guard let plan = record.platformTrack else { throw invalid("a platform track needs its plan") }
            self = .addPlatformTrack(plan)
        case "addPassingLoop":
            guard let plan = record.passingLoop else { throw invalid("a passing loop needs its plan") }
            self = .addPassingLoop(plan)
        case "buildDepotYard":
            guard let plan = record.depotYard else { throw invalid("a depot's sidings need their plan") }
            self = .buildDepotYard(plan)
        case "autoService":
            guard let plan = record.autoService else { throw invalid("simple rules' service needs its plan") }
            self = .autoService(plan)
        case "acquireRealLine":
            guard let acquisition = record.acquisition else { throw invalid("a line bought needs its layout") }
            self = .acquireRealLine(acquisition)
        case "edit":
            guard let edit = record.edit else { throw invalid("an edit needs its value") }
            self = .edit(edit)
        case "removeTrack":
            guard let edge = record.edge else { throw invalid("needs its edge") }
            self = .removeTrack(.edge(edge))
        case "buildTrackChain":
            let stretches = try (record.stretches ?? []).map { command in
                guard case .buildTrack(let stretch) = command else { throw invalid("a chain's piece is a stretch") }
                return stretch
            }
            guard !stretches.isEmpty else { throw invalid("a chain needs its stretches") }
            self = .buildTrackChain(stretches)
        case "buildDoubleTrackChain":
            func pieces(_ commands: [PlayerCommand]?) throws -> [TrackStretch] {
                try (commands ?? []).map { command in
                    guard case .buildTrack(let stretch) = command else { throw invalid("a chain's piece is a stretch") }
                    return stretch
                }
            }
            let parallel = try pieces(record.parallelChain)
            guard !parallel.isEmpty else { throw invalid("a double track needs its second track") }
            self = .buildDoubleTrackChain(
                main: try pieces(record.stretches), parallel: parallel, platforms: record.platforms ?? [], crossovers: try pieces(record.crossovers)
            )
        default:
            throw invalid("unknown command")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var record = Record(kind: name)
        if case .edit = self { record.kind = "edit" }
        func anchor(_ anchor: NetworkAnchor) -> Record.Anchor {
            switch anchor {
            case .node(.node(let node)): Record.Anchor(kind: "node", node: node)
            case .point(let point): Record.Anchor(kind: "point", point: [point.x, point.y])
            case .track(let point): Record.Anchor(kind: "track", edge: point.edge.number, distance: point.distance)
            }
        }
        func write(_ stretch: TrackStretch) {
            record.start = anchor(stretch.start)
            record.end = anchor(stretch.end)
            record.from = [stretch.from.x, stretch.from.y, stretch.from.z]
            record.to = [stretch.to.x, stretch.to.y, stretch.to.z]
            if case .cubic(let a, let b) = stretch.curve { record.controls = [a.x, a.y, b.x, b.y] }
            record.transitions = [stretch.profile.startTransition, stretch.profile.endTransition]
            record.structure = stretch.structure.rawValue
            record.ground = stretch.ground.flatMap { [$0.x, $0.y] }
        }
        switch self {
        case .buildTrack(let stretch):
            write(stretch)
        case .buildDoubleTrack(let stretch, let parallel, let crossovers):
            write(stretch)
            record.parallel = .buildTrack(parallel)
            record.crossovers = crossovers.isEmpty ? nil : crossovers.map(PlayerCommand.buildTrack)
        case .addPlatform(let addition):
            record.edge = addition.edge.number
            record.startDistance = addition.start
            record.endDistance = addition.end
            record.levelling = addition.levelling
            record.beside = addition.beside.map {
                Record.Beside(edge: $0.edge.number, startDistance: $0.start, endDistance: $0.end, levelling: $0.levelling)
            }
            switch addition.station {
            case .existing(let id):
                record.station = id.rawValue
            case .new(let name, let point, let demand):
                record.name = name
                record.point = [point.x, point.y]
                record.demand = Record.Demand(kind: demand.kind.rawValue, dailyTrips: demand.dailyTrips, hinterland: demand.hinterland)
            }
        case .removePlatform(let platform):
            record.station = platform.station.rawValue
            record.edge = platform.edge.number
            record.startDistance = platform.start
            record.endDistance = platform.end
        case .removeTrack(let edge):
            record.edge = edge.number
        case .buildCrossover(let plan, let structure):
            record.crossover = plan
            record.structure = structure.rawValue
        case .addPlatformTrack(let plan):
            record.platformTrack = plan
        case .addPassingLoop(let plan):
            record.passingLoop = plan
        case .buildDepotYard(let plan):
            record.depotYard = plan
        case .edit(let edit):
            record.edit = edit
        case .buildTrackChain(let stretches):
            record.stretches = stretches.map(PlayerCommand.buildTrack)
        case .buildDoubleTrackChain(let main, let parallel, let platforms, let crossovers):
            record.stretches = main.map(PlayerCommand.buildTrack)
            record.parallelChain = parallel.map(PlayerCommand.buildTrack)
            record.platforms = platforms.isEmpty ? nil : platforms
            record.crossovers = crossovers.isEmpty ? nil : crossovers.map(PlayerCommand.buildTrack)
        case .autoService(let plan):
            record.autoService = plan
        case .acquireRealLine(let acquisition):
            record.acquisition = acquisition
        }
        try record.encode(to: encoder)
    }
}

extension TrackEdgeID {
    /// The edge's number, as a log writes it.
    var number: Int {
        switch self {
        case .edge(let number): number
        }
    }
}

extension PlayerCommand {
    /// What the command does, as a refusal for want of cash names it
    /// (``GameError/insufficientFundsText(required:available:doing:in:)``):
    /// "buy a train", 「買列車」. `nil` for a command that spends nothing,
    /// or that a refusal need not name.
    public func actionText(in language: DisplayLanguage) -> String? {
        switch self {
        case .buildTrack, .buildDoubleTrack, .buildTrackChain:
            language.text("lay this track", "鋪這段軌道")
        case .addPlatform(let addition):
            switch addition.station {
            case .new(let name, _, _):
                language.text("build station “\(name)” and its platform", "建造車站「\(name)」與月台")
            case .existing:
                language.text("add this platform", "加這座月台")
            }
        case .buildDoubleTrackChain(let main, _, _, _):
            main.isEmpty ? language.text("make this track double", "把這段改成複線") : language.text("lay this track", "鋪這段軌道")
        case .buildCrossover:
            language.text("build this crossover", "建這組渡線")
        case .addPlatformTrack:
            language.text("add this platform track", "加這條月台線")
        case .addPassingLoop:
            language.text("build this passing loop", "建這條待避線")
        case .buildDepotYard:
            language.text("build this depot", "建這座機廠")
        case .autoService(let plan):
            if plan.newLine != nil {
                language.text("open this line with a train", "開這條線並配一列車")
            } else if plan.trains == 0 {
                language.text("build this passing loop", "建這條待避線")
            } else {
                language.text("add a train", "加開一列車")
            }
        case .acquireRealLine(let acquisition):
            language.text("buy \(acquisition.lineName)", "收購\(acquisition.lineName)")
        case .removePlatform, .removeTrack:
            nil
        case .edit(let edit):
            switch edit {
            case .purchaseTrain: language.text("buy a train", "買列車")
            case .setTrainCars: language.text("add cars", "加掛車廂")
            case .setTrainType: language.text("change the train's type", "更換車型")
            case .staffLine, .addLineTrains, .setLineTrains: language.text("add trains to the line", "為路線補列車")
            case .reformLine: language.text("re-form the line's trains", "改編路線的列車")
            case .placeBuilding: language.text("put up this building", "蓋這棟建物")
            case .demolishBuilding: language.text("demolish this building", "拆除這棟建物")
            case .buyMapTile: language.text("buy this land", "買下這塊地")
            case .buildFreightYard: language.text("build a freight yard", "建貨場")
            case .investInSouvenirShop: language.text("invest in the souvenir shop", "投資紀念品店")
            case .buildStationCommerce: language.text("build the station's shops", "蓋車站商店")
            case .upgradeStationCommerce: language.text("upgrade the station's shops", "升級車站商店")
            case .repayLoan: language.text("repay the loan", "還款")
            default: nil
            }
        }
    }
}
