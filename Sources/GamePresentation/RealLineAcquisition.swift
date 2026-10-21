import GameCore

// Buying a real branch line (ARCHITECTURE decision 315): on a real-world
// map, a TRA branch line with its track, stations, trains and real
// timetable, in one command (``PlayerCommand/acquireRealLine(_:)``). The
// session lays it out on a copy of the world as the ground demo lays the
// Pingxi Line (decision 132, ``RealWorldDemo/GroundLayout``): the real
// line's centre line from its junction to its terminal, level at each
// station, a passing loop where the real trains meet or stand side by
// side, the trains where the real ones stand at midnight, and the line
// running TRA's own trains (decision 133, `tra_branch_runs.json`). GameCore
// then records the purchase and its riders' price
// (``GameWorld/recordLineAcquisition(line:realLine:dailyRiders:)``).
//
// The reference has no purchase of a line (decision 315's reference
// table): its data (the timetable, the stations' riders) and the ground
// demo's layout are what is reused.

/// A TRA branch line a company can buy (decision 315).
public struct RealBranchLine: Hashable, Sendable {
    /// Its `tra.json` id: `PINGXI`.
    public let network: String
    public let english: String
    public let chinese: String
    /// Its stations by their Chinese names, the junction first.
    public let stops: [String]

    /// The name GameCore records it by (``LineAcquisition/realLine``).
    public var id: String { "tra:\(network)" }

    public func name(in language: DisplayLanguage) -> String {
        language.text(english, chinese)
    }

    /// The lines on sale: those whose real trains run on a single track
    /// with passing loops. The Liujia and Shalun Lines are double track
    /// and wait for a later step (decision 315).
    static let names: [String: (english: String, chinese: String)] = [
        "PINGXI": ("Pingxi Line", "平溪線"),
        "JIJI": ("Jiji Line", "集集線"),
        "NEIWAN": ("Neiwan Line", "內灣線"),
        "SHENAO": ("Shenao Line", "深澳線"),
    ]
}

/// A real line bought, as the session laid it out: every node, edge,
/// station, platform and train, so the command log replays it without the
/// real data (decision 193).
public struct RealLineAcquisition: Hashable, Sendable, Codable {
    /// A node of a piece built before.
    public struct NodeAt: Hashable, Sendable, Codable {
        public let piece: Int
        public let node: Int
    }

    /// A stretch of track: its nodes, the first and last perhaps nodes of
    /// pieces built before, and its edges between them, each `distances`
    /// along the plan's path; `together`, built as one (a passing loop,
    /// ``GameWorld/buildTrackEdges(_:)``). `ground` is read in first.
    public struct Piece: Hashable, Sendable, Codable {
        public let nodes: [WorldCoordinate]
        public let start: NodeAt?
        public let end: NodeAt?
        public let curves: [TrackCurve]
        public let distances: [Double]
        public let structure: TrackStructure
        public let together: Bool
        public let ground: [PlanPoint]
    }

    /// A place on a piece: `distance` along its path.
    public struct PieceAt: Hashable, Sendable, Codable {
        public let piece: Int
        public let distance: Double
    }

    /// A station: one the company has (the junction's, decision 315 §4),
    /// or a new one by its real name at `at`, with `demand` where a managed
    /// company sets ridership rather than the land.
    public struct Stop: Hashable, Sendable, Codable {
        public let name: String
        public let at: PlanPoint
        public let existing: StationID?
        public let demand: StationDemand
    }

    /// A platform of stop `stop`, from `at` on for `length`.
    public struct Platform: Hashable, Sendable, Codable {
        public let stop: Int
        public let at: PieceAt
        public let length: Int64
    }

    /// A train standing at a platform beginning at `at` overnight, facing
    /// along its piece or back.
    public struct Start: Hashable, Sendable, Codable {
        public let name: String
        public let at: PieceAt
        public let forward: Bool
    }

    public let realLine: String
    public let pieces: [Piece]
    public let stops: [Stop]
    public let platforms: [Platform]
    public let lineName: String
    public let color: LineColor?
    public let runs: [LineRun]
    public let trains: [Start]
    public let cars: Int
    /// The real riders a day of its stations past the junction (decision
    /// 298), which its price pays for.
    public let dailyRiders: Int64

