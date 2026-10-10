import Foundation
import GameCore

// The real-world demo on the ground (ARCHITECTURE decision 132, the
// author's request of 2026-10-10: "rebuild the real-world Pingxi demo as it
// is with the new terrain, longer, and with more trains; it is a demo, to
// test on later"). Since decision 124's second step a new real-world game
// measures its track from the ground; the demo was left flat at 0 m. Now it
// reads the ground under its lines as the network tool does, lays its track
// at heights worked out from it (``TrackRise``), level at the stations,
// and lets the automatic structure make it embankment, cutting, viaduct,
// bridge or tunnel. It also reaches further along the real lines: the
// Yilan Line from Qidu through Badu to Mudan, the Western Trunk Line from
// Badu to Keelung, the Pingxi Line from Sandiaoling to Jingtong and the
// Shenao Line from Ruifang to Badouzi, with six trains on four lines.
//
// The Pingxi challenge (decision 90) keeps the flat demo it was measured
// on (``RealWorldDemo/makeFlat(in:railways:land:water:steep:)``).

extension RealWorldDemo {
    /// The demo's game, built on `railways` over the ground of `heights`
    /// (decision 132; without them, the flat demo,
    /// ``makeFlat(in:railways:land:water:steep:)``), with `land` the map's
    /// people (``LandImport``; without it,
    /// the towns of a new game), `water` its water (``WaterGrid``, decision
    /// 105) and `steep` its steep slopes (decision 115).
    ///
    /// Built like ``DemoWorld``: a new game at ``anchor`` and ordinary
    /// `GameWorld` commands that charge their usual costs. The game starts
    /// with what they cost on top of a new game's money, so what is left is
    /// a new game's: the track's price depends on the ground under it, so
    /// the layout is planned over the ground first and priced edge by edge
    /// (``GameWorld/trackEdgePrice(from:to:curve:profile:structure:)``).
    public static func make(
        in language: DisplayLanguage, railways: RealRailways, land: [LandCell]? = nil, water: [CellPosition] = [],
        steep: [CellPosition] = [], heights: HeightGrid? = nil
    ) -> GameWorld {
        // Without the heights the lines would cross each other at 0 m where
        // on the ground one passes over the other: the flat demo instead.
        guard let heights else { return makeFlat(in: language, railways: railways, land: land, water: water, steep: steep) }
        let routes = GroundRoutes(railways: railways)
        func world(balance: Money, ground: [GroundBlock]) throws(GameError) -> GameWorld {
            var world = GameWorld.newGame(anchor: anchor, balance: balance, land: land, water: water, steep: steep)
            // Its stations keep the ridership it gives them, as the flat
            // demo's (Phase 6b): most of its riders come for the sights.
            world.setLandDemand(false)
            try world.mapGround()
            if !ground.isEmpty { try world.setGround(ground) }
            return world
        }
        do throws(GameError) {
            var planned = try world(balance: GameWorld.startingBalance, ground: [])
            try planned.setGround(heights.ground(of: planned.missingGroundBlocks(under: routes.groundPoints), frame: routes.frame))
            let layout = GroundLayout(routes: routes, over: planned)
            let cost = try layout.cost(in: planned)
            var game = try world(balance: GameWorld.startingBalance + cost, ground: planned.ground.sortedBlocks)
            try layout.build(in: &game, language: language)
            return game
        } catch {
            preconditionFailure("The real-world demo no longer builds: \(error)")
        }
    }

    // MARK: - The lines

    /// The ground layout's numbers: how far the main track runs on past its
    /// terminals, and where the Western Trunk Line leaves it west of Badu.
    static let runOn = 300.0 * metre
    static let baduJunction = 250.0 * metre
    /// The steepest grade the demo lays: the `Railway/` site's 25 in 1,000
    /// for the TRA's lines (`rail-3d/physical/level-profiles.json`'s
    /// `basis`), well under the game's 40 (``TrackProfile/maximumGrade``).
    static let rulingGrade = 0.025
    /// How far a passing loop stands off the main track: a metre more than
    /// on the flat demo, so the two keep the game's 4 m apart on a curve,
    /// each fitted within a metre of its line.
    static let groundLoopOffset = 6.0 * metre
    /// How far above or below the ground a station may be laid.
    static let stationReach = 8.0 * metre

    /// Where everything goes in plan: the real lines' centre lines and
    /// stations, worked out before the ground is read.
    struct GroundRoutes {
        let frame: RealWorldFrame
        /// The main track: the Western Trunk Line from past Qidu to Badu,
        /// then the Yilan Line on to past Mudan.
        let main: WorldPath
        /// The Western Trunk Line from its junction west of Badu to Keelung.
        let trunk: WorldPath
        /// The Pingxi Line from the south end of Sandiaoling's loop.
        let pingxi: WorldPath
        /// The Shenao Line from the west end of Ruifang's loop.
        let shenao: WorldPath
        let mainStops: [Stop]
        let trunkStops: [Stop]
        let pingxiStops: [Stop]
        let shenaoStops: [Stop]
        /// The stations on the main track with a passing loop.
        let mainLoops: Set<String>
        let trunkLoops: Set<String>
        let pingxiLoops: Set<String>
        /// Where on the main track the Western Trunk Line leaves it.
        let trunkJunction: Double

        init(railways: RealRailways) {
            let frame = RealWorldFrame(anchor: RealWorldDemo.anchor, bounds: GameWorld.newGameBounds)
            func line(_ prefix: String) -> WorldPath {
                guard let line = railways.lines.first(where: { $0.name.hasPrefix(prefix) }) else {
                    preconditionFailure("The real railways have no \(prefix)")
                }
                return WorldPath(line.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) })
            }
            func stop(_ name: String) -> Stop {
                guard let station = railways.stations.first(where: { $0.id == "tra_sched|\(name)" }) else {
                    preconditionFailure("The real railways have no \(name)")
                }
                return Stop(station: station, point: WorldVector(frame.worldPosition(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude)))
            }
            self.frame = frame
            // The site's Western Trunk Line runs from Keelung through Badu
            // to Qidu and south, its Yilan Line from Su'ao to Badu, its
            // Pingxi Line from Sandiaoling and its Shenao Line from Ruifang.
            let trunkLine = line("縱貫線北段"), yilan = line("宜蘭線"), pingxiLine = line("平溪線"), shenaoLine = line("深澳線")
            let qidu = stop("七堵"), badu = stop("八堵"), mudan = stop("牡丹")
            mainStops = [qidu, badu] + ["暖暖", "四腳亭", "瑞芳", "猴硐", "三貂嶺"].map(stop) + [mudan]
            trunkStops = [badu] + ["三坑", "基隆"].map(stop)
            pingxiStops = ["大華", "十分", "望古", "嶺腳", "平溪", "菁桐"].map(stop)
            shenaoStops = ["海科館", "八斗子"].map(stop)
            mainLoops = ["七堵", "四腳亭", "瑞芳", "猴硐", "三貂嶺", "牡丹"]
            trunkLoops = ["三坑"]
            pingxiLoops = ["十分"]

            // West of Badu the two lines are one; east of it the Yilan Line
            // runs some 25 m south of the trunk line before it turns away.
            // The main track leaves the trunk line 250 m west of Badu for
            // the Yilan Line's end at Badu, and the trunk line goes on from
            // there on its own track.
            let trunkBadu = trunkLine.project(badu.point)
            let parting = trunkLine.point(at: trunkBadu + baduJunction)
            let west = trunkLine.points(from: trunkBadu + baduJunction, to: trunkLine.project(qidu.point) + runOn).reversed()
            let east = yilan.points(from: yilan.project(mudan.point) - runOn, to: yilan.length).reversed()
            main = WorldPath(Array(west) + east).smoothed()
            trunkJunction = main.project(parting)
            trunk = WorldPath([main.point(at: trunkJunction)] + trunkLine.points(from: 0, to: trunkBadu + 150 * metre).reversed()).smoothed()

            // The Pingxi Line shares the Yilan Line's alignment south of
            // Sandiaoling and parts from it some 400 m on: it leaves the
            // main track at the south end of Sandiaoling's loop and joins
            // its own line 30 m off.
            let pingxiJunction = main.project(mainStops[6].point) + loopReach
            let parted = pingxiLine.project(main.point(at: pingxiJunction)) + 230 * metre
            pingxi = WorldPath([main.point(at: pingxiJunction)] + pingxiLine.points(from: parted, to: pingxiLine.length).dropFirst()).smoothed()