    /// Cars per train: the DR1000's three (decision 315's reference row).
    static let carsPerTrain = 3
    static let metre = Double(WorldCoordinate.unitsPerMetre)
    /// How far past each end the track runs on, so a loop at a terminal
    /// has room: a loop's reach and a little.
    static let runOn = RealWorldDemo.loopReach + 60 * metre
    /// How near the real junction a station of the company's is the one
    /// the line joins (decision 295's 450 m).
    static let junctionReach = 450 * metre
    /// How far a real station may be from its line's centre line.
    static let stationReach = 150 * metre
}

/// What buying a line costs, item by item (decision 315 §2).
public struct RealLineAcquisitionPrice: Hashable, Sendable {
    /// Its track, stations and platforms, at the game's prices.
    public let building: Money
    public let trains: Money
    /// Its riders (``LineAcquisition/value(ofDailyRiders:)``).
    public let riders: Money

    public var total: Money { building + trains + riders }
}

/// The offer of a line: what the purchase lays and costs, or why it
/// cannot be bought here.
public struct RealLineOffer: Sendable {
    public let line: RealBranchLine
    public let acquisition: RealLineAcquisition?
    public let price: RealLineAcquisitionPrice?
    /// Why it cannot be bought, as the player reads it.
    public let problem: String?
}

extension GameSession {
    // MARK: - On sale

    /// The branch lines this map sells (decision 315 §1): on a real-world
    /// map with the real trains loaded, each whose stations all lie in the
    /// world and that the company has not bought.
    public var buyableRealLines: [RealBranchLine] {
        guard let railways, let frame = RealWorldFrame(world: world) else { return [] }
        return RealBranchLine.names.keys.sorted().compactMap { network in
            guard let runs = railways.branchRuns[network], let names = RealBranchLine.names[network] else { return nil }
            let line = RealBranchLine(network: network, english: names.english, chinese: names.chinese, stops: runs.stops)
            guard world.acquisition(of: line.id) == nil,
                  runs.stops.allSatisfy({ name in realPoint(of: name, railways: railways, frame: frame).map { world.bounds.contains($0.plan) } ?? false })
            else { return nil }
            return line
        }
    }

    /// The branch line on sale that real station `name` (its Chinese name)
    /// is on past its junction, if any.
    public func buyableRealLine(through name: String) -> RealBranchLine? {
        buyableRealLines.first { $0.stops.dropFirst().contains(name) }
    }

    private func realPoint(of name: String, railways: RealRailways, frame: RealWorldFrame) -> WorldVector? {
        railways.stations.first { $0.id == "tra_sched|\(name)" }.map {
            WorldVector(frame.worldPosition(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))
        }
    }

    // MARK: - The offer