            // The Shenao Line leaves at the west end of Ruifang's loop,
            // heading west beside the Yilan Line before it turns north, as
            // on the flat demo.
            let shenaoJunction = main.project(mainStops[4].point) - loopReach
            let beside = shenaoLine.project(main.point(at: shenaoJunction))
            shenao = WorldPath([main.point(at: shenaoJunction)] + shenaoLine.points(from: beside + 120 * metre, to: shenaoLine.length).dropFirst()).smoothed()
        }

        /// The points whose ground the demo reads: every 32 m along its
        /// lines, and 16 m round each, so curves a few metres off them and
        /// the passing loops stand on ground read.
        var groundPoints: [PlanPoint] {
            let step = 32 * metre, reach = 16 * metre
            return [main, trunk, pingxi, shenao].flatMap { path in
                (0...Int(path.length / step)).flatMap { index -> [PlanPoint] in
                    let point = path.point(at: Double(index) * step)
                    return [(-reach, -reach), (-reach, reach), (reach, -reach), (reach, reach)].map { dx, dy in
                        WorldVector(x: point.x + dx, y: point.y + dy).plan
                    }
                }
            }
        }
    }

    /// The tracks to build, in order, with their heights over the ground
    /// of a world that has read it.
    struct GroundLayout {
        /// A track and how it joins those built before it: at its start or
        /// end, the node of track `host` at a distance along that track.
        struct Piece {
            let plan: TrackPlan
            let start: (host: Int, at: Double)?
            let end: (host: Int, at: Double)?
        }

        /// A platform: the station, the piece it is on and where.
        struct Platform {
            let stop: Stop
            let piece: Int
            let zone: ClosedRange<Double>
        }

        /// A line, the stations it calls at, and where its trains start:
        /// each at a platform of its first call, facing the way it leaves;
        /// `platforms`, the piece whose platform it takes at a station with
        /// platforms on more than one track.
        struct Service {
            let names: (String, String)
            let stops: [String]
            let starts: [(piece: Int, zone: ClosedRange<Double>, forward: Bool)]
            var platforms: [String: Int] = [:]
        }

        let pieces: [Piece]
        let platforms: [Platform]
        let services: [Service]

        init(routes: GroundRoutes, over world: GameWorld) {
            let mapped = world.ground.isMapped
            func ground(_ point: WorldVector) -> Double {
                guard let height = world.groundHeight(at: point.plan) else {
                    preconditionFailure("The demo's ground is not read at \(point.plan)")
                }
                return Double(height)
            }
            func water(_ point: WorldVector) -> Bool {
                guard mapped else { return false }
                let plan = point.plan
                return world.terrain.isWater(row: Int(plan.y / Land.cellLength), column: Int(plan.x / Land.cellLength))
            }
            // A station is level, within a few metres of the ground where it
            // first stands; where it stands again (Badu, on two lines), at
            // the height it was laid at.
            var levels: [String: Double] = [:]
            func level(_ stop: Stop, on path: WorldPath, over range: ClosedRange<Double>) -> TrackRise.Level {
                if let level = levels[stop.station.id] { return TrackRise.Level(range, at: level) }
                let height = ground(path.point(at: path.project(stop.point)))
                return TrackRise.Level(range, from: height - stationReach, to: height + stationReach)
            }
            let structure: TrackStructure = .automatic
            var pieces: [Piece] = []
            var platforms: [Platform] = []
            var loopStarts: [String: (piece: Int, zone: ClosedRange<Double>)] = [:]
            var starts: [String: [Int: ClosedRange<Double>]] = [:]

            /// Lays `path` with its stations `stops` and their loops
            /// (`loops`), joined at its start to `host` at `at` with its
            /// height there; `junctions` are the further distances where
            /// other tracks leave it, and `spans` the stretches level at a
            /// station other than its platform's or its loop's.
            func lay(
                _ path: WorldPath, stops: [Stop], loops: Set<String>, junctions: [Double] = [], from host: (host: Int, at: Double)? = nil,
                looseUntil: Double = 0, close: [ClosedRange<Double>] = [], spans: [String: ClosedRange<Double>] = [:]
            ) -> Int {
                let zones = stops.map { platformZone(on: path, at: $0.point) }
                var forced = [0, path.length] + junctions
                var flat: [TrackRise.Level] = []
                var stations: [(Stop, ClosedRange<Double>)] = []
                var loopEnds: [(Stop, Double, Double)] = []
                for (stop, zone) in zip(stops, zones) {
                    let span: ClosedRange<Double>
                    if loops.contains(stop.station.name(in: .traditionalChinese)) {
                        let at = path.project(stop.point)
                        loopEnds.append((stop, at - loopReach, at + loopReach))
                        span = (at - loopReach)...(at + loopReach)
                    } else {
                        span = spans[stop.station.id] ?? (zone.lowerBound - platformMargin)...(zone.upperBound + platformMargin)
                    }
                    forced += [span.lowerBound, span.upperBound]
                    flat.append(level(stop, on: path, over: span))
                    stations.append((stop, span))
                }
                var startNode: (point: PlanPoint, direction: WorldVector)?
                if let host {
                    let hostPlan = pieces[host.host].plan
                    guard let node = hostPlan.node(at: host.at), let index = hostPlan.distances.firstIndex(where: { abs($0 - host.at) < 1 }) else {
                        preconditionFailure("A junction is not a node")
                    }
                    // Leaves the host along it, whichever way the path goes.
                    let ahead = path.point(at: min(path.length, 50 * metre)) - WorldVector(node.point)
                    startNode = (node.point, ahead.dot(node.direction) >= 0 ? node.direction : node.direction.reversed)
                    flat.append(TrackRise.Level(0...0, at: Double(hostPlan.heights[index])))
                }
                let rise = TrackRise(path: path, ground: ground, water: water, levels: flat)
                for (stop, span) in stations where levels[stop.station.id] == nil {
                    levels[stop.station.id] = Double(rise.node(at: span.lowerBound))
                }
                // Closely through the loops, so the two tracks keep apart.
                let loopSpans = loopEnds.map { $0.1...$0.2 }
                let plan = TrackPlan(
                    path, forced: forced, avoiding: zones, looseUntil: looseUntil, close: close + loopSpans, start: startNode, rise: rise,
                    structure: structure
                )
                pieces.append(Piece(plan: plan, start: host, end: nil))
                let index = pieces.count - 1
                for (stop, zone) in zip(stops, zones) {
                    platforms.append(Platform(stop: stop, piece: index, zone: zone))
                    starts[stop.station.id, default: [:]][index] = zone
                }
                // Each loop leaves the track at one node and joins it again
                // at the next, standing off it, level, in the middle.
                for (stop, a, b) in loopEnds {
                    let loop = path.offset(from: a, to: b, by: groundLoopOffset, ramp: loopRamp)
                    let loopRise = TrackRise(path: loop, ground: ground, water: water, levels: [TrackRise.Level(0...loop.length, at: Double(rise.node(at: a)))])
                    guard let start = plan.node(at: a), let end = plan.node(at: b) else { preconditionFailure("A loop's ends are not nodes") }
                    let zone = middlePlatform(of: loop)
                    pieces.append(Piece(
                        plan: TrackPlan(
                            loop, forced: [0, loop.length], avoiding: [zone], close: [0...loop.length], start: start, end: end, rise: loopRise,
                            structure: structure
                        ),
                        start: (index, a), end: (index, b)
                    ))
                    platforms.append(Platform(stop: stop, piece: pieces.count - 1, zone: zone))
                    loopStarts[stop.station.id] = (pieces.count - 1, zone)
                }
                return index
            }

            let main = routes.main
            let badu = routes.mainStops[1]
            let mainZone = platformZone(on: main, at: badu.point)
            let sandiaoling = main.project(routes.mainStops[6].point) + loopReach
            let ruifang = main.project(routes.mainStops[4].point) - loopReach
            // Badu is level from the trunk line's junction to the end of its
            // platforms, so the two lines run through it side by side.
            let mainIndex = lay(
                main, stops: routes.mainStops, loops: routes.mainLoops, junctions: [routes.trunkJunction, sandiaoling, ruifang],
                close: [(ruifang - besideReach)...ruifang], spans: [badu.station.id: routes.trunkJunction...(mainZone.upperBound + platformMargin)]
            )
            let trunkZone = platformZone(on: routes.trunk, at: badu.point)
            let trunk = lay(
                routes.trunk, stops: routes.trunkStops, loops: routes.trunkLoops, from: (mainIndex, routes.trunkJunction), looseUntil: 120 * metre,
                spans: [badu.station.id: 0...(trunkZone.upperBound + platformMargin)]
            )
            _ = lay(routes.pingxi, stops: routes.pingxiStops, loops: routes.pingxiLoops, from: (mainIndex, sandiaoling), looseUntil: 260 * metre)
            let shenao = lay(
                routes.shenao, stops: routes.shenaoStops, loops: [], from: (mainIndex, ruifang), looseUntil: 300 * metre, close: [0...besideReach]
            )

            let ids = (main: routes.mainStops.map(\.station.id), trunk: routes.trunkStops.map(\.station.id))
            func loop(_ id: String) -> (piece: Int, zone: ClosedRange<Double>, forward: Bool) {
                guard let start = loopStarts[id] else { preconditionFailure("\(id) has no loop") }
                return (start.piece, start.zone, true)
            }
            func on(_ piece: Int, _ id: String, forward: Bool) -> (piece: Int, zone: ClosedRange<Double>, forward: Bool) {
                guard let zone = starts[id]?[piece] else { preconditionFailure("\(id) has no platform there") }
                return (piece, zone, forward)
            }
            let (qidu, ruifangID, mudan) = (ids.main[0], ids.main[4], ids.main[7])
            var mudanLoop = loop(mudan)
            mudanLoop.forward = false
            services = [
                Service(
                    names: ("Pingxi Line", "平溪線"), stops: Array(ids.main[4...6]) + routes.pingxiStops.map(\.station.id),
                    starts: [on(mainIndex, ruifangID, forward: true), loop(ruifangID)]
                ),
                Service(names: ("Yilan Line", "宜蘭線"), stops: ids.main.reversed(), starts: [on(mainIndex, mudan, forward: false), mudanLoop]),
                Service(
                    names: ("Shenao Line", "深澳線"), stops: routes.shenaoStops.reversed().map(\.station.id) + [ruifangID],
                    starts: [on(shenao, routes.shenaoStops[1].station.id, forward: false)]
                ),
                // At Badu the trunk line's trains take their own track's
                // platform, which goes on to Keelung.
                Service(
                    names: ("Western Trunk Line", "縱貫線"), stops: [qidu] + ids.trunk, starts: [on(mainIndex, qidu, forward: true)],
                    platforms: [ids.trunk[0]: trunk]
                ),
            ]
            self.pieces = pieces
            self.platforms = platforms
        }

        /// What building it costs in `world`: each edge as the ground there
        /// prices it, a station each and the trains with their cars.
        func cost(in world: GameWorld) throws(GameError) -> Money {
            let costs = world.economy.costs
            var total = Int64(Set(platforms.map(\.stop.station.id)).count) * costs.station.amount
            total += Int64(services.map(\.starts.count).reduce(0, +)) * (costs.train.amount + Int64(cars - 1) * costs.car.amount)
            for piece in pieces {
                let plan = piece.plan
                for (index, curve) in plan.curves.enumerated() {
                    func at(_ index: Int) -> WorldCoordinate {
                        WorldCoordinate(x: plan.nodes[index].point.x, y: plan.nodes[index].point.y, z: plan.heights[index])
                    }
                    total += try world.trackEdgePrice(from: at(index), to: at(index + 1), curve: curve, structure: plan.structure).amount
                }
            }
            return Money(total)
        }

        func build(in world: inout GameWorld, language: DisplayLanguage) throws(GameError) {
            var tracks: [Track] = []
            for piece in pieces {
                func node(_ end: (host: Int, at: Double)?) -> TrackNodeID? {
                    guard let end else { return nil }
                    guard let node = tracks[end.host].node(at: end.at) else { preconditionFailure("A junction is not built") }
                    return node
                }
                tracks.append(try piece.plan.build(in: &world, start: node(piece.start), end: node(piece.end), together: piece.end != nil))
            }

            // The stations, each at its first platform.
            var ids: [String: StationID] = [:]
            for platform in platforms {
                let track = tracks[platform.piece]
                let id: StationID
                if let built = ids[platform.stop.station.id] {
                    id = built
                } else {
                    let middle = track.plan.path.point(at: (platform.zone.lowerBound + platform.zone.upperBound) / 2)
                    id = try world.buildStation(named: platform.stop.station.name(in: language), at: middle.plan).id
                    ids[platform.stop.station.id] = id
                }
                let (edge, offset) = track.edge(at: platform.zone.lowerBound, in: world)
                try world.addTrackPlatform(id, on: edge, from: offset, to: offset + platformLength)
            }
            func id(_ station: String) -> StationID {
                guard let id = ids[station] else { preconditionFailure("\(station) was not built") }
                return id
            }
            // Every station has ridership: the game's numbers, not real ones.
            var seen: Set<String> = []
            for platform in platforms where seen.insert(platform.stop.station.id).inserted {
                if let (kind, trips) = ridershipByName[platform.stop.station.name(in: .traditionalChinese)] {
                    try world.setStationDemand(id(platform.stop.station.id), to: StationDemand(kind: kind, dailyTrips: trips))
                }
            }

            for service in services {
                let name = language.text(service.names.0, service.names.1)
                let line = try world.createLine(named: name, stops: service.stops.map(id)).id
                // Each leg into a station that names its platform's track.
                var preferences: [LineRoutePreference] = []
                for (to, station) in service.stops.enumerated() {
                    guard let piece = service.platforms[station],
                          let platform = world.trackPlatforms(of: id(station)).first(where: { tracks[piece].edges.contains($0.edge) })
                    else { continue }
                    for from in [to - 1, to + 1] where service.stops.indices.contains(from) {
                        preferences.append(LineRoutePreference(from: from, to: to, platform: platform))
                    }
                }
                if !preferences.isEmpty { try world.setLineRoutePreferences(line, to: preferences) }
                let count = service.starts.count
                try world.setLineServiceWindow(line, to: .allDay)
                try world.setLineTrainsInService(line, to: TrainsInService(peak: count, offPeak: count, low: count))
                for (number, start) in service.starts.enumerated() {
                    let train = try world.purchaseTrain(named: trainName(line: name, number: number + 1, in: language)).id
                    try world.setTrainCars(train, to: cars)
                    let track = tracks[start.piece]
                    let (edge, at) = track.edge(at: start.zone.lowerBound, in: world)
                    let length = world.network.edge(edge)?.length ?? 0
                    let offset = start.forward ? at + platformLength : length - at
                    try world.placeTrain(
                        train, at: .onEdge(TrackTraversal(edge: edge, direction: start.forward ? .forward : .backward), offset: offset)
                    )
                    try world.setTrainContinuation(train, along: [], stoppingAt: offset)
                    try world.setTrainMovementRate(train, to: 512)
                    try world.assignTrain(train, to: line)
                }
            }
        }
    }
}

// MARK: - The track's heights

/// The height of track along a path (decision 132): as near the ground as
/// it can be, smoothed over 160 m either way, but never steeper than
/// ``RealWorldDemo/rulingGrade``, level along each of its `levels` within
/// the heights it allows, at least 5 m over water (a bridge) or, where no
/// grade reaches that, at least 12 m under it (a tunnel), and at most 56 m
/// over the ground (the game's viaducts stand up to 64 m). Where the ground
/// rises or falls faster than that, the track goes into a cutting or a
/// tunnel, or out on an embankment, a viaduct or a bridge: the automatic
/// structure decides.
///
/// Worked out every 8 m and at the ends of each level stretch, as the
/// closest such line to the smoothed ground: the heights each sample's
/// constraints leave reachable from the others at the ruling grade (a
/// pass each way), then from the start the nearest of them to the smoothed
/// ground.
struct TrackRise {
    /// A stretch of the path that is level, somewhere from `low` to `high`.
    struct Level {
        let range: ClosedRange<Double>
        let low: Double
        let high: Double

        /// Level at exactly `height`.
        init(_ range: ClosedRange<Double>, at height: Double) {
            self.init(range, from: height, to: height)
        }

        init(_ range: ClosedRange<Double>, from low: Double, to high: Double) {
            self.range = range
            self.low = low
            self.high = high
        }
    }