    /// Lays `line` out on a copy of the world and prices it (decision 315):
    /// the purchase, or why it cannot be made here (track in the way, land
    /// not bought, a grade too steep). Want of cash is not a problem here:
    /// the card weighs the price against the balance.
    public func realLineOffer(for line: RealBranchLine) -> RealLineOffer {
        func refused(_ english: String, _ chinese: String) -> RealLineOffer {
            RealLineOffer(line: line, acquisition: nil, price: nil, problem: language.text(english, chinese))
        }
        guard let railways, let frame = RealWorldFrame(world: world), let runs = railways.branchRuns[line.network],
              let traces = realRailwayTraces else {
            return refused("This map has no real railway to buy.", "這張地圖沒有可以收購的真實鐵路。")
        }
        guard world.acquisition(of: line.id) == nil else {
            return refused("This line is already yours.", "這條線已經是你的了。")
        }
        let points = runs.stops.compactMap { realPoint(of: $0, railways: railways, frame: frame) }
        guard points.count == runs.stops.count, points.allSatisfy({ world.bounds.contains($0.plan) }) else {
            return refused("The whole line is not on this map.", "這張地圖框不住整條線。")
        }
        // The real line's way from the junction to the terminal, run on
        // straight past each end (Checheng stands 81 m past the end of
        // the Jiji Line's drawing).
        let reach = RealLineAcquisition.stationReach
        guard let first = traces.snap(points[0], within: reach),
              let last = traces.snap(points[points.count - 1], within: reach, group: traces.groups[first.place.line]),
              let way = traces.path(from: first.place, to: last.place) else {
            return refused("The real line's track could not be followed here.", "這裡沒辦法沿著真實鐵路鋪軌。")
        }
        let traced = WorldPath(way).smoothed()
        guard traced.length > 2 * RealLineAcquisition.runOn else {
            return refused("The real line's track could not be followed here.", "這裡沒辦法沿著真實鐵路鋪軌。")
        }
        let startDirection = traced.tangent(at: 0), endDirection = traced.tangent(at: traced.length)
        let path = WorldPath(
            [traced.point(at: 0) - startDirection * RealLineAcquisition.runOn] + traced.points
                + [traced.point(at: traced.length) + endDirection * RealLineAcquisition.runOn]
        )
        let along = points.map { path.nearest($0) }
        guard along.allSatisfy({ $0.away <= RealLineAcquisition.stationReach }), zip(along, along.dropFirst()).allSatisfy({ $0.along < $1.along }) else {
            return refused("The real line's stations are not along its track here.", "真實車站不在這段鐵路上。")
        }

        // The ground under the way, read in on a copy.
        var draft = world
        let step = 32 * RealLineAcquisition.metre, side = 16 * RealLineAcquisition.metre
        let samples = (0...Int(path.length / step)).flatMap { index -> [PlanPoint] in
            let point = path.point(at: Double(index) * step)
            return [(-side, -side), (-side, side), (side, -side), (side, side)].map { dx, dy in WorldVector(x: point.x + dx, y: point.y + dy).plan }
        }
        try? draft.readGround(under: samples, from: heights)
        let mapped = draft.ground.isMapped
        let planning = draft
        func ground(_ point: WorldVector) -> Double {
            Double(planning.groundHeight(at: point.plan) ?? 0)
        }
        func water(_ point: WorldVector) -> Bool {
            guard mapped else { return false }
            let plan = point.plan
            return planning.terrain.isWater(row: Int(plan.y / Land.cellLength), column: Int(plan.x / Land.cellLength))
        }

        // Each station level, its loops' stretch with it.
        let half = Double(Int64(RealLineAcquisition.carsPerTrain + 1) * Train.carLength) / 2
        let platformLength = Int64(RealLineAcquisition.carsPerTrain + 1) * Train.carLength
        var forced = [0, path.length]
        var levels: [TrackRise.Level] = []
        var zones: [ClosedRange<Double>] = []
        var loopSpans: [(stop: Int, a: Double, b: Double, sides: Int)] = []
        for (index, name) in runs.stops.enumerated() {
            let at = along[index].along
            let zone = (at - half)...(at + half)
            zones.append(zone)
            let tracks = runs.tracks[name] ?? 1
            let span: ClosedRange<Double>
            if tracks > 1 {
                span = (at - RealWorldDemo.loopReach)...(at + RealWorldDemo.loopReach)
                loopSpans.append((index, span.lowerBound, span.upperBound, tracks - 1))
            } else {
                span = (zone.lowerBound - RealWorldDemo.platformMargin)...(zone.upperBound + RealWorldDemo.platformMargin)
            }
            forced += [span.lowerBound, span.upperBound]
            let height = ground(path.point(at: at))
            levels.append(TrackRise.Level(span, from: height - RealWorldDemo.stationReach, to: height + RealWorldDemo.stationReach))
        }
        let carried = railways.structures?.stretches(along: path, frame: frame, system: "tra_sched") ?? []
        guard let rise = TrackRise(path: path, ground: ground, water: water, levels: levels, carried: carried) else {
            return refused(
                "The track cannot climb along this line within the steepest grade.",
                "沿這條線的高低差超過遊戲的坡度上限，鋪不上去。"
            )
        }
        let main = RealWorldDemo.TrackPlan(
            path, forced: forced, avoiding: zones, close: loopSpans.map { $0.a...$0.b }, rise: rise, structure: .automatic
        )
        var plans: [(plan: RealWorldDemo.TrackPlan, start: RealLineAcquisition.NodeAt?, end: RealLineAcquisition.NodeAt?, together: Bool)] = [
            (main, nil, nil, false),
        ]
        var platformsAt: [(stop: Int, piece: Int, zone: ClosedRange<Double>)] = zones.enumerated().map { ($0.offset, 0, $0.element) }
        for loop in loopSpans {
            for offset in [RealWorldDemo.groundLoopOffset, -RealWorldDemo.groundLoopOffset].prefix(loop.sides) {
                let loopPath = path.offset(from: loop.a, to: loop.b, by: offset, ramp: RealWorldDemo.loopRamp)
                guard let loopRise = TrackRise(
                    path: loopPath, ground: ground, water: water, levels: [TrackRise.Level(0...loopPath.length, at: Double(rise.node(at: loop.a)))]
                ), let startNode = main.node(at: loop.a), let endNode = main.node(at: loop.b),
                    let a = main.distances.firstIndex(where: { abs($0 - loop.a) < 1 }), let b = main.distances.firstIndex(where: { abs($0 - loop.b) < 1 })
                else {
                    return refused("A passing loop does not fit here.", "這裡放不下待避線。")
                }
                let zone = RealWorldDemo.middlePlatform(of: loopPath)
                plans.append((
                    RealWorldDemo.TrackPlan(
                        loopPath, forced: [0, loopPath.length], avoiding: [zone], close: [0...loopPath.length],
                        start: startNode, end: endNode, rise: loopRise, structure: .automatic
                    ),
                    RealLineAcquisition.NodeAt(piece: 0, node: a), RealLineAcquisition.NodeAt(piece: 0, node: b), true
                ))
                platformsAt.append((loop.stop, plans.count - 1, zone))
            }
        }
        let pieces = plans.map { entry in
            let plan = entry.plan
            let nodes = plan.nodes.indices.map { WorldCoordinate(x: plan.nodes[$0].point.x, y: plan.nodes[$0].point.y, z: plan.heights[$0]) }
            let ground = plan.curves.indices.flatMap { index -> [PlanPoint] in
                let surveyed = TrackGeometry(from: nodes[index], to: nodes[index + 1], curve: plan.curves[index]).map(NetworkBuilding.surveyedPoints(of:)) ?? []
                return [nodes[index].plan, nodes[index + 1].plan] + surveyed
            }
            return RealLineAcquisition.Piece(
                nodes: nodes, start: entry.start, end: entry.end, curves: plan.curves, distances: plan.distances, structure: plan.structure,
                together: entry.together, ground: ground
            )
        }

        // The stations: the company's own by the junction, if it has one.
        let junctionStation = world.stations
            .filter { (WorldVector($0.location) - points[0]).length <= RealLineAcquisition.junctionReach }
            .min { (WorldVector($0.location) - points[0]).length < (WorldVector($1.location) - points[0]).length }
        let stops = runs.stops.enumerated().map { index, name in
            let at = path.point(at: along[index].along).plan
            let real = railways.stations.first { $0.id == "tra_sched|\(name)" }
            return RealLineAcquisition.Stop(
                name: real?.name(in: language) ?? name, at: at, existing: index == 0 ? junctionStation?.id : nil, demand: newStationDemand(at: at)
            )
        }
        let platforms = platformsAt.map {
            RealLineAcquisition.Platform(stop: $0.stop, at: RealLineAcquisition.PieceAt(piece: $0.piece, distance: $0.zone.lowerBound), length: platformLength)
        }

        // The trains where the real ones stand at midnight, one to a track,
        // each facing up the line but at the terminal.
        var starts: [RealLineAcquisition.Start] = []
        for (name, count) in runs.overnight.sorted(by: { $0.key < $1.key }) {
            guard let stop = runs.stops.firstIndex(of: name) else { continue }
            let tracks = platformsAt.filter { $0.stop == stop }
            guard count <= tracks.count else {
                return refused("The line's trains have no room to stand overnight.", "這條線的列車晚上沒有地方停。")
            }
            for track in tracks.prefix(count) {
                starts.append(RealLineAcquisition.Start(
                    name: "", at: RealLineAcquisition.PieceAt(piece: track.piece, distance: track.zone.lowerBound), forward: stop < runs.stops.count - 1
                ))
            }
        }
        let lineName = line.name(in: language)
        starts = starts.enumerated().map { number, start in
            RealLineAcquisition.Start(name: RealWorldDemo.trainName(line: lineName, number: number + 1, in: language), at: start.at, forward: start.forward)
        }
        let lineRuns = runs.runs.map { run in
            LineRun(
                from: runs.stops.firstIndex(of: run.calls[0].station) ?? 0,
                to: runs.stops.firstIndex(of: run.calls[run.calls.count - 1].station) ?? 0,
                times: run.calls.map { LineRunTime(arrival: $0.arrival, departure: $0.departure) },
                days: run.days.reduce(0) { $0 | 1 << $1 }
            )
        }
        let riders = runs.stops.dropFirst().reduce(Int64(0)) { total, name in
            guard let real = railways.stations.first(where: { $0.id == "tra_sched|\(name)" }) else { return total }
            return total + Int64(railways.ridership?.riders(of: real, data: railways.stationData) ?? 0)
        }
        let color = railways.lines.first { $0.system.id == "tra_sched" && $0.name.hasPrefix(line.chinese) }
            .flatMap { LineColor(rgb: Int($0.palette.color.red) << 16 | Int($0.palette.color.green) << 8 | Int($0.palette.color.blue)) }
        let acquisition = RealLineAcquisition(
            realLine: line.id, pieces: pieces, stops: stops, platforms: platforms, lineName: lineName, color: color, runs: lineRuns,
            trains: starts, cars: RealLineAcquisition.carsPerTrain, dailyRiders: min(riders, LineAcquisition.maximumDailyRiders)
        )

        // GameCore's answer and the price, on a funded copy.
        var probe = world.pricingCopy()
        do throws(GameError) {
            let price = try build(acquisition, in: &probe)
            return RealLineOffer(line: line, acquisition: acquisition, price: price, problem: nil)
        } catch {
            return RealLineOffer(line: line, acquisition: nil, price: nil, problem: error.playerMessage(in: language))
        }
    }