    static let spacing = 8.0 * RealWorldDemo.metre
    static let smoothing = 160.0 * RealWorldDemo.metre
    static let waterClearance = 5.0 * RealWorldDemo.metre
    static let underWater = 12.0 * RealWorldDemo.metre
    static let highest = 56.0 * RealWorldDemo.metre
    /// How much further from the ground than they ask the stations may
    /// stand, tried in turn.
    static let slack = [0.0, 4, 8, 12].map { $0 * RealWorldDemo.metre }
    /// How far a node may stand from the ground: the game's 64 m, less a
    /// margin.
    static let nodeReach = 60.0 * RealWorldDemo.metre
    /// How far an edge's straight grade may stray from the line.
    static let fit = 1.0 * RealWorldDemo.metre

    let distances: [Double]
    let heights: [Double]
    let ground: [Double]
    /// Each level stretch and the height it is laid at.
    let levels: [(range: ClosedRange<Double>, height: Double)]

    init(path: WorldPath, ground: (WorldVector) -> Double, water: (WorldVector) -> Bool, levels: [Level]) {
        let count = max(1, Int((path.length / Self.spacing).rounded(.up)))
        let grid = (0...count).map { min(Double($0) * Self.spacing, path.length) }
        let ends = levels.flatMap { [$0.range.lowerBound, $0.range.upperBound] }.filter { (0...path.length).contains($0) }
        var distances: [Double] = []
        for distance in (grid + ends).sorted() where distances.last.map({ distance - $0 > 0.5 }) ?? true {
            distances.append(distance)
        }
        self.distances = distances
        let points = distances.map { path.point(at: $0) }
        let ground = points.map(ground)
        self.ground = ground
        let wet = points.map(water)

        // What each sample would rather be, and what it may be.
        let reach = Self.smoothing
        var target: [Double] = []
        var window = 0...0
        for index in distances.indices {
            while distances[window.lowerBound] < distances[index] - reach { window = (window.lowerBound + 1)...window.upperBound }
            while window.upperBound + 1 < distances.count, distances[window.upperBound + 1] <= distances[index] + reach {
                window = window.lowerBound...(window.upperBound + 1)
            }
            target.append(window.map { ground[$0] }.reduce(0, +) / Double(window.count))
        }
        // How far each sample may rise or fall from the one before: none
        // within a level stretch.
        var steps = [0.0] + zip(distances, distances.dropFirst()).map { RealWorldDemo.rulingGrade * ($1 - $0) }
        for level in levels {
            for index in distances.indices.dropFirst() where level.range.contains(distances[index]) && level.range.contains(distances[index - 1]) {
                steps[index] = 0
            }
        }
        // The runs of water, each a bridge until no grade reaches one.
        var runs: [ClosedRange<Int>] = []
        for index in distances.indices where wet[index] {
            if let last = runs.last, last.upperBound >= index - 2 {
                runs[runs.count - 1] = last.lowerBound...index
            } else {
                runs.append(index...index)
            }
        }
        // Where no grade reaches the water's either way, the stations may
        // stand further from the ground, a few metres at a time.
        for slack in Self.slack {
            var low = [Double](repeating: -.infinity, count: distances.count)
            var high = ground.map { $0 + Self.highest }
            for level in levels {
                let widen = level.low < level.high ? slack : 0
                for index in distances.indices where level.range.contains(distances[index]) {
                    low[index] = max(low[index], level.low - widen)
                    high[index] = min(high[index], level.high + widen)
                }
            }
            var tunnels: Set<Int> = []
            while true {
                var low = low, high = high
                for (number, run) in runs.enumerated() {
                    for index in max(0, run.lowerBound - 1)...min(distances.count - 1, run.upperBound + 1) {
                        if tunnels.contains(number) {
                            high[index] = min(high[index], ground[index] - Self.underWater)
                        } else {
                            low[index] = max(low[index], ground[index] + Self.waterClearance)
                        }
                    }
                }
                let stuck: Stuck
                switch Self.solve(target: target, low: low, high: high, steps: steps) {
                case .success(let heights):
                    self.heights = heights
                    self.levels = levels.map { level in
                        (level.range, distances.firstIndex { level.range.contains($0) }.map { heights[$0] } ?? level.low)
                    }
                    return
                case .failure(let failure):
                    stuck = failure
                }
                // Under the water nearest where no grade reaches.
                let nearest = runs.indices.filter { !tunnels.contains($0) }.min { a, b in
                    min(abs(runs[a].lowerBound - stuck.index), abs(runs[a].upperBound - stuck.index))
                        < min(abs(runs[b].lowerBound - stuck.index), abs(runs[b].upperBound - stuck.index))
                }
                guard let nearest else { break }
                tunnels.insert(nearest)
            }
        }
        preconditionFailure("No grade reaches along a demo track \(Int(path.length / RealWorldDemo.metre)) m long")
    }

    /// Where no grade reaches.
    struct Stuck: Error {
        let index: Int
    }

    /// The heights nearest `target` within `low` and `high` that change by
    /// at most `steps` from one sample to the next.
    private static func solve(target: [Double], low: [Double], high: [Double], steps: [Double]) -> Result<[Double], Stuck> {
        var low = low, high = high
        for index in low.indices.dropFirst() {
            low[index] = max(low[index], low[index - 1] - steps[index])
            high[index] = min(high[index], high[index - 1] + steps[index])
        }
        for index in low.indices.dropLast().reversed() {
            low[index] = max(low[index], low[index + 1] - steps[index + 1])
            high[index] = min(high[index], high[index + 1] + steps[index + 1])
        }
        if let index = low.indices.first(where: { low[$0] > high[$0] + 1e-6 }) { return .failure(Stuck(index: index)) }
        var heights: [Double] = []
        for index in low.indices {
            var lowest = low[index], highest = high[index]
            if let last = heights.last {
                lowest = max(lowest, last - steps[index])
                highest = min(highest, last + steps[index])
            }
            heights.append(min(max(target[index], lowest), max(lowest, highest)))
        }
        return .success(heights)
    }

    /// The track's height `distance` along the path, in world units.
    func height(at distance: Double) -> Double {
        if let level = levels.first(where: { $0.range.contains(distance) }) { return level.height }
        return interpolate(heights, at: distance)
    }