    // MARK: - Building it

    /// Builds `acquisition` in `world` and records it (decision 315 §5):
    /// all of it or, throwing, none, the caller's copy dropped. What each
    /// part cost.
    @discardableResult
    func build(_ acquisition: RealLineAcquisition, in world: inout GameWorld) throws(GameError) -> RealLineAcquisitionPrice {
        let opening = world.economy.balance
        var nodes: [[TrackNodeID]] = []
        var edges: [[TrackEdgeID]] = []
        for piece in acquisition.pieces {
            try world.readGround(under: piece.ground, from: heights)
            var ids: [TrackNodeID] = []
            for (index, position) in piece.nodes.enumerated() {
                if index == 0, let start = piece.start {
                    ids.append(nodes[start.piece][start.node])
                } else if index == piece.nodes.count - 1, let end = piece.end {
                    ids.append(nodes[end.piece][end.node])
                } else {
                    ids.append(try world.buildTrackNode(at: position))
                }
            }
            if piece.together {
                edges.append(try world.buildTrackEdges(piece.curves.enumerated().map { index, curve in
                    TrackEdgePlan(from: ids[index], to: ids[index + 1], curve: curve, structure: piece.structure)
                }))
            } else {
                var built: [TrackEdgeID] = []
                for (index, curve) in piece.curves.enumerated() {
                    built.append(try world.buildTrackEdge(from: ids[index], to: ids[index + 1], curve: curve, structure: piece.structure))
                }
                edges.append(built)
            }
            nodes.append(ids)
        }
        /// The edge `at` is on and how far along it.
        func edge(_ at: RealLineAcquisition.PieceAt) throws(GameError) -> (TrackEdgeID, Int64) {
            guard acquisition.pieces.indices.contains(at.piece) else { throw .invalidTrackGeometry }
            let distances = acquisition.pieces[at.piece].distances, built = edges[at.piece]
            guard !built.isEmpty, distances.count == built.count + 1 else { throw .invalidTrackGeometry }
            let index = max(0, min(built.count - 1, distances.lastIndex { $0 <= at.distance } ?? 0))
            let a = distances[index], b = distances[index + 1]
            let length = Double(world.network.edge(built[index])?.length ?? 0)
            return (built[index], Int64(((at.distance - a) / max(b - a, 1) * length).rounded()))
        }

        var stations: [StationID] = []
        for stop in acquisition.stops {
            if let existing = stop.existing {
                guard world.station(id: existing) != nil else { throw .unknownStation(existing) }
                stations.append(existing)
            } else {
                let station = try world.buildStation(named: stop.name, at: stop.at)
                if world.accounts.mode == .management, !world.landDemand {
                    try world.setStationDemand(station.id, to: stop.demand)
                }
                stations.append(station.id)
            }
        }
        for platform in acquisition.platforms {
            guard stations.indices.contains(platform.stop) else { throw .invalidTrackGeometry }
            let (on, offset) = try edge(platform.at)
            try world.addTrackPlatform(stations[platform.stop], on: on, from: offset, to: offset + platform.length)
        }
        Self.readLand(roundStationsOf: &world, population: population, places: places, water: water, coverage: coverage)
        let built = world.economy.balance

        let line = try world.createLine(named: acquisition.lineName, stops: stations)
        if let color = acquisition.color { try world.setLineColor(line.id, to: color) }
        try world.setLineServiceWindow(line.id, to: .allDay)
        try world.setLineRuns(line.id, to: acquisition.runs)
        let count = acquisition.trains.count
        try world.setLineTrainsInService(line.id, to: TrainsInService(peak: count, offPeak: count, low: count))
        let length = Int64(acquisition.cars + 1) * Train.carLength
        for start in acquisition.trains {
            let train = try world.purchaseTrain(named: start.name).id
            try world.setTrainCars(train, to: acquisition.cars)
            let (on, at) = try edge(start.at)
            let edgeLength = world.network.edge(on)?.length ?? 0
            let offset = start.forward ? at + length : edgeLength - at
            try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: on, direction: start.forward ? .forward : .backward), offset: offset))
            try world.setTrainContinuation(train, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(train, to: 512)
            try world.assignTrain(train, to: line.id)
        }
        let bought = world.economy.balance
        try world.recordLineAcquisition(line: line.id, realLine: acquisition.realLine, dailyRiders: acquisition.dailyRiders)
        return RealLineAcquisitionPrice(
            building: opening - built, trains: built - bought, riders: bought - world.economy.balance
        )
    }
}