    /// A node's height `distance` along the path: whole units.
    func node(at distance: Double) -> Int64 {
        Int64(height(at: distance).rounded())
    }

    /// Whether a node may stand `distance` along the path: near enough the
    /// ground.
    func allowsNode(at distance: Double) -> Bool {
        abs(height(at: distance) - interpolate(ground, at: distance)) <= Self.nodeReach
    }

    /// Whether a straight grade from `a` to `b` keeps close to the line.
    func fits(from a: Double, to b: Double) -> Bool {
        let start = height(at: a), end = height(at: b)
        var index = sample(at: a)
        while index < distances.count, distances[index] < b {
            let distance = distances[index]
            if distance > a, abs(start + (end - start) * (distance - a) / (b - a) - height(at: distance)) > Self.fit { return false }
            index += 1
        }
        return true
    }

    /// The last sample at or before `distance`.
    private func sample(at distance: Double) -> Int {
        var lower = 0, upper = distances.count - 1
        while lower < upper {
            let middle = (lower + upper + 1) / 2
            if distances[middle] <= distance { lower = middle } else { upper = middle - 1 }
        }
        return lower
    }

    private func interpolate(_ values: [Double], at distance: Double) -> Double {
        let index = min(sample(at: distance), distances.count - 2)
        guard index >= 0 else { return values[0] }
        let a = distances[index], b = distances[index + 1]
        let t = b > a ? min(1, max(0, (distance - a) / (b - a))) : 0
        return values[index] + (values[index + 1] - values[index]) * t
    }
}