/// What the "line bought" card says (decision 315 §8): the line, its
/// stations at each end, and what the company now runs.
public struct RealLineAcquired: Hashable, Sendable {
    public let line: LineID
    public let name: String
    public let color: LineColor?
    /// The junction's and the terminal's names.
    public let ends: (from: String, to: String)
    public let stations: Int
    /// Its length in metres, along the main track.
    public let metres: Int64
    public let trains: Int
    /// The real trains of a weekday (Wednesday) it runs.
    public let weekdayTrains: Int

    public static func == (a: RealLineAcquired, b: RealLineAcquired) -> Bool {
        a.line == b.line && a.name == b.name && a.color == b.color && a.ends == b.ends && a.stations == b.stations && a.metres == b.metres
            && a.trains == b.trains && a.weekdayTrains == b.weekdayTrains
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(line)
    }

    /// "7 stations, 13.0 km, 3 trains".
    public func sizeText(in language: DisplayLanguage) -> String {
        let km = String(format: "%.1f", Double(metres) / 1_000)
        return language.text(
            "\(stations) stations, \(km) km, \(trains) \(trains == 1 ? "train" : "trains")",
            "\(stations) 站、\(km) 公里、\(trains) 列車"
        )
    }

    public func handoverText(in language: DisplayLanguage) -> String {
        language.text("Yours to run from tomorrow's first train", "明天首班車起由你經營")
    }

    public func timetableText(in language: DisplayLanguage) -> String {
        language.text("Real timetable: \(weekdayTrains) trains a weekday", "真實班次：平日 \(weekdayTrains) 班")
    }
}

extension GameSession {
    /// Buys the line `offer` laid out (decision 315), as one command: its
    /// track, stations, trains and real timetable. The card it opens
    /// (``lastLineAcquired``) says what was bought; a refusal says why.
    @discardableResult
    public func acquireRealLine(_ offer: RealLineOffer) -> Bool {
        guard let acquisition = offer.acquisition else {
            message = StatusMessage(kind: .failure, text: offer.problem ?? "")
            return false
        }
        let name = acquisition.lineName
        let made = perform(.acquireRealLine(acquisition)) { _, _, _ in
            language.text(
                "Bought \(name): its track, \(acquisition.stops.count) stations, \(acquisition.trains.count) trains and its real timetable. Yours to run from tomorrow's first train.",
                "已收購\(name)：軌道、\(acquisition.stops.count) 座車站、\(acquisition.trains.count) 列車與真實班次。明天首班車起由你經營。"
            )
        }
        guard let line = made?.line else { return false }
        let main = acquisition.pieces.first
        let metres = main.map { piece in
            Int64(((piece.distances.last ?? 0) - 2 * RealLineAcquisition.runOn) / RealLineAcquisition.metre)
        } ?? 0
        // Wednesday: 1 << 3.
        let weekday = acquisition.runs.count { $0.days & (1 << 3) != 0 }
        lastLineAcquired = RealLineAcquired(
            line: line.id, name: name, color: acquisition.color,
            ends: (acquisition.stops.first?.name ?? "", acquisition.stops.last?.name ?? ""),
            stations: acquisition.stops.count, metres: max(0, metres), trains: acquisition.trains.count, weekdayTrains: weekday
        )
        selectLine(line.id)
        return true
    }
}
